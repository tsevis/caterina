import CryptoKit
import Foundation

/// One parameter of a signed request.
///
/// Ordered pairs rather than a dictionary because RFC 5849 allows a key to
/// repeat, and because the signature depends on the exact set of pairs — a
/// dictionary would silently drop the second `a3` and produce a signature for
/// a request that was never sent.
public struct OAuthParameter: Sendable, Equatable, Hashable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// OAuth 1.0a request signing, HMAC-SHA1, per RFC 5849.
///
/// **This is not form encoding.** `URLComponents` and
/// `addingPercentEncoding(withAllowedCharacters:)` both have their own ideas
/// about which characters are safe, and neither matches §3.6: a space that
/// arrives as `+` is answered by Flickr with HTTP 401
/// `oauth_problem=signature_invalid`, which looks like a credentials problem
/// and is not one. The unreserved set is therefore written out here rather
/// than borrowed, and the same encoder builds both the signature and the query
/// string that goes on the wire.
public enum OAuth1 {

    public enum SigningError: Error, Equatable {
        case unusableURL(String)
    }

    /// Consumer credentials, and the token pair once there is one.
    ///
    /// The request-token step has no token yet, so both token fields are
    /// optional; `token == nil` is what makes `oauth_token` absent rather than
    /// present and empty, which Flickr rejects.
    public struct Credentials: Sendable, Equatable {
        public let consumerKey: String
        public let consumerSecret: String
        public let token: String?
        public let tokenSecret: String?

        public init(consumerKey: String, consumerSecret: String,
                    token: String? = nil, tokenSecret: String? = nil) {
            self.consumerKey = consumerKey
            self.consumerSecret = consumerSecret
            self.token = token
            self.tokenSecret = tokenSecret
        }

        /// The same credentials with a token pair attached.
        public func authenticated(token: String, tokenSecret: String) -> Credentials {
            Credentials(consumerKey: consumerKey, consumerSecret: consumerSecret,
                        token: token, tokenSecret: tokenSecret)
        }
    }

    // MARK: - Encoding

    /// RFC 3986 unreserved characters — the *only* bytes left literal.
    private static let unreserved: Set<UInt8> = {
        var allowed = Set<UInt8>()
        for byte in UInt8(ascii: "A")...UInt8(ascii: "Z") { allowed.insert(byte) }
        for byte in UInt8(ascii: "a")...UInt8(ascii: "z") { allowed.insert(byte) }
        for byte in UInt8(ascii: "0")...UInt8(ascii: "9") { allowed.insert(byte) }
        for scalar in "-._~".unicodeScalars { allowed.insert(UInt8(ascii: scalar)) }
        return allowed
    }()

    private static let hexDigits: [Character] = Array("0123456789ABCDEF")

    /// Percent-encode per RFC 5849 §3.6: UTF-8 bytes, uppercase hex, space as
    /// `%20`, and `-._~` left alone.
    public static func percentEncode(_ value: String) -> String {
        var encoded = ""
        encoded.reserveCapacity(value.utf8.count)
        for byte in value.utf8 {
            if unreserved.contains(byte) {
                encoded.append(Character(UnicodeScalar(byte)))
            } else {
                encoded.append("%")
                encoded.append(hexDigits[Int(byte >> 4)])
                encoded.append(hexDigits[Int(byte & 0x0F)])
            }
        }
        return encoded
    }

    // MARK: - The base string

    /// The base string URI, §3.4.1.2: scheme and host lowercased, the default
    /// port for the scheme removed, query and fragment dropped.
    static func baseStringURI(_ url: String) throws -> String {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty
        else { throw SigningError.unusableURL(url) }

        let defaultPort: Int?
        switch scheme {
        case "https": defaultPort = 443
        case "http": defaultPort = 80
        default: defaultPort = nil
        }
        var port = ""
        if let given = components.port, given != defaultPort {
            port = ":" + String(given)
        }
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        return "\(scheme)://\(host)\(port)\(path)"
    }

    /// The signature base string, §3.4.1.1.
    ///
    /// Parameters sort by *encoded* key and then by encoded value — sorting the
    /// raw text puts `c2` before `c@`, where the encoded forms put `c%40`
    /// first, because `%` precedes `2`.
    public static func signatureBaseString(method: String, url: String,
                                           parameters: [OAuthParameter]) throws -> String {
        let encoded: [OAuthParameter] = parameters.map {
            OAuthParameter(name: percentEncode($0.name), value: percentEncode($0.value))
        }
        let ordered: [OAuthParameter] = encoded.sorted { left, right in
            left.name == right.name ? left.value < right.value : left.name < right.name
        }
        let pairs: [String] = ordered.map { $0.name + "=" + $0.value }
        let normalised: String = pairs.joined(separator: "&")

        let uri: String = try baseStringURI(url)
        return method.uppercased() + "&" + percentEncode(uri) + "&" + percentEncode(normalised)
    }

    // MARK: - Signing

    /// HMAC-SHA1 over the base string, §3.4.2.
    ///
    /// The key is always `consumerSecret&tokenSecret` — the ampersand is there
    /// even when there is no token secret yet.
    public static func signature(baseString: String, consumerSecret: String,
                                 tokenSecret: String?) -> String {
        let key = "\(percentEncode(consumerSecret))&\(percentEncode(tokenSecret ?? ""))"
        let mac = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(baseString.utf8), using: SymmetricKey(data: Data(key.utf8)))
        return Data(mac).base64EncodedString()
    }

    /// `parameters` plus every mandatory OAuth field and the signature over all
    /// of them.
    public static func signedParameters(method: String, url: String,
                                        parameters: [OAuthParameter],
                                        credentials: Credentials,
                                        nonce: String = Self.nonce(),
                                        timestamp: Int = Int(Date().timeIntervalSince1970)
    ) throws -> [OAuthParameter] {
        var all = parameters
        all.append(OAuthParameter(name: "oauth_consumer_key", value: credentials.consumerKey))
        all.append(OAuthParameter(name: "oauth_nonce", value: nonce))
        all.append(OAuthParameter(name: "oauth_signature_method", value: "HMAC-SHA1"))
        all.append(OAuthParameter(name: "oauth_timestamp", value: String(timestamp)))
        all.append(OAuthParameter(name: "oauth_version", value: "1.0"))
        if let token = credentials.token {
            all.append(OAuthParameter(name: "oauth_token", value: token))
        }

        let base = try signatureBaseString(method: method, url: url, parameters: all)
        all.append(OAuthParameter(
            name: "oauth_signature",
            value: signature(baseString: base,
                             consumerSecret: credentials.consumerSecret,
                             tokenSecret: credentials.tokenSecret)))
        return all
    }

    /// The signed request as a URL.
    ///
    /// The query is assembled with `percentEncode` rather than handed to
    /// `URLComponents`, which would re-encode the values by its own rules and
    /// leave the signature describing a different request than the one sent.
    public static func signedURL(method: String, url: String,
                                 parameters: [OAuthParameter],
                                 credentials: Credentials,
                                 nonce: String = Self.nonce(),
                                 timestamp: Int = Int(Date().timeIntervalSince1970)
    ) throws -> URL {
        let signed = try signedParameters(method: method, url: url, parameters: parameters,
                                          credentials: credentials,
                                          nonce: nonce, timestamp: timestamp)
        let query = signed
            .map { "\(percentEncode($0.name))=\(percentEncode($0.value))" }
            .joined(separator: "&")

        guard let base = URL(string: try baseStringURI(url)),
              let result = URL(string: "\(base.absoluteString)?\(query)")
        else { throw SigningError.unusableURL(url) }
        return result
    }

    /// A fresh nonce. 16 random bytes, hex — long enough that Flickr never sees
    /// the same one twice within a timestamp.
    public static func nonce() -> String {
        (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}
