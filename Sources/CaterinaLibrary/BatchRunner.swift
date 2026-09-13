import Foundation

import FlickrKit

/// Where writes go. `FlickrClient` in the app; a script in tests.
public protocol PhotoWriter: Sendable {
    func perform(_ write: FlickrWrite, priority: CallPriority) async throws -> Data
}

extension FlickrClient: PhotoWriter {}

/// Running a batch edit, photo by photo.
///
/// **Every step is written down before the next begins**, so a batch
/// interrupted by quitting, sleep or a lost connection resumes from the first
/// photo still pending — nothing is sent twice and nothing is skipped.
public struct BatchRunner: Sendable {
    private let writer: PhotoWriter
    private let store: LibraryStore

    public init(writer: PhotoWriter, store: LibraryStore) {
        self.writer = writer
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
                for write in entry.change.writes {
                    _ = try await writer.perform(write, priority: .edit)
                }
                try store.record(entry, as: .applied)
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
}
