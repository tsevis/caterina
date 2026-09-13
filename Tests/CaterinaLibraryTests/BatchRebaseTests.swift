import Foundation
import Testing

import FlickrKit
@testable import CaterinaLibrary

/// A batch reads each photo from Flickr just before changing it.
///
/// **The local copy holds clean tags and may be behind.** Writing from it
/// would respell every tag it touched and undo edits made on flickr.com since
/// the last sync, so each change is laid over the photo as Flickr has it.
@Suite struct BatchRebaseTests {

    private func library() throws -> LibraryStore {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryStoreTests.photo("1", title: "Harbour", tags: ["newyork", "night"]),
                        LibraryStoreTests.photo("2", title: "Bridge", tags: ["night"])], generation: 1)
        return store
    }

    private func live(_ id: String, title: String, tags: [String]) -> LibraryPhoto {
        LibraryPhoto(id: id, title: title, tags: tags,
                     visibility: .init(isPublic: true, isFriend: false, isFamily: false),
                     uploaded: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func batch(_ store: LibraryStore, _ edit: PhotoEdit) throws -> EditBatch {
        try store.createBatch(title: "Edit", edit: edit, photos: try store.photos(ids: ["1", "2"]))
    }

    @Test func eachPhotoIsReadAtEditPriorityBeforeItIsWritten() async throws {
        let store = try library()
        let batch = try batch(store, .addTags(["sea"]))
        let flickr = ScriptedWriter(store: store)

        _ = try await BatchRunner(writer: flickr, store: store).run(batch.id)

        #expect(await flickr.read == ["1", "2"])
    }

    @Test func tagsAreWrittenWithTheSpellingFlickrHas() async throws {
        let store = try library()
        let batch = try batch(store, .addTags(["sea"]))
        let flickr = ScriptedWriter(store: store, live: ["1": live("1", title: "Harbour", tags: ["New York", "night"])])

        _ = try await BatchRunner(writer: flickr, store: store).run(batch.id)

        #expect(await flickr.sent.first?.arguments["tags"] == #""New York" night sea"#)
    }

    /// Undo puts back what Flickr had, spelling included, not what the local
    /// copy thought it had.
    @Test func undoRestoresTheSpellingFlickrHad() async throws {
        let store = try library()
        let batch = try batch(store, .removeTags(["night"]))
        let before = live("1", title: "Harbour", tags: ["New York", "Night Shot", "night"])
        _ = try await BatchRunner(writer: ScriptedWriter(store: store, live: ["1": before]), store: store).run(batch.id)
        let undo = try store.undoBatch(for: batch.id)
        let removed = live("1", title: "Harbour", tags: ["New York", "Night Shot"])
        let flickr = ScriptedWriter(store: store, live: ["1": removed, "2": live("2", title: "Bridge", tags: [])])

        _ = try await BatchRunner(writer: flickr, store: store).run(undo.id)

        let tags = await flickr.sent.compactMap { $0.arguments["tags"] }
        #expect(tags.contains(#""New York" "Night Shot" night"#))
    }

    @Test func aPhotoChangedOnFlickrSinceTheSyncIsLeftAloneAndReported() async throws {
        let store = try library()
        let batch = try batch(store, .setTitle("Piraeus"))
        let flickr = ScriptedWriter(store: store, live: ["1": live("1", title: "Renamed on flickr.com", tags: [])])

        let summary = try await BatchRunner(writer: flickr, store: store).run(batch.id)

        #expect(summary == EditBatch.Summary(applied: 1, failed: 1, pending: 0))
        #expect(await flickr.sent.map { $0.arguments["photo_id"] } == ["2"])
        let refused = try #require(try store.entries(in: batch.id).first { $0.photoID == "1" })
        #expect(refused.state == .failed)
        #expect(refused.message?.contains("title") == true)
    }

    /// The local copy keeps what only it has (thumbnails, views) and stores
    /// tags in the clean form its filters match on.
    @Test func theLocalCopyKeepsItsOwnFieldsAndCleanTags() async throws {
        let store = try library()
        let batch = try batch(store, .addTags(["Blue Hour"]))
        let flickr = ScriptedWriter(store: store, live: ["1": live("1", title: "Harbour", tags: ["New York"])])

        _ = try await BatchRunner(writer: flickr, store: store).run(batch.id)

        let photo = try #require(try store.photos(ids: ["1"]).first)
        #expect(photo.thumbnailURL == "https://live.staticflickr.com/1_q.jpg")
        #expect(photo.tags == ["newyork", "bluehour"])
        #expect(try store.photos(.tagged("Blue Hour")).map(\.id).sorted() == ["1", "2"])
    }

    @Test func aPhotoFlickrCannotFindFailsAloneButFlickrUnreachableStopsTheBatch() async throws {
        let store = try library()
        let first = try batch(store, .setTitle("A"))
        let missing = ScriptedWriter(store: store,
                                     failingReads: ["1": .api(code: 1, message: "Photo not found", transient: false)])
        #expect(try await BatchRunner(writer: missing, store: store).run(first.id)
                == EditBatch.Summary(applied: 1, failed: 1, pending: 0))

        let second = try batch(store, .setTitle("B"))
        let offline = ScriptedWriter(store: store, failingReads: ["1": .transport("The network connection was lost.")])
        await #expect(throws: FlickrError.transport("The network connection was lost.")) {
            _ = try await BatchRunner(writer: offline, store: store).run(second.id)
        }
        #expect(try store.summary(of: second.id).pending == 2)
    }
}
