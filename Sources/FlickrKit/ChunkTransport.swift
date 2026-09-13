import Foundation
import Synchronization

/// Streaming bytes from a URL, in chunks.
///
/// A protocol so cancellation and partial-file behaviour can be tested without
/// a network — a stalled transfer in a test is a stream that suspends, not a
/// real socket left open.
public protocol ChunkTransport: Sendable {
    func chunks(from url: URL) async throws -> AsyncThrowingStream<Data, any Error>
}

/// The real one. **Every transfer carries a timeout**; one without a timeout
/// hung the reference application forever, with a progress bar and no way out.
///
/// **Chunks are forwarded as URLSession delivers them.** Iterating
/// `URLSession.AsyncBytes` one byte at a time peaked at 32 MB/s with a core
/// pegged — the loop, not the connection, set the speed — and it held back
/// anything under 64KB, so a server that sent a little and stalled delivered
/// nothing until the timeout.
public struct URLSessionChunkTransport: ChunkTransport {
    public static let requestTimeout: TimeInterval = 30
    public static let resourceTimeout: TimeInterval = 600

    private let session: URLSession
    private let router: TransferRouter

    /// `protocolClasses` is for tests: a stubbed `URLProtocol` in place of
    /// the network.
    public init(protocolClasses: [AnyClass] = []) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.resourceTimeout
        if !protocolClasses.isEmpty { configuration.protocolClasses = protocolClasses }
        let router = TransferRouter()
        self.router = router
        self.session = URLSession(configuration: configuration, delegate: router,
                                  delegateQueue: nil)
    }

    /// Returns once the server has answered with a success status, so an error
    /// page never reaches a partial file.
    public func chunks(from url: URL) async throws -> AsyncThrowingStream<Data, any Error> {
        let (stream, chunks) = AsyncThrowingStream<Data, any Error>.makeStream()
        let task = session.dataTask(with: url)
        chunks.onTermination = { _ in task.cancel() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { response in
                router.register(Transfer(response: response, chunks: chunks), for: task)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
        return stream
    }
}

/// One transfer's two ends: the caller waiting for a status, and the stream.
final class Transfer: Sendable {
    private let response: Mutex<CheckedContinuation<Void, any Error>?>
    let chunks: AsyncThrowingStream<Data, any Error>.Continuation

    init(response: CheckedContinuation<Void, any Error>,
         chunks: AsyncThrowingStream<Data, any Error>.Continuation) {
        self.response = Mutex(response)
        self.chunks = chunks
    }

    func accept() {
        response.withLock { $0.take() }?.resume()
    }

    /// Safe to call more than once: the first failure is the one reported.
    func fail(_ error: any Error) {
        response.withLock { $0.take() }?.resume(throwing: error)
        chunks.finish(throwing: error)
    }
}

/// The session's delegate, routing callbacks to the transfer they belong to.
final class TransferRouter: NSObject, URLSessionDataDelegate, Sendable {
    private let transfers = Mutex<[Int: Transfer]>([:])

    func register(_ transfer: Transfer, for task: URLSessionTask) {
        transfers.withLock { $0[task.taskIdentifier] = transfer }
    }

    private func transfer(for task: URLSessionTask) -> Transfer? {
        transfers.withLock { $0[task.taskIdentifier] }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        guard let transfer = transfer(for: dataTask) else { return .cancel }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            transfer.fail(FlickrError.transport("The photo server answered HTTP \(http.statusCode)."))
            return .cancel
        }
        transfer.accept()
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        transfer(for: dataTask)?.chunks.yield(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: (any Error)?) {
        guard let transfer = transfers.withLock({ $0.removeValue(forKey: task.taskIdentifier) })
        else { return }
        if let error {
            transfer.fail(error)
        } else {
            transfer.accept()
            transfer.chunks.finish()
        }
    }
}
