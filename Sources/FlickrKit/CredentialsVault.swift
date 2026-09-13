import Foundation
import Security

/// Somewhere to keep a secret.
///
/// A protocol so the vault's logic can be tested without writing to the user's
/// login keychain — a unit test that stores real items is a side effect on the
/// machine it runs on.
public protocol SecretStore: Sendable {
    func string(for key: String) -> String?
    func set(_ value: String, for key: String) throws
    func remove(_ key: String) throws
}

/// The Keychain.
///
/// **The only place credentials are ever written.** Not UserDefaults, not a
/// `.env` file, and not source: an API secret in any of those is readable by
/// anything running as the user and survives in backups.
public struct KeychainSecretStore: SecretStore {
    /// Caterina's own. A key saved by FlickrDownloader, under that app's
    /// service, is not read: Caterina is registered at Flickr with a key of
    /// its own.
    public static let defaultService = "com.tsevis.Caterina"

    private let service: String

    public init(service: String = defaultService) {
        self.service = service
    }

    public func string(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String, for key: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let data = Data(value.utf8)

        let status = SecItemUpdate(base as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        if status == errSecItemNotFound {
            var insert = base
            insert[kSecValueData as String] = data
            // `ThisDeviceOnly`: a Flickr read token and an API secret have no
            // business riding an iCloud Keychain sync or a device-migration
            // backup onto another Mac.
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(insert as CFDictionary, nil)
            guard added == errSecSuccess else { throw Self.error(added) }
            return
        }
        throw Self.error(status)
    }

    public func remove(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Self.error(status)
        }
    }

    private static func error(_ status: OSStatus) -> FlickrError {
        let detail = SecCopyErrorMessageString(status, nil) as String?
        return .invalidInput("Could not use the Keychain: \(detail ?? "error \(status)").")
    }
}

/// Everything the application keeps secret, as one value.
public struct StoredCredentials: Sendable, Equatable, Codable {
    public var apiKey: String
    public var apiSecret: String
    public var token: String?
    public var tokenSecret: String?
    public var nsid: String?
    public var username: String?

    public init(apiKey: String, apiSecret: String, token: String? = nil,
                tokenSecret: String? = nil, nsid: String? = nil, username: String? = nil) {
        self.apiKey = apiKey
        self.apiSecret = apiSecret
        self.token = token
        self.tokenSecret = tokenSecret
        self.nsid = nsid
        self.username = username
    }

    public var hasAPIKey: Bool { !apiKey.trimmed.isEmpty && !apiSecret.trimmed.isEmpty }
    public var isSignedIn: Bool { !(token ?? "").isEmpty }

    public var oauth: OAuth1.Credentials {
        OAuth1.Credentials(consumerKey: apiKey, consumerSecret: apiSecret,
                           token: token.flatMap { $0.isEmpty ? nil : $0 },
                           tokenSecret: tokenSecret.flatMap { $0.isEmpty ? nil : $0 })
    }

    public var account: CredentialsVault.StoredAccount? {
        guard isSignedIn else { return nil }
        return CredentialsVault.StoredAccount(nsid: nsid ?? "", username: username ?? "")
    }

    public func signedOut() -> StoredCredentials {
        StoredCredentials(apiKey: apiKey, apiSecret: apiSecret)
    }
}

/// The application's credentials, and the only route to them.
///
/// **One Keychain item, not six.** Each item is its own access-control entry,
/// so a vault spread across `api-key`, `api-secret`, `oauth-token` and the rest
/// asked the user to unlock the Keychain once *per field* — four or five
/// prompts in a row, every time the app's signature changed. Everything is one
/// JSON document under one account now, so there is one prompt at most.
public struct CredentialsVault: Sendable {
    private enum Key {
        static let credentials = "credentials"
        /// What the six-item layout used, kept only so an existing install can
        /// be carried across once and then forgotten.
        static let legacy = ["api-key", "api-secret", "oauth-token",
                             "oauth-token-secret", "user-nsid", "username"]
    }

    public struct StoredAccount: Sendable, Equatable {
        public let nsid: String
        public let username: String

        public init(nsid: String, username: String) {
            self.nsid = nsid
            self.username = username
        }
    }

    private let store: any SecretStore

    public init(store: any SecretStore = KeychainSecretStore()) {
        self.store = store
    }

    /// Read everything, in one go. Callers are expected to do this **once** and
    /// hold on to the result: reading from a SwiftUI view body put a Keychain
    /// prompt on screen every time the view was re-evaluated.
    public func load() -> StoredCredentials? {
        if let document = store.string(for: Key.credentials),
           let stored = try? JSONDecoder().decode(StoredCredentials.self,
                                                  from: Data(document.utf8)) {
            return stored.hasAPIKey ? stored : nil
        }
        return migrateFromSeparateItems()
    }

    public func save(_ credentials: StoredCredentials) throws {
        guard credentials.hasAPIKey else {
            throw FlickrError.invalidInput("Both the API key and the secret are needed.")
        }
        let data = try JSONEncoder().encode(credentials)
        guard let document = String(data: data, encoding: .utf8) else {
            throw FlickrError.invalidInput("Could not store the credentials.")
        }
        try store.set(document, for: Key.credentials)
    }

    public func forgetEverything() throws {
        try store.remove(Key.credentials)
        for key in Key.legacy { try? store.remove(key) }
    }

    /// Carry an install from the six-item layout, once.
    private func migrateFromSeparateItems() -> StoredCredentials? {
        guard let key = store.string(for: "api-key"), !key.isEmpty,
              let secret = store.string(for: "api-secret"), !secret.isEmpty
        else { return nil }

        let carried = StoredCredentials(
            apiKey: key, apiSecret: secret,
            token: store.string(for: "oauth-token"),
            tokenSecret: store.string(for: "oauth-token-secret"),
            nsid: store.string(for: "user-nsid"),
            username: store.string(for: "username"))

        // Best effort: if the write fails the app still works, it just asks
        // again next launch.
        try? save(carried)
        for key in Key.legacy { try? store.remove(key) }
        return carried
    }
}
