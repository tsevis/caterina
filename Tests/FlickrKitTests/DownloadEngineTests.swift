import Foundation
import Testing

@testable import FlickrKit

/// A transport that can be told to stall, so cancellation can be tested without
/// waiting for anything real.
struct StubChunkTransport: ChunkTransport {
    /// URLs whose transfer never finishes until the task is cancelled.
    let stalling: Set<String>
    /// URLs that fail part-way through, after writing something.
    let failingMidstream: Set<String>
    /// URLs that fail before a byte arrives.
    let failing: Set<String>
    let chunk: Data

    init(stalling: Set<String> = [], failingMidstream: Set<String> = [],
         failing: Set<String> = [], chunk: Data = Data(repeating: 0x41, count: 1024)) {
        self.stalling = stalling
        self.failingMidstream = failingMidstream
        self.failing = failing
        self.chunk = chunk
    }

    func chunks(from url: URL) async throws -> AsyncThrowingStream<Data, any Error> {
        let address = url.absoluteString
        if failing.contains(address) {
            throw FlickrError.transport("HTTP 404")
        }
        let chunk = chunk
        let stalls = stalling.contains(address)
        let failsLate = failingMidstream.contains(address)

        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(chunk)
                if failsLate {
                    continuation.finish(throwing: FlickrError.transport("connection reset"))
                    return
                }
                if stalls {
                    // Suspends until the surrounding task is cancelled, then
                    // **ends without throwing** — which is what a real
                    // `AsyncThrowingStream` does when its consumer is
                    // cancelled. Finishing with a `CancellationError` here
                    // sent the engine down its `catch`, so the re-check after
                    // the loop — the guard against renaming a truncated file
                    // into place — was never the thing under test.
                    try? await Task.sleep(for: .seconds(60))
                    continuation.finish()
                    return
                }
                continuation.yield(chunk)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Ported from `tests/test_download_core.py`.
///
/// Every failure mode here was a real defect: a filesystem error aborted the
/// whole batch, the success count reported photos that were never written, and
/// a cancelled transfer left a truncated image behind for the user to find
/// later.
@Suite struct DownloadEngineTests {

    private func directory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flickrdownloader-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func photo(_ id: String, title: String? = nil,
                       variants: [PhotoVariant: String]? = nil) -> Photo {
        Photo(id: id, title: title ?? "Photo \(id)",
              variants: variants ?? [
                .medium: "https://live.staticflickr.com/\(id)_m.jpg",
                .original: "https://live.staticflickr.com/\(id)_o.jpg",
              ])
    }

    /// The photographs, without the credits file that is written beside them.
    /// Waits for a condition rather than for a number of milliseconds.
    private func waitFor(_ description: String, within seconds: Double = 10,
                         _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(15))
        }
        Issue.record("timed out waiting for \(description)")
    }

    private func files(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0 != Credits.filename }
            .sorted()
    }

    private func credits(in directory: URL) -> String? {
        try? String(contentsOf: directory.appendingPathComponent(Credits.filename),
                    encoding: .utf8)
    }

    // MARK: - The ordinary case

    @Test func everyPhotoIsSavedAndCountedOnce() async throws {
        let folder = try directory()
        let engine = DownloadEngine(transport: StubChunkTransport())
        let report = await engine.download([photo("1"), photo("2"), photo("3")],
                                           to: folder, variant: .original)

        #expect(report.saved == 3)
        #expect(report.requested == 3)
        #expect(!report.wasCancelled)
        #expect(try files(in: folder).count == 3)
        // And every one of them is credited.
        let written = try #require(credits(in: folder))
        #expect(written.split(separator: "\n").count == 4)  // header plus three
        #expect(report.creditsProblem == nil)
    }

    /// The count the user is shown has to be the number of files that exist.
    @Test func theReportedCountEqualsTheFilesOnDisk() async throws {
        let folder = try directory()
        let engine = DownloadEngine(transport: StubChunkTransport(
            failing: ["https://live.staticflickr.com/2_o.jpg"]))
        let report = await engine.download([photo("1"), photo("2"), photo("3")],
                                           to: folder, variant: .original)

        #expect(report.saved == 2)
        #expect(try files(in: folder).count == 2)
    }

    @Test func duplicateTitlesAllSurvive() async throws {
        let folder = try directory()
        let photos = ["1", "2", "3"].map { photo($0, title: "Untitled") }
        let engine = DownloadEngine(transport: StubChunkTransport())
        let report = await engine.download(photos, to: folder, variant: .original)

        #expect(report.saved == 3)
        #expect(try files(in: folder).count == 3)
    }

    @Test func progressIsReportedOnceForEveryPhotoAttempted() async throws {
        let folder = try directory()
        let recorder = ProgressRecorder()
        let engine = DownloadEngine(transport: StubChunkTransport())
        _ = await engine.download([photo("1"), photo("2")], to: folder,
                                  variant: .original, onProgress: recorder.record)

        let reported = recorder.reports
        #expect(reported.count == 2)
        #expect(reported.map(\.completed) == [1, 2])
        #expect(reported.allSatisfy { $0.total == 2 })
    }

    @Test func theFileIsWrittenAtomicallyWithNoPartLeftBehind() async throws {
        let folder = try directory()
        let engine = DownloadEngine(transport: StubChunkTransport())
        _ = await engine.download([photo("1")], to: folder, variant: .original)

        #expect(try files(in: folder) == ["Photo 1_1.jpg"])
        #expect(try !files(in: folder).contains { $0.hasSuffix(".part") })
    }

    // MARK: - One photo's failure is not the batch's

    @Test func aTransportFailureDoesNotAbortTheBatch() async throws {
        let folder = try directory()
        let engine = DownloadEngine(transport: StubChunkTransport(
            failing: ["https://live.staticflickr.com/1_o.jpg"]))
        let report = await engine.download([photo("1"), photo("2")],
                                           to: folder, variant: .original)

        #expect(report.outcomes.count == 2)
        #expect(report.saved == 1)
        #expect(report.outcomes.first?.failure != nil)
    }

    @Test func aFilesystemFailureDoesNotAbortTheBatch() async throws {
        // A directory that does not exist and cannot be created under a file.
        let blocker = try directory().appendingPathComponent("not-a-directory")
        try Data("x".utf8).write(to: blocker)
        let engine = DownloadEngine(transport: StubChunkTransport())
        let report = await engine.download([photo("1"), photo("2")],
                                           to: blocker, variant: .original)

        #expect(report.outcomes.count == 2)
        #expect(report.saved == 0)
        #expect(report.outcomes.allSatisfy { $0.failure != nil })
    }

    @Test func aMidstreamFailureLeavesNoPartialFile() async throws {
        let folder = try directory()
        let engine = DownloadEngine(transport: StubChunkTransport(
            failingMidstream: ["https://live.staticflickr.com/1_o.jpg"]))
        let report = await engine.download([photo("1")], to: folder, variant: .original)

        #expect(report.saved == 0)
        #expect(try files(in: folder).isEmpty)
        // Nothing saved, so nothing to credit.
        #expect(credits(in: folder) == nil)
    }

    /// A photo with no downloadable URL is a result the user should see, not a
    /// silent gap between the count and the folder.
    @Test func aPhotoWithNoURLIsReportedRatherThanSkipped() async throws {
        let folder = try directory()
        let engine = DownloadEngine(transport: StubChunkTransport())
        let report = await engine.download([Photo(id: "9", title: "Nothing")],
                                           to: folder, variant: .original)

        #expect(report.outcomes.count == 1)
        #expect(report.saved == 0)
        #expect(report.outcomes.first?.failure?.isEmpty == false)
    }

    /// The save directory may be shared and the temp name is predictable, so a
    /// pre-planted symlink must not redirect the write.
    @Test func thePartialFileIsNotWrittenThroughASymlink() async throws {
        let folder = try directory()
        let victim = folder.appendingPathComponent("victim.txt")
        try Data("original".utf8).write(to: victim)
        let partial = folder.appendingPathComponent("Photo 1_1.jpg.part")
        try FileManager.default.createSymbolicLink(at: partial, withDestinationURL: victim)

        let engine = DownloadEngine(transport: StubChunkTransport())
        let report = await engine.download([photo("1")], to: folder, variant: .original)

        #expect(report.saved == 0)
        #expect(try String(contentsOf: victim, encoding: .utf8) == "original")
    }

    // MARK: - Cancellation

    /// Cancel mid-batch: what was finished stays, what was in flight leaves
    /// nothing behind, and the report says exactly how many were saved.
    @Test func cancellingMidBatchSavesWhatWasFinishedAndNothingElse() async throws {
        let folder = try directory()
        let engine = DownloadEngine(transport: StubChunkTransport(
            stalling: ["https://live.staticflickr.com/2_o.jpg"]))

        let task = Task {
            await engine.download([photo("1"), photo("2"), photo("3")],
                                  to: folder, variant: .original)
        }
        // Transfers run side by side, so photo 3 finishes while 2 stalls.
        // Wait for both to land rather than guessing how long that takes: a
        // fixed interval fails whenever the machine is busy.
        try await waitFor("photos 1 and 3 to be saved") {
            (try? files(in: folder))?.filter { !$0.hasSuffix(".part") }.count == 2
        }
        task.cancel()
        let report = await task.value

        #expect(report.wasCancelled)
        #expect(report.saved == 2)
        #expect(report.requested == 3)
        #expect(report.summary == "Saved 2 of 3")
        #expect(try files(in: folder) == ["Photo 1_1.jpg", "Photo 3_3.jpg"])
        // Photographs saved before a cancel need crediting just as much as
        // forty would have.
        #expect(credits(in: folder)?.contains("Photo 1_1.jpg") == true)
        #expect(credits(in: folder)?.contains("Photo 3_3.jpg") == true)
        #expect(try !files(in: folder).contains { $0.hasSuffix(".part") })
    }

    @Test func cancellingBeforeTheFirstPhotoDownloadsNothing() async throws {
        let folder = try directory()
        let engine = DownloadEngine(transport: StubChunkTransport(
            stalling: ["https://live.staticflickr.com/1_o.jpg"]))

        let task = Task {
            await engine.download([photo("1"), photo("2")], to: folder, variant: .original)
        }
        task.cancel()
        let report = await task.value

        #expect(report.saved == 0)
        #expect(try files(in: folder).isEmpty)
    }

    /// The report survives cancellation — closing the window mid-download must
    /// not lose the count.
    @Test func theReportIsStillReturnedAfterCancellation() async throws {
        let folder = try directory()
        let engine = DownloadEngine(transport: StubChunkTransport(
            stalling: ["https://live.staticflickr.com/1_o.jpg"]))
        let task = Task {
            await engine.download([photo("1")], to: folder, variant: .original)
        }
        task.cancel()
        let report = await task.value
        #expect(report.requested == 1)
        #expect(report.summary == "Saved 0 of 1")
    }

    // MARK: - Which URL is used

    @Test func theRequestedSizeIsPreferred() {
        let photo = photo("1")
        #expect(photo.downloadURL(preferring: .medium) == "https://live.staticflickr.com/1_m.jpg")
        #expect(photo.downloadURL(preferring: .original) == "https://live.staticflickr.com/1_o.jpg")
    }

    /// Largest first, so a fallback never downgrades more than it must.
    @Test func anAbsentSizeFallsBackToTheLargestThatExists() {
        let photo = photo("1", variants: [.medium: "https://live.staticflickr.com/m.jpg",
                                          .small: "https://live.staticflickr.com/s.jpg"])
        #expect(photo.downloadURL(preferring: .original) == "https://live.staticflickr.com/m.jpg")
    }

    @Test func aPhotoWithNoVariantsHasNoDownloadURL() {
        #expect(Photo(id: "1").downloadURL(preferring: .original) == nil)
    }

    // MARK: - Timeouts

    /// A request without a timeout hung the reference application forever.
    @Test func everyTransferCarriesATimeout() {
        #expect(URLSessionChunkTransport.requestTimeout > 0)
        #expect(URLSessionChunkTransport.resourceTimeout
            > URLSessionChunkTransport.requestTimeout)
    }
}

/// Collects progress reports from the engine's callback.
final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [DownloadProgress] = []

    var reports: [DownloadProgress] {
        lock.lock(); defer { lock.unlock() }
        return collected
    }

    var record: @Sendable (DownloadProgress) -> Void {
        { [self] progress in
            lock.lock(); collected.append(progress); lock.unlock()
        }
    }
}
