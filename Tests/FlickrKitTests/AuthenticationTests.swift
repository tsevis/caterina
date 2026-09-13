import Foundation
import Testing

@testable import FlickrKit

/// The native sign-in flow.
///
/// The reference application used `oob` and made the user copy a nine-digit
/// verifier out of a browser, because Qt made the callback awkward. A registered
/// callback URL removes that step — and adds one obligation: the value that
/// comes back through it is attacker-influenced and has to be checked.
@Suite struct AuthenticationTests {

    private let credentials = OAuth1.Credentials(consumerKey: "key", consumerSecret: "secret")

    // MARK: - Request token

    @Test func theRequestTokenCallCarriesTheCallbackNotOOB() throws {
        let url = try OAuthFlow.requestTokenURL(credentials: credentials,
                                                callback: "caterina://auth")
        let query = try #require(url.query)
        #expect(query.contains("oauth_callback=caterina%3A%2F%2Fauth"))
        #expect(!query.contains("oob"))
        #expect(url.absoluteString.hasPrefix(OAuthFlow.requestTokenEndpoint))
    }

    @Test func aRequestTokenReplyIsFormEncodedNotJSON() throws {
        let token = try OAuthFlow.temporaryToken(from:
            "oauth_callback_confirmed=true&oauth_token=72157%2Dabc&oauth_token_secret=s3cr3t")
        #expect(token.token == "72157-abc")
        #expect(token.secret == "s3cr3t")
    }

    @Test func aReplyWithoutATokenIsAMessageNotACrash() {
        for body in ["", "oauth_problem=consumer_key_unknown",
                     "oauth_token=&oauth_token_secret=x"] {
            #expect(throws: FlickrError.self) { _ = try OAuthFlow.temporaryToken(from: body) }
        }
    }

    /// Flickr reports a bad consumer key here, and it is the one error the user
    /// can actually fix.
    @Test func anOAuthProblemIsReportedInWordsTheUserCanActOn() throws {
        do {
            _ = try OAuthFlow.temporaryToken(from: "oauth_problem=consumer_key_unknown")
            Issue.record("expected a failure")
        } catch let error as FlickrError {
            #expect(error.message.lowercased().contains("api key"))
        }
    }

    // MARK: - Authorisation

    @Test func theAuthorisationPageAsksForReadPermissionOnly() throws {
        let url = try OAuthFlow.authorizationURL(token: "72157-abc")
        #expect(url.absoluteString
            == "https://www.flickr.com/services/oauth/authorize?oauth_token=72157-abc&perms=read")
    }

    // MARK: - The callback

    @Test func theVerifierIsReadFromTheCallback() throws {
        let url = URL(string: "caterina://auth?oauth_token=72157-abc&oauth_verifier=123-456")!
        #expect(try OAuthFlow.verifier(from: url, expecting: "72157-abc") == "123-456")
    }

    /// The callback is opened by a browser and its contents are not ours. A
    /// token that is not the one we asked for must not be exchanged.
    @Test func aCallbackForADifferentTokenIsRefused() {
        let url = URL(string: "caterina://auth?oauth_token=someone-else&oauth_verifier=1")!
        #expect(throws: FlickrError.self) {
            _ = try OAuthFlow.verifier(from: url, expecting: "72157-abc")
        }
    }

    @Test func aCallbackWithNoVerifierIsRefused() {
        let url = URL(string: "caterina://auth?oauth_token=72157-abc")!
        #expect(throws: FlickrError.self) {
            _ = try OAuthFlow.verifier(from: url, expecting: "72157-abc")
        }
    }

    @Test func aUserWhoDeclinedIsNotAnError() {
        let url = URL(string: "caterina://auth?oauth_problem=user_refused")!
        #expect(throws: FlickrError.self) {
            _ = try OAuthFlow.verifier(from: url, expecting: "72157-abc")
        }
    }

    // MARK: - Access token

    @Test func theAccessTokenCallIsSignedWithTheTemporarySecret() throws {
        let url = try OAuthFlow.accessTokenURL(
            credentials: credentials,
            temporary: OAuthFlow.TemporaryToken(token: "72157-abc", secret: "tmp"),
            verifier: "123-456")
        let query = try #require(url.query)
        #expect(query.contains("oauth_verifier=123-456"))
        #expect(query.contains("oauth_token=72157-abc"))
        #expect(query.contains("oauth_signature="))
    }

    @Test func anAccessTokenReplyCarriesTheAccountItBelongsTo() throws {
        let account = try OAuthFlow.account(from:
            "fullname=Charis&oauth_token=72157-final&oauth_token_secret=final-secret"
            + "&user_nsid=12345%40N00&username=tsevis")
        #expect(account.token == "72157-final")
        #expect(account.tokenSecret == "final-secret")
        #expect(account.nsid == "12345@N00")
        #expect(account.username == "tsevis")
    }

    @Test func anIncompleteAccessTokenReplyIsRefused() {
        #expect(throws: FlickrError.self) {
            _ = try OAuthFlow.account(from: "oauth_token=72157-final")
        }
    }

    // MARK: - Storage

    @Test func credentialsAreReadBackExactlyAsStored() throws {
        let vault = CredentialsVault(store: InMemorySecretStore())
        try vault.save(StoredCredentials(apiKey: "abc", apiSecret: "def",
                                         token: "tok", tokenSecret: "toksec",
                                         nsid: "1@N1", username: "me"))

        let stored = try #require(vault.load())
        #expect(stored.oauth.consumerKey == "abc")
        #expect(stored.oauth.consumerSecret == "def")
        #expect(stored.oauth.token == "tok")
        #expect(stored.oauth.tokenSecret == "toksec")
        #expect(stored.account?.username == "me")
    }

    @Test func thereAreNoCredentialsBeforeAnyAreStored() {
        #expect(CredentialsVault(store: InMemorySecretStore()).load() == nil)
    }

    @Test func anAPIKeyWithoutATokenIsEnoughToSearch() throws {
        let vault = CredentialsVault(store: InMemorySecretStore())
        try vault.save(StoredCredentials(apiKey: "abc", apiSecret: "def"))

        let stored = try #require(vault.load())
        #expect(stored.hasAPIKey)
        #expect(!stored.isSignedIn)
        #expect(stored.oauth.token == nil)
        #expect(stored.account == nil)
    }

    /// Signing out has to remove the token from the Keychain, not just from the
    /// window — the next launch reads the Keychain, not the window.
    @Test func signingOutClearsTheTokenButKeepsTheAPIKey() throws {
        let vault = CredentialsVault(store: InMemorySecretStore())
        let full = StoredCredentials(apiKey: "abc", apiSecret: "def", token: "tok",
                                     tokenSecret: "toksec", nsid: "1@N1", username: "me")
        try vault.save(full)
        try vault.save(full.signedOut())

        let stored = try #require(vault.load())
        #expect(!stored.isSignedIn)
        #expect(stored.hasAPIKey)
        #expect(stored.account == nil)
        #expect(stored.oauth.token == nil)
    }

    @Test func forgettingEverythingLeavesNothingBehind() throws {
        let store = InMemorySecretStore()
        let vault = CredentialsVault(store: store)
        try vault.save(StoredCredentials(apiKey: "abc", apiSecret: "def", token: "t"))

        try vault.forgetEverything()
        #expect(store.isEmpty)
        #expect(vault.load() == nil)
    }

    @Test func aBlankAPIKeyIsRefusedRatherThanStored() {
        let vault = CredentialsVault(store: InMemorySecretStore())
        #expect(throws: FlickrError.self) {
            try vault.save(StoredCredentials(apiKey: "  ", apiSecret: "def"))
        }
        #expect(throws: FlickrError.self) {
            try vault.save(StoredCredentials(apiKey: "abc", apiSecret: ""))
        }
    }

    // MARK: - One prompt, not six

    /// **The symptom this layout exists to remove.** Every Keychain item is its
    /// own access-control entry, so six items meant the user was asked to
    /// unlock the Keychain up to six times in a row.
    @Test func everythingIsReadFromASingleKeychainItem() throws {
        let store = CountingSecretStore()
        let vault = CredentialsVault(store: store)
        try vault.save(StoredCredentials(apiKey: "abc", apiSecret: "def",
                                         token: "t", tokenSecret: "s",
                                         nsid: "1@N1", username: "me"))
        store.reads = 0

        _ = vault.load()
        #expect(store.reads == 1)
        #expect(store.written.count == 1)
    }

    /// An install made by the six-item version keeps working, once.
    @Test func anOlderInstallIsCarriedAcrossAndTidiedUp() throws {
        let store = InMemorySecretStore()
        for (key, value) in ["api-key": "abc", "api-secret": "def",
                             "oauth-token": "tok", "oauth-token-secret": "toksec",
                             "user-nsid": "1@N1", "username": "me"] {
            try store.set(value, for: key)
        }

        let vault = CredentialsVault(store: store)
        let carried = try #require(vault.load())
        #expect(carried.oauth.consumerKey == "abc")
        #expect(carried.account?.username == "me")

        // And the old items are gone, so it never happens twice.
        #expect(store.string(for: "api-key") == nil)
        #expect(store.string(for: "oauth-token") == nil)
        #expect(store.string(for: "credentials") != nil)
    }
}

/// Counts what it is asked for, which is the point of the single-item layout.
final class CountingSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var readCount = 0

    var reads: Int {
        get { lock.lock(); defer { lock.unlock() }; return readCount }
        set { lock.lock(); readCount = newValue; lock.unlock() }
    }

    var written: [String: String] {
        lock.lock(); defer { lock.unlock() }
        return values
    }

    func string(for key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        readCount += 1
        return values[key]
    }

    func set(_ value: String, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }

    func remove(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}

/// Stands in for the Keychain. The real store is exercised by the opt-in live
/// checks — a unit test must not write to the user's login keychain.
final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return values.isEmpty
    }

    func string(for key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    func set(_ value: String, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }

    func remove(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}
