import Foundation

import CaterinaLibrary
import FlickrKit

/// One batch as the Activity panel lists it.
public struct BatchActivity: Sendable, Equatable, Identifiable {

    public struct Failure: Sendable, Equatable, Identifiable {
        public var id: String { photoID }
        public let photoID: String
        public let title: String
        /// Flickr's reason.
        public let message: String
    }

    public var id: String { batch.id }
    public let batch: EditBatch
    public let summary: EditBatch.Summary
    public let failures: [Failure]
    /// Pending photos, and nothing running it now.
    public let canResume: Bool
    /// Something changed, it is not itself an undo, and it has not been undone.
    public let canUndo: Bool

    static func rows(from store: LibraryStore, limit: Int, runningID: String?) throws -> [BatchActivity] {
        let batches = try store.recentBatches(limit: limit)
        let undone = Set(batches.compactMap(\.undoes))
        return try batches.map { batch in
            let summary = try store.summary(of: batch.id)
            let failures = try store.entries(in: batch.id)
                .filter { $0.state == .failed || $0.state == .partial }
                .map { Failure(photoID: $0.photoID, title: $0.change.before.title, message: $0.message ?? "") }
            let isRunning = batch.id == runningID
            return BatchActivity(batch: batch, summary: summary, failures: failures,
                                 canResume: summary.pending > 0 && !isRunning,
                                 canUndo: batch.undoes == nil && !undone.contains(batch.id) && !isRunning
                                    && summary.applied + failures.count > 0 && summary.pending == 0)
        }
    }
}
