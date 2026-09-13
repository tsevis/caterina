import AppKit
import Foundation
import SwiftUI
import Testing

import CaterinaLibrary
import FlickrKit
@testable import CaterinaUI

actor OnePageLibrary: LibrarySource {
    private let ids: [String]
    private let failure: FlickrError?
    private(set) var calls = 0

    init(ids: [String], failure: FlickrError? = nil) {
        self.ids = ids
        self.failure = failure
    }

    func library(_ query: LibraryQuery, priority: CallPriority) async throws -> LibraryPage {
        calls += 1
        if let failure { throw failure }
        return LibraryPage(page: 1, pages: 1, total: ids.count,
                           photos: ids.map { LibraryPhoto(id: $0) }, skippedEntries: 0)
    }
}

/// The library as the window shows it: how many photos, and how fresh.
@MainActor
@Suite struct LibraryModelTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func itOpensShowingWhatTheCopyAlreadyHolds() throws {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryPhoto(id: "1"), LibraryPhoto(id: "2")], generation: 1)
        try store.save(LibrarySyncState(generation: 1, lastFullSync: now, changesSince: now, lastSynced: now))

        let model = LibraryModel(store: store, source: OnePageLibrary(ids: []))

        #expect(model.photoCount == 2)
        #expect(model.lastSynced == now)
        #expect(model.phase == .idle)
    }

    @Test func syncingFillsTheCopy() async throws {
        let store = try LibraryStore.inMemory()
        let model = LibraryModel(store: store, source: OnePageLibrary(ids: ["1", "2", "3"]),
                                 now: { self.now })

        await model.sync(signedIn: true)

        #expect(model.photoCount == 3)
        #expect(model.lastSynced == now)
        #expect(model.phase == .idle)
    }

    @Test func signedOutThereIsNothingToSync() async throws {
        let source = OnePageLibrary(ids: ["1"])
        let model = LibraryModel(store: try LibraryStore.inMemory(), source: source)

        await model.sync(signedIn: false)

        #expect(await source.calls == 0)
        #expect(model.phase == .failed("Sign in to Flickr to keep a copy of your library."))
    }

    @Test func aFailedSyncSaysWhyAndKeepsWhatWasThere() async throws {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryPhoto(id: "1")], generation: 1)
        let model = LibraryModel(store: store,
                                 source: OnePageLibrary(ids: [], failure: .busy("Flickr is busy right now.")))

        await model.sync(signedIn: true)

        #expect(model.phase == .failed("Flickr is busy right now."))
        #expect(model.photoCount == 1)
    }

    /// No store (the disk refused) is a state the window can show, not a crash.
    @Test func withoutACopyOnDiskItSaysSo() async throws {
        let model = LibraryModel(store: nil, source: OnePageLibrary(ids: ["1"]))
        await model.sync(signedIn: true)
        #expect(model.phase == .unavailable)
        #expect(model.photoCount == 0)
    }

    @Test func theStatusLineReadsNaturally() {
        #expect(LibraryModel.status(count: 18_402, lastSynced: now, at: now.addingTimeInterval(120))
                == "18,402 photos · synced 2 minutes ago")
        #expect(LibraryModel.status(count: 1, lastSynced: nil, at: now) == "1 photo · never synced")
    }
}

/// The status bar under Organize, drawn offscreen.
@MainActor
@Suite struct LibraryStatusBarRenderTests {
    @Test func theStatusBarDrawsItsWords() throws {
        let model = AppModel(vault: CredentialsVault(store: MemoryStore(seeded: true)),
                             transport: FakeTransport(body: "{}"),
                             libraryStore: try LibraryStore.inMemory())
        let renderer = ImageRenderer(content: LibraryStatusBar(model: model)
            .frame(width: 640, height: 40)
            .background(Color(nsColor: .windowBackgroundColor)))
        let image = try #require(renderer.nsImage)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var seen = Set<String>()
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
            guard let colour = bitmap.colorAt(x: x, y: bitmap.pixelsHigh / 2) else { continue }
            seen.insert(String(format: "%.2f", colour.brightnessComponent))
        }
        #expect(seen.count > 2)
    }
}
