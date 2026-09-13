import Foundation
import Testing

import FlickrKit
@testable import CaterinaLibrary

/// Answers stats from a script keyed on day.
actor ScriptedStats: StatsSource {
    private let perDay: [String: [[PhotoDayStats]]]
    private let failure: FlickrError?
    private(set) var askedDays: [String] = []

    /// `perDay[day]` is that day's pages.
    init(_ perDay: [String: [[PhotoDayStats]]], failure: FlickrError? = nil) {
        self.perDay = perDay
        self.failure = failure
    }

    func popularPhotos(on day: StatsDay, page: Int, priority: CallPriority) async throws -> PopularPage {
        if let failure { throw failure }
        askedDays.append(day.text)
        let pages = perDay[day.text] ?? [[]]
        return PopularPage(page: page, pages: pages.count, photos: pages[page - 1])
    }

    func totalViews(on day: StatsDay?, priority: CallPriority) async throws -> ViewTotals {
        if let failure { throw failure }
        let views = (perDay[day?.text ?? ""] ?? []).joined().reduce(0) { $0 + $1.views }
        return ViewTotals(total: views + 10, photos: views, photostream: 10, albums: 0, collections: 0)
    }
}

@Suite struct StatsHistoryTests {

    /// 2024-06-01 12:00 GMT: whole days available are 05-31 back to 05-05.
    private let now = Date(timeIntervalSince1970: 1_717_243_200)

    private func stats(_ id: String, views: Int, faves: Int = 0, comments: Int = 0) -> PhotoDayStats {
        PhotoDayStats(photoID: id, title: "", views: views, comments: comments, faves: faves)
    }

    private func day(_ text: String) -> StatsDay { StatsDay(text)! }

    @Test func everyWholeDayFlickrStillHoldsIsSavedOldestFirst() async throws {
        let store = try LibraryStore.inMemory()
        let source = ScriptedStats(["2024-05-31": [[stats("1", views: 5)], [stats("2", views: 3)]]])

        let outcome = try await StatsSnapshot(source: source, store: store).run(now: now)

        #expect(outcome == .saved(days: 27))
        #expect(await source.askedDays.first == "2024-05-05")
        #expect(try store.savedStatsDays().count == 27)
        #expect(try store.statsHistory(photoID: "2").map(\.views) == [3])
        #expect(try store.accountHistory().last?.totals.photos == 8)
    }

    @Test func aDayAlreadySavedIsNotAskedForAgain() async throws {
        let store = try LibraryStore.inMemory()
        let source = ScriptedStats([:])
        _ = try await StatsSnapshot(source: source, store: store).run(now: now)

        let later = ScriptedStats([:])
        let outcome = try await StatsSnapshot(source: later, store: store).run(now: now.addingTimeInterval(86_400))

        #expect(outcome == .saved(days: 1))
        #expect(await later.askedDays == ["2024-06-01"])
    }

    /// A day half-fetched when Flickr failed is not a day with no views.
    @Test func aDayThatFailedPartWayIsNotSaved() async throws {
        let store = try LibraryStore.inMemory()
        let source = ScriptedStats([:], failure: .busy("Flickr is busy right now."))
        await #expect(throws: FlickrError.self) {
            _ = try await StatsSnapshot(source: source, store: store).run(now: now)
        }
        #expect(try store.savedStatsDays().isEmpty)
    }

    @Test func anAccountWithoutStatsSaysSo() async throws {
        let store = try LibraryStore.inMemory()
        let source = ScriptedStats([:], failure: .api(code: 1, message: "User does not have stats", transient: false))
        #expect(try await StatsSnapshot(source: source, store: store).run(now: now) == .statsUnavailable)
    }

    // MARK: - Reading history

    @Test func aPhotosHistoryRunsOldestToNewestWithQuietDaysAbsent() throws {
        let store = try LibraryStore.inMemory()
        try store.saveStatsDay(day("2024-05-30"), photos: [stats("1", views: 4, faves: 1)], totals: .zero)
        try store.saveStatsDay(day("2024-05-29"), photos: [stats("1", views: 9)], totals: .zero)
        try store.saveStatsDay(day("2024-05-31"), photos: [stats("2", views: 1)], totals: .zero)

        let history = try store.statsHistory(photoID: "1")
        #expect(history.map(\.day.text) == ["2024-05-29", "2024-05-30"])
        #expect(history.map(\.faves) == [0, 1])
    }

    @Test func topPhotosOverAPeriod() throws {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryPhoto(id: "1", title: "Harbour"), LibraryPhoto(id: "2", title: "Hill")], generation: 1)
        try store.saveStatsDay(day("2024-05-30"), photos: [stats("1", views: 10, faves: 3), stats("2", views: 50)], totals: .zero)
        try store.saveStatsDay(day("2024-05-31"), photos: [stats("1", views: 30, faves: 1), stats("3", views: 5)], totals: .zero)

        let byViews = try store.topPhotos(from: day("2024-05-30"), through: day("2024-05-31"), by: .views, limit: 10)
        #expect(byViews.map(\.photoID) == ["2", "1", "3"])
        #expect(byViews.map(\.total) == [50, 40, 5])
        #expect(byViews.first?.photo?.title == "Hill")
        #expect(byViews.last?.photo == nil)

        let byFaves = try store.topPhotos(from: day("2024-05-30"), through: day("2024-05-31"), by: .faves, limit: 1)
        #expect(byFaves.map(\.photoID) == ["1"])
        #expect(byFaves.first?.total == 4)
    }

    /// Rising: most views gained this week over the week before.
    @Test func risingPhotosCompareThisWeekWithTheLast() throws {
        let store = try LibraryStore.inMemory()
        var current = day("2024-05-18")
        for _ in 0..<14 {
            let recent = current >= day("2024-05-25")
            try store.saveStatsDay(current, photos: [stats("steady", views: 10),
                                                     stats("rising", views: recent ? 30 : 2),
                                                     stats("falling", views: recent ? 1 : 20)], totals: .zero)
            current = StatsDay(containing: current.start.addingTimeInterval(36 * 3600))
        }

        let rising = try store.risingPhotos(endingOn: day("2024-05-31"), limit: 5)

        #expect(rising.map(\.photoID) == ["rising"])
        #expect(rising.first?.thisWeek == 210)
        #expect(rising.first?.weekBefore == 14)
    }
}
