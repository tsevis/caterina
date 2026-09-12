import Foundation
import Testing

import FlickrKit
@testable import FlickrDownloaderUI

/// Search, select, download — against the real Flickr, with real files landing
/// on a real disk.
///
/// Opt-in, like the other live checks, and for the same reason: a default
/// `swift test` is offline. What this covers that nothing else does is the
/// whole path in one piece — a signed request, a decoded page, a selection
/// held per source, and bytes arriving under the filename the rules produce.
///
/// ```
/// FLICKR_API_KEY=… FLICKR_API_SECRET=… swift test --filter LiveEndToEndTests
/// ```
///
/// The Keychain is deliberately not consulted: a test that reads the app's own
/// credentials would put a Keychain prompt on the screen of whoever runs it.
@MainActor
@Suite(.enabled(if: LiveModelCredentials.value != nil))
struct LiveEndToEndTests {

    private func model() throws -> AppModel {
        let credentials = try #require(LiveModelCredentials.value)
        let store = SeededStore(key: credentials.consumerKey,
                                secret: credentials.consumerSecret)
        return AppModel(vault: CredentialsVault(store: store), settleTime: .milliseconds(5))
    }

    private func directory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flickrdownloader-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Waits for a source to stop loading, rather than sleeping a guessed
    /// interval: a real request takes as long as it takes.
    private func settle(_ model: AppModel, _ source: PhotoSource,
                        within seconds: Double = 20) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if model.workspace[source].status != .loading { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("\(source) was still loading after \(seconds)s")
    }

    @Test func aSearchFillsTheGridWithRealPhotos() async throws {
        let model = try model()
        model.setInput("harbour at dusk", for: .search)
        model.submit(.search)
        try await settle(model, .search)

        let state = model.workspace[.search]
        #expect(state.status == .ready)
        #expect(!state.photos.isEmpty)
        #expect(state.total > 0)
        #expect(state.totalPages >= 1)
        // Every photo must be drawable and downloadable, or the grid shows
        // placeholders and the download reports failures.
        #expect(state.photos.allSatisfy { $0.gridThumbnailURL() != nil })
        #expect(state.photos.allSatisfy { $0.downloadURL(preferring: .medium) != nil })
    }

    @Test func pagingForwardBringsDifferentPhotos() async throws {
        let model = try model()
        model.setInput("mountain", for: .search)
        model.submit(.search)
        try await settle(model, .search)
        let first = Set(model.workspace[.search].photos.map(\.id))

        model.nextPage(in: .search)
        try await settle(model, .search)
        let second = Set(model.workspace[.search].photos.map(\.id))

        #expect(model.workspace[.search].page == 2)
        #expect(!second.isEmpty)
        // **Not disjoint — Flickr does not promise that.** Measured: page 2 of
        // a relevance search repeated 4 of 25 photos from page 1, because the
        // ranking shifts between two requests seconds apart. What would mean
        // paging is broken is page 2 coming back *as* page 1, so the assertion
        // is that most of it is new.
        let repeated = first.intersection(second).count
        #expect(repeated < second.count / 2)
    }

    /// The whole point of the application, once.
    @Test func selectedPhotosArriveOnDiskUnderTheirOwnNames() async throws {
        let model = try model()
        let folder = try directory()

        model.setInput("lighthouse", for: .search)
        model.submit(.search)
        try await settle(model, .search)

        let wanted = Array(model.workspace[.search].photos.prefix(3))
        try #require(wanted.count == 3)
        model.select(Set(wanted.map(\.id)), in: .search)

        model.startDownload(from: .search, to: folder, variant: .small320)
        let deadline = Date().addingTimeInterval(60)
        while model.download.isRunning, Date() < deadline {
            try await Task.sleep(for: .milliseconds(150))
        }

        let report = try #require(model.download.report)
        #expect(report.saved == 3)
        #expect(report.failures.isEmpty)

        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(files.count == 3)
        #expect(!files.contains { $0.hasSuffix(".part") })
        // Every id appears in a filename, which is what stops two photos with
        // the same title overwriting each other.
        for photo in wanted {
            #expect(files.contains { $0.contains(photo.id) })
        }
        // And the bytes are actually a JPEG, not an error page.
        for file in files {
            let data = try Data(contentsOf: folder.appendingPathComponent(file))
            #expect(data.count > 1000)
            #expect(data.prefix(2) == Data([0xFF, 0xD8]))
        }
    }

    @Test func aGroupPoolLoadsAndSaysItsFiltersAreInactive() async throws {
        let model = try model()
        model.setInput("https://www.flickr.com/groups/blackandwhite/", for: .groups)
        model.submit(.groups)
        try await settle(model, .groups)

        #expect(model.workspace[.groups].status == .ready)
        #expect(model.resolvedGroup?.name == "Black and White")
        #expect(model.workspace[.groups].query?.supportsFilters == false)
    }
}

enum LiveModelCredentials {
    static let value: OAuth1.Credentials? = {
        let environment = ProcessInfo.processInfo.environment
        guard let key = environment["FLICKR_API_KEY"], !key.isEmpty,
              let secret = environment["FLICKR_API_SECRET"], !secret.isEmpty
        else { return nil }
        return OAuth1.Credentials(consumerKey: key, consumerSecret: secret)
    }()
}

/// An in-memory store holding the credentials the environment supplied.
final class SeededStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]

    init(key: String, secret: String) {
        values = ["api-key": key, "api-secret": secret]
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
