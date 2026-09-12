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
    private let service: String

    public init(service: String = "com.tsevis.FlickrDownloader") {
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
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
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

/// The application's credentials, and the only route to them.
public struct CredentialsVault: Sendable {
    private enum Key {
        static let apiKey = "api-key"
        static let apiSecret = "api-secret"
        static let token = "oauth-token"
        static let tokenSecret = "oauth-token-secret"
        static let nsid = "user-nsid"
        static let username = "username"
    }

    public struct StoredAccount: Sendable, Equatable {
        public let nsid: String
        public let username: String
    }

    private let store: any SecretStore

    public init(store: any SecretStore = KeychainSecretStore()) {
        self.store = store
    }

    public var hasAPIKey: Bool {
        !(store.string(for: Key.apiKey) ?? "").isEmpty
            && !(store.string(for: Key.apiSecret) ?? "").isEmpty
    }

    public var isSignedIn: Bool {
        !(store.string(for: Key.token) ?? "").isEmpty
    }

    /// Nil when there is no API key yet — which is the state the onboarding
    /// sheet exists for.
    public func credentials() -> OAuth1.Credentials? {
        guard let key = store.string(for: Key.apiKey), !key.isEmpty,
              let secret = store.string(for: Key.apiSecret), !secret.isEmpty
        else { return nil }

        let token = store.string(for: Key.token).flatMap { $0.isEmpty ? nil : $0 }
        let tokenSecret = store.string(for: Key.tokenSecret).flatMap { $0.isEmpty ? nil : $0 }
        return OAuth1.Credentials(consumerKey: key, consumerSecret: secret,
                                  token: token, tokenSecret: tokenSecret)
    }

    public func account() -> StoredAccount? {
        guard isSignedIn else { return nil }
        return StoredAccount(nsid: store.string(for: Key.nsid) ?? "",
                             username: store.string(for: Key.username) ?? "")
    }

    public func saveAPIKey(key: String, secret: String) throws {
        let key = key.trimmed
        let secret = secret.trimmed
        guard !key.isEmpty, !secret.isEmpty else {
            throw FlickrError.invalidInput("Both the API key and the secret are needed.")
        }
        try store.set(key, for: Key.apiKey)
        try store.set(secret, for: Key.apiSecret)
    }

    public func saveAccount(token: String, secret: String,
                            nsid: String, username: String) throws {
        try store.set(token, for: Key.token)
        try store.set(secret, for: Key.tokenSecret)
        try store.set(nsid, for: Key.nsid)
        try store.set(username, for: Key.username)
    }

    /// Signing out removes the token from the Keychain, not only from the
    /// window: the next launch reads the Keychain.
    public func signOut() throws {
        for key in [Key.token, Key.tokenSecret, Key.nsid, Key.username] {
            try store.remove(key)
        }
    }

    public func forgetEverything() throws {
        try signOut()
        try store.remove(Key.apiKey)
        try store.remove(Key.apiSecret)
    }
}
