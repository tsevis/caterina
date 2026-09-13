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

    private let source: LibrarySource
    private let store: LibraryStore
    private let now: @Sendable () -> Date

    public init(source: LibrarySource, store: LibraryStore,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source
        self.store = store
        self.now = now
    }

    public func run(progress: @Sendable (Progress) -> Void = { _ in }) async throws -> Outcome {
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
        let saved = try await fetchAll(generation: generation, progress: progress) { .everything(page: $0) }

        // Only after every page arrived: a sync that failed on page 30 has not
        // learned that pages 31 to 40 were deleted.
        let removed = saved == 0 && existing > 0 ? 0 : try store.removePhotos(olderThan: generation)
        try store.save(LibrarySyncState(generation: generation, lastFullSync: started, changesSince: started))
        return .full(saved: saved, removed: removed)
    }

    private func changes(since: Date, state: LibrarySyncState, started: Date,
                         progress: (Progress) -> Void) async throws -> Outcome {
        let saved = try await fetchAll(generation: state.generation, progress: progress) {
            .updated(since: since, page: $0)
        }
        try store.save(LibrarySyncState(generation: state.generation,
                                        lastFullSync: state.lastFullSync, changesSince: started))
        return .changes(saved: saved)
    }

    /// Every page of `query`, saved as it arrives.
    private func fetchAll(generation: Int, progress: (Progress) -> Void,
                          query: (Int) -> LibraryQuery) async throws -> Int {
        var page = 1
        var pages = 1
        var saved = 0
        repeat {
            try Task.checkCancellation()
            let reply = try await source.library(query(page), priority: .background)
            try store.save(reply.photos, generation: generation)
            saved += reply.photos.count
            pages = reply.pages
            progress(Progress(fetched: saved, total: max(reply.total, saved)))
            page += 1
        } while page <= pages
        return saved
    }
}
