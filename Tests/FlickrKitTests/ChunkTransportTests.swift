import Foundation
import Synchronization
import Testing

@testable import FlickrKit

/// The real transport, against a stubbed `URLProtocol` rather than a network.
///
/// **It streams what URLSession delivers, not one byte at a time.** Iterating
/// `URLSession.AsyncBytes` byte by byte peaked at 32 MB/s with a core pegged —
/// slower than the connection it was reading from on anything above ~250 Mbit.
@Suite struct ChunkTransportTests {

    private let transport = URLSessionChunkTransport(protocolClasses: [StubProtocol.self])

    private func collect(_ url: URL) async throws -> (data: Data, pieces: Int) {
        var data = Data()
        var pieces = 0
        for try await chunk in try await transport.chunks(from: url) {
            data.append(chunk)
            pieces += 1
        }
        return (data, pieces)
    }

    @Test func everyByteArrivesInOrder() async throws {
        let body = Data((0..<(3 * 1024 * 1024)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let url = StubProtocol.serve(.init(status: 200, pieces: body.split(into: 7)))

        let received = try await collect(url)
        #expect(received.data == body)
    }

    /// Chunks are passed through as delivered, so a transfer is a handful of
    /// iterations rather than one per byte.
    @Test func chunksAreForwardedWhole() async throws {
        let body = Data(count: 4 * 1024 * 1024)
        let url = StubProtocol.serve(.init(status: 200, pieces: body.split(into: 4)))

        let received = try await collect(url)
        #expect(received.data.count == body.count)
        #expect(received.pieces <= 32)
    }

    /// Before any chunk — so no partial file is ever opened for an error page.
    @Test func anHTTPErrorThrowsBeforeTheStreamIsReturned() async throws {
        let url = StubProtocol.serve(.init(status: 404, pieces: [Data("Not Found".utf8)]))

        await #expect {
            _ = try await transport.chunks(from: url)
        } throws: { error in
            (error as? FlickrError)?.message.contains("404") == true
        }
    }

    @Test func aFailureMidTransferEndsTheStreamWithTheError() async throws {
        let url = StubProtocol.serve(.init(status: 200, pieces: [Data(count: 1024)],
                                           failure: URLError(.networkConnectionLost)))

        await #expect(throws: URLError.self) { _ = try await collect(url) }
    }

    /// Walking away from the stream must close the connection, not leave it
    /// downloading into a buffer nobody reads.
    @Test func abandoningTheStreamCancelsTheTransfer() async throws {
        let url = StubProtocol.serve(.init(status: 200, pieces: [Data(count: 1024)],
                                           stallsAfterPieces: true))

        let consumer = Task {
            for try await _ in try await transport.chunks(from: url) { break }
        }
        _ = try? await consumer.value

        try await poll("the stub to be stopped") { StubProtocol.wasStopped(url) }
    }

    @Test func cancellingTheCallerCancelsTheTransfer() async throws {
        let url = StubProtocol.serve(.init(status: 200, pieces: [Data(count: 1024)],
                                           stallsAfterPieces: true))

        let consumer = Task {
            var count = 0
            for try await chunk in try await transport.chunks(from: url) { count += chunk.count }
            return count
        }
        try await poll("the first chunk to be sent") { StubProtocol.hasStarted(url) }
        consumer.cancel()

        try await poll("the stub to be stopped") { StubProtocol.wasStopped(url) }
    }
}

private func poll(_ description: String, within seconds: Double = 10,
                  _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("timed out waiting for \(description)")
}

private extension Data {
    func split(into count: Int) -> [Data] {
        let size = Swift.max(1, (self.count + count - 1) / count)
        return stride(from: 0, to: self.count, by: size).map {
            subdata(in: $0..<Swift.min($0 + size, self.count))
        }
    }
}

/// Serves a scripted response per URL. Keyed by URL so parallel tests do not
/// share a script.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Script: Sendable {
        var status: Int
        var pieces: [Data]
        var failure: URLError?
        var stallsAfterPieces = false
    }

    private struct Registry {
        var scripts: [URL: Script] = [:]
        var started: Set<URL> = []
        var stopped: Set<URL> = []
    }

    private static let registry = Mutex(Registry())

    static func serve(_ script: Script) -> URL {
        let url = URL(string: "https://stub.invalid/\(UUID().uuidString).jpg")!
        registry.withLock { $0.scripts[url] = script }
        return url
    }

    static func hasStarted(_ url: URL) -> Bool { registry.withLock { $0.started.contains(url) } }
    static func wasStopped(_ url: URL) -> Bool { registry.withLock { $0.stopped.contains(url) } }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "stub.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let script = Self.registry.withLock({ $0.scripts[url] }),
              let response = HTTPURLResponse(url: url, statusCode: script.status,
                                             httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for piece in script.pieces { client?.urlProtocol(self, didLoad: piece) }
        Self.registry.withLock { _ = $0.started.insert(url) }

        if script.stallsAfterPieces { return }
        if let failure = script.failure {
            client?.urlProtocol(self, didFailWithError: failure)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        guard let url = request.url else { return }
        Self.registry.withLock { _ = $0.stopped.insert(url) }
    }
}
