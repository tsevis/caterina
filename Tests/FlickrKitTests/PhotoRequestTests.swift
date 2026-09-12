import Foundation
import Testing

@testable import FlickrKit

/// The outgoing query is the only place a wrong parameter can be caught.
///
/// Flickr answers `stat=ok` for a `sort` it does not recognise and ignores
/// filters the chosen method does not support, so asserting on the response
/// proves nothing. Every expectation here is on what goes out.
@Suite struct PhotoRequestTests {

    private func parameters(_ request: PhotoRequest) -> [String: String] {
        Dictionary(request.parameters().map { ($0.name, $0.value) },
                   uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Methods

    @Test func aTextSearchUsesPhotosSearch() {
        let sent = parameters(PhotoRequest(query: .search(text: "harbour")))
        #expect(sent["method"] == "flickr.photos.search")
        #expect(sent["text"] == "harbour")
    }

    @Test func aUsersPhotosUsePeopleGetPhotos() {
        let sent = parameters(PhotoRequest(query: .userPhotos(userID: "12345@N00")))
        #expect(sent["method"] == "flickr.people.getPhotos")
        #expect(sent["user_id"] == "12345@N00")
    }

    @Test func theSignedInUsersPhotosAskForMe() {
        let sent = parameters(PhotoRequest(query: .myPhotos))
        #expect(sent["method"] == "flickr.people.getPhotos")
        #expect(sent["user_id"] == "me")
    }

    @Test func aGroupPoolUsesPoolsGetPhotos() {
        let sent = parameters(PhotoRequest(query: .groupPool(groupID: "99@N01")))
        #expect(sent["method"] == "flickr.groups.pools.getPhotos")
        #expect(sent["group_id"] == "99@N01")
        #expect(sent["text"] == nil)
    }

    @Test func searchingInsideAGroupUsesPhotosSearchWithAGroupID() {
        let sent = parameters(PhotoRequest(
            query: .groupSearch(groupID: "99@N01", text: "boats")))
        #expect(sent["method"] == "flickr.photos.search")
        #expect(sent["group_id"] == "99@N01")
        #expect(sent["text"] == "boats")
    }

    // MARK: - Which queries can be filtered

    /// `flickr.groups.pools.getPhotos` and `flickr.people.getPhotos` accept
    /// none of the Search Settings filters. Sending them anyway made the
    /// interface claim a filter was applied when Flickr had ignored it.
    @Test func filtersAreOmittedByTheMethodsThatCannotHonourThem() {
        let filters = SearchFilters(licenses: [.by], sizes: [.large],
                                    sort: .interestingnessDescending, colors: [.red])
        for query in [PhotoQuery.groupPool(groupID: "9@N1"),
                      .userPhotos(userID: "1@N1"), .myPhotos] {
            let request = PhotoRequest(query: query, filters: filters)
            #expect(!request.supportsFilters)
            let sent = parameters(request)
            #expect(sent["license"] == nil)
            #expect(sent["sort"] == nil)
            #expect(sent["color_codes"] == nil)
        }
    }

    @Test func filtersAreSentByTheMethodsThatDoHonourThem() {
        let filters = SearchFilters(licenses: [.allRightsReserved, .by],
                                    sort: .dateTakenAscending, colors: [.blue])
        for query in [PhotoQuery.search(text: "x"),
                      .groupSearch(groupID: "9@N1", text: "x")] {
            let request = PhotoRequest(query: query, filters: filters)
            #expect(request.supportsFilters)
            let sent = parameters(request)
            #expect(sent["license"] == "0,4")
            #expect(sent["sort"] == "date-taken-asc")
            #expect(sent["color_codes"] == "4")
        }
    }

    /// The size filter has no Flickr parameter at all — it is applied to the
    /// results. Sending one would be inventing an API.
    @Test func theSizeFilterIsNeverSentAsAParameter() {
        let request = PhotoRequest(query: .search(text: "x"),
                                   filters: SearchFilters(sizes: [.large]))
        #expect(parameters(request)["size"] == nil)
        #expect(!request.parameters().contains { $0.name.contains("size") })
    }

    @Test func anUnsetFilterIsAbsentRatherThanEmpty() {
        let sent = parameters(PhotoRequest(query: .search(text: "x")))
        #expect(sent["license"] == nil)
        #expect(sent["color_codes"] == nil)
        // Sort is never unset; relevance is a real choice.
        #expect(sent["sort"] == "relevance")
    }

    // MARK: - Paging and extras

    @Test func everyRequestAsksForEveryVariantAndTheLicence() {
        for query in [PhotoQuery.search(text: "x"), .myPhotos,
                      .groupPool(groupID: "9@N1")] {
            let extras = parameters(PhotoRequest(query: query))["extras"]
            #expect(extras == PhotoVariant.extrasParameter)
        }
    }

    @Test func pagingDefaultsAreSane() {
        let sent = parameters(PhotoRequest(query: .search(text: "x")))
        #expect(sent["page"] == "1")
        #expect(sent["per_page"] == "25")
        #expect(sent["format"] == "json")
        #expect(sent["nojsoncallback"] == "1")
    }

    @Test func pagingIsCarriedThrough() {
        let sent = parameters(PhotoRequest(query: .search(text: "x"), page: 4, perPage: 100))
        #expect(sent["page"] == "4")
        #expect(sent["per_page"] == "100")
    }

    @Test func searchTextIsTrimmed() {
        #expect(parameters(PhotoRequest(query: .search(text: "  harbour  ")))["text"] == "harbour")
    }

    // MARK: - Which queries must be signed

    @Test func onlyTheSignedInUsersOwnPhotosRequireAToken() {
        #expect(PhotoRequest(query: .myPhotos).requiresAuthentication)
        #expect(!PhotoRequest(query: .search(text: "x")).requiresAuthentication)
        #expect(!PhotoRequest(query: .userPhotos(userID: "1@N1")).requiresAuthentication)
        #expect(!PhotoRequest(query: .groupPool(groupID: "9@N1")).requiresAuthentication)
    }
}
