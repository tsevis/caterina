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
        // A signature Flickr rejects throws, so the assertion that matters is
        // that this returns at all. `page.total >= 0` is not an assertion —
        // the decoder clamps it — so it says nothing and is not made.
        let page = try await client().photos(
            PhotoRequest(query: .search(text: "blue sky & sea"), perPage: 3))
        #expect(page.perPage > 0)
        #expect(page.photos.allSatisfy { !$0.id.isEmpty })
    }

    /// Flickr answers `stat=ok` for a licence id it does not know, so asking
    /// for all of them and checking the replies proves nothing on its own. What
    /// it does catch is the opposite direction: a photo coming back under a
    /// licence id this build has never heard of, which means Flickr has added
    /// one and `License` is out of date.
    @Test func flickrHasNotAddedALicenceThisBuildCannotName() async throws {
        let page = try await client().photos(PhotoRequest(
            query: .search(text: "sunset"),
            filters: SearchFilters(licenses: Set(License.allCases)), perPage: 25))
        #expect(!page.photos.isEmpty)
        #expect(page.photos.allSatisfy { $0.license != nil })
        #expect(page.skippedEntries == 0)
    }

    /// Narrowing the licence filter has to narrow the results. If Flickr ever
    /// starts ignoring the parameter, this is where it shows.
    @Test func aSingleLicenceFilterComesBackAsThatLicence() async throws {
        let page = try await client().photos(PhotoRequest(
            query: .search(text: "mountain"),
            filters: SearchFilters(licenses: [.publicDomainMark]), perPage: 25))
        #expect(page.photos.allSatisfy { $0.license == .publicDomainMark })
    }

    @Test func aGroupResolvesByItsExactName() async throws {
        let group = try await client().resolveGroup(from: "Black and White")
        #expect(!group.nsid.isEmpty)
    }
}
