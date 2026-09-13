import Foundation

/// Reading files the person chose, now and after a relaunch.
///
/// Under the sandbox a dropped file is readable only until the app quits; a
/// security-scoped bookmark carries that permission across a relaunch.
public protocol FileAccess: Sendable {
    func bookmark(for file: URL) -> Data?
    /// The file a bookmark points at, or the stored path when there is none.
    func resolve(bookmark: Data?, path: String) -> URL
    func withAccess<T: Sendable>(to file: URL, _ work: () async throws -> T) async throws -> T
}

/// No sandbox: paths are enough. For tests and tools.
public struct PlainFileAccess: FileAccess {
    public init() {}
    public func bookmark(for file: URL) -> Data? { nil }
    public func resolve(bookmark: Data?, path: String) -> URL { URL(fileURLWithPath: path) }
    public func withAccess<T: Sendable>(to file: URL, _ work: () async throws -> T) async throws -> T {
        try await work()
    }
}

/// The app's: security-scoped bookmarks.
public struct SecurityScopedFileAccess: FileAccess {
    public init() {}

    public func bookmark(for file: URL) -> Data? {
        try? file.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                               includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public func resolve(bookmark: Data?, path: String) -> URL {
        guard let bookmark else { return URL(fileURLWithPath: path) }
        var stale = false
        let resolved = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                relativeTo: nil, bookmarkDataIsStale: &stale)
        return resolved ?? URL(fileURLWithPath: path)
    }

    public func withAccess<T: Sendable>(to file: URL, _ work: () async throws -> T) async throws -> T {
        let started = file.startAccessingSecurityScopedResource()
        defer { if started { file.stopAccessingSecurityScopedResource() } }
        return try await work()
    }
}
