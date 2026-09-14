import Foundation
import Testing

@testable import FlickrKit

/// The shapes an account is organised into, and the photos inside each.
@Suite struct AccountListsTests {

    private func client(_ transport: ScriptedTransport) -> FlickrClient {
        FlickrClient(credentials: Fixtures.credentials, transport: transport, budget: .unspaced,
                     sleep: SleepRecorder().sleep)
    }

    private let photo = #"{"id":"1","owner":"9@N00","ownername":"someone","title":"A","url_q":"q","url_z":"z","views":"5"}"#

    // MARK: - Photo lists

    @Test(arguments: [
        (PhotoList.album(id: "72157001", ownerID: "9@N00"), "flickr.photosets.getPhotos", ["photoset_id": "72157001", "user_id": "9@N00"]),
        (PhotoList.groupPool(groupID: "34427469792@N01", contributorID: "9@N00"), "flickr.groups.pools.getPhotos", ["group_id": "34427469792@N01", "user_id": "9@N00"]),
        (PhotoList.gallery(id: "5704-72157622637971865"), "flickr.galleries.getPhotos", ["gallery_id": "5704-72157622637971865"]),
        (PhotoList.yourFaves, "flickr.favorites.getList", [:]),
        (PhotoList.photostream(userID: "12@N01"), "flickr.people.getPhotos", ["user_id": "12@N01"]),
        (PhotoList.photosOf(userID: "12@N01"), "flickr.people.getPhotosOf", ["user_id": "12@N01"]),
        (PhotoList.photosOfIn(userID: "12@N01", ownerID: "me@N00"), "flickr.people.getPhotosOf",
         ["user_id": "12@N01", "owner_id": "me@N00"]),
        (PhotoList.explore, "flickr.interestingness.getList", [:]),
        (PhotoList.notInAlbum, "flickr.photos.getNotInSet", [:]),
    ])
    func eachListAsksTheRightMethod(list: PhotoList, method: String, arguments: [String: String]) {
        let fields = Dictionary(uniqueKeysWithValues: list.parameters(page: 2).map { ($0.name, $0.value) })
        #expect(fields["method"] == method)
        #expect(fields["page"] == "2")
        #expect(fields["extras"]?.contains("url_z") == true)
        for (name, value) in arguments { #expect(fields[name] == value) }
    }

    /// Albums answer under `photoset`, everything else under `photos`.
    @Test func albumPhotosAreReadFromTheirOwnEnvelope() async throws {
        let transport = ScriptedTransport(always: """
        {"photoset":{"id":"4","primary":"2483","page":1,"perpage":500,"pages":"3","total":"1201","photo":[\(photo)]},"stat":"ok"}
        """)
        let page = try await client(transport).photoList(.album(id: "4", ownerID: "9@N00"), page: 1)
        #expect(page.photos.map(\.id) == ["1"])
        #expect(page.pages == 3)
        #expect(page.total == 1201)
        #expect(page.photos.first?.ownerName == "someone")
    }

    @Test func otherListsAreReadFromPhotos() async throws {
        let transport = ScriptedTransport(always: #"{"photos":{"page":1,"pages":1,"total":1,"photo":[\#(photo)]},"stat":"ok"}"#)
        let page = try await client(transport).photoList(.explore, page: 1)
        #expect(page.photos.first?.mediumURL == "z")
    }

    /// `people.getPhotosOf` has no page count, only whether more follow.
    @Test func aListThatOnlySaysMoreFollowsStillPages() throws {
        let data = Data(#"{"photos":{"page":2,"has_next_page":1,"perpage":10,"photo":[\#(photo)]},"stat":"ok"}"#.utf8)
        #expect(try LibraryResponse.page(from: data).pages == 3)
    }

    @Test func aListOfTheWrongShapeSaysSo() {
        #expect(throws: FlickrError.malformedResponse("Flickr sent the photos in an unexpected shape.")) {
            _ = try LibraryResponse.page(from: Data(#"{"photos":"nope","stat":"ok"}"#.utf8))
        }
    }

    @Test func everyPageOfGalleriesIsRead() async throws {
        let transport = ScriptedTransport([
            .body(#"{"galleries":{"page":1,"pages":2,"gallery":[{"id":"1","title":{"_content":"A"}}]},"stat":"ok"}"#),
            .body(#"{"galleries":{"page":2,"pages":2,"gallery":[{"id":"2","title":{"_content":"B"}}]},"stat":"ok"}"#),
        ])
        #expect(try await client(transport).galleries().map(\.id) == ["1", "2"])
    }

    // MARK: - Structures

    @Test func yourGroups() async throws {
        let transport = ScriptedTransport(always: """
        {"groups":{"group":[{"nsid":"17274427@N00","name":"Cream &amp; the Crop","admin":0,"members":"11935","pool_count":"12522"},
                             {"nsid":"20083316@N00","name":"Apple","members":11776,"pool_count":62438,"admin":1}]},"stat":"ok"}
        """)
        let groups = try await client(transport).groups(of: "9@N00")
        #expect(groups == [AccountGroup(id: "17274427@N00", name: "Cream & the Crop", members: 11_935, photos: 12_522, isAdmin: false),
                           AccountGroup(id: "20083316@N00", name: "Apple", members: 11_776, photos: 62_438, isAdmin: true)])
    }

    @Test func yourGalleries() async throws {
        let transport = ScriptedTransport(always: """
        {"galleries":{"total":9,"page":1,"pages":1,"gallery":[{"id":"5704-72157622637971865","owner":"9@N00",
          "count_photos":"16","count_videos":2,"title":{"_content":"Black & white"},"description":{"_content":"bw"},
          "primary_photo_id":"107391222"}]},"stat":"ok"}
        """)
        let galleries = try await client(transport).galleries()
        #expect(galleries == [Gallery(id: "5704-72157622637971865", title: "Black & white", description: "bw", itemCount: 18)])
        #expect(await transport.lastQueryItems["continuation"] == "0")
    }

    @Test func collectionsNestWithTheirAlbums() async throws {
        let transport = ScriptedTransport(always: """
        {"collections":{"collection":[{"id":"12-1","title":"All My Photos","description":"a collection",
          "set":[{"id":"92157594171298291","title":"kitesurfing","description":"a set"}],
          "collection":[{"id":"12-2","title":"Travel","set":[{"id":"7","title":"Athens"}]}]}]},"stat":"ok"}
        """)
        let tree = try await client(transport).collections()
        #expect(tree.map(\.title) == ["All My Photos"])
        #expect(tree.first?.albums.map(\.title) == ["kitesurfing"])
        #expect(tree.first?.children.first?.albums.map(\.id) == ["7"])
    }

    @Test func noCollectionsIsEmpty() async throws {
        let transport = ScriptedTransport(always: #"{"collections":{},"stat":"ok"}"#)
        #expect(try await client(transport).collections().isEmpty)
    }

    @Test func yourContacts() async throws {
        let transport = ScriptedTransport(always: """
        {"contacts":{"page":1,"pages":1,"perpage":1000,"total":2,"contact":[
          {"nsid":"12037949629@N01","username":"Eric","realname":"Eric Costello","friend":1,"family":0,"ignored":1},
          {"nsid":"41578656547@N01","username":"cal_abc","realname":"","friend":"1","family":"1"}]},"stat":"ok"}
        """)
        let page = try await client(transport).contacts(page: 1)
        #expect(page.contacts == [Contact(id: "12037949629@N01", username: "Eric", realName: "Eric Costello", isFriend: true, isFamily: false),
                                  Contact(id: "41578656547@N01", username: "cal_abc", realName: "", isFriend: true, isFamily: true)])
        #expect(await transport.lastQueryItems["per_page"] == "1000")
    }
}
