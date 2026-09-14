import Foundation
import Testing

@testable import FlickrKit

/// Finding exactly the member someone means, before tagging them in photos.
@Suite struct PersonLookupTests {

    private func client(_ transport: ScriptedTransport) -> FlickrClient {
        FlickrClient(credentials: Fixtures.credentials, transport: transport, budget: .unspaced,
                     sleep: SleepRecorder().sleep)
    }

    /// A photostream address names its owner by path alias, not username:
    /// Flickr resolves the address itself.
    @Test func anAddressIsResolvedByFlickrNotByGuessingAUsername() async throws {
        let transport = ScriptedTransport(always: #"{"user":{"id":"12037949632@N01","username":{"_content":"Stewart"}},"stat":"ok"}"#)
        let person = try await client(transport).lookUpPerson("https://www.flickr.com/photos/stewart/")
        #expect(person == FlickrPerson(nsid: "12037949632@N01", username: "Stewart"))
        #expect(await transport.lastQueryItems["method"] == "flickr.urls.lookupUser")
        #expect(await transport.lastQueryItems["url"] == "https://www.flickr.com/photos/stewart/")
    }

    @Test func aUsernameIsFoundByName() async throws {
        let transport = ScriptedTransport(always: #"{"user":{"id":"1@N01","nsid":"1@N01","username":{"_content":"tsevis"}},"stat":"ok"}"#)
        #expect(try await client(transport).lookUpPerson(" tsevis ") == FlickrPerson(nsid: "1@N01", username: "tsevis"))
        #expect(await transport.lastQueryItems["method"] == "flickr.people.findByUsername")
    }

    @Test func anNSIDIsConfirmedAndNamed() async throws {
        let transport = ScriptedTransport(always: #"{"person":{"id":"66@N07","nsid":"66@N07","username":{"_content":"Ann"}},"stat":"ok"}"#)
        #expect(try await client(transport).lookUpPerson("66@N07") == FlickrPerson(nsid: "66@N07", username: "Ann"))
        #expect(await transport.lastQueryItems["method"] == "flickr.people.getInfo")
    }

    @Test func somethingWithAnAtSignThatIsNotAnNSIDIsNotTakenAsOne() {
        #expect(FlickrClient.isNSID("12345@N07"))
        #expect(!FlickrClient.isNSID("https://flickr.com/photos/12345@N07/"))
        #expect(!FlickrClient.isNSID("me@example.com"))
    }
}
