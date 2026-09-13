import Foundation
import Testing
@testable import FlickrKit

/// The names the outside world holds on to.
///
/// **Each of these is registered somewhere this code cannot see.** The
/// callback scheme is on the app's record at Flickr and in `Info.plist`; the
/// Keychain service is where an existing key lives. Changing one here without
/// the other breaks sign-in or loses the key, so the values are pinned.
@Suite struct AppIdentityTests {
    @Test func signInReturnsThroughTheCaterinaScheme() {
        #expect(OAuthFlow.callbackScheme == "caterina")
        #expect(OAuthFlow.callbackURL == "caterina://auth")
    }

    @Test func theKeychainServiceIsCaterinas() {
        #expect(KeychainSecretStore.defaultService == "com.tsevis.Caterina")
    }

    @Test func infoPlistRegistersTheSameScheme() throws {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Caterina/Info.plist")
        let data = try Data(contentsOf: plist)
        let root = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let types = try #require(root["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes == [OAuthFlow.callbackScheme])
    }
}
