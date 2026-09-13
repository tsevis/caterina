import Foundation

/// Waiting, injectable so tests do not actually wait.
public typealias Sleeper = @Sendable (Duration) async throws -> Void

/// Fetching bytes from a URL.
///
/// A protocol so the retry policy, the query construction and the decoding can
/// all be tested without a network — which is what keeps the test suite offline
/// and fast.
public protocol HTTPTransport: Sendable {
    func data(from url: URL) async throws -> Data
    /// A request that is not a plain GET — Flickr's write methods are POSTed.
    func send(_ request: URLRequest) async throws -> Data
    /// A request whose body is streamed from `file`, reporting bytes sent.
    func upload(_ request: URLRequest, fromFile file: URL,
                progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> Data
}

extension HTTPTransport {
    /// Transports that only read — most test doubles — refuse uploads plainly.
    public func upload(_ request: URLRequest, fromFile file: URL,
                       progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> Data {
        throw FlickrError.transport("This connection cannot upload files.")
    }
}

/// The real one.
///
/// **Every request carries a timeout.** A request without one hung the
/// reference application forever, with a spinner and no way out.
public struct URLSessionTransport: HTTPTransport {
    public static let requestTimeout: TimeInterval = 15
    public static let resourceTimeout: TimeInterval = 60
    /// An upload may take a long time in total, but not a long silence.
    public static let uploadIdleTimeout: TimeInterval = 60
    public static let uploadResourceTimeout: TimeInterval = 4 * 3600

    private let session: URLSession
    /// Separate, because a 60-second resource timeout ends any upload of a
    /// large photo on an ordinary connection.
    private let uploadSession: URLSession

    public init(session: URLSession? = nil) {
        let uploads = URLSessionConfiguration.ephemeral
        uploads.timeoutIntervalForRequest = Self.uploadIdleTimeout
        uploads.timeoutIntervalForResource = Self.uploadResourceTimeout
        uploads.waitsForConnectivity = false
        self.uploadSession = URLSession(configuration: uploads)
        if let session {
            self.session = session
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.resourceTimeout
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    public func data(from url: URL) async throws -> Data {
        try await send(URLRequest(url: url))
    }

    public func upload(_ request: URLRequest, fromFile file: URL,
                       progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> Data {
        do {
            let (data, response) = try await uploadSession.upload(
                for: request, fromFile: file, delegate: UploadProgress(report: progress))
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw FlickrError.transport("Flickr answered HTTP \(http.statusCode).")
            }
            return data
        } catch let error as FlickrError {
            throw error
        } catch {
            throw FlickrError.transport(error.localizedDescription)
        }
    }

    public func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw FlickrError.transport("Flickr answered HTTP \(http.statusCode).")
            }
            return data
        } catch let error as FlickrError {
            throw error
        } catch {
            throw FlickrError.transport(error.localizedDescription)
        }
    }
}

/// How hard to try before telling the user.
///
/// Measured against the live API: a single request fails around a third of the
/// time during a blip, and blips last a few seconds — so the budget spans
/// roughly five seconds rather than one.
public struct RetryPolicy: Sendable, Equatable {
    public let attempts: Int
    public let backoff: [Duration]

    public init(attempts: Int, backoff: [Duration]) {
        self.attempts = max(1, attempts)
        self.backoff = backoff
    }

    public static let standard = RetryPolicy(
        attempts: 4, backoff: [.milliseconds(500), .milliseconds(1500), .seconds(3)])

    func delay(afterAttempt index: Int) -> Duration {
        guard !backoff.isEmpty else { return .zero }
        return backoff[min(index, backoff.count - 1)]
    }
}

/// Bytes sent, per task.
private final class UploadProgress: NSObject, URLSessionTaskDelegate, Sendable {
    private let report: @Sendable (Int64, Int64) -> Void

    init(report: @escaping @Sendable (Int64, Int64) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        report(totalBytesSent, totalBytesExpectedToSend)
    }
}
