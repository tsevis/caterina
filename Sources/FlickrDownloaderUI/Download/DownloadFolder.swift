import Foundation

/// Remembering where the last download went.
///
/// **A security-scoped bookmark, not a path.** Under the sandbox the Save
/// panel's grant does not survive a relaunch, so a remembered *path* would be
/// pre-filled, look right, and fail to write. A bookmark is the grant.
enum DownloadFolder {
    /// Plain bookmarks in a process that is not sandboxed; the security scope
    /// is what the app itself needs.
    static let scope: URL.BookmarkCreationOptions = [.withSecurityScope]
    static let resolution: URL.BookmarkResolutionOptions = [.withSecurityScope]

    static func bookmark(for url: URL,
                         options: URL.BookmarkCreationOptions = scope) -> Data {
        (try? url.bookmarkData(options: options,
                               includingResourceValuesForKeys: nil,
                               relativeTo: nil)) ?? Data()
    }

    /// The folder a bookmark names, or `nil` if it no longer names one.
    static func restored(from data: Data,
                         options: URL.BookmarkResolutionOptions = resolution) -> URL? {
        remembered(from: data, resolution: options, creation: [])?.url
    }

    /// The folder a bookmark names, and a replacement bookmark if it was stale.
    ///
    /// Every failure is a `nil` rather than a throw: a corrupted bookmark or
    /// one pointing at a folder since deleted both mean the same thing to the
    /// panel — ask again. **Stale is not a failure.** It means the folder was
    /// moved or renamed; the bookmark still resolves, to where it is now, and
    /// wants re-creating.
    static func remembered(from data: Data,
                           resolution: URL.BookmarkResolutionOptions = resolution,
                           creation: URL.BookmarkCreationOptions = scope,
                           using access: FolderAccess = .system) -> RememberedFolder? {
        guard !data.isEmpty else { return nil }

        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: resolution,
                                 relativeTo: nil, bookmarkDataIsStale: &isStale),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }

        guard isStale else { return RememberedFolder(url: url, refreshedBookmark: nil) }
        // Re-creating a security-scoped bookmark needs the scope held.
        let refreshed = access.within(url) { bookmark(for: url, options: creation) }
        return RememberedFolder(url: url, refreshedBookmark: refreshed.isEmpty ? nil : refreshed)
    }

    /// Whether the download can write to `url`.
    ///
    /// **Inside the security scope.** Under the sandbox a folder restored from
    /// a bookmark is invisible to `isWritableFile` until its scope is started,
    /// so asking first and starting the scope later refused every remembered
    /// folder after a relaunch.
    static func isWritable(_ url: URL, using access: FolderAccess = .system) -> Bool {
        access.within(url) { access.isWritable(url.path) }
    }
}

/// A folder from a bookmark.
struct RememberedFolder: Equatable {
    let url: URL
    /// A bookmark to store in place of the old one; `nil` when it was fresh.
    let refreshedBookmark: Data?
}

/// The file-system calls a sandboxed folder needs, injectable so the order they
/// run in can be tested from a process that is not sandboxed.
struct FolderAccess: Sendable {
    let start: @Sendable (URL) -> Bool
    let stop: @Sendable (URL) -> Void
    let isWritable: @Sendable (String) -> Bool

    static let system = FolderAccess(
        start: { $0.startAccessingSecurityScopedResource() },
        stop: { $0.stopAccessingSecurityScopedResource() },
        isWritable: { FileManager.default.isWritableFile(atPath: $0) })

    /// Runs `body` with the scope held, and releases only a scope it started.
    func within<T>(_ url: URL, _ body: () -> T) -> T {
        let started = start(url)
        defer { if started { stop(url) } }
        return body()
    }
}
