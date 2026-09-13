import Foundation

import FlickrKit

/// Where writes go. `FlickrClient` in the app; a script in tests.
public protocol PhotoWriter: Sendable {
    func perform(_ write: FlickrWrite, priority: CallPriority) async throws -> Data
}

/// Where a photo is read back from just before it is changed.
public protocol LivePhotoReader: Sendable {
    func livePhoto(id: String, priority: CallPriority) async throws -> LibraryPhoto
}

extension FlickrClient: PhotoWriter, LivePhotoReader {}

/// Running a batch edit, photo by photo.
///
/// **Every step is written down before the next begins**, so a batch
/// interrupted by quitting, sleep or a lost connection resumes from the first
/// photo still pending — nothing is sent twice and nothing is skipped.
///
/// **Each photo is read from Flickr first.** The change recorded from the
/// local copy is laid over what Flickr has now (`PhotoChange.rebased`), which
/// keeps raw tag spellings and refuses to write over a field changed on
/// flickr.com since the last sync. The laid-over change is what is recorded,
/// so undo puts back what Flickr really had.
public struct BatchRunner: Sendable {
    private let flickr: any PhotoWriter & LivePhotoReader
    private let store: LibraryStore

    public init(writer: any PhotoWriter & LivePhotoReader, store: LibraryStore) {
        self.flickr = writer
        self.store = store
    }

    /// Run every pending entry. Stops, leaving the rest pending, when Flickr
    /// needs more permission, cannot be reached, or the task is cancelled; a
    /// photo Flickr refuses is recorded as failed and the batch carries on.
    @discardableResult
    public func run(_ batchID: String,
                    progress: @Sendable (EditBatch.Summary) -> Void = { _ in }) async throws -> EditBatch.Summary {
        for entry in try store.entries(in: batchID) where entry.state == .pending {
            try Task.checkCancellation()
            do {
                try await apply(entry)
            } catch let error as FlickrError {
                // Nothing about this photo: every photo after it would fail the
                // same way.
                if case .permissionNeeded = error { throw error }
                if error.isTransient { throw error }
                try store.record(entry, as: .failed, message: error.message)
            }
            progress(try store.summary(of: batchID))
        }
        return try store.summary(of: batchID)
    }

    private func apply(_ entry: EditEntry) async throws {
        let live = try await flickr.livePhoto(id: entry.photoID, priority: .edit)
        switch entry.change.rebased(onto: live) {
        case let .conflict(reason):
            try store.record(entry, as: .failed, message: reason)
        case let .change(change):
            let rebased = try store.replaceChange(of: entry, with: change)
            for write in change.writes {
                _ = try await flickr.perform(write, priority: .edit)
            }
            try store.record(rebased, as: .applied)
        }
    }
}
