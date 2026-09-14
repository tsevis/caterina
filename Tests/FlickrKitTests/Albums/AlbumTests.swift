import Foundation
import Testing

@testable import FlickrKit

/// Your albums: listing them, making one, putting photos in.
@Suite struct AlbumTests {

    private func client(_ transport: ScriptedTransport) -> FlickrClient {
        FlickrClient(credentials: Fixtures.credentials, permission: .write, transport: transport,
                     budget: .unspaced, sleep: SleepRecorder().sleep)
    }

    @Test func albumsAreListedInYourOwnOrder() async throws {
        let transport = ScriptedTransport(always: """
        {"photosets":{"page":1,"pages":2,"perpage":500,"total":501,"photoset":[
          {"id":"72157001","primary":"53712","photos":12,"videos":"1","count_views":"44",
           "title":{"_content":"Athens 2026"},"description":{"_content":"Spring"},"date_update":"1717243200"},
          {"id":"72157002","primary":"1","photos":"0","videos":0,"title":{"_content":"Empty"},"description":{"_content":""}},
          {"title":{"_content":"No id"}}
        ]},"stat":"ok"}
        """)

        let page = try await client(transport).albums(page: 1)

        #expect(page.albums == [
            Album(id: "72157001", title: "Athens 2026", description: "Spring", photoCount: 13,
                  coverPhotoID: "53712", views: 44),
            Album(id: "72157002", title: "Empty", description: "", photoCount: 0, coverPhotoID: "1", views: 0),
        ])
        #expect(page.pages == 2)
        #expect(await transport.lastQueryItems["method"] == "flickr.photosets.getList")
        #expect(await transport.lastQueryItems["per_page"] == "500")
    }

    /// Creating an album twice leaves two, so it is never sent twice.
    @Test func creatingAnAlbumNeedsItsFirstPhotoAndReturnsItsID() async throws {
        let transport = ScriptedTransport(always: #"{"photoset":{"id":"72157999","url":"https://flickr.com/x"},"stat":"ok"}"#)

        let id = try await client(transport).createAlbum(title: "Athens", description: "", coverPhotoID: "53712")

        #expect(id == "72157999")
        let fields = await transport.lastPostedFields
        #expect(fields["method"] == "flickr.photosets.create")
        #expect(fields["title"] == "Athens")
        #expect(fields["primary_photo_id"] == "53712")
        #expect(fields["description"] == nil)
        #expect(AlbumWrites.create(title: "A", description: "", coverPhotoID: "1").repeatable == false)
    }

    /// Already in the album is what adding was for.
    @Test func addingAPhotoAlreadyInTheAlbumIsFine() async throws {
        let transport = ScriptedTransport(always: Fixtures.failure(code: 3, message: "Photo already in set"))
        try await client(transport).addToAlbum(photoID: "1", albumID: "72157001")
        #expect(await transport.lastPostedFields["photoset_id"] == "72157001")
    }

    @Test func aFullAlbumIsReportedPlainly() async throws {
        let transport = ScriptedTransport(always: Fixtures.failure(code: 10, message: "Maximum number of photos in set"))
        await #expect(throws: FlickrError.api(code: 10, message: "Maximum number of photos in set", transient: false)) {
            try await client(transport).addToAlbum(photoID: "1", albumID: "72157001")
        }
    }
}

/// Reading an album as it stands, just before an edit changes it.
@Suite struct AlbumSnapshotTests {

    private func client(_ transport: ScriptedTransport) -> FlickrClient {
        FlickrClient(credentials: Fixtures.credentials, permission: .write, transport: transport,
                     budget: .unspaced, sleep: SleepRecorder().sleep)
    }

    @Test func infoAndEveryPageOfPhotosAreRead() async throws {
        let transport = ScriptedTransport([
            .body(#"{"photoset":{"id":"A","owner":"me","primary":"2","title":{"_content":"Athens"},"description":{"_content":"Spring"}},"stat":"ok"}"#),
            .body(#"{"photoset":{"id":"A","page":1,"pages":2,"photo":[{"id":"1"},{"id":"2"}]},"stat":"ok"}"#),
            .body(#"{"photoset":{"id":"A","page":2,"pages":2,"photo":[{"id":"3"}]},"stat":"ok"}"#),
        ])

        let snapshot = try await client(transport).albumSnapshot(reading: [.info, .photos], albumID: "A",
                                                                 ownerID: "me", priority: .edit)

        #expect(snapshot == AlbumSnapshot(title: "Athens", description: "Spring", coverPhotoID: "2",
                                          photoIDs: ["1", "2", "3"], albumOrder: []))
        let asked = await transport.requested.compactMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        #expect(asked.map { $0.queryItems?.first { $0.name == "method" }?.value }
                == ["flickr.photosets.getInfo", "flickr.photosets.getPhotos", "flickr.photosets.getPhotos"])
        #expect(asked[1].queryItems?.first { $0.name == "user_id" }?.value == "me")
    }

    @Test func theOrderOfAlbumsIsReadAcrossPages() async throws {
        let transport = ScriptedTransport([
            .body(#"{"photosets":{"page":1,"pages":2,"photoset":[{"id":"B"},{"id":"A"}]},"stat":"ok"}"#),
            .body(#"{"photosets":{"page":2,"pages":2,"photoset":[{"id":"C"}]},"stat":"ok"}"#),
        ])
        let snapshot = try await client(transport).albumSnapshot(reading: [.albumOrder], albumID: nil,
                                                                 ownerID: "me", priority: .edit)
        #expect(snapshot.albumOrder == ["B", "A", "C"])
    }

    @Test func nothingToReadCostsNothing() async throws {
        let transport = ScriptedTransport([])
        #expect(try await client(transport).albumSnapshot(reading: [], albumID: nil, ownerID: "me", priority: .edit)
                == .empty)
        #expect(await transport.callCount == 0)
    }
}
