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
