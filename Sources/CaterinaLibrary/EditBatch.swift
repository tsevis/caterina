import Foundation

import FlickrKit

/// One batch edit: what it was called, and one entry per photo it changes.
public struct EditBatch: Sendable, Equatable, Identifiable {

    public struct Summary: Sendable, Equatable {
        public let applied: Int
        /// Refused outright or in part.
        public let failed: Int
        public let pending: Int

        public init(applied: Int, failed: Int, pending: Int) {
            self.applied = applied
            self.failed = failed
            self.pending = pending
        }

        public var isFinished: Bool { pending == 0 }
    }

    public let id: String
    public let title: String
    public let createdAt: Date
    /// The batch this one takes back, when it is an undo.
    public let undoes: String?
    /// Flickr calls still to make, for the up-front cost: an estimate, since
    /// each photo's writes are settled only once it is read from Flickr.
    public let calls: Int
}

public struct EditEntry: Sendable, Equatable {
    public enum State: String, Sendable {
        case pending, applied, failed
        /// Some of the photo's writes landed before Flickr refused one.
        case partial
    }

    public let batchID: String
    public let position: Int
    public let photoID: String
    public let change: PhotoChange
    public let state: State
    /// Flickr's reason, when it refused.
    public let message: String?
    /// Laid over the photo as Flickr had it; the before is Flickr's own.
    public let isRebased: Bool
}
