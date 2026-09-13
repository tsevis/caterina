import Foundation
import Testing

import FlickrKit
@testable import CaterinaLibrary

/// Pages of photos from a script, failing where told.
actor ScriptedLists: PhotoListSource {
    private let pages: [LibraryPage]
    private let failOnPage: Int?
    private(set) var asked: [Int] = []

    init(_ ids: [[String]], failOnPage: Int? = nil) {
        self.pages = ids.enumerated().map { index, page in
            LibraryPage(page: index + 1, pages: ids.count, total: 0,
                        photos: page.map { LibraryPhoto(id: $0) }, skippedEntries: 0)
        }
        self.failOnPage = failOnPage
    }

    func photoList(_ list: PhotoList, page: Int) async throws -> LibraryPage {
        asked.append(page)
        if page == failOnPage { throw FlickrError.transport("The network connection was lost.") }
        return pages[page - 1]
    }
}

/// "Not in an album" is the one smart view the library copy cannot answer:
/// album membership is not a photo field. `photos.getNotInSet` is read whole
/// and kept beside the copy.
@Suite struct NotInAlbumTests {

    private func library() throws -> LibraryStore {
        let store = try LibraryStore.inMemory()
        try store.save(["1", "2", "3", "4"].map { LibraryStoreTests.photo($0) }, generation: 1)
        return store
    }

    @Test func everyPageIsReadAndTheViewShowsThem() async throws {
        let store = try library()
        let lists = ScriptedLists([["1", "2"], ["4"]])

        let count = try await NotInAlbumIndex(source: lists, store: store).refresh()

        #expect(count == 3)
        #expect(await lists.asked == [1, 2])
        #expect(try store.photos(.notInAlbum).map(\.id).sorted() == ["1", "2", "4"])
        #expect(try store.count(.notInAlbum) == 3)
        #expect(try store.notInAlbumReadAt() != nil)
    }

    /// Half a list would show photos as filed that are not; the last complete
    /// answer stays until a new one is whole.
    @Test func aReadCutOffKeepsTheLastCompleteAnswer() async throws {
        let store = try library()
        _ = try await NotInAlbumIndex(source: ScriptedLists([["1", "2"]]), store: store).refresh()

        await #expect(throws: FlickrError.self) {
            _ = try await NotInAlbumIndex(source: ScriptedLists([["3"], ["4"]], failOnPage: 2), store: store).refresh()
        }
        #expect(try store.photos(.notInAlbum).map(\.id).sorted() == ["1", "2"])
    }

    @Test func photosFiledHereLeaveTheViewAtOnce() async throws {
        let store = try library()
        _ = try await NotInAlbumIndex(source: ScriptedLists([["1", "2", "3"]]), store: store).refresh()
        try store.markFiled(["2", "3"])
        #expect(try store.photos(.notInAlbum).map(\.id) == ["1"])
    }

    @Test func neverReadMeansEmptyAndUnread() throws {
        let store = try library()
        #expect(try store.photos(.notInAlbum).isEmpty)
        #expect(try store.notInAlbumReadAt() == nil)
    }

    @Test func recentlyUpdatedIsAnOrder() throws {
        let store = try LibraryStore.inMemory()
        let photo = { (id: String, updated: Double?) in
            LibraryPhoto(id: id, lastUpdated: updated.map(Date.init(timeIntervalSince1970:)))
        }
        try store.save([photo("a", 10), photo("b", nil), photo("c", 30)], generation: 1)
        #expect(try store.photos(.all, order: .recentlyUpdated).map(\.id) == ["c", "a", "b"])
    }
}
