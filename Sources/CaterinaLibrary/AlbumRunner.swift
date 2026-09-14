import Foundation

import FlickrKit

/// Flickr, as album edits need it. `FlickrClient` in the app.
public protocol AlbumService: PhotoWriter {
    func albumSnapshot(reading reads: [AlbumEdit.Read], albumID: String?, ownerID: String,
                       priority: CallPriority) async throws -> AlbumSnapshot
    func createAlbum(title: String, description: String, coverPhotoID: String,
                     priority: CallPriority) async throws -> String
}

extension FlickrClient: AlbumService {}

/// Running a batch of album edits, step by step.
///
/// Each edit reads its album once, before its first call, and keeps that
/// snapshot: a resume carries on from the step it reached with the same
/// plan, and undo is worked out from what the album was.
public struct AlbumRunner: Sendable {
    private let flickr: any AlbumService
    private let store: LibraryStore
    private let ownerID: String

    public init(flickr: any AlbumService, store: LibraryStore, ownerID: String) {
        self.flickr = flickr
        self.store = store
        self.ownerID = ownerID
    }

    /// Stops, leaving the rest pending, when Flickr needs permission, cannot
    /// be reached, or the task is cancelled. An edit Flickr refuses fails
    /// alone.
    public func run(_ batchID: String,
                    progress: @Sendable (EditBatch.Summary) -> Void = { _ in }) async throws {
        for entry in try store.albumEntries(in: batchID) where entry.state == .pending {
            try Task.checkCancellation()
            do {
                try await apply(entry)
            } catch let refusal as AlbumEdit.Refusal {
                try store.recordAlbum(entry, as: .failed, message: refusal.message)
            } catch let error as FlickrError where !error.stopsTheBatch {
                try store.recordAlbum(entry, as: .failed, message: error.message)
            }
            progress(try store.summary(of: batchID))
        }
    }

    private func apply(_ pending: AlbumEntry) async throws {
        var entry = pending
        if entry.snapshot == nil {
            let snapshot = try await flickr.albumSnapshot(reading: entry.edit.reads, albumID: entry.edit.albumID,
                                                          ownerID: ownerID, priority: .edit)
            entry = try store.recordSnapshot(snapshot, for: entry)
        }
        let plan = try entry.edit.plan(entry.snapshot ?? .empty)
        for step in plan.steps.dropFirst(entry.done) {
            try Task.checkCancellation()
            entry = try await send(step, for: entry)
        }
        try store.recordAlbum(entry, as: .applied)
    }

    private func send(_ step: AlbumPlan.Step, for entry: AlbumEntry) async throws -> AlbumEntry {
        switch step {
        case let .createAlbum(title, description, cover):
            do {
                let id = try await flickr.createAlbum(title: title, description: description,
                                                      coverPhotoID: cover, priority: .edit)
                return try store.recordStep(entry, createdAlbumID: id)
            } catch let error as FlickrError where error.isTransient {
                // Flickr may have made it. Sending again could make two.
                try store.recordAlbum(entry, as: .failed, message: """
                    The connection dropped while making “\(title)”. Look on flickr.com before trying again: \
                    it may have been made.
                    """)
                throw error
            }
        case let .write(write):
            do {
                _ = try await flickr.perform(resolved(write, entry), priority: .edit)
            } catch let error as FlickrError where Self.alreadyDone(error, write) {
                // What the call was for is already so.
            }
            return try store.recordStep(entry)
        }
    }

    private func resolved(_ write: FlickrWrite, _ entry: AlbumEntry) -> FlickrWrite {
        guard write.arguments["photoset_id"] == AlbumEdit.createdAlbum, let id = entry.createdAlbumID else { return write }
        return FlickrWrite(method: write.method, arguments: write.arguments.merging(["photoset_id": id]) { $1 },
                           repeatable: write.repeatable, permission: write.permission)
    }

    /// Already in the album; already not in it; already deleted.
    private static func alreadyDone(_ error: FlickrError, _ write: FlickrWrite) -> Bool {
        guard case let .api(code, _, _) = error else { return false }
        switch (write.method, code) {
        case ("flickr.photosets.addPhoto", 3), ("flickr.photosets.removePhotos", 2), ("flickr.photosets.delete", 1):
            return true
        default:
            return false
        }
    }
}
