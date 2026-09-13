import Foundation
import Testing

import CaterinaLibrary
import FlickrKit
@testable import CaterinaUI

actor FakeRecords: PhotoRecordSource, StatsSource {
    var infoFailure: FlickrError?
    var statsFailure: FlickrError?
    private(set) var favePagesAsked: [Int] = []

    init(infoFailure: FlickrError? = nil, statsFailure: FlickrError? = nil) {
        self.infoFailure = infoFailure
        self.statsFailure = statsFailure
    }

    func photoInfo(id: String) async throws -> PhotoInfo {
        if let infoFailure { throw infoFailure }
        return PhotoInfo(id: id, title: "Harbour", description: "", owner: .init(nsid: "me", username: "c", realName: ""),
                         views: 1842, commentCount: 1, license: .by, tags: ["sea"], posted: nil, taken: nil,
                         visibility: .init(isPublic: true, isFriend: false, isFamily: false),
                         location: nil, place: nil, pageURL: nil)
    }
    func favorites(photoID: String, page: Int) async throws -> FavePage {
        favePagesAsked.append(page)
        return FavePage(page: page, pages: 2, total: 3, faves: page == 1
            ? [Fave(nsid: "a", username: "A", date: Date(timeIntervalSince1970: 200)),
               Fave(nsid: "b", username: "B", date: Date(timeIntervalSince1970: 100))]
            : [Fave(nsid: "c", username: "C", date: Date(timeIntervalSince1970: 50))])
    }
    func comments(photoID: String) async throws -> [PhotoComment] {
        [PhotoComment(id: "1", authorName: "A", date: Date(timeIntervalSince1970: 10), text: "Lovely")]
    }
    func contexts(photoID: String) async throws -> PhotoContexts {
        PhotoContexts(albums: [.init(id: "s", title: "Athens")], groups: [])
    }
    func exif(photoID: String) async throws -> PhotoExif {
        PhotoExif(camera: "Canon", fields: [], isHidden: false)
    }
    func popularPhotos(on day: StatsDay, page: Int, priority: CallPriority) async throws -> PopularPage {
        if let statsFailure { throw statsFailure }
        return PopularPage(page: 1, pages: 1, photos: [PhotoDayStats(photoID: "1", title: "", views: 5, comments: 0, faves: 1)])
    }
    func totalViews(on day: StatsDay?, priority: CallPriority) async throws -> ViewTotals {
        if let statsFailure { throw statsFailure }
        return ViewTotals(total: 7, photos: 5, photostream: 2, albums: 0, collections: 0)
    }
}

@MainActor
@Suite struct BrowseModelTests {

    /// 2024-06-01 12:00 GMT.
    private let now = Date(timeIntervalSince1970: 1_717_243_200)

    private func library() throws -> LibraryStore {
        let store = try LibraryStore.inMemory()
        try store.save([
            LibraryPhoto(id: "1", title: "Harbour", uploaded: Date(timeIntervalSince1970: 300), views: 50),
            LibraryPhoto(id: "2", title: "Hill", uploaded: Date(timeIntervalSince1970: 900), views: 500),
            LibraryPhoto(id: "3", title: "", uploaded: Date(timeIntervalSince1970: 600), views: 5),
        ], generation: 1)
        return store
    }

    private func model(_ store: LibraryStore?, _ records: FakeRecords = FakeRecords()) -> BrowseModel {
        BrowseModel(store: store, records: records, stats: records, now: { self.now })
    }

    @Test func itOpensOnYourMostViewedPhotosOfAllTime() throws {
        let model = model(try library())
        #expect(model.ranking == .mostViewed)
        #expect(model.rows.map(\.photoID) == ["2", "1", "3"])
        #expect(model.rows.first?.figure == "500 views")
        #expect(model.rows.last?.title == "Untitled")
    }

    @Test func recentUploadsAreNewestFirst() throws {
        let model = model(try library())
        model.show(.recentUploads)
        #expect(model.rows.map(\.photoID) == ["2", "3", "1"])
    }

    @Test func thisWeeksTopPhotosComeFromSavedHistory() throws {
        let store = try library()
        try store.saveStatsDay(StatsDay("2024-05-31")!, photos: [
            PhotoDayStats(photoID: "3", title: "", views: 90, comments: 0, faves: 4),
            PhotoDayStats(photoID: "1", title: "", views: 10, comments: 0, faves: 9)], totals: .zero)
        try store.saveStatsDay(StatsDay("2024-05-01")!, photos: [
            PhotoDayStats(photoID: "2", title: "", views: 1000, comments: 0, faves: 0)], totals: .zero)
        let model = model(store)

        model.show(.topThisWeek)
        #expect(model.rows.map(\.photoID) == ["3", "1"])
        #expect(model.rows.first?.figure == "90 views this week")

        model.show(.mostFavedThisMonth)
        #expect(model.rows.map(\.photoID) == ["1", "3"])
        #expect(model.rows.first?.figure == "9 faves in 28 days")
    }

    @Test func choosingAPhotoLoadsItsWholeRecord() async throws {
        let store = try library()
        try store.saveStatsDay(StatsDay("2024-05-31")!, photos: [
            PhotoDayStats(photoID: "1", title: "", views: 12, comments: 0, faves: 1)], totals: .zero)
        let records = FakeRecords()
        let model = model(store, records)

        await model.select("1")

        guard case let .loaded(record) = model.record else { Issue.record("not loaded: \(model.record)"); return }
        #expect(record.info.views == 1842)
        #expect(record.faves.map(\.username) == ["A", "B", "C"])
        #expect(record.faveTotal == 3)
        #expect(record.comments.count == 1)
        #expect(record.contexts.albums.map(\.title) == ["Athens"])
        #expect(record.exif.camera == "Canon")
        #expect(record.history.map(\.views) == [12])
        #expect(await records.favePagesAsked == [1, 2])
    }

    /// Faves over time, oldest first, as a running total.
    @Test func favesAddUpOverTime() {
        let faves = [Fave(nsid: "a", username: "", date: Date(timeIntervalSince1970: 300)),
                     Fave(nsid: "b", username: "", date: Date(timeIntervalSince1970: 100))]
        #expect(PhotoRecord.cumulativeFaves(faves, total: 2).map(\.count) == [1, 2])
        #expect(PhotoRecord.cumulativeFaves(faves, total: 2).first?.date == Date(timeIntervalSince1970: 100))
    }

    /// Only the latest faves are read; the curve starts from the ones before.
    @Test func aHeavilyFavedPhotosCurveStartsFromTheFavesNotRead() {
        let faves = [Fave(nsid: "a", username: "", date: Date(timeIntervalSince1970: 300)),
                     Fave(nsid: "b", username: "", date: Date(timeIntervalSince1970: 300))]
        let counts = PhotoRecord.cumulativeFaves(faves, total: 40_000)
        #expect(counts.map(\.count) == [39_999, 40_000])
        #expect(Set(counts.map(\.id)).count == 2)
    }

    /// Rising compares two whole weeks; with fewer saved, every photo with a
    /// view this week would "rise" from nothing.
    @Test func risingWaitsForTwoWeeksOfHistory() throws {
        let store = try library()
        try store.saveStatsDay(StatsDay("2024-05-31")!, photos: [
            PhotoDayStats(photoID: "1", title: "", views: 90, comments: 0, faves: 0)], totals: .zero)
        let model = model(store)
        model.show(.rising)
        #expect(model.rows.isEmpty)
        #expect(!model.hasHistory(for: .rising))
    }

    @Test func theDetailThumbnailComesFromTheLibraryNotTheRanking() throws {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryPhoto(id: "9", thumbnailURL: "https://live.staticflickr.com/9_q.jpg")], generation: 1)
        #expect(model(store).thumbnailURL(for: "9") == "https://live.staticflickr.com/9_q.jpg")
    }

    @Test func aPhotoThatCannotBeReadSaysWhy() async throws {
        let model = model(try library(), FakeRecords(infoFailure: .notFound("Photo not found")))
        await model.select("1")
        #expect(model.record == .failed("Photo not found"))
    }

    @Test func savingStatsFillsTheAccountHistory() async throws {
        let model = model(try library())
        await model.saveStats()
        #expect(model.statsPhase == .saved(days: 27))
        #expect(model.accountHistory.count == 27)
    }

    @Test func withoutFlickrProInsightsSaysSo() async throws {
        let model = model(try library(), FakeRecords(statsFailure: .api(code: 1, message: "User does not have stats", transient: false)))
        await model.saveStats()
        #expect(model.statsPhase == .unavailable)
    }
}
