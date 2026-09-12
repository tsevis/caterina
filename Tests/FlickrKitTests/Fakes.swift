import Foundation

@testable import FlickrKit

/// A transport that answers from a script, and remembers what it was asked.
actor ScriptedTransport: HTTPTransport {
    enum Reply: Sendable {
        case body(String)
        case failure(FlickrError)
    }

    private var replies: [Reply]
    private(set) var requested: [URL] = []

    init(_ replies: [Reply]) { self.replies = replies }

    /// Convenience: the same body however many times it is asked for.
    init(always body: String) { self.replies = [.body(body)] }

    var callCount: Int { requested.count }

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
        let reply: Reply
        if replies.count > 1 {
            reply = replies.removeFirst()
        } else {
            reply = replies.first ?? .body(#"{"stat":"ok"}"#)
        }
        switch reply {
        case let .body(body): return Data(body.utf8)
        case let .failure(error): throw error
        }
    }
}

/// Records what the retry policy asked to wait for, without waiting.
final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Duration] = []

    var durations: [Duration] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    private func record(_ duration: Duration) {
        lock.lock(); defer { lock.unlock() }
        recorded.append(duration)
    }

    var sleep: Sleeper {
        { [self] duration in record(duration) }
    }
}

enum Fixtures {
    static func page(ids: [String], page: Int = 1, pages: Int = 1,
                     perPage: Int = 25, total: Int? = nil) -> String {
        let photos = ids.map {
            #"{"id":"\#($0)","title":"Photo \#($0)","url_o":"https://example.com/\#($0)_o.jpg","url_m":"https://example.com/\#($0)_m.jpg"}"#
        }.joined(separator: ",")
        return """
        {"photos":{"page":\(page),"pages":\(pages),"perpage":\(perPage),\
        "total":\(total ?? ids.count),"photo":[\(photos)]},"stat":"ok"}
        """
    }

    static func failure(code: Int, message: String = "Sorry, the Flickr API service is not currently available.") -> String {
        #"{"stat":"fail","code":\#(code),"message":"\#(message)"}"#
    }

    static let credentials = OAuth1.Credentials(
        consumerKey: "key", consumerSecret: "secret",
        token: "token", tokenSecret: "tokensecret")

    static let unauthenticated = OAuth1.Credentials(
        consumerKey: "key", consumerSecret: "secret")
}
