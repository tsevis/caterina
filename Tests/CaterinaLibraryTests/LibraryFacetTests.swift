import Foundation
import GRDB
import Testing

import FlickrKit
@testable import CaterinaLibrary

/// The ways into a library without calling Flickr: tags, time, licence, who
/// can see a photo, what kind it is.
@Suite struct LibraryFacetTests {

    private func store() throws -> LibraryStore {
        let store = try LibraryStore.inMemory()
        try store.save([
            LibraryPhoto(id: "1", tags: ["sea", "athens"], license: .by,
                         visibility: .init(isPublic: true, isFriend: false, isFamily: false),
                         taken: "2024-06-01 10:00:00", media: .photo, mediumURL: "z1"),
            LibraryPhoto(id: "2", tags: ["sea"], license: .allRightsReserved,
                         visibility: .init(isPublic: false, isFriend: true, isFamily: true),
                         taken: "2024-06-20 10:00:00", media: .video),
            LibraryPhoto(id: "3", tags: ["mosaic", "sea"], license: .by,
                         visibility: .init(isPublic: false, isFriend: false, isFamily: false),
                         taken: "2023-12-31 23:59:59"),
            LibraryPhoto(id: "4", taken: nil),
        ], generation: 1)
        return store
    }

    @Test func theLargerThumbnailIsKept() throws {
        #expect(try store().photo(id: "1")?.mediumURL == "z1")
    }

    @Test func tagsAreCountedMostUsedFirst() throws {
        let counts = try store().tagCounts()
        #expect(counts == [TagCount(tag: "sea", count: 3), TagCount(tag: "athens", count: 1), TagCount(tag: "mosaic", count: 1)])
    }

    @Test func monthsAreCountedByDateTakenNewestFirst() throws {
        let months = try store().monthCounts()
        #expect(months == [MonthCount(month: "2024-06", count: 2), MonthCount(month: "2023-12", count: 1)])
        #expect(months.first?.year == "2024")
        #expect(months.first?.title == "June 2024")
    }

    @Test func aYearOrAMonthFiltersByDateTaken() throws {
        let store = try store()
        #expect(Set(try store.photos(.takenIn("2024")).map(\.id)) == ["1", "2"])
        #expect(try store.photos(.takenIn("2023-12")).map(\.id) == ["3"])
    }

    /// `_` in a typed period must not match any character.
    @Test func aPeriodIsMatchedLiterally() throws {
        #expect(try store().photos(.takenIn("2024_06")).isEmpty)
    }

    @Test func licenceVisibilityAndKind() throws {
        let store = try store()
        #expect(Set(try store.photos(.licensed(.by)).map(\.id)) == ["1", "3"])
        #expect(try store.photos(.seenBy(.everyone)).map(\.id) == ["1", "4"])
        #expect(try store.photos(.seenBy(.friendsOrFamily)).map(\.id) == ["2"])
        #expect(try store.photos(.seenBy(.onlyYou)).map(\.id) == ["3"])
        #expect(try store.photos(.videos).map(\.id) == ["2"])
    }

    /// Copies made before the larger thumbnail was stored have none; the next
    /// sync is a full one, so they fill in.
    @Test func upgradingAnOlderCopyMakesTheNextSyncFull() throws {
        let queue = try DatabaseQueue()
        try LibrarySchema.migrator.migrate(queue, upTo: "v4-stats-history")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO syncState (id, generation, lastFullSync, changesSince, lastSynced) VALUES (1, 3, 1700000000, 1700000000, 1700000000)")
        }
        let store = try LibraryStore(database: queue)
        let state = try store.syncState()
        #expect(state.lastFullSync == nil)
        #expect(state.generation == 3)
    }
}

/// The timeline by the month photos were posted, as well as taken.
@Suite struct UploadedTimelineTests {
    @Test func monthsPostedAreCountedAndFiltered() throws {
        let store = try LibraryStore.inMemory()
        // 2024-06-01 and 2024-06-30 (GMT), 2024-05-15.
        try store.save([LibraryPhoto(id: "1", uploaded: Date(timeIntervalSince1970: 1_717_243_200)),
                        LibraryPhoto(id: "2", uploaded: Date(timeIntervalSince1970: 1_719_748_800)),
                        LibraryPhoto(id: "3", uploaded: Date(timeIntervalSince1970: 1_715_774_400)),
                        LibraryPhoto(id: "4")], generation: 1)
        #expect(try store.uploadedMonthCounts() == [MonthCount(month: "2024-06", count: 2), MonthCount(month: "2024-05", count: 1)])
        #expect(try store.photos(.uploadedIn("2024-06")).map(\.id).sorted() == ["1", "2"])
    }
}
