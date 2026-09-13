import Foundation
import Testing

import FlickrKit
@testable import FlickrDownloaderUI

/// The download side of the model, headlessly.
@MainActor
@Suite struct AppModelDownloadTests {

    private func directory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flickrdownloader-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func model(stalling: Set<String> = []) -> AppModel {
        AppModel(vault: CredentialsVault(store: MemoryStore(seeded: true)),
                 transport: FakeTransport(body: Fixtures.page(ids: ["1", "2", "3"])),
                 engine: DownloadEngine(transport: StubBytes(stalling: stalling)),
                 policy: RetryPolicy(attempts: 1, backoff: []),
                 settleTime: .milliseconds(5))
    }

    private func loadSearch(_ model: AppModel) async throws {
        model.setInput("boats", for: .search)
        model.submit(.search)
        try await waitUntil("the search to load") {
            model.workspace[.search].status != .loading
        }
    }

    private func finished(_ model: AppModel) async throws {
        try await waitUntil("the download to finish") { model.download.report != nil }
    }

    /// The photographs, without the credits file written beside them.
    private func files(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0 != Credits.filename }
            .sorted()
    }

    /// The button downloads what *this* source has selected, whatever else has
    /// loaded since.
    @Test func theSelectedPhotosOfTheNamedSourceAreWhatGetsDownloaded() async throws {
        let folder = try directory()
        let model = model()
        try await loadSearch(model)
        model.select(["1", "3"], in: .search)

        model.startDownload(from: .search, to: folder, variant: .medium)
        try await finished(model)

        #expect(model.download.report?.saved == 2)
        #expect(try files(in: folder).count == 2)
        #expect(try files(in: folder).allSatisfy { !$0.hasSuffix(".part") })
        #expect(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent(Credits.filename).path))
    }

    @Test func nothingSelectedIsNotADownload() async throws {
        let folder = try directory()
        let model = model()
        try await loadSearch(model)

        model.startDownload(from: .search, to: folder, variant: .medium)
        #expect(!model.download.isRunning)
        #expect(try files(in: folder).isEmpty)
    }

    /// A second batch started over a running one would share its progress and
    /// its report, and the bar would read a count from the wrong download.
    @Test func aSecondDownloadCannotStartOverARunningOne() async throws {
        let folder = try directory()
        let model = model(stalling: ["https://live.staticflickr.com/1.jpg"])
        try await loadSearch(model)
        model.select(["1", "2"], in: .search)

        model.startDownload(from: .search, to: folder, variant: .medium)
        try await waitUntil("the download to start") { model.download.isRunning }
        #expect(model.download.isRunning)
        #expect(model.download.total == 2)

        model.select(["3"], in: .search)
        model.startDownload(from: .search, to: folder, variant: .medium)
        #expect(model.download.total == 2)

        model.cancelDownload()
        try await finished(model)
    }

    /// Closing mid-download cancels, waits, and keeps the count.
    @Test func quittingMidDownloadKeepsTheReportAndLeavesNoPartialFile() async throws {
        let folder = try directory()
        let model = model(stalling: ["https://live.staticflickr.com/2.jpg"])
        try await loadSearch(model)
        model.select(["1", "2", "3"], in: .search)

        model.startDownload(from: .search, to: folder, variant: .medium)
        // Transfers run side by side: wait for 1 and 3 to be on disk, so what
        // is cancelled is the second one mid-transfer.
        try await waitUntil("photos 1 and 3 to land") {
            (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?
                .filter { $0.hasSuffix(".jpg") }.count == 2
        }
        await model.finishDownloadBeforeClosing()

        let report = try #require(model.download.report)
        #expect(report.wasCancelled)
        #expect(report.summary == "Saved 2 of 3")
        #expect(try files(in: folder) == ["Photo 1_1.jpg", "Photo 3_3.jpg"])
    }

    @Test func theReportCanBeDismissed() async throws {
        let folder = try directory()
        let model = model()
        try await loadSearch(model)
        model.select(["1"], in: .search)

        model.startDownload(from: .search, to: folder, variant: .medium)
        try await finished(model)
        #expect(model.download.report != nil)

        model.dismissDownloadReport()
        #expect(model.download.report == nil)
        #expect(!model.download.isRunning)
    }
}

/// Yields two chunks, or stalls until cancelled.
struct StubBytes: ChunkTransport {
    let stalling: Set<String>

    func chunks(from url: URL) async throws -> AsyncThrowingStream<Data, any Error> {
        let stalls = stalling.contains(url.absoluteString)
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(Data(repeating: 0x41, count: 512))
                if stalls {
                    // Ends without throwing when cancelled, as a real stream does.
                    try? await Task.sleep(for: .seconds(60))
                    continuation.finish()
                    return
                }
                continuation.yield(Data(repeating: 0x42, count: 512))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
