import Foundation

/// The three-legged OAuth exchange, as URLs and parsers.
///
/// Only the browser step needs a window, so everything here stays in FlickrKit
/// and stays testable: the URLs that go out and the bodies that come back are
/// the part that can be wrong.
public enum OAuthFlow {
    public static let requestTokenEndpoint =
        "https://www.flickr.com/services/oauth/request_token"
    public static let authorizeEndpoint =
        "https://www.flickr.com/services/oauth/authorize"
    public static let accessTokenEndpoint =
        "https://www.flickr.com/services/oauth/access_token"

    /// The scheme registered on the Flickr app record.
    public static let callbackScheme = "caterina"
    public static let callbackURL = "\(callbackScheme)://auth"

    public struct TemporaryToken: Sendable, Equatable {
        public let token: String
        public let secret: String

        public init(token: String, secret: String) {
            self.token = token
            self.secret = secret
        }
    }

    public struct Account: Sendable, Equatable {
        public let token: String
        public let tokenSecret: String
        public let nsid: String
        public let username: String
        /// What was asked for on the authorisation page. Flickr's reply does
        /// not repeat it.
        public let permission: FlickrPermission

        public init(token: String, tokenSecret: String, nsid: String, username: String,
                    permission: FlickrPermission = .read) {
            self.token = token
            self.tokenSecret = tokenSecret
            self.nsid = nsid
            self.username = username
            self.permission = permission
        }
    }

    // MARK: - Step one

    public static func requestTokenURL(credentials: OAuth1.Credentials,
                                       callback: String = callbackURL) throws -> URL {
        try OAuth1.signedURL(
            method: "GET", url: requestTokenEndpoint,
            parameters: [OAuthParameter(name: "oauth_callback", value: callback)],
            credentials: credentials)
    }

    public static func temporaryToken(from body: String) throws -> TemporaryToken {
        let fields = formEncoded(body)
        if let problem = fields["oauth_problem"] { throw problemError(problem) }
        guard let token = fields["oauth_token"], !token.isEmpty,
              let secret = fields["oauth_token_secret"], !secret.isEmpty
        else {
            throw FlickrError.invalidInput(
                "Flickr did not start the sign-in. Check the API key and secret in Settings.")
        }
        return TemporaryToken(token: token, secret: secret)
    }

    // MARK: - Step two

    /// Flickr's approval page, asking for `permission` and nothing more.
    public static func authorizationURL(token: String,
                                        permission: FlickrPermission = .read) throws -> URL {
        guard let url = URL(string: "\(authorizeEndpoint)?oauth_token=\(token)&perms=\(permission.rawValue)")
        else { throw FlickrError.invalidInput("Could not build the Flickr sign-in address.") }
        return url
    }

    /// The verifier from the callback, checked against the token we asked for.
    ///
    /// The callback is opened by a browser and everything in it is
    /// attacker-influenced: a callback naming a *different* request token is
    /// someone else's sign-in being handed to this application, and exchanging
    /// it would attach their account to this window.
    public static func verifier(from url: URL, expecting token: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let fields = Dictionary(items.map { ($0.name, $0.value ?? "") },
                                uniquingKeysWith: { first, _ in first })

        if let problem = fields["oauth_problem"] { throw problemError(problem) }
        guard fields["oauth_token"] == token else {
            throw FlickrError.invalidInput(
                "That sign-in did not match the one this window started. Try again.")
        }
        guard let verifier = fields["oauth_verifier"], !verifier.isEmpty else {
            throw FlickrError.invalidInput("Flickr did not return a sign-in confirmation.")
        }
        return verifier
    }

    // MARK: - Step three

    public static func accessTokenURL(credentials: OAuth1.Credentials,
                                      temporary: TemporaryToken,
                                      verifier: String) throws -> URL {
        try OAuth1.signedURL(
            method: "GET", url: accessTokenEndpoint,
            parameters: [OAuthParameter(name: "oauth_verifier", value: verifier)],
            credentials: credentials.authenticated(token: temporary.token,
                                                   tokenSecret: temporary.secret))
    }

    public static func account(from body: String,
                               permission: FlickrPermission = .read) throws -> Account {
        let fields = formEncoded(body)
        if let problem = fields["oauth_problem"] { throw problemError(problem) }
        guard let token = fields["oauth_token"], !token.isEmpty,
              let secret = fields["oauth_token_secret"], !secret.isEmpty
        else {
            throw FlickrError.invalidInput("Flickr did not complete the sign-in. Try again.")
        }
        return Account(token: token, tokenSecret: secret,
                       nsid: fields["user_nsid"] ?? "",
                       username: fields["username"] ?? "",
                       permission: permission)
    }

    // MARK: - Reading what came back

    /// These endpoints answer `application/x-www-form-urlencoded`, not JSON.
    static func formEncoded(_ body: String) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard let name = parts.first.map(String.init) else { continue }
            let raw = parts.count > 1 ? String(parts[1]) : ""
            fields[name] = raw.replacingOccurrences(of: "+", with: " ")
                .removingPercentEncoding ?? raw
        }
        return fields
    }

    private static func problemError(_ problem: String) -> FlickrError {
        switch problem {
        case "consumer_key_unknown", "consumer_key_rejected":
            return .invalidInput(
                "Flickr does not recognise this API key. Check it in Settings.")
        case "signature_invalid":
            return .invalidInput(
                "Flickr rejected the signature. Check the API secret in Settings.")
        case "user_refused":
            return .invalidInput("Sign-in was cancelled.")
        default:
            return .invalidInput("Flickr refused the sign-in: \(problem).")
        }
    }
}
