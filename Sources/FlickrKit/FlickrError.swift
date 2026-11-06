import Foundation

/// Everything that can go wrong between asking Flickr for photos and having
/// them.
///
/// `transient` is the distinction the user actually cares about: "Flickr is
/// busy, this usually clears" is not the same message as "that group does not
/// exist", and the reference application got complaints for showing the second
/// when it meant the first.
public enum FlickrError: Error, Equatable, Sendable {
    /// Flickr answered `stat=fail`.
    case api(code: Int, message: String, transient: Bool)
    /// Flickr answered something this build cannot read.
    case malformedResponse(String)
    /// The request never completed — no network, timeout, TLS.
    case transport(String)
    /// The user asked for something that cannot be turned into a request.
    case invalidInput(String)
    /// The request was well formed and the thing is not there.
    case notFound(String)
    /// Retries were exhausted while Flickr was still failing transiently.
    case busy(String)
    /// The signed-in account has not allowed this yet. The fix is a trip to
    /// Flickr's approval page, not a retry.
    case permissionNeeded(FlickrPermission)
    /// HTTP 401: Flickr would not accept this token, for the reason it gave.
    /// Nothing was done, so whatever was being sent is safe to send again.
    case signInRejected(String)

    /// Flickr codes that mean "try again", not "you asked for something wrong".
    ///
    /// Measured against the live API: a single request fails around a third of
    /// the time during a blip, and the same request usually succeeds moments
    /// later.
    public static let transientCodes: Set<Int> = [105, 106, 111, 112, 201]

    /// Whether a new token can cure this `oauth_problem`. Anything else would
    /// bring the approval page straight back, however often it was approved.
    public static func isTokenProblem(_ problem: String) -> Bool {
        problem.hasPrefix("token_")
    }

    /// Only a token problem is cured by signing in again, so only that says so.
    private static func rejection(_ problem: String) -> String {
        if isTokenProblem(problem) {
            return "Flickr did not accept this sign-in (\(problem)). Sign in again in Settings."
        }
        if problem == "timestamp_refused" {
            return "Flickr refused the request because this Mac's clock looks wrong. Check the date and time."
        }
        return problem.isEmpty ? "Flickr refused the request (HTTP 401)." : "Flickr refused the request (\(problem))."
    }

    public var isTransient: Bool {
        switch self {
        case let .api(_, _, transient): return transient
        case .transport, .busy: return true
        case .malformedResponse, .invalidInput, .notFound, .permissionNeeded, .signInRejected: return false
        }
    }

    /// What to put in front of the user.
    public var message: String {
        switch self {
        case let .api(_, message, _): return message
        case let .malformedResponse(detail): return detail
        case let .transport(detail): return detail
        case let .invalidInput(detail): return detail
        case let .notFound(detail): return detail
        case let .busy(detail): return detail
        case let .permissionNeeded(permission): return permission.reason
        case let .signInRejected(problem): return Self.rejection(problem)
        }
    }
}
