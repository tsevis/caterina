import Foundation
import Testing

@testable import FlickrKit

/// The photo as Flickr has it at the moment an edit is about to be sent.
///
/// `photos.getInfo` is the only read that gives raw tags, so it is what a
/// batch edit lays each change over (`PhotoRebaseTests`).
@Suite struct LivePhotoTests {

    private let reply = """
    {"photo":{"id":"2733","license":"4","media":"video",
      "title":{"_content":"Brooklyn and the bridge"},"description":{"_content":"hello!"},
      "visibility":{"ispublic":0,"isfriend":1,"isfamily":1},
      "dates":{"posted":"1100897479","taken":"2004-11-19 12:51:19","takengranularity":"0","takenunknown":"0",
               "lastupdate":"1093022469"},
      "tags":{"tag":[{"id":"1234","raw":"New York","_content":"newyork"},
                     {"id":"1235","raw":"night","_content":"night"}]},
      "location":{"latitude":"52.09","longitude":"1.53","accuracy":"16"}},"stat":"ok"}
    """

    @Test func theEditableFieldsAreReadWithRawTags() async throws {
        let transport = ScriptedTransport(always: reply)
        let client = FlickrClient(credentials: Fixtures.credentials, transport: transport, budget: .unspaced,
                                  sleep: SleepRecorder().sleep)

        let photo = try await client.livePhoto(id: "2733", priority: .edit)

        #expect(photo == LibraryPhoto(
            id: "2733", title: "Brooklyn and the bridge", description: "hello!", tags: ["New York", "night"],
            license: .by, visibility: .init(isPublic: false, isFriend: true, isFamily: true),
            uploaded: Date(timeIntervalSince1970: 1_100_897_479),
            lastUpdated: Date(timeIntervalSince1970: 1_093_022_469),
            taken: "2004-11-19 12:51:19", media: .video,
            location: .init(latitude: 52.09, longitude: 1.53, accuracy: 16)))
        #expect(await transport.lastQueryItems["method"] == "flickr.photos.getInfo")
        #expect(await transport.lastQueryItems["photo_id"] == "2733")
    }

    @Test func anUnknownDateTakenIsNil() async throws {
        let unknown = reply.replacingOccurrences(of: #""takenunknown":"0""#, with: #""takenunknown":"1""#)
        let client = FlickrClient(credentials: Fixtures.credentials, transport: ScriptedTransport(always: unknown),
                                  budget: .unspaced, sleep: SleepRecorder().sleep)
        #expect(try await client.livePhoto(id: "2733", priority: .edit).taken == nil)
    }
}

/// `photos.geo.getPerms`, read only for an edit that changes who can see a
/// location: it is a call per photo.
@Suite struct GeoPermissionReadTests {

    private func client(_ replies: [ScriptedTransport.Reply]) -> (FlickrClient, ScriptedTransport) {
        let transport = ScriptedTransport(replies)
        return (FlickrClient(credentials: Fixtures.credentials, transport: transport, budget: .unspaced,
                             sleep: SleepRecorder().sleep), transport)
    }

    @Test func theFourFlagsAreRead() async throws {
        let (client, transport) = client([.body(
            #"{"perms":{"id":"10592","ispublic":0,"iscontact":"1","isfriend":0,"isfamily":1},"stat":"ok"}"#)])
        #expect(try await client.geoPermissions(photoID: "10592", priority: .edit)
                == .init(isPublic: false, isContact: true, isFriend: false, isFamily: true))
        #expect(await transport.lastQueryItems["method"] == "flickr.photos.geo.getPerms")
    }

    /// Code 2: the photo has no location, so nobody can see one.
    @Test func aPhotoWithNoLocationHasNoPermissions() async throws {
        let (client, _) = client([.body(#"{"stat":"fail","code":2,"message":"Photo has no location information"}"#)])
        #expect(try await client.geoPermissions(photoID: "1", priority: .edit) == nil)
    }
}
