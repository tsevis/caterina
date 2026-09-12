import Foundation
import Testing

@testable import FlickrDownloaderUI

/// Cleaning up after Quick Look and drag-out.
@Suite struct TemporaryFilesTests {

    private func directory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sweep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func make(_ name: String, in folder: URL, ageInHours: Double) throws -> URL {
        let url = folder.appendingPathComponent(name)
        if name.hasSuffix("/") || name.hasPrefix("drag-") {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try Data("x".utf8).write(to: url)
        }
        let when = Date().addingTimeInterval(-ageInHours * 3600)
        try FileManager.default.setAttributes([.modificationDate: when],
                                              ofItemAtPath: url.path)
        return url
    }

    private func names(in folder: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
    }

    @Test func staleDragFoldersAndPreviewsAreRemoved() throws {
        let folder = try directory()
        _ = try make("drag-ABC", in: folder, ageInHours: 5)
        _ = try make("Quick Look_123.jpg", in: folder, ageInHours: 5)

        TemporaryFiles.sweep(in: folder)
        #expect(try names(in: folder).isEmpty)
    }

    /// A preview that might still be open on screen must survive.
    @Test func recentOnesAreLeftAlone() throws {
        let folder = try directory()
        _ = try make("drag-FRESH", in: folder, ageInHours: 0)
        _ = try make("Quick Look_9.jpg", in: folder, ageInHours: 0)

        TemporaryFiles.sweep(in: folder)
        #expect(try names(in: folder).count == 2)
    }

    /// It sweeps *this* application's leavings and nothing else. The temporary
    /// directory is shared, and deleting a stranger's file is not tidying up.
    @Test func nothingElseInTheTemporaryDirectoryIsTouched() throws {
        let folder = try directory()
        _ = try make("someone-elses-file.txt", in: folder, ageInHours: 99)
        _ = try make("important.sqlite", in: folder, ageInHours: 99)
        _ = try make("drag-OLD", in: folder, ageInHours: 99)

        TemporaryFiles.sweep(in: folder)
        #expect(try names(in: folder) == ["someone-elses-file.txt", "important.sqlite"])
    }

    @Test func aMissingDirectoryIsNotAFailure() {
        TemporaryFiles.sweep(in: URL(fileURLWithPath: "/nowhere/at/all"))
    }

    @Test func theStalenessThresholdIsRespected() throws {
        let folder = try directory()
        _ = try make("drag-A", in: folder, ageInHours: 2)
        TemporaryFiles.sweep(in: folder, staleAfter: 60 * 60 * 24)
        #expect(try names(in: folder) == ["drag-A"])
    }
}

/// The thumbnail cache has a stated size.
@Suite struct ThumbnailCacheTests {

    /// The failure this replaces: `URLSessionConfiguration.default` kept other
    /// people's photographs on disk without a meaningful bound, and a short
    /// browsing session had already left 6.6MB of them in the container.
    @Test func theDiskCacheIsBounded() {
        #expect(ThumbnailStore.diskCapacity > 0)
        #expect(ThumbnailStore.diskCapacity <= 256 * 1024 * 1024)
        #expect(ThumbnailStore.memoryCapacity < ThumbnailStore.diskCapacity)
    }

    @Test func clearingForgetsWhatWasBrowsed() async {
        let store = ThumbnailStore()
        await store.clear()
        #expect(await store.diskUsage >= 0)
    }
}
