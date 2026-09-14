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
    /// Pending photos, nothing running it, and made by this account.
    public let canResume: Bool
    /// Something on Flickr changed, it is not itself an undo, it has not been
    /// undone, nothing is running it, and it was made by this account.
    public let canUndo: Bool

    static func rows(from store: LibraryStore, limit: Int, runningID: String?,
                     accountID: String?) throws -> [BatchActivity] {
        let batches = try store.recentBatches(limit: limit)
        let undone = try store.undoneBatchIDs()
        return try batches.map { batch in
            let summary = try store.summary(of: batch.id)
            let (failures, changed) = try outcome(of: batch, in: store)
            let ours = batch.accountID == nil || batch.accountID == accountID
            let idle = batch.id != runningID
            return BatchActivity(batch: batch, summary: summary, failures: failures,
                                 canResume: ours && idle && summary.pending > 0 && !undone.contains(batch.id),
                                 canUndo: ours && idle && changed && batch.undoes == nil && !undone.contains(batch.id))
        }
    }

    /// What was refused, and whether anything on Flickr changed.
    private static func outcome(of batch: EditBatch, in store: LibraryStore) throws -> ([Failure], Bool) {
        switch batch.kind {
        case .photos:
            let entries = try store.entries(in: batch.id)
            let failures = entries.filter { $0.state == .failed || $0.state == .partial }
                .map { Failure(photoID: $0.photoID, title: $0.change.before.title, message: $0.message ?? "") }
            return (failures, entries.contains { $0.state == .applied || $0.state == .partial })
        case .albums:
            let entries = try store.albumEntries(in: batch.id)
            let failures = entries.filter { $0.state == .failed }
                .map { Failure(photoID: "\($0.position)", title: $0.snapshot?.title ?? "", message: $0.message ?? "") }
            return (failures, entries.contains { $0.state == .applied || $0.done > 0 })
        }
    }
}
