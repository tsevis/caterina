import Foundation
import Testing

import FlickrKit
@testable import CaterinaLibrary

/// Rotations, people and deletions, as batches.
@Suite struct PhotoActionBatchTests {

    private func library() throws -> LibraryStore {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryStoreTests.photo("1"), LibraryStoreTests.photo("2")], generation: 1)
        return store
    }

    @Test func rotatingRunsAndUndoTurnsBack() async throws {
        let store = try library()
        let flickr = ScriptedWriter(store: store)
        let batch = try store.createActionBatch(title: "Rotate", action: .rotate(degrees: 90), photoIDs: ["1", "2"],
                                                accountID: "me")
        try await PhotoActionRunner(writer: flickr, store: store).run(batch.id)
        #expect(await flickr.sent.map { $0.arguments["degrees"] } == ["90", "90"])

        let undo = try store.undoBatch(for: batch.id)
        try await PhotoActionRunner(writer: flickr, store: store).run(undo.id)
        #expect(await flickr.sent.suffix(2).map { $0.arguments["photo_id"] } == ["2", "1"])
        #expect(await flickr.sent.suffix(2).map { $0.arguments["degrees"] } == ["270", "270"])
    }

    /// A lost reply to a rotation may have turned the photo. It is not sent
    /// again; the photo fails saying so, and the batch stops.
    @Test func aLostRotationIsNotSentAgain() async throws {
        let store = try library()
        let flickr = ScriptedWriter(store: store, failing: ["1": .transport("The network connection was lost.")])
        let batch = try store.createActionBatch(title: "Rotate", action: .rotate(degrees: 90), photoIDs: ["1", "2"],
                                                accountID: "me")
        await #expect(throws: FlickrError.self) { try await PhotoActionRunner(writer: flickr, store: store).run(batch.id) }
        let entries = try store.actionEntries(in: batch.id)
        #expect(entries[0].state == .failed)
        #expect(entries[0].message?.contains("may have") == true)
        #expect(entries[1].state == .pending)
    }

    @Test func aRepeatableActionLostStaysPendingForResume() async throws {
        let store = try library()
        let flickr = ScriptedWriter(store: store, failing: ["1": .transport("lost")])
        let batch = try store.createActionBatch(title: "Tag", action: .addPerson(userID: "u"), photoIDs: ["1"],
                                                accountID: "me")
        await #expect(throws: FlickrError.self) { try await PhotoActionRunner(writer: flickr, store: store).run(batch.id) }
        #expect(try store.actionEntries(in: batch.id).first?.state == .pending)
    }

    /// Deleted photos leave the library copy, and the batch cannot be undone.
    @Test func deletingRemovesFromTheCopyAndHasNoUndo() async throws {
        let store = try library()
        let batch = try store.createActionBatch(title: "Delete", action: .delete, photoIDs: ["1"], accountID: "me")
        try await PhotoActionRunner(writer: ScriptedWriter(store: store), store: store).run(batch.id)
        #expect(try store.photos(ids: ["1", "2"]).map(\.id) == ["2"])
        #expect(!(try store.canUndo(batch.id)))
        #expect(throws: FlickrError.self) { _ = try store.undoBatch(for: batch.id) }
    }

    @Test func aPhotoFlickrRefusesFailsAlone() async throws {
        let store = try library()
        let flickr = ScriptedWriter(store: store, failing: ["1": .api(code: 4, message: "Rotation disabled", transient: false)])
        let batch = try store.createActionBatch(title: "Rotate", action: .rotate(degrees: 180), photoIDs: ["1", "2"],
                                                accountID: "me")
        try await PhotoActionRunner(writer: flickr, store: store).run(batch.id)
        #expect(try store.summary(of: batch.id) == EditBatch.Summary(applied: 1, failed: 1, pending: 0))
        #expect(try store.batch(batch.id).kind == .actions)
    }
}

@Suite struct PhotoActionInterruptionTests {
    @Test func aRotationSentBeforeQuittingIsNotSentAgain() async throws {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryStoreTests.photo("1")], generation: 1)
        let batch = try store.createActionBatch(title: "Rotate", action: .rotate(degrees: 90), photoIDs: ["1"], accountID: "me")
        try store.markSending(try #require(try store.actionEntries(in: batch.id).first))
        let flickr = ScriptedWriter(store: store)
        try await PhotoActionRunner(writer: flickr, store: store).run(batch.id)
        #expect(await flickr.sent.isEmpty)
        #expect(try store.actionEntries(in: batch.id).first?.state == .failed)
    }
}

/// Found in review: a marker left set by a call that never went out.
@Suite struct SendingMarkerTests {
    @Test func needingPermissionClearsTheMarkerSoTheRotationResumes() async throws {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryStoreTests.photo("1")], generation: 1)
        let batch = try store.createActionBatch(title: "Rotate", action: .rotate(degrees: 90), photoIDs: ["1"], accountID: "me")
        await #expect(throws: FlickrError.self) {
            try await PhotoActionRunner(writer: ScriptedWriter(store: store, failing: ["1": .permissionNeeded(.write)]),
                                        store: store).run(batch.id)
        }
        #expect(try store.actionEntries(in: batch.id).first?.isSending == false)
        try await PhotoActionRunner(writer: ScriptedWriter(store: store), store: store).run(batch.id)
        #expect(try store.actionEntries(in: batch.id).first?.state == .applied)
    }

    @Test func aGroupPairThatNeverWentOutIsNotCountedAsPlaced() async throws {
        let store = try LibraryStore.inMemory()
        let batch = try store.createGroupBatch(title: "Remove", removing: [GroupPair(photoID: "p9", groupID: "g")],
                                               accountID: "me")
        let refusing = PermissionThenPools()
        await #expect(throws: FlickrError.self) { try await GroupShareRunner(flickr: refusing, store: store).run(batch.id) }
        try await GroupShareRunner(flickr: FakePools(pools: ["g": []]), store: store).run(batch.id)
        #expect(try store.groupEntries(in: batch.id).first?.outcome == .notInPool)
    }

    /// Code 3 from an album add after a lost reply was this batch's add.
    @Test func anAlbumAddResumedAfterALostReplyIsUndoneToo() async throws {
        let store = try LibraryStore.inMemory()
        let flickr = FakeAlbumFlickr(["A": .init(title: "A", description: "", cover: "1", photos: ["1"])])
        let batch = try store.createAlbumBatch(title: "Add", edits: [.addPhotos(albumID: "A", photoIDs: ["2"])], accountID: "me")
        var entry = try #require(try store.albumEntries(in: batch.id).first)
        entry = try store.recordSnapshot(AlbumSnapshot(title: "A", description: "", coverPhotoID: "1", photoIDs: ["1"],
                                                       albumOrder: []), for: entry)
        _ = try await flickr.perform(AlbumWrites.add(photoID: "2", albumID: "A"), priority: .edit)
        try store.markSending(entry)

        try await AlbumRunner(flickr: flickr, store: store, ownerID: "me").run(batch.id)
        try await AlbumRunner(flickr: flickr, store: store, ownerID: "me").run(try store.undoBatch(for: batch.id).id)
        #expect(await flickr.albums["A"]?.photos == ["1"])
    }

    @Test func albumPhotoWritesAreNotRetriedInsideOneCall() {
        #expect(!AlbumWrites.add(photoID: "1", albumID: "A").repeatable)
        #expect(!AlbumWrites.remove(photoIDs: ["1"], albumID: "A").repeatable)
    }

    @Test func undoingARemovalReordersOnlyPhotosItPutsBack() {
        let edit = AlbumEdit.reorderPhotos(albumID: "A", photoIDs: ["1", "2", "3"])
        #expect(edit.excluding(["2"]) == .reorderPhotos(albumID: "A", photoIDs: ["1", "3"]))
    }
}

actor PermissionThenPools: GroupPoolWriter {
    func perform(_ write: FlickrWrite, priority: CallPriority) async throws -> Data {
        throw FlickrError.permissionNeeded(.write)
    }
}
