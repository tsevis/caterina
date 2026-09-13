import Foundation
import Testing

import FlickrKit
@testable import CaterinaLibrary

@Suite struct EditBatchTests {

    private func library(_ ids: [String]) throws -> LibraryStore {
        let store = try LibraryStore.inMemory()
        try store.save(ids.map { LibraryStoreTests.photo($0, title: "Photo \($0)", tags: ["old"]) },
                       generation: 1)
        return store
    }

    private func batch(_ store: LibraryStore, _ ids: [String], _ edit: PhotoEdit) throws -> EditBatch {
        let photos = try store.photos(.all).filter { ids.contains($0.id) }
        return try store.createBatch(title: "Add tag", edit: edit, photos: photos)
    }

    @Test func aBatchRecordsEachPhotoBeforeAndAfter() throws {
        let store = try library(["1", "2"])
        let batch = try batch(store, ["1", "2"], .addTags(["sea"]))

        let entries = try store.entries(in: batch.id)
        #expect(entries.map(\.photoID) == ["1", "2"])
        #expect(entries.allSatisfy { $0.state == .pending })
        #expect(entries.first?.change.after.tags == ["old", "sea"])
        #expect(entries.first?.change.before.tags == ["old"])
    }

    /// A photo the edit would not change is not in the batch at all, so it
    /// costs no call and its undo is not a call either.
    @Test func photosTheEditWouldNotChangeAreLeftOut() throws {
        let store = try library(["1", "2"])
        try store.save([LibraryStoreTests.photo("2", title: "Photo 2", tags: ["old", "sea"])], generation: 1)
        let batch = try batch(store, ["1", "2"], .addTags(["sea"]))
        #expect(try store.entries(in: batch.id).map(\.photoID) == ["1"])
        // One read to check the photo as Flickr has it, one write.
        #expect(batch.calls == 2)
    }

    @Test func runningABatchSendsItsWritesAndUpdatesTheLocalCopy() async throws {
        let store = try library(["1", "2"])
        let batch = try batch(store, ["1", "2"], .addTags(["sea"]))
        let writer = ScriptedWriter(store: store)

        let summary = try await BatchRunner(writer: writer, store: store).run(batch.id)

        #expect(summary == EditBatch.Summary(applied: 2, failed: 0, pending: 0))
        #expect(await writer.sent.map(\.method) == ["flickr.photos.setTags", "flickr.photos.setTags"])
        #expect(try store.photos(.tagged("sea")).count == 2)
        #expect(try store.entries(in: batch.id).allSatisfy { $0.state == .applied })
    }

    /// One photo Flickr refuses does not stop the other 799.
    @Test func aRefusedPhotoIsRecordedAndTheRestCarryOn() async throws {
        let store = try library(["1", "2", "3"])
        let batch = try batch(store, ["1", "2", "3"], .setTitle("New"))
        let writer = ScriptedWriter(store: store, failing: ["2": .api(code: 1, message: "Photo not found", transient: false)])

        let summary = try await BatchRunner(writer: writer, store: store).run(batch.id)

        #expect(summary == EditBatch.Summary(applied: 2, failed: 1, pending: 0))
        let failed = try #require(try store.entries(in: batch.id).first { $0.photoID == "2" })
        #expect(failed.state == .failed)
        #expect(failed.message == "Photo not found")
        #expect(try store.photos(.all).first { $0.id == "2" }?.title == "Photo 2")
    }

    /// Needing permission stops the batch where it is; after approving, the
    /// rest runs from there.
    @Test func needingPermissionPausesTheBatchAndItResumes() async throws {
        let store = try library(["1", "2"])
        let batch = try batch(store, ["1", "2"], .setTitle("New"))

        await #expect(throws: FlickrError.permissionNeeded(.write)) {
            _ = try await BatchRunner(writer: ScriptedWriter(store: store, failing: ["1": .permissionNeeded(.write)]),
                                      store: store).run(batch.id)
        }
        #expect(try store.summary(of: batch.id) == EditBatch.Summary(applied: 0, failed: 0, pending: 2))

        let summary = try await BatchRunner(writer: ScriptedWriter(store: store), store: store).run(batch.id)
        #expect(summary == EditBatch.Summary(applied: 2, failed: 0, pending: 0))
    }

    /// With the network gone, every photo would fail in turn; the batch stops
    /// instead, and the photos stay pending for when it is back.
    @Test func aLostConnectionPausesTheBatchRatherThanFailingEveryPhoto() async throws {
        let store = try library(["1", "2", "3"])
        let batch = try batch(store, ["1", "2", "3"], .setTitle("New"))
        let writer = ScriptedWriter(store: store, failing: ["2": .busy("Flickr is busy right now.")])

        await #expect(throws: FlickrError.busy("Flickr is busy right now.")) {
            _ = try await BatchRunner(writer: writer, store: store).run(batch.id)
        }
        #expect(try store.summary(of: batch.id) == EditBatch.Summary(applied: 1, failed: 0, pending: 2))
    }

    @Test func undoWritesBackWhatWasThere() async throws {
        let store = try library(["1", "2"])
        let batch = try batch(store, ["1", "2"], .addTags(["sea"]))
        _ = try await BatchRunner(writer: ScriptedWriter(store: store), store: store).run(batch.id)

        let undo = try store.undoBatch(for: batch.id)
        let writer = ScriptedWriter(store: store)
        _ = try await BatchRunner(writer: writer, store: store).run(undo.id)

        #expect(undo.undoes == batch.id)
        #expect(undo.title == "Undo Add tag")
        #expect(await writer.sent.map { $0.arguments["tags"] } == ["old", "old"])
        #expect(try store.photos(.tagged("sea")).isEmpty)
    }

    /// Only what actually changed is undone: a photo that failed was never
    /// changed, and writing its "before" back would be a wasted call at best.
    @Test func undoLeavesOutPhotosThatWereNeverChanged() async throws {
        let store = try library(["1", "2"])
        let batch = try batch(store, ["1", "2"], .setTitle("New"))
        _ = try await BatchRunner(writer: ScriptedWriter(store: store, failing: ["2": .api(code: 1, message: "x", transient: false)]),
                                  store: store).run(batch.id)
        let undo = try store.undoBatch(for: batch.id)
        #expect(try store.entries(in: undo.id).map(\.photoID) == ["1"])
    }

    @Test func recentBatchesAreListedNewestFirst() throws {
        let store = try library(["1"])
        let first = try batch(store, ["1"], .setTitle("A"))
        let second = try batch(store, ["1"], .setTitle("B"))
        #expect(try store.recentBatches(limit: 10).map(\.id) == [second.id, first.id])
    }

    @Test func progressIsReportedPhotoByPhoto() async throws {
        let store = try library(["1", "2"])
        let batch = try batch(store, ["1", "2"], .setTitle("New"))
        let seen = Counted()
        _ = try await BatchRunner(writer: ScriptedWriter(store: store), store: store).run(batch.id) { seen.add($0) }
        #expect(seen.values == [EditBatch.Summary(applied: 1, failed: 0, pending: 1),
                                EditBatch.Summary(applied: 2, failed: 0, pending: 0)])
    }
}

final class Counted: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [EditBatch.Summary] = []
    var values: [EditBatch.Summary] { lock.withLock { stored } }
    func add(_ value: EditBatch.Summary) { lock.withLock { stored.append(value) } }
}
