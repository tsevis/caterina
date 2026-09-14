import Foundation

import FlickrKit

/// Running rotations, people and deletions, photo by photo.
///
/// A write that cannot be repeated (rotating) whose reply is lost may have
/// happened: that photo fails saying so, and the batch stops, rather than
/// turning it twice on a resume.
public struct PhotoActionRunner: Sendable {
    private let writer: any PhotoWriter
    private let store: LibraryStore

    public init(writer: any PhotoWriter, store: LibraryStore) {
        self.writer = writer
        self.store = store
    }

    public func run(_ batchID: String, progress: @Sendable (EditBatch.Summary) -> Void = { _ in }) async throws {
        for entry in try store.actionEntries(in: batchID) where entry.state == .pending {
            try Task.checkCancellation()
            let write = entry.action.write(photoID: entry.photoID)
            do {
                _ = try await writer.perform(write, priority: .edit)
                try store.recordAction(entry, as: .applied)
            } catch let error as FlickrError where error.stopsTheBatch {
                if error.isTransient, !write.repeatable {
                    try store.recordAction(entry, as: .failed, message: """
                        The connection dropped, so this may have happened. Look at the photo on flickr.com \
                        before trying again.
                        """)
                }
                throw error
            } catch let error as FlickrError {
                try store.recordAction(entry, as: .failed, message: error.message)
            }
            progress(try store.summary(of: batchID))
        }
    }
}
