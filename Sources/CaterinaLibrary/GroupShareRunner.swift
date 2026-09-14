import Foundation

import FlickrKit

/// Where pool writes go. `FlickrClient` in the app.
public protocol GroupPoolWriter: PhotoWriter {}

extension FlickrClient: GroupPoolWriter {}

/// Sending photos to pools, and taking them out, pair by pair.
///
/// A refusal that closes a group (its limit, a full or closed pool) or a
/// photo (in too many pools) skips the rest of that group's or photo's pairs
/// without a call each. Flickr unreachable, or permission needed, stops the
/// batch with the rest pending.
public struct GroupShareRunner: Sendable {
    private let flickr: any GroupPoolWriter
    private let store: LibraryStore

    public init(flickr: any GroupPoolWriter, store: LibraryStore) {
        self.flickr = flickr
        self.store = store
    }

    public func run(_ batchID: String, progress: @Sendable (EditBatch.Summary) -> Void = { _ in }) async throws {
        let entries = try store.groupEntries(in: batchID)
        var closed = Closed(entries)
        for entry in entries where entry.state == .pending {
            try Task.checkCancellation()
            if let reason = closed.reason(for: entry.pair) {
                try store.recordGroup(entry, .skipped(reason))
            } else {
                let wasSending = entry.isSending
                try store.markSending(entry)
                let outcome = Self.settled(try await send(entry), wasSending: wasSending)
                try store.recordGroup(entry, outcome)
                closed.note(outcome, for: entry.pair)
            }
            progress(try store.summary(of: batchID))
        }
    }

    private func send(_ entry: GroupEntry) async throws -> GroupShareOutcome {
        let (photo, group) = (entry.pair.photoID, entry.pair.groupID)
        do {
            switch entry.action {
            case .add: _ = try await flickr.perform(GroupWrites.add(photoID: photo, groupID: group), priority: .edit)
            case .remove: _ = try await flickr.perform(GroupWrites.remove(photoID: photo, groupID: group), priority: .edit)
            }
            return entry.action == .add ? .added : .removed
        } catch let error as FlickrError where !error.stopsTheBatch {
            return entry.action == .add ? GroupShareOutcome(addingFailedWith: error)
                                        : GroupShareOutcome(removingFailedWith: error)
        }
    }

    /// Sent before an interruption and found already so on resume: that was
    /// this batch, so undo must take it back.
    static func settled(_ outcome: GroupShareOutcome, wasSending: Bool) -> GroupShareOutcome {
        guard wasSending else { return outcome }
        switch outcome {
        case .alreadyInPool: return .added
        case .alreadyPending: return .pendingModeration
        case .notInPool: return .removed
        default: return outcome
        }
    }

    /// Whether a refusal from an earlier run still stands: a limit or a full
    /// pool may have cleared since.
    public static func carriesOver(_ refusal: GroupShareOutcome.Refusal) -> Bool {
        switch refusal {
        case .poolDisabled, .groupNotFound, .photoInTooManyPools, .photoNotFound: true
        case .groupLimitReached, .poolFull, .contentNotAllowed, .other: false
        }
    }

    /// Groups and photos an earlier refusal closed, this run or a previous.
    private struct Closed {
        private var groups: [String: GroupShareOutcome.Refusal] = [:]
        private var photos: [String: GroupShareOutcome.Refusal] = [:]

        init(_ entries: [GroupEntry]) {
            for entry in entries {
                guard case let .refused(reason) = entry.outcome, GroupShareRunner.carriesOver(reason) else { continue }
                note(.refused(reason), for: entry.pair)
            }
        }

        func reason(for pair: GroupPair) -> GroupShareOutcome.Refusal? {
            groups[pair.groupID] ?? photos[pair.photoID]
        }

        mutating func note(_ outcome: GroupShareOutcome, for pair: GroupPair) {
            guard case let .refused(reason) = outcome else { return }
            switch reason.closes {
            case .group: groups[pair.groupID] = reason
            case .photo: photos[pair.photoID] = reason
            case nil: break
            }
        }
    }
}
