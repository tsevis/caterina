import Foundation
import Testing

import FlickrKit
@testable import CaterinaLibrary

/// Answers library queries from a script, and remembers them.
actor ScriptedLibrary: LibrarySource {
    private var replies: [LibraryQuery: Result<LibraryPage, FlickrError>]
    private(set) var asked: [LibraryQuery] = []

    init(_ replies: [LibraryQuery: Result<LibraryPage, FlickrError>]) { self.replies = replies }

    func library(_ query: LibraryQuery, priority: CallPriority) async throws -> LibraryPage {
        asked.append(query)
        guard let reply = replies[query] else {
            return LibraryPage(page: 1, pages: 1, total: 0, photos: [], skippedEntries: 0)
        }
        return try reply.get()
    }
}

final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

@Suite struct LibrarySyncTests {

    private func page(_ ids: [String], page: Int = 1, of pages: Int = 1) -> Result<LibraryPage, FlickrError> {
        .success(LibraryPage(page: page, pages: pages, total: ids.count * pages,
                             photos: ids.map { LibraryStoreTests.photo($0) }, skippedEntries: 0))
    }

    @Test func theFirstSyncFetchesEveryPage() async throws {
        let store = try LibraryStore.inMemory()
        let clock = Clock()
        let source = ScriptedLibrary([
            .everything(page: 1): page(["1", "2"], page: 1, of: 2),
            .everything(page: 2): page(["3"], page: 2, of: 2),
        ])
        let sync = LibrarySync(source: source, store: store, now: { clock.now })

        let outcome = try await sync.run()

        #expect(outcome == .full(saved: 3, removed: 0))
        #expect(try store.count(.all) == 3)
        let state = try store.syncState()
        #expect(state.generation == 1)
        #expect(state.lastFullSync == clock.now)
        #expect(state.changesSince == clock.now)
    }

    /// Changes are asked for from when the last sync *started*: a photo edited
    /// while page 30 of 40 was downloading is caught next time.
    @Test func afterThatOnlyChangesAreFetched() async throws {
        let store = try LibraryStore.inMemory()
        let clock = Clock()
        let started = clock.now
        try store.save(LibrarySyncState(generation: 1, lastFullSync: started, changesSince: started))
        clock.advance(3600)
        let source = ScriptedLibrary([.updated(since: started, page: 1): page(["9"])])
        let sync = LibrarySync(source: source, store: store, now: { clock.now })

        let outcome = try await sync.run()

        #expect(outcome == .changes(saved: 1))
        #expect(await source.asked == [.updated(since: started, page: 1)])
        #expect(try store.syncState().changesSince == clock.now)
        #expect(try store.syncState().lastFullSync == started)
    }

    /// Changes never report a deletion, so a full pass runs weekly to notice.
    @Test func aWeekAfterTheLastFullSyncTheNextIsFullAgain() async throws {
        let store = try LibraryStore.inMemory()
        let clock = Clock()
        try store.save(LibrarySyncState(generation: 4, lastFullSync: clock.now, changesSince: clock.now))
        try store.save([LibraryStoreTests.photo("gone"), LibraryStoreTests.photo("1")], generation: 4)
        clock.advance(LibrarySync.fullSyncInterval + 1)
        let source = ScriptedLibrary([.everything(page: 1): page(["1"])])
        let sync = LibrarySync(source: source, store: store, now: { clock.now })

        let outcome = try await sync.run()

        #expect(outcome == .full(saved: 1, removed: 1))
        #expect(try store.photos(.all).map(\.id) == ["1"])
        #expect(try store.syncState().generation == 5)
    }

    /// A sync that fails halfway must not decide that everything after the
    /// failure was deleted.
    @Test func aFullSyncThatFailsHalfwayRemovesNothing() async throws {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryStoreTests.photo("old")], generation: 0)
        let source = ScriptedLibrary([
            .everything(page: 1): page(["1"], page: 1, of: 2),
            .everything(page: 2): .failure(.busy("Flickr is busy right now.")),
        ])
        let sync = LibrarySync(source: source, store: store, now: { Date() })

        await #expect(throws: FlickrError.busy("Flickr is busy right now.")) {
            _ = try await sync.run()
        }
        #expect(Set(try store.photos(.all).map(\.id)) == ["old", "1"])
        #expect(try store.syncState() == .never)
    }

    /// An empty answer about a library that had photos is far likelier to be
    /// Flickr misbehaving than every photo deleted since last week.
    @Test func anEmptyReplyDoesNotEmptyALibraryThatHadPhotos() async throws {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryStoreTests.photo("1")], generation: 0)
        let source = ScriptedLibrary([.everything(page: 1): page([])])
        let sync = LibrarySync(source: source, store: store, now: { Date() })

        let outcome = try await sync.run()

        #expect(outcome == .full(saved: 0, removed: 0))
        #expect(try store.count(.all) == 1)
    }

    @Test func progressIsReportedPageByPage() async throws {
        let store = try LibraryStore.inMemory()
        let source = ScriptedLibrary([
            .everything(page: 1): page(["1", "2"], page: 1, of: 2),
            .everything(page: 2): page(["3", "4"], page: 2, of: 2),
        ])
        let sync = LibrarySync(source: source, store: store, now: { Date() })
        let seen = Recorded()

        _ = try await sync.run { progress in seen.append(progress) }

        #expect(seen.values == [LibrarySync.Progress(fetched: 2, total: 4),
                                LibrarySync.Progress(fetched: 4, total: 4)])
    }
}

final class Recorded: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [LibrarySync.Progress] = []
    var values: [LibrarySync.Progress] { lock.withLock { stored } }
    func append(_ value: LibrarySync.Progress) { lock.withLock { stored.append(value) } }
}
