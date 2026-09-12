import Foundation
import Testing

import FlickrKit
@testable import FlickrDownloaderUI

/// The window's state machine, exercised headlessly — no window is created by
/// anything here.
@MainActor
@Suite struct AppModelTests {

    private func model(_ transport: FakeTransport) -> AppModel {
        AppModel(vault: CredentialsVault(store: MemoryStore(seeded: true)),
                 transport: transport,
                 // No real backoff: the retry policy's timings are FlickrKit's
                 // to test, and waiting five seconds here proves nothing.
                 policy: RetryPolicy(attempts: 2, backoff: [.milliseconds(1)]),
                 // The inspector debounces so eight ticks are one search; the
                 // interval itself is not what these tests are about.
                 settleTime: .milliseconds(5))
    }

    private func settle() async throws {
        // Long enough for the load task to run and write back; the transport
        // never touches the network, so this is scheduling, not waiting.
        try await Task.sleep(for: .milliseconds(60))
    }

    // MARK: - One source's state is its own

    @Test func loadingOneSourceLeavesAnothersSelectionAndPageAlone() async throws {
        let transport = FakeTransport(body: Fixtures.page(ids: ["1", "2", "3"], pages: 8))
        let model = model(transport)

        model.setInput("boats", for: .search)
        model.submit(.search)
        try await settle()
        model.nextPage(in: .search)
        try await settle()
        model.select(["1", "3"], in: .search)

        model.setInput("12345@N00", for: .user)
        model.submit(.user)
        try await settle()

        #expect(model.workspace[.search].selection == ["1", "3"])
        #expect(model.workspace[.search].page == 2)
        #expect(model.workspace[.user].page == 1)
        #expect(model.workspace[.user].selection.isEmpty)
    }

    @Test func theDownloadSetComesFromTheSourceItWasSelectedIn() async throws {
        let transport = FakeTransport(body: Fixtures.page(ids: ["1", "2"]))
        let model = model(transport)

        model.setInput("boats", for: .search)
        model.submit(.search)
        try await settle()
        model.select(["2"], in: .search)

        model.setInput("12345@N00", for: .user)
        model.submit(.user)
        try await settle()
        model.select(["1"], in: .user)

        #expect(model.workspace[.search].selectedPhotos.map(\.id) == ["2"])
        #expect(model.workspace[.user].selectedPhotos.map(\.id) == ["1"])
    }

    // MARK: - A new query resets to page 1

    @Test func aNewSearchTermGoesBackToPageOne() async throws {
        let transport = FakeTransport(body: Fixtures.page(ids: ["1"], pages: 9))
        let model = model(transport)

        model.setInput("boats", for: .search)
        model.submit(.search)
        try await settle()
        model.nextPage(in: .search)
        model.nextPage(in: .search)
        try await settle()
        #expect(model.workspace[.search].page > 1)

        model.setInput("harbours", for: .search)
        model.submit(.search)
        #expect(model.workspace[.search].page == 1)
    }

    @Test func changingAFilterRerunsTheQueryFromPageOne() async throws {
        let transport = FakeTransport(body: Fixtures.page(ids: ["1"], pages: 9))
        let model = model(transport)

        model.setInput("boats", for: .search)
        model.submit(.search)
        try await settle()
        model.nextPage(in: .search)
        try await settle()

        model.setFilters(SearchFilters(licenses: [.by]), for: .search)
        #expect(model.workspace[.search].page == 1)
        try await settle()
        #expect(await transport.lastQueryItems["license"] == "4")
    }

    // MARK: - A superseded reply must not draw

    /// Typing a second search while the first is still in flight must leave the
    /// second one's results on screen, not whichever answered last.
    @Test func aSlowFirstReplyDoesNotOverwriteAFastSecondOne() async throws {
        let transport = FakeTransport(
            body: Fixtures.page(ids: ["late"]),
            secondBody: Fixtures.page(ids: ["current"]),
            delayFirstBy: .milliseconds(250))
        let model = model(transport)

        model.setInput("first", for: .search)
        model.submit(.search)
        model.setInput("second", for: .search)
        model.submit(.search)

        try await Task.sleep(for: .milliseconds(400))
        #expect(model.workspace[.search].photos.map(\.id) == ["current"])
    }

    // MARK: - Failures

    @Test func aBusyFlickrReadsDifferentlyFromARealError() async throws {
        let busy = FakeTransport(body: #"{"stat":"fail","code":201,"message":"busy"}"#)
        let model = model(busy)
        model.setInput("x", for: .search)
        model.submit(.search)
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.workspace[.search].status.isTransient)

        let gone = FakeTransport(body: #"{"stat":"fail","code":1,"message":"Photo not found"}"#)
        let other = self.model(gone)
        other.setInput("x", for: .search)
        other.submit(.search)
        try await settle()
        #expect(other.workspace[.search].status.error?.isTransient == false)
    }

    @Test func askingForYourOwnPhotosWithoutSigningInSaysSo() async throws {
        let model = AppModel(vault: CredentialsVault(store: MemoryStore(seeded: true)),
                             transport: FakeTransport(body: Fixtures.page(ids: ["1"])))
        model.submit(.you)
        try await settle()
        #expect(model.workspace[.you].status.error != nil)
    }

    // MARK: - Credentials

    @Test func withNoAPIKeyTheOnboardingSheetIsWhatOpens() {
        let model = AppModel(vault: CredentialsVault(store: MemoryStore(seeded: false)),
                             transport: FakeTransport(body: "{}"))
        #expect(model.isShowingOnboarding)
        #expect(!model.hasAPIKey)
    }

    @Test func signingOutClearsTheYouSource() async throws {
        let store = MemoryStore(seeded: true)
        try store.set("tok", for: "oauth-token")
        let model = AppModel(vault: CredentialsVault(store: store),
                             transport: FakeTransport(body: Fixtures.page(ids: ["1"])))

        model.submit(.you)
        try await settle()
        #expect(!model.workspace[.you].photos.isEmpty)

        try model.signOut()
        #expect(model.workspace[.you].photos.isEmpty)
        #expect(model.workspace[.you].status == .idle)
        #expect(!model.isSignedIn)
    }
}

// MARK: - Doubles

actor FakeTransport: HTTPTransport {
    private let body: String
    private let secondBody: String?
    private let delayFirstBy: Duration?
    private(set) var requested: [URL] = []

    init(body: String, secondBody: String? = nil, delayFirstBy: Duration? = nil) {
        self.body = body
        self.secondBody = secondBody
        self.delayFirstBy = delayFirstBy
    }

    var lastQueryItems: [String: String] {
        guard let url = requested.last,
              let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.query
        else { return [:] }
        var items: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            let name = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value = parts.count > 1
                ? (String(parts[1]).removingPercentEncoding ?? String(parts[1])) : ""
            items[name] = value
        }
        return items
    }

    func data(from url: URL) async throws -> Data {
        requested.append(url)
        let chosen = requested.count > 1 ? (secondBody ?? body) : body
        // Flickr echoes the page it served, and the model believes the reply
        // rather than its own request — so a fake that always says page 1 makes
        // paging look broken when it is not.
        let answer = chosen.replacingOccurrences(
            of: "\"page\":1", with: "\"page\":\(requestedPage)")

        if requested.count == 1, let delayFirstBy {
            try? await Task.sleep(for: delayFirstBy)
            return Data(body.utf8)
        }
        return Data(answer.utf8)
    }

    private var requestedPage: Int {
        Int(lastQueryItems["page"] ?? "1") ?? 1
    }
}

final class MemoryStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    init(seeded: Bool) {
        if seeded {
            values = ["api-key": "key", "api-secret": "secret"]
        }
    }

    func string(for key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    func set(_ value: String, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }

    func remove(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}

enum Fixtures {
    static func page(ids: [String], page: Int = 1, pages: Int = 1) -> String {
        let photos = ids.map {
            #"{"id":"\#($0)","title":"Photo \#($0)","url_m":"https://example.com/\#($0).jpg"}"#
        }.joined(separator: ",")
        return """
        {"photos":{"page":\(page),"pages":\(pages),"perpage":25,"total":\(ids.count),\
        "photo":[\(photos)]},"stat":"ok"}
        """
    }
}
