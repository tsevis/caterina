import Foundation
import Testing

@testable import FlickrKit

/// The only tests here that touch the network, and they are opt-in.
///
/// A default `swift test` must be offline, headless and fast, so these run only
/// when a key is put in the environment on purpose:
///
/// ```
/// FLICKR_API_KEY=… FLICKR_API_SECRET=… swift test --filter LiveAPITests
/// ```
///
/// What they are for is the class of defect no fixture can catch: Flickr
/// changing a reply's shape, adding a licence, or rejecting a signature this
/// build believes in. `stat=ok` is never the assertion — the outgoing query is.
/// Kept outside the suite: a suite trait that reads a static of its own type is
/// a circular reference the macro cannot resolve.
enum LiveCredentials {
    static let value: OAuth1.Credentials? = {
        let environment = ProcessInfo.processInfo.environment
        guard let key = environment["FLICKR_API_KEY"], !key.isEmpty,
              let secret = environment["FLICKR_API_SECRET"], !secret.isEmpty
        else { return nil }
        return OAuth1.Credentials(consumerKey: key, consumerSecret: secret)
    }()
}

@Suite(.enabled(if: LiveCredentials.value != nil))
struct LiveAPITests {

    private func client() throws -> FlickrClient {
        FlickrClient(credentials: try #require(LiveCredentials.value))
    }

    @Test func aRealSearchComesBackAndDecodes() async throws {
        let page = try await client().photos(
            PhotoRequest(query: .search(text: "harbour"), perPage: 5))
        #expect(!page.photos.isEmpty)
        #expect(page.photos.allSatisfy { !$0.id.isEmpty })
        // Every photo should carry at least one variant, or `extras` is wrong.
        #expect(page.photos.allSatisfy { $0.thumbnailURL() != nil })
    }

    /// The signature, end to end. A `+` where a `%20` belongs comes back as
    /// HTTP 401 `oauth_problem=signature_invalid`, and this is the only place
    /// that can be observed.
    @Test func aSearchWithSpacesAndPunctuationSignsCorrectly() async throws {
        let page = try await client().photos(
            PhotoRequest(query: .search(text: "blue sky & sea"), perPage: 3))
        #expect(page.total >= 0)
    }

    @Test func everyLicenceThisBuildKnowsIsStillOneFlickrAccepts() async throws {
        let page = try await client().photos(PhotoRequest(
            query: .search(text: "sunset"),
            filters: SearchFilters(licenses: Set(License.allCases)), perPage: 5))
        #expect(page.photos.allSatisfy { $0.license != nil })
    }

    @Test func aGroupResolvesByItsExactName() async throws {
        let group = try await client().resolveGroup(from: "Black and White")
        #expect(!group.nsid.isEmpty)
    }
}
