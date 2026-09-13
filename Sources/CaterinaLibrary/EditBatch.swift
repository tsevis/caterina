import Foundation

import FlickrKit

/// One batch edit: what it was called, and one entry per photo it changes.
public struct EditBatch: Sendable, Equatable, Identifiable {

    public struct Summary: Sendable, Equatable {
        public let applied: Int
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
    /// Flickr calls the whole batch takes, for the up-front cost.
    public let calls: Int
}

public struct EditEntry: Sendable, Equatable {
    public enum State: String, Sendable {
        case pending, applied, failed
    }

    public let batchID: String
    public let position: Int
    public let photoID: String
    public let change: PhotoChange
    public let state: State
    /// Flickr's reason, when it refused.
    public let message: String?
}
