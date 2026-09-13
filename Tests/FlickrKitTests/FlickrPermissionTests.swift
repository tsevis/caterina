import Foundation
import Testing

@testable import FlickrKit

/// What the signed-in account is allowed to do, and asking for more.
///
/// **Asked for when it is first needed, never at launch.** Browsing needs
/// `read`; uploading and editing need `write`; deleting a photo needs `delete`,
/// which Flickr grants separately. Each is a fresh trip to Flickr's
/// authorisation page, which issues a new token.
@Suite struct FlickrPermissionTests {

    private func client(_ transport: ScriptedTransport, granted: FlickrPermission) -> FlickrClient {
        FlickrClient(credentials: Fixtures.credentials, permission: granted,
                     transport: transport, sleep: SleepRecorder().sleep)
    }

    @Test func eachLevelIncludesTheOnesBelowIt() {
        #expect(FlickrPermission.read < .write)
        #expect(FlickrPermission.write < .delete)
        #expect(FlickrPermission.allCases == [.read, .write, .delete])
    }

    @Test func theAuthorisationPageIsAskedForTheLevelNeeded() throws {
        let url = try OAuthFlow.authorizationURL(token: "72157-abc", permission: .write)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "perms" }?.value == "write")
    }

    @Test func aSignInRemembersWhatItWasGranted() throws {
        let account = try OAuthFlow.account(
            from: "oauth_token=t&oauth_token_secret=s&user_nsid=1%40N00&username=c",
            permission: .write)
        #expect(account.permission == .write)

        let stored = StoredCredentials(apiKey: "k", apiSecret: "s")
            .signedIn(account)
        #expect(stored.permission == .write)
        #expect(stored.account?.permission == .write)
        #expect(stored.signedOut().permission == nil)
    }

    /// Everyone signed in before this build asked for `read`, and the Keychain
    /// document they have says nothing about it.
    @Test func aTokenStoredBeforePermissionsWereRecordedIsRead() throws {
        let document = #"{"apiKey":"k","apiSecret":"s","token":"t","tokenSecret":"ts","nsid":"n","username":"u"}"#
        let stored = try JSONDecoder().decode(StoredCredentials.self, from: Data(document.utf8))
        #expect(stored.grantedPermission == .read)
        #expect(stored.account?.permission == .read)
    }

    @Test func aWriteBeyondWhatWasGrantedIsRefusedBeforeItIsSent() async throws {
        let transport = ScriptedTransport(always: #"{"stat":"ok"}"#)
        let write = FlickrWrite(method: "flickr.photos.setMeta",
                                arguments: ["photo_id": "1"], repeatable: true)
        await #expect(throws: FlickrError.permissionNeeded(.write)) {
            _ = try await client(transport, granted: .read).perform(write)
        }
        #expect(await transport.callCount == 0)
    }

    @Test func deletingAPhotoNeedsItsOwnPermission() async throws {
        let transport = ScriptedTransport(always: #"{"stat":"ok"}"#)
        let delete = FlickrWrite(method: "flickr.photos.delete", arguments: ["photo_id": "1"],
                                 repeatable: true, permission: .delete)
        await #expect(throws: FlickrError.permissionNeeded(.delete)) {
            _ = try await client(transport, granted: .write).perform(delete)
        }
        _ = try await client(transport, granted: .delete).perform(delete)
        #expect(await transport.callCount == 1)
    }

    /// Revoked on flickr.com since: Flickr's own refusal says so, and it is the
    /// same "ask again" as never having had it.
    @Test func flickrsInsufficientPermissionsReadsAsPermissionNeeded() async throws {
        let transport = ScriptedTransport(always: Fixtures.failure(code: 99, message: "Insufficient permissions. Method requires write privileges; read granted."))
        let write = FlickrWrite(method: "flickr.photos.setMeta",
                                arguments: ["photo_id": "1"], repeatable: true)
        await #expect(throws: FlickrError.permissionNeeded(.write)) {
            _ = try await client(transport, granted: .write).perform(write)
        }
        #expect(FlickrError.permissionNeeded(.write).isTransient == false)
    }
}
