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
    ///
    /// Every failure is a `nil` rather than a throw: a bookmark that has gone
    /// stale, been corrupted, or points at a folder since deleted all mean the
    /// same thing to the panel — ask again.
    static func restored(from data: Data,
                         options: URL.BookmarkResolutionOptions = resolution) -> URL? {
        guard !data.isEmpty else { return nil }

        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: options,
                                 relativeTo: nil, bookmarkDataIsStale: &isStale),
              !isStale,
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }
}
