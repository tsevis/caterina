import Foundation
import Testing

import CaterinaLibrary
import FlickrKit
@testable import CaterinaUI

@MainActor
@Suite struct OrganizeAlbumTests {

    private func setUp() throws -> (OrganizeModel, FakeOrganizeFlickr) {
        let store = try LibraryStore.inMemory()
        try store.save([
            LibraryPhoto(id: "1", title: "Harbour", taken: "2024-06-01 10:00:00", views: 5),
            LibraryPhoto(id: "2", title: "Anchor", taken: "2024-05-01 10:00:00", views: 50),
            LibraryPhoto(id: "3", title: "Pier", taken: "2024-07-01 10:00:00", views: 1),
        ], generation: 1)
        let flickr = FakeOrganizeFlickr(store: store, albums: [
            .init(id: "A", title: "Athens", description: "", cover: "1", photos: ["3", "1"]),
            .init(id: "B", title: "Beaches", description: "", cover: "2", photos: ["2"]),
        ])
        return (OrganizeModel(store: store, flickr: flickr, accountID: { "me" }), flickr)
    }

    @Test func anAlbumShowsItsPhotosInAlbumOrder() async throws {
        let (model, _) = try setUp()
        await model.loadAlbums()
        #expect(model.albums.map(\.title) == ["Athens", "Beaches"])
        await model.open(.album(id: "A", title: "Athens"))
        #expect(model.photos.map(\.id) == ["3", "1"])
    }

    @Test func theTrayGoesIntoAnAlbumAndUndoTakesItOut() async throws {
        let (model, flickr) = try setUp()
        await model.loadAlbums()
        model.selectAll()
        model.addSelectionToTray()

        await model.addTray(toAlbum: "A")
        #expect(await flickr.album("A")?.photos == ["3", "1", "2"])
        let batch = try #require(model.activity.first)
        #expect(batch.batch.kind == .albums)
        #expect(batch.canUndo)

        await model.undo(batch.batch.id)
        #expect(await flickr.album("A")?.photos == ["3", "1"])
    }

    @Test func aNewAlbumIsMadeFromTheTrayWithItsFirstPhotoAsCover() async throws {
        let (model, flickr) = try setUp()
        model.click("2", modifiers: [])
        model.click("3", modifiers: .command)
        model.addSelectionToTray()

        await model.createAlbum(title: "Harbours", description: "Old ports")

        let made = try #require(await flickr.albumTitled("Harbours"))
        #expect(made.cover == model.tray.first)
        #expect(made.photos == model.tray)
        #expect(model.albums.contains { $0.title == "Harbours" })
    }

    @Test func removingSettingTheCoverAndSorting() async throws {
        let (model, flickr) = try setUp()
        await model.open(.album(id: "A", title: "Athens"))
        model.click("1", modifiers: [])
        await model.setCoverToSelection()
        #expect(await flickr.album("A")?.cover == "1")

        await model.sortAlbum(by: .dateTaken)
        #expect(await flickr.album("A")?.photos == ["1", "3"])

        model.click("3", modifiers: [])
        await model.removeSelectionFromAlbum()
        #expect(await flickr.album("A")?.photos == ["1"])
        #expect(model.photos.map(\.id) == ["1"])
    }

    @Test func draggingPhotosMovesThemBeforeTheTarget() {
        #expect(AlbumOrdering.moving(["4", "1"], before: "3", in: ["1", "2", "3", "4", "5"]) == ["2", "1", "4", "3", "5"])
        #expect(AlbumOrdering.moving(["1"], before: nil, in: ["1", "2", "3"]) == ["2", "3", "1"])
        #expect(AlbumOrdering.moving(["2"], before: "2", in: ["1", "2", "3"]) == ["1", "2", "3"])
    }

    @Test func albumsAreReorderedByDragging() async throws {
        let (model, flickr) = try setUp()
        await model.loadAlbums()
        await model.moveAlbums(from: IndexSet(integer: 1), to: 0)
        #expect(await flickr.albumOrder == ["B", "A"])
        #expect(model.albums.map(\.id) == ["B", "A"])
    }

    @Test func renamingAndDeletingAnAlbum() async throws {
        let (model, flickr) = try setUp()
        await model.loadAlbums()
        await model.editAlbum("B", title: "Beaches 2024", description: "Summer")
        #expect(await flickr.album("B")?.title == "Beaches 2024")
        await model.deleteAlbum("B")
        #expect(await flickr.album("B") == nil)
        #expect(!model.albums.contains { $0.id == "B" })
    }

    @Test func albumEditsNeedASignedInAccount() async throws {
        let store = try LibraryStore.inMemory()
        let model = OrganizeModel(store: store, flickr: FakeOrganizeFlickr(store: store), accountID: { nil })
        await model.deleteAlbum("A")
        #expect(model.problem == "Sign in to Flickr to change your albums.")
    }
}

@MainActor
@Suite struct OrganizeAlbumSafetyTests {

    @Test func deletingTheOpenAlbumReturnsToAllPhotos() async throws {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryPhoto(id: "1")], generation: 1)
        let flickr = FakeOrganizeFlickr(store: store, albums: [.init(id: "A", title: "A", description: "", cover: "1", photos: ["1"])])
        let model = OrganizeModel(store: store, flickr: flickr, accountID: { "me" })
        await model.loadAlbums()
        await model.open(.album(id: "A", title: "A"))
        await model.deleteAlbum("A")
        #expect(model.scope == .all)
    }

    /// Nothing selected, or the album not read yet: no empty batch.
    @Test func removingNothingRecordsNothing() async throws {
        let store = try LibraryStore.inMemory()
        let model = OrganizeModel(store: store, flickr: FakeOrganizeFlickr(store: store), accountID: { "me" })
        await model.removeSelectionFromAlbum()
        #expect(model.activity.isEmpty)
    }

    /// Photos leave "Not in an Album" only when the add went through.
    @Test func aFailedAddLeavesPhotosNotInAnAlbum() async throws {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryPhoto(id: "1")], generation: 1)
        let flickr = FakeOrganizeFlickr(store: store, notInAlbum: ["1"])
        let model = OrganizeModel(store: store, flickr: flickr, accountID: { "me" })
        await model.open(.notInAlbum)
        model.selectAll()
        model.addSelectionToTray()
        await model.addTray(toAlbum: "missing")
        #expect(try store.photos(.notInAlbum).map(\.id) == ["1"])
    }
}

@MainActor
@Suite struct OrganizeFindingTests {
    @Test func searchingFindsTitlesDescriptionsAndTags() async throws {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryPhoto(id: "1", title: "Harbour at dusk"), LibraryPhoto(id: "2", title: "Hill", tags: ["dusk"]),
                        LibraryPhoto(id: "3", title: "Pier")], generation: 1)
        let model = OrganizeModel(store: store, flickr: FakeOrganizeFlickr(store: store))
        await model.open(.search("dusk"))
        #expect(Set(model.photos.map(\.id)) == ["1", "2"])
        #expect(OrganizeScope.search("dusk").title == "“dusk”")
    }

    @Test func collectionsAreReadForShowingOnly() async throws {
        let store = try LibraryStore.inMemory()
        let model = OrganizeModel(store: store, flickr: FakeOrganizeFlickr(store: store))
        await model.loadCollections()
        #expect(model.collections.map(\.title) == ["Travel"])
        #expect(model.collections.first?.children.first?.albums.map(\.title) == ["Athens"])
    }
}

@MainActor
@Suite struct SavedViewTests {
    /// A view saved by name acts like a smart album: it opens with today's
    /// photos, not the ones it had when saved.
    @Test func aViewIsSavedByNameAndOpensAgain() async throws {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryPhoto(id: "1", title: "Dusk")], generation: 1)
        let model = OrganizeModel(store: store, flickr: FakeOrganizeFlickr(store: store))
        await model.open(.search("dusk"))
        model.saveView(named: "Dusk shots")
        model.saveView(named: "Untagged", scope: .untagged)
        #expect(model.savedViews.map(\.name) == ["Dusk shots", "Untagged"])

        try store.save([LibraryPhoto(id: "2", title: "More dusk")], generation: 1)
        await model.open(.all)
        await model.open(try #require(model.savedViews.first).scope)
        #expect(Set(model.photos.map(\.id)) == ["1", "2"])

        model.deleteView(named: "Untagged")
        let reopened = OrganizeModel(store: store, flickr: FakeOrganizeFlickr(store: store))
        #expect(reopened.savedViews.map(\.name) == ["Dusk shots"])
    }
}

@MainActor
@Suite struct SavedViewFormatTests {
    /// The stored shape is pinned: renaming a case would silently lose saved
    /// views, so this JSON must keep reading.
    @Test func theStoredFormatStillReads() throws {
        let json = #"[{"name":"Dusk","scope":{"search":{"_0":"dusk"}}},{"name":"June","scope":{"month":{"_0":"2024-06"}}},{"name":"Bad","scope":{"gone":{}}}]"#
        let store = try LibraryStore.inMemory()
        try store.setSetting(OrganizeModel.savedViewsKey, to: Data(json.utf8))
        let model = OrganizeModel(store: store, flickr: FakeOrganizeFlickr(store: store))
        #expect(model.savedViews.map(\.scope) == [.search("dusk"), .month("2024-06")])

        // One unreadable entry must not wipe the rest on the next save.
        model.saveView(named: "Untagged", scope: .untagged)
        let reread = OrganizeModel(store: store, flickr: FakeOrganizeFlickr(store: store))
        #expect(reread.savedViews.map(\.name) == ["Dusk", "June", "Untagged"])
    }
}
