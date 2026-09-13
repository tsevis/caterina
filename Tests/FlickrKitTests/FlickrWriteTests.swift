import Foundation
import Testing

@testable import FlickrKit

/// Changing something on Flickr.
///
/// **A retry must not do the thing twice.** Setting a title twice leaves one
/// title; creating an album twice leaves two albums. A write says which kind it
/// is, and only the first kind is retried after a failure that might have
/// landed.
@Suite struct FlickrWriteTests {

    private func client(_ transport: ScriptedTransport,
                        credentials: OAuth1.Credentials = Fixtures.credentials) -> FlickrClient {
        FlickrClient(credentials: credentials, transport: transport, sleep: SleepRecorder().sleep)
    }

    private let setTitle = FlickrWrite(method: "flickr.photos.setMeta",
                                       arguments: ["photo_id": "1", "title": "Harbour"],
                                       repeatable: true)
    private let createAlbum = FlickrWrite(method: "flickr.photosets.create",
                                          arguments: ["title": "Athens", "primary_photo_id": "1"],
                                          repeatable: false)

    @Test func aWriteIsPostedWithItsMethodAndArguments() async throws {
        let transport = ScriptedTransport(always: #"{"stat":"ok"}"#)
        _ = try await client(transport).perform(setTitle)

        let posted = await transport.posted
        #expect(posted.count == 1)
        #expect(posted.first?.httpMethod == "POST")
        let fields = await transport.lastPostedFields
        #expect(fields["method"] == "flickr.photos.setMeta")
        #expect(fields["photo_id"] == "1")
        #expect(fields["title"] == "Harbour")
        #expect(fields["format"] == "json")
        #expect(fields["nojsoncallback"] == "1")
        #expect(fields["oauth_signature"] != nil)
    }

    @Test func aRepeatableWriteIsRetriedWhileFlickrIsBusy() async throws {
        let transport = ScriptedTransport([
            .body(Fixtures.failure(code: 201)),
            .body(#"{"stat":"ok"}"#),
        ])
        _ = try await client(transport).perform(setTitle)
        #expect(await transport.callCount == 2)
    }

    /// The first attempt may have created the album before the reply was lost.
    @Test func aWriteThatWouldDuplicateIsNotRetried() async throws {
        let transport = ScriptedTransport([
            .failure(.transport("The network connection was lost.")),
            .body(#"{"stat":"ok"}"#),
        ])
        await #expect(throws: FlickrError.self) {
            _ = try await client(transport).perform(createAlbum)
        }
        #expect(await transport.callCount == 1)
    }

    /// `stat=fail` means Flickr read the request and did nothing, so even a
    /// write that would duplicate can go again. A lost connection means nobody
    /// knows.
    @Test func aWriteThatWouldDuplicateIsRetriedWhenFlickrSaysItDidNothing() async throws {
        let transport = ScriptedTransport([
            .body(Fixtures.failure(code: 105)),
            .body(#"{"stat":"ok"}"#),
        ])
        _ = try await client(transport).perform(createAlbum)
        #expect(await transport.callCount == 2)
    }

    @Test func aRefusalIsNotRetried() async throws {
        let transport = ScriptedTransport([
            .body(Fixtures.failure(code: 99, message: "Insufficient permissions.")),
        ])
        await #expect(throws: FlickrError.api(code: 99, message: "Insufficient permissions.",
                                               transient: false)) {
            _ = try await client(transport).perform(setTitle)
        }
        #expect(await transport.callCount == 1)
    }

    @Test func writingNeedsASignedInAccount() async throws {
        let transport = ScriptedTransport(always: #"{"stat":"ok"}"#)
        await #expect(throws: FlickrError.self) {
            _ = try await client(transport, credentials: Fixtures.unauthenticated).perform(setTitle)
        }
        #expect(await transport.callCount == 0)
    }

    /// Arguments go out in a stable order, so the same write signs the same way.
    @Test func argumentsAreSentInNameOrder() {
        #expect(createAlbum.parameters.map(\.name)
                == ["method", "primary_photo_id", "title", "format", "nojsoncallback"])
    }
}
