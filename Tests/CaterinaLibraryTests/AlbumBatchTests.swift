import Foundation
import Testing

import FlickrKit
@testable import CaterinaLibrary

/// Album edits, recorded like photo edits: each read, planned, sent, and
/// undone from what the album was just before.
@Suite struct AlbumBatchTests {

    private let athens = FakeAlbumFlickr.Album(title: "Athens", description: "Spring", cover: "1", photos: ["1", "2", "3"])

    private func run(_ edits: [AlbumEdit], on flickr: FakeAlbumFlickr,
                     store: LibraryStore) async throws -> EditBatch {
        let batch = try store.createAlbumBatch(title: "Albums", edits: edits, accountID: "me")
        try await AlbumRunner(flickr: flickr, store: store, ownerID: "me").run(batch.id)
        return batch
    }

    @Test func addingAndUndoingLeavesTheAlbumAsItWas() async throws {
        let store = try LibraryStore.inMemory()
        let flickr = FakeAlbumFlickr(["A": athens])

        let batch = try await run([.addPhotos(albumID: "A", photoIDs: ["3", "4", "5"])], on: flickr, store: store)
        #expect(await flickr.albums["A"]?.photos == ["1", "2", "3", "4", "5"])
        #expect(try store.summary(of: batch.id) == EditBatch.Summary(applied: 1, failed: 0, pending: 0))

        let undo = try store.undoBatch(for: batch.id)
        try await AlbumRunner(flickr: flickr, store: store, ownerID: "me").run(undo.id)
        #expect(await flickr.albums["A"] == athens)
    }

    @Test func removingAndUndoingRestoresMembershipAndOrder() async throws {
        let store = try LibraryStore.inMemory()
        let flickr = FakeAlbumFlickr(["A": athens])
        let batch = try await run([.removePhotos(albumID: "A", photoIDs: ["1", "2"])], on: flickr, store: store)
        #expect(await flickr.albums["A"]?.photos == ["3"])
        try await AlbumRunner(flickr: flickr, store: store, ownerID: "me").run(try store.undoBatch(for: batch.id).id)
        #expect(await flickr.albums["A"]?.photos == ["1", "2", "3"])
    }

    @Test func metaCoverAndDeleteAllUndo() async throws {
        let store = try LibraryStore.inMemory()
        let flickr = FakeAlbumFlickr(["A": athens, "B": .init(title: "B", description: "", cover: "9", photos: ["9"])])
        let batch = try await run([.editMeta(albumID: "A", title: "Piraeus", description: ""),
                                   .setCover(albumID: "A", photoID: "3"),
                                   .orderAlbums(["B", "A"])], on: flickr, store: store)
        #expect(await flickr.albums["A"]?.title == "Piraeus")
        #expect(await flickr.order == ["B", "A"])
        try await AlbumRunner(flickr: flickr, store: store, ownerID: "me").run(try store.undoBatch(for: batch.id).id)
        #expect(await flickr.albums["A"] == athens)
        #expect(await flickr.order == ["A", "B"])
    }

    /// Flickr cannot bring a deleted album back; undo makes it again, with
    /// its title, cover and photos in order.
    @Test func undoingADeleteMakesTheAlbumAgain() async throws {
        let store = try LibraryStore.inMemory()
        let flickr = FakeAlbumFlickr(["A": .init(title: "Athens", description: "Spring", cover: "2", photos: ["1", "2", "3"])])
        let batch = try await run([.delete(albumID: "A")], on: flickr, store: store)
        #expect(await flickr.albums.isEmpty)
        try await AlbumRunner(flickr: flickr, store: store, ownerID: "me").run(try store.undoBatch(for: batch.id).id)
        let remade = try #require(await flickr.albums.values.first)
        #expect(remade == .init(title: "Athens", description: "Spring", cover: "2", photos: ["1", "2", "3"]))
    }

    @Test func aCreatedAlbumIsUndoneByDeletingIt() async throws {
        let store = try LibraryStore.inMemory()
        let flickr = FakeAlbumFlickr([:])
        let batch = try await run([.create(title: "Hydra", description: "", coverPhotoID: "2", photoIDs: ["1", "2"])],
                                  on: flickr, store: store)
        let made = try #require(await flickr.albums.first)
        #expect(made.value.photos == ["1", "2"])
        #expect(try store.albumEntries(in: batch.id).first?.createdAlbumID == made.key)
        try await AlbumRunner(flickr: flickr, store: store, ownerID: "me").run(try store.undoBatch(for: batch.id).id)
        #expect(await flickr.albums.isEmpty)
    }

    /// A lost reply to "create" may have made the album. Sending it again
    /// could make two, so the entry fails with that said, and the batch stops.
    @Test func aLostReplyToCreateIsNeverSentAgain() async throws {
        let store = try LibraryStore.inMemory()
        let flickr = FakeAlbumFlickr([:])
        await flickr.fail("create", with: .transport("The network connection was lost."))
        let batch = try store.createAlbumBatch(title: "New", edits: [
            .create(title: "Hydra", description: "", coverPhotoID: "1", photoIDs: ["1"]),
            .create(title: "Spetses", description: "", coverPhotoID: "2", photoIDs: ["2"])], accountID: "me")

        await #expect(throws: FlickrError.self) {
            try await AlbumRunner(flickr: flickr, store: store, ownerID: "me").run(batch.id)
        }
        let entries = try store.albumEntries(in: batch.id)
        #expect(entries[0].state == .failed)
        #expect(entries[0].message?.contains("flickr.com") == true)
        #expect(entries[1].state == .pending)

        try await AlbumRunner(flickr: flickr, store: store, ownerID: "me").run(batch.id)
        #expect(await flickr.sent.filter { $0 == "create" }.count == 2)
    }

    /// Cut off halfway through adding: the resume sends only what is left,
    /// and the undo still knows what the album held before.
    @Test func aResumeCarriesOnFromTheStepItReached() async throws {
        let store = try LibraryStore.inMemory()
        let flickr = FakeAlbumFlickr(["A": athens])
        await flickr.fail("flickr.photosets.addPhoto", with: .busy("Flickr is busy right now."))
        let batch = try store.createAlbumBatch(title: "Add", edits: [.addPhotos(albumID: "A", photoIDs: ["4", "5"])],
                                               accountID: "me")
        // The first add fails and stops the batch.
        await #expect(throws: FlickrError.self) {
            try await AlbumRunner(flickr: flickr, store: store, ownerID: "me").run(batch.id)
        }
        try await AlbumRunner(flickr: flickr, store: store, ownerID: "me").run(batch.id)
        #expect(await flickr.albums["A"]?.photos == ["1", "2", "3", "4", "5"])
        try await AlbumRunner(flickr: flickr, store: store, ownerID: "me").run(try store.undoBatch(for: batch.id).id)
        #expect(await flickr.albums["A"] == athens)
    }

    @Test func aRefusedEditFailsAloneWithItsReason() async throws {
        let store = try LibraryStore.inMemory()
        let flickr = FakeAlbumFlickr(["A": athens])
        let batch = try await run([.removePhotos(albumID: "A", photoIDs: ["1", "2", "3"]),
                                   .editMeta(albumID: "A", title: "Kept", description: "")], on: flickr, store: store)
        let entries = try store.albumEntries(in: batch.id)
        #expect(entries.map(\.state) == [.failed, .applied])
        #expect(entries[0].message == "Flickr deletes an album left empty. Delete the album instead.")
    }

    @Test func albumBatchesAreListedWithPhotoBatches() async throws {
        let store = try LibraryStore.inMemory()
        let batch = try store.createAlbumBatch(title: "Albums", edits: [.delete(albumID: "A")], accountID: "me")
        #expect(try store.recentBatches(limit: 5).map(\.id) == [batch.id])
        #expect(try store.recentBatches(limit: 5).first?.kind == .albums)
        #expect(batch.calls == 3)
    }
}
