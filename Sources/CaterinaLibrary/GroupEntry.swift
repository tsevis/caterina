import Foundation

import FlickrKit

/// One photo and one group.
public struct GroupPair: Sendable, Equatable, Hashable {
    public let photoID: String
    public let groupID: String

    public init(photoID: String, groupID: String) {
        self.photoID = photoID
        self.groupID = groupID
    }
}

/// One photo to put in, or take out of, one pool, and what happened.
public struct GroupEntry: Sendable, Equatable {
    public enum Action: String, Sendable { case add, remove }

    public let batchID: String
    public let position: Int
    public let pair: GroupPair
    public let action: Action
    public let state: EditEntry.State
    /// Nil until sent (or skipped).
    public let outcome: GroupShareOutcome?
}

/// A named choice of groups, to pick again.
public struct GroupSet: Sendable, Equatable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public let groupIDs: [String]

    public init(name: String, groupIDs: [String]) {
        self.name = name
        self.groupIDs = groupIDs
    }
}

/// Per group, what a sharing batch did.
public enum GroupShareReport {
    public struct Row: Sendable, Equatable, Identifiable {
        public var id: String { groupID }
        public let groupID: String
        public let added: Int
        /// In a moderator's queue.
        public let waiting: Int
        public let already: Int
        public let refused: [GroupShareOutcome.Refusal: Int]
        public let pending: Int

        public init(groupID: String, added: Int, waiting: Int, already: Int,
                    refused: [GroupShareOutcome.Refusal: Int], pending: Int) {
            self.groupID = groupID
            self.added = added
            self.waiting = waiting
            self.already = already
            self.refused = refused
            self.pending = pending
        }
    }

    static func rows(_ entries: [GroupEntry]) -> [Row] {
        let groups = entries.map(\.pair.groupID).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return groups.map { group in
            let mine = entries.filter { $0.pair.groupID == group }
            let count = { (test: (GroupShareOutcome) -> Bool) in mine.count { $0.outcome.map(test) ?? false } }
            let refusals = mine.compactMap { entry -> GroupShareOutcome.Refusal? in
                switch entry.outcome {
                case let .refused(reason), let .skipped(reason): reason
                default: nil
                }
            }
            return Row(groupID: group,
                       added: count { $0 == .added || $0 == .removed },
                       waiting: count { $0 == .pendingModeration || $0 == .alreadyPending },
                       already: count { $0 == .alreadyInPool || $0 == .notInPool },
                       refused: Dictionary(refusals.map { ($0, 1) }, uniquingKeysWith: +),
                       pending: mine.count { $0.state == .pending })
        }
    }
}
