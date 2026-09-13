import Foundation
import Testing

@testable import CaterinaUI

/// The remembered folder after a relaunch.
///
/// **Under the sandbox a restored bookmark grants nothing until the scope is
/// started.** The sheet asked `isWritableFile` first and started the scope
/// later, inside `startDownload` — so a folder remembered across a relaunch
/// was pre-filled, looked right, and was refused as "cannot be written to".
/// Confirmed with a sandboxed probe: `isWritableFile` answers `false` for an
/// ungranted folder the process can plainly see. This process is not
/// sandboxed, so the order is what is pinned.
@Suite struct FolderAccessTests {

    private final class Log: @unchecked Sendable {
        var entries: [String] = []
    }

    private func access(_ log: Log, granted: Bool = true, writable: Bool = true) -> FolderAccess {
        FolderAccess(start: { _ in log.entries.append("start"); return granted },
                     stop: { _ in log.entries.append("stop") },
                     isWritable: { _ in log.entries.append("check"); return writable })
    }

    private let folder = URL(fileURLWithPath: "/Users/someone/Pictures/Flickr")

    @Test func theWritabilityCheckRunsInsideTheSecurityScope() {
        let log = Log()
        #expect(DownloadFolder.isWritable(folder, using: access(log)))
        #expect(log.entries == ["start", "check", "stop"])
    }

    @Test func aFolderThatCannotBeWrittenIsStillReleased() {
        let log = Log()
        #expect(!DownloadFolder.isWritable(folder, using: access(log, writable: false)))
        #expect(log.entries == ["start", "check", "stop"])
    }

    /// A folder the panel granted this launch needs no scope started, and
    /// stopping one that was never started would unbalance the count.
    @Test func aScopeThatWasNotStartedIsNotStopped() {
        let log = Log()
        #expect(DownloadFolder.isWritable(folder, using: access(log, granted: false)))
        #expect(log.entries == ["start", "check"])
    }
}

/// A moved or renamed folder is still the folder.
@Suite struct StaleBookmarkTests {

    private func directory(_ name: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("caterina-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// **Stale means "refresh me", not "gone".** The bookmark still resolves,
    /// to where the folder is now; throwing it away made renaming the folder
    /// in the Finder forget it.
    @Test func aRenamedFolderIsFollowedAndItsBookmarkRefreshed() throws {
        let folder = try directory("before")
        let data = DownloadFolder.bookmark(for: folder, options: [])
        let moved = folder.deletingLastPathComponent()
            .appendingPathComponent("caterina-after-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: folder, to: moved)
        defer { try? FileManager.default.removeItem(at: moved) }

        let remembered = try #require(DownloadFolder.remembered(
            from: data, resolution: [], creation: []))

        #expect(remembered.url.resolvingSymlinksInPath().path
            == moved.resolvingSymlinksInPath().path)
        let refreshed = try #require(remembered.refreshedBookmark)
        #expect(DownloadFolder.remembered(from: refreshed, resolution: [], creation: [])?
            .refreshedBookmark == nil, "a refreshed bookmark should not be stale")
    }

    @Test func aFreshBookmarkNeedsNoRefresh() throws {
        let folder = try directory("fresh")
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = DownloadFolder.bookmark(for: folder, options: [])
        let remembered = try #require(DownloadFolder.remembered(
            from: data, resolution: [], creation: []))
        #expect(remembered.refreshedBookmark == nil)
    }
}
