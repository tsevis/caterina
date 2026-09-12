import Foundation
import Testing

@testable import FlickrKit

/// OAuth signing is RFC 5849, not form encoding.
///
/// Verified against the live API: a `+` where a `%20` belongs comes back
/// HTTP 401 `oauth_problem=signature_invalid`. The expectations below are not
/// remembered from the RFC — the RFC's own worked example carries a known
/// erratum in its signature — but generated from `oauthlib` 3.2.2, an
/// independent implementation, and pasted here verbatim.
@Suite struct OAuth1Tests {

    // MARK: - The encoder

    @Test func spaceEncodesAsPercentTwentyNeverAsPlus() {
        #expect(OAuth1.percentEncode("r b") == "r%20b")
        #expect(!OAuth1.percentEncode("r b").contains("+"))
    }

    @Test func plusIsItselfEncoded() {
        // A literal `+` in a tag must survive as data, not arrive as a space.
        #expect(OAuth1.percentEncode("a+b") == "a%2Bb")
    }

    @Test func unreservedSetIsExactlyTheRFCs() {
        let unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        #expect(OAuth1.percentEncode(unreserved) == unreserved)
    }

    @Test func everythingOutsideTheUnreservedSetIsEncodedUppercase() {
        #expect(OAuth1.percentEncode("=%3D") == "%3D%253D")
        #expect(OAuth1.percentEncode("c@") == "c%40")
        #expect(OAuth1.percentEncode("blue sky & sea") == "blue%20sky%20%26%20sea")
        #expect(OAuth1.percentEncode("0,4,9") == "0%2C4%2C9")
    }

    @Test func nonASCIIIsEncodedAsUTF8Bytes() {
        #expect(OAuth1.percentEncode("ünïcode ~ test") == "%C3%BCn%C3%AFcode%20~%20test")
    }

    // MARK: - The base string

    /// RFC 5849 §3.4.1.1, including its duplicate `a3` key — which is why the
    /// builder takes ordered pairs rather than a dictionary.
    @Test func baseStringMatchesTheRFCWorkedExample() throws {
        let parameters = [
            OAuthParameter(name: "b5", value: "=%3D"),
            OAuthParameter(name: "a3", value: "a"),
            OAuthParameter(name: "c@", value: ""),
            OAuthParameter(name: "a2", value: "r b"),
            OAuthParameter(name: "oauth_consumer_key", value: "9djdj82h48djs9d2"),
            OAuthParameter(name: "oauth_token", value: "kkk9d7dh3k39sjv7"),
            OAuthParameter(name: "oauth_signature_method", value: "HMAC-SHA1"),
            OAuthParameter(name: "oauth_timestamp", value: "137131201"),
            OAuthParameter(name: "oauth_nonce", value: "7d8f3e4a"),
            OAuthParameter(name: "c2", value: ""),
            OAuthParameter(name: "a3", value: "2 q"),
        ]

        let base = try OAuth1.signatureBaseString(
            method: "POST", url: "http://example.com/request", parameters: parameters)

        #expect(base == "POST&http%3A%2F%2Fexample.com%2Frequest&a2%3Dr%2520b%26a3%3D2%2520q%26a3%3Da%26b5%3D%253D%25253D%26c%2540%3D%26c2%3D%26oauth_consumer_key%3D9djdj82h48djs9d2%26oauth_nonce%3D7d8f3e4a%26oauth_signature_method%3DHMAC-SHA1%26oauth_timestamp%3D137131201%26oauth_token%3Dkkk9d7dh3k39sjv7")
    }

    @Test func rfcExampleSignsToTheIndependentlyComputedValue() throws {
        let base = "POST&http%3A%2F%2Fexample.com%2Frequest&a2%3Dr%2520b%26a3%3D2%2520q%26a3%3Da%26b5%3D%253D%25253D%26c%2540%3D%26c2%3D%26oauth_consumer_key%3D9djdj82h48djs9d2%26oauth_nonce%3D7d8f3e4a%26oauth_signature_method%3DHMAC-SHA1%26oauth_timestamp%3D137131201%26oauth_token%3Dkkk9d7dh3k39sjv7"

        let signature = OAuth1.signature(
            baseString: base, consumerSecret: "j49sk3j29djd", tokenSecret: "dh893hdasih9")

        #expect(signature == "r6/TJjbCOr97/+UU0NsvSne7s5g=")
    }

    /// The shape this application actually sends: a Flickr REST call carrying a
    /// space, an ampersand, a literal `+`, a comma, a tilde and non-ASCII.
    @Test func flickrShapedCallMatchesTheIndependentImplementation() throws {
        let parameters = [
            OAuthParameter(name: "method", value: "flickr.photos.search"),
            OAuthParameter(name: "text", value: "blue sky & sea"),
            OAuthParameter(name: "sort", value: "date-posted-desc"),
            OAuthParameter(name: "license", value: "0,4,9"),
            OAuthParameter(name: "tags", value: "a+b"),
            OAuthParameter(name: "machine_tags", value: "ünïcode ~ test"),
            OAuthParameter(name: "oauth_consumer_key", value: "abc123"),
            OAuthParameter(name: "oauth_nonce", value: "0123456789abcdef"),
            OAuthParameter(name: "oauth_signature_method", value: "HMAC-SHA1"),
            OAuthParameter(name: "oauth_timestamp", value: "1700000000"),
            OAuthParameter(name: "oauth_token", value: "72157600000000000-aaaaaaaaaaaaaaaa"),
            OAuthParameter(name: "oauth_version", value: "1.0"),
        ]

        let base = try OAuth1.signatureBaseString(
            method: "GET", url: "https://api.flickr.com/services/rest/", parameters: parameters)

        #expect(base == "GET&https%3A%2F%2Fapi.flickr.com%2Fservices%2Frest%2F&license%3D0%252C4%252C9%26machine_tags%3D%25C3%25BCn%25C3%25AFcode%2520~%2520test%26method%3Dflickr.photos.search%26oauth_consumer_key%3Dabc123%26oauth_nonce%3D0123456789abcdef%26oauth_signature_method%3DHMAC-SHA1%26oauth_timestamp%3D1700000000%26oauth_token%3D72157600000000000-aaaaaaaaaaaaaaaa%26oauth_version%3D1.0%26sort%3Ddate-posted-desc%26tags%3Da%252Bb%26text%3Dblue%2520sky%2520%2526%2520sea")

        let signature = OAuth1.signature(
            baseString: base, consumerSecret: "s3cr3t", tokenSecret: "t0k3ns3cr3t")
        #expect(signature == "IrWuIKvi4YwCPGZ2CXuxAllMLDg=")
    }

    // MARK: - Sorting and normalisation

    @Test func parametersSortByEncodedKeyThenEncodedValue() throws {
        // `c%40` sorts before `c2` because `%` (0x25) precedes `2` (0x32) —
        // sorting the raw keys would put them the other way round.
        let base = try OAuth1.signatureBaseString(
            method: "GET", url: "https://example.com/",
            parameters: [OAuthParameter(name: "c2", value: ""),
                         OAuthParameter(name: "c@", value: "")])
        #expect(base.hasSuffix("c%2540%3D%26c2%3D"))
    }

    @Test func baseStringURIDropsQueryAndDefaultPortAndLowercasesHost() throws {
        let base = try OAuth1.signatureBaseString(
            method: "get", url: "HTTPS://API.Flickr.com:443/services/rest/?already=here",
            parameters: [OAuthParameter(name: "a", value: "1")])
        #expect(base == "GET&https%3A%2F%2Fapi.flickr.com%2Fservices%2Frest%2F&a%3D1")
    }

    @Test func aNonDefaultPortIsKept() throws {
        let base = try OAuth1.signatureBaseString(
            method: "GET", url: "https://example.com:8443/x",
            parameters: [OAuthParameter(name: "a", value: "1")])
        #expect(base == "GET&https%3A%2F%2Fexample.com%3A8443%2Fx&a%3D1")
    }

    @Test func anUnusableURLIsAnErrorNotACrash() {
        #expect(throws: OAuth1.SigningError.self) {
            try OAuth1.signatureBaseString(method: "GET", url: "not a url", parameters: [])
        }
    }

    // MARK: - Signing a whole request

    @Test func signingWithoutATokenSecretUsesATrailingAmpersandKey() {
        // The request-token step has no token secret yet; the key is still
        // `consumerSecret&`, never a bare `consumerSecret`.
        let withNil = OAuth1.signature(baseString: "x", consumerSecret: "s", tokenSecret: nil)
        let withEmpty = OAuth1.signature(baseString: "x", consumerSecret: "s", tokenSecret: "")
        #expect(withNil == withEmpty)
    }

    @Test func signedParametersCarryEveryMandatoryOAuthField() throws {
        let credentials = OAuth1.Credentials(
            consumerKey: "key", consumerSecret: "secret",
            token: "tok", tokenSecret: "toksecret")

        let signed = try OAuth1.signedParameters(
            method: "GET", url: "https://api.flickr.com/services/rest/",
            parameters: [OAuthParameter(name: "method", value: "flickr.test.login")],
            credentials: credentials,
            nonce: "nonce123", timestamp: 1_700_000_000)

        let names = Set(signed.map(\.name))
        #expect(names.isSuperset(of: ["oauth_consumer_key", "oauth_nonce",
                                      "oauth_signature_method", "oauth_timestamp",
                                      "oauth_version", "oauth_token", "oauth_signature"]))
        #expect(signed.first { $0.name == "oauth_signature_method" }?.value == "HMAC-SHA1")
        #expect(signed.first { $0.name == "oauth_version" }?.value == "1.0")
    }

    @Test func anUnauthenticatedCredentialCarriesNoTokenField() throws {
        let credentials = OAuth1.Credentials(consumerKey: "key", consumerSecret: "secret")
        let signed = try OAuth1.signedParameters(
            method: "GET", url: "https://api.flickr.com/services/rest/",
            parameters: [], credentials: credentials,
            nonce: "n", timestamp: 1)
        #expect(!signed.contains { $0.name == "oauth_token" })
    }

    /// The query string that goes on the wire must use the same encoder as the
    /// signature. Handing the parameters to `URLComponents` re-encodes them by
    /// its own rules and the signature stops matching.
    @Test func signedQueryStringUsesTheSameEncoderAsTheSignature() throws {
        let credentials = OAuth1.Credentials(consumerKey: "key", consumerSecret: "secret")
        let url = try OAuth1.signedURL(
            method: "GET", url: "https://api.flickr.com/services/rest/",
            parameters: [OAuthParameter(name: "text", value: "blue sky & sea")],
            credentials: credentials, nonce: "n", timestamp: 1)

        let query = try #require(url.query)
        #expect(query.contains("text=blue%20sky%20%26%20sea"))
        #expect(!query.contains("+"))
    }
}
