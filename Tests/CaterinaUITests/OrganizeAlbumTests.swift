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
