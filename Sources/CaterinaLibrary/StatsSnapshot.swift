import Foundation

import FlickrKit

/// Where daily stats come from. `FlickrClient` in the app.
public protocol StatsSource: Sendable {
    func popularPhotos(on day: StatsDay, page: Int, priority: CallPriority) async throws -> PopularPage
    func totalViews(on day: StatsDay?, priority: CallPriority) async throws -> ViewTotals
}

extension FlickrClient: StatsSource {}

/// Saving each whole day of stats before Flickr lets it go.
///
/// Flickr keeps 28 days. Every day this saves is kept for good, so history
/// starts on the first run and grows from there.
public actor StatsSnapshot {

    public enum Outcome: Sendable, Equatable {
        case saved(days: Int)
        /// No Flickr Pro, or stats switched off.
        case statsUnavailable
    }

    private let source: StatsSource
    private let store: LibraryStore
    private var inFlight: Task<Outcome, Error>?

    public init(source: StatsSource, store: LibraryStore) {
        self.source = source
        self.store = store
    }

    public func run(now: Date = Date()) async throws -> Outcome {
        if let inFlight { return try await inFlight.value }
        let task = Task { try await self.snapshot(now: now) }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    private func snapshot(now: Date) async throws -> Outcome {
        let saved = try store.savedStatsDays()
        // Oldest first: the day closest to being lost goes first.
        let missing = StatsDay.completeDaysAvailable(at: now).filter { !saved.contains($0) }.reversed()
        var count = 0
        do {
            for day in missing {
                try Task.checkCancellation()
                try await save(day)
                count += 1
            }
        } catch let error as FlickrError where error.meansStatsUnavailable {
            return .statsUnavailable
        }
        return .saved(days: count)
    }

    /// Every page of the day, then its totals, written together.
    private func save(_ day: StatsDay) async throws {
        var photos: [PhotoDayStats] = []
        var page = 1
        var pages = 1
        repeat {
            let reply = try await source.popularPhotos(on: day, page: page, priority: .background)
            photos += reply.photos
            pages = reply.pages
            page += 1
        } while page <= pages
        let totals = try await source.totalViews(on: day, priority: .background)
        try store.saveStatsDay(day, photos: photos, totals: totals)
    }
}
