import Foundation
import Testing

import CaterinaLibrary
import FlickrKit
@testable import CaterinaUI

@MainActor
@Suite struct OrganizeSortTests {
    /// Posted order, taken order and title order all differ, and the newest
    /// upload has no date taken — the shape of the real library.
    private func library() throws -> LibraryStore {
        let store = try LibraryStore.inMemory()
        try store.save([
            LibraryPhoto(id: "old", title: "Zebra", uploaded: Date(timeIntervalSince1970: 1_000),
                         taken: "2024-01-01 10:00:00", views: 5),
            LibraryPhoto(id: "mid", title: "apple", uploaded: Date(timeIntervalSince1970: 2_000),
                         taken: "2001-01-01 10:00:00", views: 50),
            LibraryPhoto(id: "new", title: "", uploaded: Date(timeIntervalSince1970: 3_000), views: 1),
        ], generation: 1)
        return store
    }

    private func model(_ store: LibraryStore) -> OrganizeModel {
        OrganizeModel(store: store, flickr: FakeOrganizeFlickr(store: store))
    }

    /// Catches: undated new uploads sinking below every dated photo.
    @Test func allPhotosOpensWithTheNewestPostedFirstEvenWithoutADateTaken() throws {
        #expect(model(try library()).photos.map(\.id) == ["new", "mid", "old"])
    }

    /// Catches: a menu choice that changes nothing, or a wrong SQL ordering.
    @Test(arguments: [
        (LibraryOrder.oldestUploaded, ["old", "mid", "new"]),
        (.newestTaken, ["old", "mid", "new"]),
        (.oldestTaken, ["mid", "old", "new"]),
        (.mostViewed, ["mid", "old", "new"]),
        (.title, ["mid", "old", "new"]),
    ])
    func choosingASortReordersThePhotos(order: LibraryOrder, expected: [String]) throws {
        let organize = model(try library())
        organize.sort(by: order)
        #expect(organize.order == order)
        #expect(organize.photos.map(\.id) == expected)
    }

    /// Catches: the chosen order being lost at relaunch.
    @Test func theChosenSortIsRememberedNextTime() throws {
        let store = try library()
        model(store).sort(by: .mostViewed)
        #expect(model(store).photos.map(\.id) == ["mid", "old", "new"])
    }

    /// Catches: the choice applying to one view and silently resetting on the next.
    @Test func theChosenSortCarriesToOtherViews() async throws {
        let organize = model(try library())
        organize.sort(by: .oldestTaken)
        await organize.open(.untagged)
        #expect(organize.photos.map(\.id) == ["mid", "old", "new"])
    }

    /// Catches: Add All filling the tray in a different order from the grid.
    @Test func addAllToTrayFollowsTheChosenSort() async throws {
        let organize = model(try library())
        organize.sort(by: .oldestTaken)
        await organize.addEntireViewToTray()
        #expect(organize.tray == ["mid", "old", "new"])
    }

    /// Catches: a remembered sort overriding the one view that is an order.
    @Test func recentlyUpdatedKeepsItsOwnOrder() async throws {
        let organize = model(try library())
        #expect(organize.canSort)
        organize.sort(by: .title)
        await organize.open(.recentlyUpdated)
        #expect(!organize.canSort)
        #expect(organize.order == .recentlyUpdated)
    }
}
