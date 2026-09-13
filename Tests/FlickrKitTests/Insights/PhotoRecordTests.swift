import Foundation
import Testing

@testable import FlickrKit

/// Everything Flickr keeps about one photo, from Flickr's documented replies.
@Suite struct PhotoRecordTests {

    private func client(_ transport: ScriptedTransport) -> FlickrClient {
        FlickrClient(credentials: Fixtures.credentials, transport: transport, budget: .unspaced,
                     sleep: SleepRecorder().sleep)
    }

    @Test func theInfoReplyIsReadWhole() async throws {
        let transport = ScriptedTransport(always: """
        {"photo":{"id":"2733","secret":"123456","server":"12","license":"3","views":"18204",
          "owner":{"nsid":"12037949754@N01","username":"Bees","realname":"Cal Henderson","location":"Bedford, UK"},
          "title":{"_content":"orford_castle_taster"},"description":{"_content":"hello!"},
          "visibility":{"ispublic":1,"isfriend":0,"isfamily":0},
          "dates":{"posted":"1100897479","taken":"2004-11-19 12:51:19","takengranularity":"0","takenunknown":"0","lastupdate":"1093022469"},
          "comments":{"_content":"37"},
          "tags":{"tag":[{"id":"1234","author":"12037949754@N01","raw":"woo yay","_content":"wooyay"}]},
          "location":{"latitude":"52.09","longitude":"1.53","accuracy":"16",
                      "locality":{"_content":"Orford"},"country":{"_content":"United Kingdom"}},
          "urls":{"url":[{"type":"photopage","_content":"https://www.flickr.com/photos/bees/2733/"}]},
          "media":"photo"},"stat":"ok"}
        """)

        let info = try await client(transport).photoInfo(id: "2733")

        #expect(info.id == "2733")
        #expect(info.title == "orford_castle_taster")
        #expect(info.description == "hello!")
        #expect(info.owner == PhotoInfo.Owner(nsid: "12037949754@N01", username: "Bees", realName: "Cal Henderson"))
        #expect(info.views == 18204)
        #expect(info.commentCount == 37)
        #expect(info.license == .byNcNd)
        #expect(info.tags == ["woo yay"])
        #expect(info.posted == Date(timeIntervalSince1970: 1_100_897_479))
        #expect(info.taken == "2004-11-19 12:51:19")
        #expect(info.visibility == .init(isPublic: true, isFriend: false, isFamily: false))
        #expect(info.place == "Orford, United Kingdom")
        #expect(info.location?.latitude == 52.09)
        #expect(info.pageURL == URL(string: "https://www.flickr.com/photos/bees/2733/"))
        #expect(await transport.lastQueryItems["method"] == "flickr.photos.getInfo")
    }

    @Test func favesComeWithWhoAndWhen() async throws {
        let transport = ScriptedTransport(always: """
        {"photo":{"id":"1253576","page":1,"pages":3,"perpage":50,"total":"127","person":[
          {"nsid":"33939862@N00","username":"Dementation","realname":"","favedate":"1166689690"},
          {"nsid":"49485425@N00","username":"indigenous_prodigy","favedate":"1166573724"}]},"stat":"ok"}
        """)

        let page = try await client(transport).favorites(photoID: "1253576", page: 1)

        #expect(page.total == 127)
        #expect(page.pages == 3)
        #expect(page.faves == [
            Fave(nsid: "33939862@N00", username: "Dementation", date: Date(timeIntervalSince1970: 1_166_689_690)),
            Fave(nsid: "49485425@N00", username: "indigenous_prodigy", date: Date(timeIntervalSince1970: 1_166_573_724)),
        ])
        #expect(await transport.lastQueryItems["per_page"] == "50")
    }

    @Test func commentsComeWithAuthorDateAndText() async throws {
        let transport = ScriptedTransport(always: """
        {"comments":{"photo_id":"109722179","comment":[{"id":"6065-109722179-72057594077818641",
          "author":"35468159852@N01","authorname":"Rev Dan Catt","datecreate":"1141841470",
          "permalink":"http://www.flickr.com/photos/straup/109722179/#comment72057594077818641",
          "_content":"Umm, I'm not sure, can I get back to you on that one?"}]},"stat":"ok"}
        """)

        let comments = try await client(transport).comments(photoID: "109722179")

        #expect(comments == [PhotoComment(id: "6065-109722179-72057594077818641", authorName: "Rev Dan Catt",
                                          date: Date(timeIntervalSince1970: 1_141_841_470),
                                          text: "Umm, I'm not sure, can I get back to you on that one?")])
    }

    /// A photo with no comments has no `comment` key at all.
    @Test func noCommentsIsAnEmptyList() async throws {
        let transport = ScriptedTransport(always: #"{"comments":{"photo_id":"1"},"stat":"ok"}"#)
        #expect(try await client(transport).comments(photoID: "1").isEmpty)
    }

    @Test func theAlbumsAndGroupsAPhotoIsIn() async throws {
        let transport = ScriptedTransport(always: """
        {"set":[{"id":"392","title":"记忆群组","view_count":12}],
         "pool":[{"id":"34427465471@N01","title":"FlickrDiscuss","members":"4521"}],"stat":"ok"}
        """)
        let contexts = try await client(transport).contexts(photoID: "1")
        #expect(contexts.albums == [PhotoContexts.Place(id: "392", title: "记忆群组")])
        #expect(contexts.groups == [PhotoContexts.Place(id: "34427465471@N01", title: "FlickrDiscuss")])
    }

    @Test func aPhotoInNothingIsInNothing() async throws {
        let transport = ScriptedTransport(always: #"{"stat":"ok"}"#)
        let contexts = try await client(transport).contexts(photoID: "1")
        #expect(contexts.albums.isEmpty && contexts.groups.isEmpty)
    }

    /// The clean value where Flickr has one, the raw one otherwise.
    @Test func cameraDataPrefersTheCleanValue() async throws {
        let transport = ScriptedTransport(always: """
        {"photo":{"id":"4424","camera":"Canon EOS 5D Mark IV","exif":[
          {"tagspace":"TIFF","tag":"Make","label":"Make","raw":{"_content":"Canon"}},
          {"tagspace":"ExifIFD","tag":"FNumber","label":"Aperture","raw":{"_content":"9.0"},"clean":{"_content":"f/9.0"}},
          {"tagspace":"ExifIFD","tag":"ExposureTime","label":"Exposure","raw":{"_content":"1/250"}}]},"stat":"ok"}
        """)
        let exif = try await client(transport).exif(photoID: "4424")
        #expect(exif.camera == "Canon EOS 5D Mark IV")
        #expect(exif.fields == [ExifField(label: "Make", value: "Canon"),
                                ExifField(label: "Aperture", value: "f/9.0"),
                                ExifField(label: "Exposure", value: "1/250")])
        #expect(exif["Aperture"] == "f/9.0")
    }

    /// The owner can hide camera data; that is an answer, not an error.
    @Test func hiddenCameraDataReadsAsNone() async throws {
        let transport = ScriptedTransport(always: Fixtures.failure(code: 2, message: "Permission denied"))
        let exif = try await client(transport).exif(photoID: "1")
        #expect(exif.fields.isEmpty)
        #expect(exif.isHidden)
    }
}
