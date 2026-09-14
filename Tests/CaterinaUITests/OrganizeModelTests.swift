import Foundation
import Testing

import CaterinaLibrary
import FlickrKit
@testable import CaterinaUI

/// Flickr for Organize: reads back from the library copy, sends writes, and
/// can hold the not-in-album list until told to answer.
actor FakeOrganizeFlickr: OrganizeFlickr {
    struct FakeAlbum: Equatable, Sendable {
        let id: String
        var title: String
        var description: String
        var cover: String
        var photos: [String]
    }

    private let store: LibraryStore
    private var albums: [FakeAlbum]
    private var refusals: [String: FlickrError]
    private var notInAlbum: [String]
    private var held: CheckedContinuation<Void, Never>?
    private var holding = false
    private(set) var sent: [FlickrWrite] = []
    var listFailure: FlickrError?
    func failLists(with error: FlickrError) { listFailure = error }

    init(store: LibraryStore, notInAlbum: [String] = [], refusals: [String: FlickrError] = [:],
         albums: [FakeAlbum] = []) {
        self.store = store
        self.albums = albums
        self.notInAlbum = notInAlbum
        self.refusals = refusals
    }

    func refuse(_ photoID: String, with error: FlickrError?) { refusals[photoID] = error }
    func hold() { holding = true }
    func release() { holding = false; held?.resume(); held = nil }
    var isHolding: Bool { held != nil }

    func perform(_ write: FlickrWrite, priority: CallPriority) async throws -> Data {
        if let refusal = refusals[write.arguments["photo_id"] ?? ""] { throw refusal }
        if write.method.hasPrefix("flickr.photosets."), write.method != "flickr.photosets.orderSets",
           let album = write.arguments["photoset_id"], !albums.contains(where: { $0.id == album }) {
            throw FlickrError.api(code: 1, message: "Photoset not found", transient: false)
        }
        sent.append(write)
        applyAlbumWrite(write)
        return Data(#"{"stat":"ok"}"#.utf8)
    }

    // MARK: Albums, in memory

    func album(_ id: String) -> FakeAlbum? { albums.first { $0.id == id } }
    func albumTitled(_ title: String) -> FakeAlbum? { albums.first { $0.title == title } }
    var albumOrder: [String] { albums.map(\.id) }

    func albums(page: Int) async throws -> AlbumPage {
        AlbumPage(page: 1, pages: 1, albums: albums.map {
            Album(id: $0.id, title: $0.title, description: $0.description, photoCount: $0.photos.count,
                  coverPhotoID: $0.cover, views: 0)
        })
    }
    func albumPhotoIDs(albumID: String, ownerID: String, priority: CallPriority) async throws -> [String] {
        album(albumID)?.photos ?? []
    }
    func albumSnapshot(reading reads: [AlbumEdit.Read], albumID: String?, ownerID: String,
                       priority: CallPriority) async throws -> AlbumSnapshot {
        let found = albumID.flatMap(album)
        return AlbumSnapshot(title: found?.title ?? "", description: found?.description ?? "",
                             coverPhotoID: found?.cover ?? "", photoIDs: found?.photos ?? [], albumOrder: albumOrder)
    }
    func createAlbum(title: String, description: String, coverPhotoID: String,
                     priority: CallPriority) async throws -> String {
        let id = "N\(albums.count + 1)"
        albums.insert(FakeAlbum(id: id, title: title, description: description, cover: coverPhotoID,
                                photos: [coverPhotoID]), at: 0)
        return id
    }

    private func applyAlbumWrite(_ write: FlickrWrite) {
        let args = write.arguments
        guard let index = albums.firstIndex(where: { $0.id == args["photoset_id"] }) ?? (write.method == "flickr.photosets.orderSets" ? 0 : nil) else { return }
        let list = (args["photo_ids"] ?? "").split(separator: ",").map(String.init)
        switch write.method {
        case "flickr.photosets.addPhoto": albums[index].photos.append(args["photo_id"] ?? "")
        case "flickr.photosets.removePhotos": albums[index].photos.removeAll { list.contains($0) }
        case "flickr.photosets.reorderPhotos":
            albums[index].photos = list + albums[index].photos.filter { !list.contains($0) }
        case "flickr.photosets.setPrimaryPhoto": albums[index].cover = args["photo_id"] ?? ""
        case "flickr.photosets.editMeta":
            albums[index].title = args["title"] ?? ""
            albums[index].description = args["description"] ?? ""
        case "flickr.photosets.delete": albums.remove(at: index)
        case "flickr.photosets.orderSets":
            let ids = (args["photoset_ids"] ?? "").split(separator: ",").map(String.init)
            albums = ids.compactMap { id in albums.first { $0.id == id } } + albums.filter { !ids.contains($0.id) }
        default: break
        }
    }
    func livePhoto(id: String, priority: CallPriority) async throws -> LibraryPhoto {
        if holding { await withCheckedContinuation { held = $0 } }
        guard let photo = try store.photos(ids: [id]).first else { throw FlickrError.notFound("gone") }
        return photo
    }
    func geoPermissions(photoID: String, priority: CallPriority) async throws -> LibraryPhoto.GeoPermissions? { nil }
    func lookUpPerson(_ input: String) async throws -> FlickrPerson { FlickrPerson(nsid: "nsid-\(input)", username: input) }
    func collections() async throws -> [PhotoCollection] {
        [PhotoCollection(id: "c1", title: "Travel", description: "", albums: [],
                         children: [PhotoCollection(id: "c2", title: "Greece", description: "",
                                                    albums: [.init(id: "A", title: "Athens")], children: [])])]
    }
    func photoList(_ list: PhotoList, page: Int) async throws -> LibraryPage {
        if holding { await withCheckedContinuation { held = $0 } }
        if let listFailure { throw listFailure }
        return LibraryPage(page: 1, pages: 1, total: notInAlbum.count,
                           photos: notInAlbum.map { LibraryPhoto(id: $0) }, skippedEntries: 0)
    }
}

@MainActor
@Suite struct OrganizeModelTests {

    private func library() throws -> LibraryStore {
        let store = try LibraryStore.inMemory()
        try store.save([
            LibraryPhoto(id: "1", title: "Harbour", tags: ["sea"], taken: "2024-06-01 10:00:00"),
            LibraryPhoto(id: "2", title: "Hill", taken: "2024-05-01 10:00:00",
                         location: .init(latitude: 1, longitude: 2, accuracy: 16)),
            LibraryPhoto(id: "3", title: "Pier", tags: ["sea"], taken: "2023-01-01 10:00:00", media: .video),
        ], generation: 1)
        return store
    }

    private func model(_ store: LibraryStore, _ flickr: FakeOrganizeFlickr? = nil) -> OrganizeModel {
        OrganizeModel(store: store, flickr: flickr ?? FakeOrganizeFlickr(store: store))
    }

    // MARK: - Finding photos

    @Test func eachViewShowsItsPhotos() async throws {
        let model = model(try library())
        #expect(model.photos.map(\.id) == ["1", "2", "3"])
        await model.open(.untagged)
        #expect(model.photos.map(\.id) == ["2"])
        await model.open(.withLocation)
        #expect(model.photos.map(\.id) == ["2"])
        await model.open(.videos)
        #expect(model.photos.map(\.id) == ["3"])
        await model.open(.tag("sea"))
        #expect(model.photos.map(\.id) == ["1", "3"])
        await model.open(.month("2024-05"))
        #expect(model.photos.map(\.id) == ["2"])
        #expect(model.count(of: .untagged) == 1)
        #expect(model.tags.map(\.tag) == ["sea"])
    }

    @Test func notInAnAlbumIsReadFromFlickrTheFirstTimeItOpens() async throws {
        let store = try library()
        let model = model(store, FakeOrganizeFlickr(store: store, notInAlbum: ["2", "3"]))
        await model.open(.notInAlbum)
        #expect(model.photos.map(\.id) == ["2", "3"])
        #expect(model.notInAlbumReadAt != nil)
    }

    /// A slow not-in-album read, failing, must not put its complaint on the
    /// view chosen after it.
    @Test func aLateNotInAlbumReplyDoesNotLandOnTheViewOpenedSince() async throws {
        let store = try library()
        let flickr = FakeOrganizeFlickr(store: store, notInAlbum: ["2"])
        await flickr.failLists(with: .busy("Flickr is busy right now."))
        await flickr.hold()
        let model = model(store, flickr)

        let opening = Task { await model.open(.notInAlbum) }
        try await waitUntil("the read to start") { await flickr.isHolding }
        await model.open(.videos)
        await flickr.release()
        await opening.value

        #expect(model.scope == .videos)
        #expect(model.photos.map(\.id) == ["3"])
        #expect(model.problem == nil)
    }

    // MARK: - Selection and the tray

    @Test func theTrayKeepsPhotosAcrossViews() async throws {
        let model = model(try library())
        model.click("1", modifiers: [])
        model.click("3", modifiers: .command)
        model.addSelectionToTray()
        await model.open(.untagged)
        model.selectAll()
        model.addSelectionToTray()
        model.addSelectionToTray()

        #expect(model.tray == ["1", "3", "2"])
        #expect(model.trayPhotos.map(\.id) == ["1", "3", "2"])
        model.removeFromTray(["3"])
        #expect(model.tray == ["1", "2"])
        model.clearTray()
        #expect(model.tray.isEmpty)
    }

    /// Changing view keeps the tray but not the grid selection.
    @Test func selectionBelongsToTheView() async throws {
        let model = model(try library())
        model.selectAll()
        await model.open(.videos)
        #expect(model.selection.isEmpty)
    }

    // MARK: - Cost before running

    @Test func theEstimateCountsOnlyPhotosTheEditChanges() throws {
        let model = model(try library())
        model.selectAll()
        model.addSelectionToTray()

        let estimate = model.estimate(.addTags(["sea"]))

        #expect(estimate.photos == 1)
        #expect(estimate.unchanged == 2)
        #expect(estimate.calls == 2)
        #expect(estimate.summary == "1 photo · 2 calls · under a minute")
        #expect(estimate.unrestorable.isEmpty)
    }

    @Test func anEditThatCannotBeUndoneSaysSo() throws {
        let model = model(try library())
        model.selectAll()
        model.addSelectionToTray()
        #expect(model.estimate(.setContentType(.screenshot)).unrestorable == ["content type"])
    }

    @Test func largeBatchesAreEstimatedInMinutesAndHours() {
        #expect(EditEstimate.describe(seconds: 0) == "a moment")
        #expect(EditEstimate.describe(seconds: 59) == "under a minute")
        #expect(EditEstimate.describe(seconds: 799) == "about 13 minutes")
        #expect(EditEstimate.describe(seconds: 8_199) == "about 2 hours 17 minutes")
    }

    // MARK: - Running, activity and undo

    @Test func applyingAnEditRunsItAndListsItInActivity() async throws {
        let store = try library()
        let flickr = FakeOrganizeFlickr(store: store)
        let model = model(store, flickr)
        model.selectAll()
        model.addSelectionToTray()

        await model.apply(.setTitle("Athens {n}"), title: "Set title")

        #expect(await flickr.sent.map { $0.arguments["title"] } == ["Athens 1", "Athens 2", "Athens 3"])
        #expect(model.activity.first?.batch.title == "Set title")
        #expect(model.activity.first?.summary == EditBatch.Summary(applied: 3, failed: 0, pending: 0))
        #expect(model.photos.map(\.title) == ["Athens 1", "Athens 2", "Athens 3"])
        #expect(model.run == .idle)
    }

    @Test func refusalsAreListedWithFlickrsReason() async throws {
        let store = try library()
        let flickr = FakeOrganizeFlickr(store: store,
                                        refusals: ["2": .api(code: 1, message: "Photo not found", transient: false)])
        let model = model(store, flickr)
        model.selectAll()
        model.addSelectionToTray()

        await model.apply(.setTitle("A"), title: "Set title")

        let row = try #require(model.activity.first)
        #expect(row.failures == [.init(photoID: "2", title: "Hill", message: "Photo not found")])
    }

    @Test func needingWritePermissionPausesUntilApprovedThenResumes() async throws {
        let store = try library()
        let flickr = FakeOrganizeFlickr(store: store, refusals: ["1": .permissionNeeded(.write)])
        let model = model(store, flickr)
        model.selectAll()
        model.addSelectionToTray()

        await model.apply(.setTitle("A"), title: "Set title")
        guard case let .needsPermission(permission, batchID) = model.run else {
            Issue.record("expected to need permission, got \(model.run)")
            return
        }
        #expect(permission == .write)
        #expect(model.activity.first?.canResume == true)

        await flickr.refuse("1", with: nil)
        await model.resume(batchID)
        #expect(model.activity.first?.summary.applied == 3)
        #expect(model.run == .idle)
    }

    @Test func undoPutsBackWhatWasThereAndIsListedToo() async throws {
        let store = try library()
        let flickr = FakeOrganizeFlickr(store: store)
        let model = model(store, flickr)
        model.click("1", modifiers: [])
        model.addSelectionToTray()
        await model.apply(.setTitle("Athens"), title: "Set title")
        let batchID = try #require(model.activity.first?.batch.id)
        #expect(model.activity.first?.canUndo == true)

        await model.undo(batchID)

        #expect(await flickr.sent.last?.arguments["title"] == "Harbour")
        #expect(model.activity.map(\.batch.title) == ["Undo Set title", "Set title"])
        #expect(model.activity.last?.canUndo == false)
        #expect(model.photos.first { $0.id == "1" }?.title == "Harbour")
    }

    /// One batch at a time: two runs of the same entries would send twice.
    @Test func aSecondApplyWhileOneRunsIsRefused() async throws {
        let store = try library()
        let flickr = FakeOrganizeFlickr(store: store)
        let model = model(store, flickr)
        model.selectAll()
        model.addSelectionToTray()
        await flickr.hold()
        let first = Task { await model.apply(.setTitle("A"), title: "Set title") }
        try await waitUntil("the first batch to start") { await flickr.isHolding }

        await model.apply(.setTitle("B"), title: "Set title")
        #expect(model.problem == "Wait for the edit that is running to finish.")
        await flickr.release()
        await first.value
        #expect(await flickr.sent.compactMap { $0.arguments["title"] } == ["A", "A", "A"])
    }
}

/// Found in review: writes nobody meant to send.
@MainActor
@Suite struct OrganizeSafetyTests {

    private func library(_ count: Int = 3) throws -> LibraryStore {
        let store = try LibraryStore.inMemory()
        try store.save((1...count).map { LibraryPhoto(id: "\($0)", title: "Photo \($0)", taken: "2024-01-0\(min($0, 9)) 10:00:00") },
                       generation: 1)
        return store
    }

    @Test func aRunningBatchCanBeStoppedAndResumedLater() async throws {
        let store = try library()
        let flickr = FakeOrganizeFlickr(store: store)
        let model = OrganizeModel(store: store, flickr: flickr, accountID: { "me" })
        model.selectAll()
        model.addSelectionToTray()
        await flickr.hold()
        let running = Task { await model.apply(.setTitle("A"), title: "T") }
        try await waitUntil("the batch to start") { await flickr.isHolding }

        model.stop()
        await flickr.release()
        await running.value

        #expect(!model.isRunning)
        let row = try #require(model.activity.first)
        #expect(row.summary.pending > 0)
        #expect(row.canResume)
    }

    /// Signed out, or signed in as someone else: the batch stops, and the
    /// first account's batches can neither resume nor undo under the second.
    @Test func anotherAccountCannotResumeOrUndoTheFirstAccountsBatches() async throws {
        let store = try library()
        let account = AccountBox("me")
        let model = OrganizeModel(store: store, flickr: FakeOrganizeFlickr(store: store), accountID: { account.value })
        model.selectAll()
        model.addSelectionToTray()
        await model.apply(.setTitle("A"), title: "T")
        let batchID = try #require(model.activity.first?.batch.id)

        account.value = "someone-else"
        model.accountChanged()

        #expect(model.tray.isEmpty)
        #expect(model.activity.first?.canUndo == false)
        await model.undo(batchID)
        #expect(model.activity.count == 1)
        #expect(model.problem == "That edit was made by another Flickr account.")
    }

    @Test func aBatchWhereEveryPhotoWasRefusedHasNothingToUndo() async throws {
        let store = try library(1)
        let flickr = FakeOrganizeFlickr(store: store, refusals: ["1": .api(code: 1, message: "Photo not found", transient: false)])
        let model = OrganizeModel(store: store, flickr: flickr, accountID: { "me" })
        model.selectAll()
        model.addSelectionToTray()
        await model.apply(.setTitle("A"), title: "T")
        #expect(model.activity.first?.canUndo == false)
    }

    /// Leaving the view while it was read and coming back must show the
    /// answer once it arrives.
    @Test func notInAnAlbumShowsItsAnswerAfterLeavingAndComingBack() async throws {
        let store = try library()
        let flickr = FakeOrganizeFlickr(store: store, notInAlbum: ["2"])
        await flickr.hold()
        let model = OrganizeModel(store: store, flickr: flickr)
        let first = Task { await model.open(.notInAlbum) }
        try await waitUntil("the read to start") { await flickr.isHolding }
        await model.open(.all)
        await model.open(.notInAlbum)
        await flickr.release()
        await first.value
        #expect(model.photos.map(\.id) == ["2"])
    }

    /// After a batch, the grid keeps as many photos as were showing.
    @Test func aReloadKeepsWhatWasLoaded() async throws {
        let store = try library(OrganizeModel.pageSize + 5)
        let model = OrganizeModel(store: store, flickr: FakeOrganizeFlickr(store: store))
        model.loadMore()
        #expect(model.photos.count == OrganizeModel.pageSize + 5)
        model.libraryChanged()
        #expect(model.photos.count == OrganizeModel.pageSize + 5)
    }
}

final class AccountBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    init(_ value: String?) { stored = value }
    var value: String? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

@MainActor
@Suite struct OrganizeActionTests {

    private func setUp() throws -> (OrganizeModel, FakeOrganizeFlickr) {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryPhoto(id: "1", title: "A"), LibraryPhoto(id: "2", title: "B")], generation: 1)
        let flickr = FakeOrganizeFlickr(store: store)
        let model = OrganizeModel(store: store, flickr: flickr, accountID: { "me" })
        model.selectAll()
        model.addSelectionToTray()
        return (model, flickr)
    }

    @Test func theTrayIsRotatedAndTheCostIsOneCallAPhoto() async throws {
        let (model, flickr) = try setUp()
        #expect(model.estimate(action: .rotate(degrees: 90)).calls == 2)
        await model.perform(.rotate(degrees: 90), title: "Rotate")
        #expect(await flickr.sent.map(\.method) == ["flickr.photos.transform.rotate", "flickr.photos.transform.rotate"])
        #expect(model.activity.first?.canUndo == true)
    }

    @Test func aPersonIsFoundByNameThenTagged() async throws {
        let (model, flickr) = try setUp()
        let person = try #require(await model.lookUpPerson("tsevis"))
        #expect(person.username == "tsevis")
        #expect(await flickr.sent.isEmpty)
        await model.perform(.addPerson(userID: person.nsid), title: "Tag tsevis")
        #expect(await flickr.sent.map { $0.arguments["user_id"] } == ["nsid-tsevis", "nsid-tsevis"])
    }

    /// Deleting: the whole tray, recorded, with nothing to undo, and the
    /// photos gone from the copy and the tray.
    @Test func deletingTheTray() async throws {
        let (model, flickr) = try setUp()
        await model.deleteTray()
        #expect(await flickr.sent.map(\.permission) == [.delete, .delete])
        #expect(model.tray.isEmpty)
        #expect(model.photos.isEmpty)
        #expect(model.activity.first?.canUndo == false)
    }
}

@MainActor
@Suite struct OrganizeGalleryTests {
    @Test func aPhotoFromBrowseGoesIntoAGalleryAndCanBeTakenOut() async throws {
        let store = try LibraryStore.inMemory()
        let flickr = FakeOrganizeFlickr(store: store)
        let model = OrganizeModel(store: store, flickr: flickr, accountID: { "me" })

        await model.addToGallery(photoID: "someone-else", galleryID: "g1", galleryTitle: "Blue", comment: "")

        #expect(await flickr.sent.map(\.method) == ["flickr.galleries.addPhoto"])
        let row = try #require(model.activity.first)
        #expect(row.batch.title == "Add a photo to gallery “Blue”")
        #expect(row.canUndo)
        await model.undo(row.batch.id)
        #expect(await flickr.sent.last?.method == "flickr.galleries.removePhoto")
    }
}

/// Whole views and whole-library tag removal, past the 600 photos a grid loads.
@MainActor
@Suite struct WholeViewTests {

    private func library(_ count: Int) throws -> LibraryStore {
        let store = try LibraryStore.inMemory()
        try store.save((1...count).map { LibraryPhoto(id: "\($0)", title: "P\($0)", tags: $0 % 2 == 0 ? ["sea", "Blue"] : ["blue"],
                                                      taken: String(format: "2024-01-01 %02d:%02d:%02d", ($0 / 3600) % 24, ($0 / 60) % 60, $0 % 60)) },
                       generation: 1)
        return store
    }

    @Test func theWholeViewGoesInTheTrayNotJustWhatIsLoaded() async throws {
        let store = try library(OrganizeModel.pageSize + 150)
        let model = OrganizeModel(store: store, flickr: FakeOrganizeFlickr(store: store), accountID: { "me" })
        await model.open(.tag("sea"))
        #expect(model.viewCount == 375)

        model.click("2", modifiers: [])
        model.addSelectionToTray()
        await model.addEntireViewToTray()

        #expect(model.tray.count == 375)
        #expect(model.tray.first == "2")
        #expect(Set(model.tray).count == 375)
    }

    @Test func theWholeAllPhotosViewTooInItsOrder() async throws {
        let store = try library(OrganizeModel.pageSize + 5)
        let model = OrganizeModel(store: store, flickr: FakeOrganizeFlickr(store: store), accountID: { "me" })
        await model.addEntireViewToTray()
        #expect(model.tray.count == OrganizeModel.pageSize + 5)
        #expect(model.tray == model.photos.map(\.id) + model.tray.dropFirst(model.photos.count))
    }

    @Test func anAlbumViewAddsEveryPhotoInTheAlbum() async throws {
        let store = try library(3)
        let flickr = FakeOrganizeFlickr(store: store, albums: [.init(id: "A", title: "A", description: "", cover: "3", photos: ["3", "1"])])
        let model = OrganizeModel(store: store, flickr: flickr, accountID: { "me" })
        await model.open(.album(id: "A", title: "A"))
        #expect(model.viewCount == 2)
        await model.addEntireViewToTray()
        #expect(model.tray == ["3", "1"])
    }

    /// Removing a tag everywhere touches only photos that carry it, in any
    /// spelling, leaves the tray alone, and says the cost first.
    @Test func aTagIsRemovedFromEveryPhotoThatHasIt() async throws {
        let store = try library(OrganizeModel.pageSize + 150)
        let flickr = FakeOrganizeFlickr(store: store)
        let model = OrganizeModel(store: store, flickr: flickr, accountID: { "me" })
        let kept = try #require(model.photos.first?.id)
        model.click(kept, modifiers: [])
        model.addSelectionToTray()

        let estimate = model.estimateRemovingEverywhere("blue")
        #expect(estimate.photos == 750)
        #expect(estimate.calls == 1_500)

        await model.removeTagEverywhere("blue")

        #expect(await flickr.sent.count == 750)
        #expect(try store.photos(.tagged("blue")).isEmpty)
        #expect(try store.photos(.tagged("sea")).count == 375)
        #expect(model.tray == [kept])
        let row = try #require(model.activity.first)
        #expect(row.batch.title == "Remove tag “blue” from 750 photos")
        #expect(row.canUndo)
    }

    @Test func aTagNobodyHasCostsNothingAndSendsNothing() async throws {
        let store = try library(3)
        let flickr = FakeOrganizeFlickr(store: store)
        let model = OrganizeModel(store: store, flickr: flickr, accountID: { "me" })
        #expect(model.estimateRemovingEverywhere("absent").photos == 0)
        await model.removeTagEverywhere("absent")
        #expect(await flickr.sent.isEmpty)
        #expect(model.activity.isEmpty)
    }
}

@MainActor
@Suite struct LargeTrayTests {
    /// The estimate is redrawn as someone types; a whole library in the tray
    /// must not make typing lag.
    @Test func estimatingEighteenThousandPhotosIsQuick() async throws {
        let store = try LibraryStore.inMemory()
        try store.save((1...18_000).map { LibraryPhoto(id: "\($0)", title: "P", tags: ["a", "b"]) }, generation: 1)
        let model = OrganizeModel(store: store, flickr: FakeOrganizeFlickr(store: store), accountID: { "me" })
        await model.addEntireViewToTray()
        #expect(model.tray.count == 18_000)
        let clock = ContinuousClock()
        // A debug build; a release build is several times quicker. It was 7 s
        // before tag cleaning stopped running a pattern on every tag.
        let took = clock.measure { _ = model.estimate(.addTags(["New York"])) }
        #expect(took < .seconds(1.5), "estimate took \(took)")
        let again = clock.measure { _ = model.estimate(.addTags(["New York"])) }
        #expect(again < .milliseconds(50), "a repeat took \(again)")
    }
}

@MainActor
@Suite struct RemoveTagSignedOutTests {
    @Test func removingATagEverywhereNeedsASignedInAccount() async throws {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryPhoto(id: "1", tags: ["sea"])], generation: 1)
        let flickr = FakeOrganizeFlickr(store: store)
        let model = OrganizeModel(store: store, flickr: flickr, accountID: { nil })
        await model.removeTagEverywhere("sea")
        #expect(await flickr.sent.isEmpty)
        #expect(model.problem == "Sign in to Flickr to change your photos.")
    }
}
