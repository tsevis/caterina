import Foundation
import Testing

import FlickrKit
@testable import CaterinaLibrary

/// The local copy of your library.
@Suite struct LibraryStoreTests {

    static func photo(_ id: String, title: String = "", tags: [String] = [],
                      taken: String? = nil, views: Int = 0,
                      location: LibraryPhoto.Location? = nil,
                      isPublic: Bool = true, license: License? = nil,
                      description: String = "") -> LibraryPhoto {
        LibraryPhoto(id: id, title: title, description: description, tags: tags, license: license,
                     visibility: .init(isPublic: isPublic, isFriend: false, isFamily: false),
                     uploaded: Date(timeIntervalSince1970: 1_700_000_000),
                     lastUpdated: Date(timeIntervalSince1970: 1_700_000_500),
                     taken: taken, views: views, media: .photo, location: location,
                     thumbnailURL: "https://live.staticflickr.com/\(id)_q.jpg")
    }

    @Test func aPhotoComesBackExactlyAsItWentIn() throws {
        let store = try LibraryStore.inMemory()
        let original = Self.photo("1", title: "Harbour", tags: ["piraeus", "dusk"],
                                  taken: "2024-06-01 21:14:05", views: 1842,
                                  location: .init(latitude: 37.9, longitude: 23.6, accuracy: 16),
                                  isPublic: false, license: .by, description: "Looking west")
        try store.save([original], generation: 1)
        #expect(try store.photos(.all) == [original])
    }

    @Test func savingAgainReplacesRatherThanDuplicates() throws {
        let store = try LibraryStore.inMemory()
        try store.save([Self.photo("1", title: "Before")], generation: 1)
        try store.save([Self.photo("1", title: "After")], generation: 1)
        #expect(try store.photos(.all).map(\.title) == ["After"])
        #expect(try store.count(.all) == 1)
    }

    // MARK: - Smart views

    @Test func untaggedMeansNoTagsAtAll() throws {
        let store = try LibraryStore.inMemory()
        try store.save([Self.photo("1", tags: ["a"]), Self.photo("2")], generation: 1)
        #expect(try store.photos(.untagged).map(\.id) == ["2"])
    }

    @Test func noLocationAndWithLocationSplitTheLibrary() throws {
        let store = try LibraryStore.inMemory()
        try store.save([Self.photo("1", location: .init(latitude: 1, longitude: 2, accuracy: 16)),
                        Self.photo("2")], generation: 1)
        #expect(try store.photos(.withoutLocation).map(\.id) == ["2"])
        #expect(try store.photos(.withLocation).map(\.id) == ["1"])
    }

    /// A tag filter matches whole tags: "sea" is not "seaside".
    @Test func aTagMatchesOnlyThatTag() throws {
        let store = try LibraryStore.inMemory()
        try store.save([Self.photo("1", tags: ["seaside"]), Self.photo("2", tags: ["blue", "sea"])],
                       generation: 1)
        #expect(try store.photos(.tagged("sea")).map(\.id) == ["2"])
    }

    @Test func searchLooksInTitleDescriptionAndTags() throws {
        let store = try LibraryStore.inMemory()
        try store.save([Self.photo("1", title: "Harbour at dusk"),
                        Self.photo("2", description: "the old harbour"),
                        Self.photo("3", tags: ["harbour"]),
                        Self.photo("4", title: "Mountains")], generation: 1)
        #expect(Set(try store.photos(.matching("harbour")).map(\.id)) == ["1", "2", "3"])
    }

    /// `%` and `_` typed into search are characters, not wildcards.
    @Test func searchTreatsWildcardsAsText() throws {
        let store = try LibraryStore.inMemory()
        try store.save([Self.photo("1", title: "100% Athens"), Self.photo("2", title: "1000 Athens")],
                       generation: 1)
        #expect(try store.photos(.matching("100%")).map(\.id) == ["1"])
    }

    // MARK: - Order

    @Test func mostViewedFirst() throws {
        let store = try LibraryStore.inMemory()
        try store.save([Self.photo("1", views: 5), Self.photo("2", views: 500), Self.photo("3", views: 50)],
                       generation: 1)
        #expect(try store.photos(.all, order: .mostViewed).map(\.id) == ["2", "3", "1"])
    }

    /// Photos with no known date taken go last, whichever way the list runs.
    @Test func newestTakenFirstPutsUnknownDatesLast() throws {
        let store = try LibraryStore.inMemory()
        try store.save([Self.photo("1", taken: "2020-01-01 00:00:00"), Self.photo("2"),
                        Self.photo("3", taken: "2024-01-01 00:00:00")], generation: 1)
        #expect(try store.photos(.all, order: .newestTaken).map(\.id) == ["3", "1", "2"])
        #expect(try store.photos(.all, order: .oldestTaken).map(\.id) == ["1", "3", "2"])
    }

    @Test func aPageOfResults() throws {
        let store = try LibraryStore.inMemory()
        try store.save((1...10).map { Self.photo(String($0), views: $0) }, generation: 1)
        #expect(try store.photos(.all, order: .mostViewed, limit: 3, offset: 3).map(\.id) == ["7", "6", "5"])
    }

    // MARK: - Reconciling

    @Test func photosNotSeenInTheLatestFullSyncAreRemoved() throws {
        let store = try LibraryStore.inMemory()
        try store.save([Self.photo("1"), Self.photo("2")], generation: 1)
        try store.save([Self.photo("2")], generation: 2)
        #expect(try store.removePhotos(olderThan: 2) == 1)
        #expect(try store.photos(.all).map(\.id) == ["2"])
    }

    @Test func syncProgressIsKept() throws {
        let store = try LibraryStore.inMemory()
        #expect(try store.syncState() == .never)
        let state = LibrarySyncState(generation: 3,
                                     lastFullSync: Date(timeIntervalSince1970: 1_700_000_000),
                                     changesSince: Date(timeIntervalSince1970: 1_700_000_100))
        try store.save(state)
        #expect(try store.syncState() == state)
    }

    @Test func aStoreOnDiskOpensAgainWithItsPhotos() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("caterina-library-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Library.sqlite")

        try LibraryStore(file: file).save([Self.photo("1", title: "Kept")], generation: 1)
        #expect(try LibraryStore(file: file).photos(.all).map(\.title) == ["Kept"])
    }
}
