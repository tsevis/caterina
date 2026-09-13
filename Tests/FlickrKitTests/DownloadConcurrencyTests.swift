import Foundation
import Synchronization
import Testing

@testable import FlickrKit

/// A transport that holds every transfer open until it is released, and counts
/// how many are open at once.
final class GatedTransport: ChunkTransport, @unchecked Sendable {
    private let state = Mutex((open: 0, peak: 0, released: Set<String>(), stalled: Set<String>()))

    init(stalling: Set<String> = []) {
        state.withLock { $0.stalled = stalling }
    }

    var open: Int { state.withLock { $0.open } }
    var peak: Int { state.withLock { $0.peak } }

    /// Lets every transfer not marked as stalling finish.
    func releaseAll() { state.withLock { $0.released = ["*"] } }

    private func isReleased(_ address: String) -> Bool {
        state.withLock { !$0.stalled.contains(address) && $0.released.contains("*") }
    }

    func chunks(from url: URL) async throws -> AsyncThrowingStream<Data, any Error> {
        let address = url.absoluteString
        state.withLock {
            $0.open += 1
            $0.peak = max($0.peak, $0.open)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(Data(repeating: 0x42, count: 512))
                while !Task.isCancelled, !self.isReleased(address) {
                    try? await Task.sleep(for: .milliseconds(5))
                }
                continuation.finish()
            }
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                self?.state.withLock { $0.open -= 1 }
            }
        }
    }
}

/// Several transfers at once, bounded.
///
/// **One at a time spent a batch waiting on round trips.** A photo is a few
/// megabytes behind a hundred milliseconds of TLS and CDN latency; running a
/// handful together is what a browser does with the same server.
@Suite struct DownloadConcurrencyTests {

    private func directory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("caterina-concurrency-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func photos(_ count: Int) -> [Photo] {
        (1...count).map {
            Photo(id: "\($0)", title: "Photo \($0)",
                  variants: [.original: "https://live.staticflickr.com/\($0)_o.jpg"])
        }
    }

    private func saved(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".jpg") }
            .sorted()
    }

    private func waitFor(_ description: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("timed out waiting for \(description)")
    }

    @Test func severalPhotosTransferAtOnceButNeverMoreThanTheLimit() async throws {
        let folder = try directory()
        let transport = GatedTransport()
        let engine = DownloadEngine(transport: transport)
        let limit = DownloadEngine.simultaneousTransfers
        #expect(limit > 1)

        let task = Task { await engine.download(photos(limit * 3), to: folder, variant: .original) }
        // Nothing completes until released, so once `limit` are open no more
        // can ever be started: the peak is exactly the limit, not a sample.
        try await waitFor("\(limit) transfers to be open") { transport.open == limit }
        #expect(transport.peak == limit)

        transport.releaseAll()
        let report = await task.value
        #expect(report.saved == limit * 3)
        #expect(transport.peak == limit)
    }

    /// A slow photo must not hold up the ones behind it.
    @Test func aStalledPhotoDoesNotHoldUpTheRest() async throws {
        let folder = try directory()
        let transport = GatedTransport(stalling: ["https://live.staticflickr.com/1_o.jpg"])
        transport.releaseAll()
        let engine = DownloadEngine(transport: transport)

        let task = Task { await engine.download(photos(3), to: folder, variant: .original) }
        try await waitFor("photos 2 and 3") { saved(in: folder).count == 2 }
        task.cancel()
        let report = await task.value

        #expect(report.wasCancelled)
        #expect(report.saved == 2)
        #expect(saved(in: folder) == ["Photo 2_2.jpg", "Photo 3_3.jpg"])
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        #expect(!leftovers.contains { $0.hasSuffix(".part") })
    }

    /// The report lists photos in the order they were asked for, whatever
    /// order they finished in.
    @Test func theReportKeepsTheOrderOfTheSelection() async throws {
        let folder = try directory()
        let transport = GatedTransport()
        transport.releaseAll()
        let engine = DownloadEngine(transport: transport)
        let batch = photos(9)

        let report = await engine.download(batch, to: folder, variant: .original)
        #expect(report.outcomes.map(\.photoID) == batch.map(\.id))
    }
}
