import Foundation
import Testing

import FlickrKit
@testable import CaterinaLibrary

/// Uploads from a script: which files fail, and what Flickr says of each ticket.
actor ScriptedUploader: PhotoUploader {
    private let refused: [String: FlickrError]
    private let processingRounds: Int
    private var round = 0
    private var tickets: [String: String] = [:]
    private(set) var sentFiles: [String] = []
    private(set) var createdAlbums: [(title: String, cover: String)] = []
    private(set) var added: [(photo: String, album: String)] = []

    /// `refused` is keyed on file name; each ticket reads as processing for
    /// `processingRounds` checks before it is done.
    init(refusing refused: [String: FlickrError] = [:], processingRounds: Int = 1) {
        self.refused = refused
        self.processingRounds = processingRounds
    }

    func upload(file: URL, metadata: UploadMetadata,
                progress: @escaping @Sendable (Double) -> Void) async throws -> String {
        sentFiles.append(file.lastPathComponent)
        if let error = refused[file.lastPathComponent] { throw error }
        progress(1)
        let ticket = "t-\(file.deletingPathExtension().lastPathComponent)"
        tickets[ticket] = "p-\(file.deletingPathExtension().lastPathComponent)"
        return ticket
    }

    func checkTickets(_ ids: [String]) async throws -> [String: TicketStatus] {
        round += 1
        return Dictionary(uniqueKeysWithValues: ids.map { id in
            (id, round <= processingRounds ? .processing : tickets[id].map { .done(photoID: $0) } ?? .invalid)
        })
    }

    func createAlbum(title: String, description: String, coverPhotoID: String,
                     priority: CallPriority) async throws -> String {
        createdAlbums.append((title, coverPhotoID))
        return "album-1"
    }

    func addToAlbum(photoID: String, albumID: String, priority: CallPriority) async throws {
        added.append((photoID, albumID))
    }
}

@Suite struct UploadQueueTests {

    private func files(_ names: [String]) -> [URL] {
        names.map { URL(fileURLWithPath: "/photos/\($0)") }
    }

    private func runner(_ store: LibraryStore, _ uploader: ScriptedUploader) -> UploadRunner {
        UploadRunner(uploader: uploader, store: store, files: PlainFileAccess(),
                     pollInterval: .zero, sleep: { _ in })
    }

    private func queue(_ store: LibraryStore, _ names: [String], album: UploadBatch.AlbumChoice = .none) throws -> UploadBatch {
        try store.createUploadBatch(
            items: files(names).map { (file: $0, metadata: UploadMetadata(title: $0.lastPathComponent)) },
            album: album, files: PlainFileAccess())
    }

    @Test func aBatchKeepsItsFilesInOrderWithWhatEachGoesWith() throws {
        let store = try LibraryStore.inMemory()
        let batch = try queue(store, ["a.jpg", "b.jpg"])
        let items = try store.uploadItems(in: batch.id)
        #expect(items.map(\.file.lastPathComponent) == ["a.jpg", "b.jpg"])
        #expect(items.map(\.metadata.title) == ["a.jpg", "b.jpg"])
        #expect(items.allSatisfy { $0.state == .queued })
    }

    @Test func eachFileIsSentThenWaitedOnUntilFlickrHasIt() async throws {
        let store = try LibraryStore.inMemory()
        let batch = try queue(store, ["a.jpg", "b.jpg"])
        let uploader = ScriptedUploader(processingRounds: 2)

        let summary = try await runner(store, uploader).run(batch.id)

        #expect(summary == UploadBatch.Summary(done: 2, failed: 0, remaining: 0, interrupted: 0))
        #expect(Set(await uploader.sentFiles) == ["a.jpg", "b.jpg"])
        #expect(try store.uploadItems(in: batch.id).map(\.photoID) == ["p-a", "p-b"])
    }

    @Test func aNewAlbumIsMadeFromTheFirstPhotoAndGetsTheRest() async throws {
        let store = try LibraryStore.inMemory()
        let batch = try queue(store, ["a.jpg", "b.jpg", "c.jpg"], album: .new(title: "Athens 2026"))
        let uploader = ScriptedUploader()

        _ = try await runner(store, uploader).run(batch.id)

        let created = await uploader.createdAlbums
        #expect(created.count == 1)
        #expect(created.first?.title == "Athens 2026")
        #expect(created.first?.cover == "p-a")
        #expect(await uploader.added.map(\.photo) == ["p-b", "p-c"])
        #expect(try store.uploadBatch(batch.id).albumID == "album-1")
        #expect(try store.uploadItems(in: batch.id).allSatisfy(\.inAlbum))
    }

    @Test func anExistingAlbumGetsEveryPhoto() async throws {
        let store = try LibraryStore.inMemory()
        let batch = try queue(store, ["a.jpg", "b.jpg"], album: .existing(id: "72157001"))
        let uploader = ScriptedUploader()
        _ = try await runner(store, uploader).run(batch.id)
        #expect(await uploader.createdAlbums.isEmpty)
        #expect(await uploader.added.map(\.album) == ["72157001", "72157001"])
    }

    @Test func aFileFlickrRefusesIsRecordedAndTheRestGo() async throws {
        let store = try LibraryStore.inMemory()
        let batch = try queue(store, ["a.jpg", "notes.txt", "c.jpg"])
        let uploader = ScriptedUploader(refusing: [
            "notes.txt": .api(code: 5, message: "Filetype was not recognised", transient: false)])

        let summary = try await runner(store, uploader).run(batch.id)

        #expect(summary == UploadBatch.Summary(done: 2, failed: 1, remaining: 0, interrupted: 0))
        let refused = try #require(try store.uploadItems(in: batch.id).first { $0.file.lastPathComponent == "notes.txt" })
        #expect(refused.state == .failed("Filetype was not recognised"))
        #expect(refused.message == "Filetype was not recognised")
    }

    @Test func needingPermissionPausesAndTheQueueResumes() async throws {
        let store = try LibraryStore.inMemory()
        let batch = try queue(store, ["a.jpg", "b.jpg"])
        await #expect(throws: FlickrError.permissionNeeded(.write)) {
            _ = try await runner(store, ScriptedUploader(refusing: ["a.jpg": .permissionNeeded(.write),
                                                                  "b.jpg": .permissionNeeded(.write)])).run(batch.id)
        }
        #expect(try store.uploadItems(in: batch.id).allSatisfy { $0.state == .queued })

        let summary = try await runner(store, ScriptedUploader()).run(batch.id)
        #expect(summary.done == 2)
    }

    /// Quit mid-send and nobody knows whether Flickr has the photo. Sending it
    /// again could make two; it waits for the person to decide.
    /// Unfinished: anything not yet on Flickr, or on Flickr but not yet in its
    /// album. Newest first.
    @Test func unfinishedBatchesAreFound() async throws {
        let store = try LibraryStore.inMemory()
        let finished = try queue(store, ["a.jpg"])
        _ = try await runner(store, ScriptedUploader()).run(finished.id)
        let waiting = try queue(store, ["b.jpg"])
        #expect(try store.unfinishedUploadBatchIDs() == [waiting.id])
    }

    @Test func aFileThatWasBeingSentWhenTheAppStoppedIsNotResentBlindly() async throws {
        let store = try LibraryStore.inMemory()
        let batch = try queue(store, ["a.jpg", "b.jpg"])
        let first = try #require(try store.uploadItems(in: batch.id).first)
        try store.markUpload(first, .sending)

        let uploader = ScriptedUploader()
        let summary = try await runner(store, uploader).run(batch.id)

        #expect(summary == UploadBatch.Summary(done: 1, failed: 0, remaining: 0, interrupted: 1))
        #expect(await uploader.sentFiles == ["b.jpg"])

        try store.resend(first)
        let again = try await runner(store, uploader).run(batch.id)
        #expect(again.done == 2)
    }

    /// Flickr refusing every attempt means nothing arrived: back in the queue.
    /// A dropped connection may have lost only the reply: interrupted.
    @Test func busyGoesBackInTheQueueButALostConnectionIsInterrupted() async throws {
        let store = try LibraryStore.inMemory()
        let busy = try queue(store, ["a.jpg"])
        await #expect(throws: FlickrError.self) {
            _ = try await runner(store, ScriptedUploader(refusing: ["a.jpg": .busy("Flickr is busy right now.")])).run(busy.id)
        }
        #expect(try store.uploadItems(in: busy.id).first?.state == .queued)

        let lost = try queue(store, ["b.jpg"])
        await #expect(throws: FlickrError.self) {
            _ = try await runner(store, ScriptedUploader(refusing: ["b.jpg": .transport("The network connection was lost.")])).run(lost.id)
        }
        #expect(try store.uploadItems(in: lost.id).first?.state == .interrupted)
    }

    /// A ticket already issued is followed up after a relaunch, not resent.
    @Test func aTicketIssuedBeforeARelaunchIsCheckedNotResent() async throws {
        let store = try LibraryStore.inMemory()
        let batch = try queue(store, ["a.jpg"])
        let item = try #require(try store.uploadItems(in: batch.id).first)
        try store.markUpload(item, .processing(ticket: "t-a"))
        let uploader = ScriptedUploader()
        _ = try await uploader.upload(file: URL(fileURLWithPath: "/photos/a.jpg"), metadata: UploadMetadata()) { _ in }

        let summary = try await runner(store, uploader).run(batch.id)

        #expect(summary.done == 1)
        #expect(await uploader.sentFiles == ["a.jpg"])
    }

    @Test func flickrFailingToProcessAFileIsAFailure() async throws {
        let store = try LibraryStore.inMemory()
        let batch = try queue(store, ["a.jpg"])
        let item = try #require(try store.uploadItems(in: batch.id).first)
        try store.markUpload(item, .processing(ticket: "unknown"))
        let summary = try await runner(store, ScriptedUploader(processingRounds: 0)).run(batch.id)
        #expect(summary.failed == 1)
    }
}
