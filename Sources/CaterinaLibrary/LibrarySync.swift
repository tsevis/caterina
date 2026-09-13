import Foundation

import FlickrKit

/// Where library pages come from. `FlickrClient` in the app; a script in tests.
public protocol LibrarySource: Sendable {
    func library(_ query: LibraryQuery, priority: CallPriority) async throws -> LibraryPage
}

extension FlickrClient: LibrarySource {}

/// Bringing the local copy up to date with Flickr.
///
/// **A full pass first, then only changes.** Changes are cheap — usually one
/// call — but Flickr never reports a deletion through them, so a full pass
/// runs again weekly and removes whatever it did not see.
public actor LibrarySync {

    public struct Progress: Sendable, Equatable {
        public let fetched: Int
        public let total: Int
    }

    public enum Outcome: Sendable, Equatable {
        case full(saved: Int, removed: Int)
        case changes(saved: Int)
    }

    public static let fullSyncInterval: TimeInterval = 7 * 24 * 3600
    /// How far back each changes query reaches past the last sync's start, for
    /// a Mac clock running ahead of Flickr's. Fetching a photo twice is free.
    public static let clockAllowance: TimeInterval = 300

    /// What one pass through every page saw.
    private struct Pass {
        var saved = 0
        var ids = Set<String>()
        var skipped = 0
        var firstTotal = 0
    }

    private let source: LibrarySource
    private let store: LibraryStore
    private let now: @Sendable () -> Date
    private var inFlight: Task<Outcome, Error>?

    public init(source: LibrarySource, store: LibraryStore,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source
        self.store = store
        self.now = now
    }

    /// Sync, or join the sync already running: two at once would interleave
    /// their generations and each undo the other's record of where it got to.
    public func run(progress: @escaping @Sendable (Progress) -> Void = { _ in }) async throws -> Outcome {
        if let inFlight { return try await inFlight.value }
        let task = Task { try await self.sync(progress: progress) }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    private func sync(progress: @Sendable (Progress) -> Void) async throws -> Outcome {
        let state = try store.syncState()
        let started = now()
        if let since = state.changesSince, let lastFull = state.lastFullSync,
           started.timeIntervalSince(lastFull) < Self.fullSyncInterval {
            return try await changes(since: since, state: state, started: started, progress: progress)
        }
        return try await full(state: state, started: started, progress: progress)
    }

    private func full(state: LibrarySyncState, started: Date,
                      progress: (Progress) -> Void) async throws -> Outcome {
        let generation = state.generation + 1
        let existing = try store.count(.all)
        let pass = try await fetchAll(generation: generation, progress: progress) { .everything(page: $0) }

        let removed = Self.provesDeletions(pass, existing: existing)
            ? try store.removePhotos(olderThan: generation) : 0
        try store.save(LibrarySyncState(generation: generation, lastFullSync: started,
                                        changesSince: started.addingTimeInterval(-Self.clockAllowance)))
        return .full(saved: pass.saved, removed: removed)
    }

    /// Whether a photo this pass did not see is really gone. Only a pass that
    /// read every entry, saw as many photos as Flickr counted, and saw any at
    /// all in a library that had some, can say so. The page loop reaching the
    /// end is not enough: a sync that failed on page 30 never gets here, but a
    /// photo deleted mid-sync shifts later ones onto pages already read.
    private static func provesDeletions(_ pass: Pass, existing: Int) -> Bool {
        pass.skipped == 0 && pass.ids.count >= pass.firstTotal && !(pass.ids.isEmpty && existing > 0)
    }

    private func changes(since: Date, state: LibrarySyncState, started: Date,
                         progress: (Progress) -> Void) async throws -> Outcome {
        let pass = try await fetchAll(generation: state.generation, progress: progress) {
            .updated(since: since, page: $0)
        }
        try store.save(LibrarySyncState(generation: state.generation, lastFullSync: state.lastFullSync,
                                        changesSince: started.addingTimeInterval(-Self.clockAllowance)))
        return .changes(saved: pass.saved)
    }

    /// Every page of `query`, saved as it arrives.
    private func fetchAll(generation: Int, progress: (Progress) -> Void,
                          query: (Int) -> LibraryQuery) async throws -> Pass {
        var pass = Pass()
        var page = 1
        var pages = 1
        repeat {
            try Task.checkCancellation()
            let reply = try await source.library(query(page), priority: .background)
            try store.save(reply.photos, generation: generation)
            if page == 1 { pass.firstTotal = reply.total }
            pass.saved += reply.photos.count
            pass.ids.formUnion(reply.photos.map(\.id))
            pass.skipped += reply.skippedEntries
            pages = reply.pages
            progress(Progress(fetched: pass.saved, total: max(reply.total, pass.saved)))
            page += 1
        } while page <= pages
        return pass
    }
}
