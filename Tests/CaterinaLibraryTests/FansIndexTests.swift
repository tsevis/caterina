import Foundation
import Testing

import FlickrKit
@testable import CaterinaLibrary

actor ScriptedFaves: FaveSource {
    private let faves: [String: [Fave]]
    private let perPage: Int
    private(set) var asked: [String] = []

    init(_ faves: [String: [Fave]], perPage: Int = 50) {
        self.faves = faves
        self.perPage = perPage
    }

    func favorites(photoID: String, page: Int, priority: CallPriority) async throws -> FavePage {
        asked.append("\(photoID)#\(page)")
        let all = faves[photoID] ?? []
        let pages = max(1, Int((Double(all.count) / Double(perPage)).rounded(.up)))
        let slice = Array(all.dropFirst((page - 1) * perPage).prefix(perPage))
        return FavePage(page: page, pages: pages, total: all.count, faves: slice)
    }
}

@Suite struct FansIndexTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fave(_ who: String, _ at: TimeInterval) -> Fave {
        Fave(nsid: who, username: who.uppercased(), date: Date(timeIntervalSince1970: at))
    }

    private func library() throws -> LibraryStore {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryPhoto(id: "popular", views: 900), LibraryPhoto(id: "quiet", views: 3),
                        LibraryPhoto(id: "middle", views: 50)], generation: 1)
        return store
    }

    @Test func mostViewedPhotosAreReadFirstAndEveryPageIsRead() async throws {
        let store = try library()
        let source = ScriptedFaves(["popular": (0..<120).map { fave("p\($0)", Double($0)) },
                                    "middle": [fave("ann", 10)]], perPage: 50)

        let outcome = try await FansIndex(source: source, store: store).run(now: now, photoLimit: 2)

        #expect(outcome == .init(photosRead: 2, favesSaved: 121))
        #expect(await source.asked == ["popular#1", "popular#2", "popular#3", "middle#1"])
    }

    @Test func fansAreRankedByHowManyOfYourPhotosTheyFaved() async throws {
        let store = try library()
        let source = ScriptedFaves(["popular": [fave("ann", 30), fave("bob", 10)],
                                    "middle": [fave("ann", 20)], "quiet": [fave("ann", 5), fave("cy", 40)]])
        _ = try await FansIndex(source: source, store: store).run(now: now, photoLimit: 10)

        let fans = try store.topFans(limit: 10)
        #expect(fans.map(\.nsid) == ["ann", "cy", "bob"])
        #expect(fans.first == Fan(nsid: "ann", username: "ANN", faveCount: 3, lastFaved: Date(timeIntervalSince1970: 30)))
        #expect(Set(try store.photoIDs(favedBy: "ann")) == ["popular", "middle", "quiet"])
    }

    @Test func recentFavesAreNewestFirst() async throws {
        let store = try library()
        let source = ScriptedFaves(["popular": [fave("ann", 30), fave("bob", 50)], "quiet": [fave("cy", 40)]])
        _ = try await FansIndex(source: source, store: store).run(now: now, photoLimit: 10)
        #expect(try store.recentFaves(limit: 2).map(\.nsid) == ["bob", "cy"])
        #expect(try store.recentFaves(limit: 2).first?.photoID == "popular")
    }

    /// A photo read recently is not read again until a week has passed; one
    /// never read goes first.
    @Test func photosReadInTheLastWeekWait() async throws {
        let store = try library()
        _ = try await FansIndex(source: ScriptedFaves([:]), store: store).run(now: now, photoLimit: 2)

        let later = ScriptedFaves([:])
        _ = try await FansIndex(source: later, store: store).run(now: now.addingTimeInterval(3600), photoLimit: 10)
        #expect(await later.asked == ["quiet#1"])

        let nextWeek = ScriptedFaves([:])
        _ = try await FansIndex(source: nextWeek, store: store).run(now: now.addingTimeInterval(8 * 86_400), photoLimit: 1)
        #expect(await nextWeek.asked == ["popular#1"])
    }

    /// Re-reading a photo replaces its faves: an unfave is not kept.
    @Test func reReadingAPhotoReplacesItsFaves() async throws {
        let store = try library()
        _ = try await FansIndex(source: ScriptedFaves(["popular": [fave("ann", 1), fave("bob", 2)]]), store: store)
            .run(now: now, photoLimit: 3)
        _ = try await FansIndex(source: ScriptedFaves(["popular": [fave("bob", 2)]]), store: store)
            .run(now: now.addingTimeInterval(8 * 86_400), photoLimit: 3)
        #expect(try store.topFans(limit: 10).map(\.nsid) == ["bob"])
    }

    /// A photo with 40,000 faves is read to a cap, not for 800 calls.
    @Test func aHeavilyFavedPhotoIsReadToACap() async throws {
        let store = try library()
        let source = ScriptedFaves(["popular": (0..<(FansIndex.pageCap * 50 + 500)).map { fave("f\($0)", Double($0)) }])
        _ = try await FansIndex(source: source, store: store).run(now: now, photoLimit: 1)
        #expect(await source.asked.count == FansIndex.pageCap)
    }
}
