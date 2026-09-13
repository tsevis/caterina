import Foundation
import Testing

import CaterinaLibrary
import FlickrKit
@testable import CaterinaUI

actor FakeDirectory: AccountDirectorySource {
    private(set) var listed: [(PhotoList, Int)] = []

    func albums(page: Int) async throws -> AlbumPage {
        AlbumPage(page: 1, pages: 1, albums: [Album(id: "a1", title: "Athens", description: "", photoCount: 2, coverPhotoID: "1", views: 9)])
    }
    func groups(of userID: String) async throws -> [AccountGroup] {
        [AccountGroup(id: "g1", name: "Mosaics", members: 10, photos: 100, isAdmin: false)]
    }
    func galleries() async throws -> [Gallery] { [Gallery(id: "gal", title: "Blue", description: "", itemCount: 4)] }
    func collections() async throws -> [PhotoCollection] { [] }
    func contacts(page: Int) async throws -> ContactPage {
        ContactPage(page: 1, pages: 1, contacts: [Contact(id: "c1", username: "cal", realName: "Cal", isFriend: true, isFamily: false)])
    }
    func photoList(_ list: PhotoList, page: Int) async throws -> LibraryPage {
        listed.append((list, page))
        let ids = page == 1 ? ["r1", "r2"] : ["r3"]
        return LibraryPage(page: page, pages: 2, total: 3,
                           photos: ids.map { LibraryPhoto(id: $0, title: $0, ownerName: "someone") }, skippedEntries: 0)
    }
}

@MainActor
@Suite struct BrowseScopeTests {

    private let now = Date(timeIntervalSince1970: 1_717_243_200)

    private func library() throws -> LibraryStore {
        let store = try LibraryStore.inMemory()
        try store.save([
            LibraryPhoto(id: "1", title: "Harbour", tags: ["sea"], taken: "2024-06-01 10:00:00", views: 50,
                         location: .init(latitude: 37.9, longitude: 23.6, accuracy: 16)),
            LibraryPhoto(id: "2", title: "Hill", tags: ["sea", "hill"], taken: "2023-01-02 10:00:00", views: 500,
                         media: .video),
        ], generation: 1)
        return store
    }

    private func model(_ store: LibraryStore? = nil, _ directory: FakeDirectory = FakeDirectory()) throws -> BrowseModel {
        BrowseModel(store: try store ?? library(), records: FakeRecords(), stats: FakeRecords(), directory: directory,
                    accountID: { "me@N00" }, now: { self.now })
    }

    @Test func aTagShowsItsPhotos() async throws {
        let model = try model()
        await model.open(.library(.tagged("hill"), title: "hill"))
        #expect(model.items.map(\.photo.id) == ["2"])
        #expect(model.scope.title == "hill")
    }

    @Test func theTagsIndexCountsEveryTag() async throws {
        let model = try model()
        await model.open(.tags)
        #expect(model.tags.map(\.tag) == ["sea", "hill"])
    }

    @Test func theTimelineIndexIsYearsAndMonths() async throws {
        let model = try model()
        await model.open(.timeline)
        #expect(model.months.map(\.month) == ["2024-06", "2023-01"])
    }

    @Test func placesAreYourLocatedPhotosOnAMap() async throws {
        let model = try model()
        await model.open(.places)
        #expect(model.items.map(\.photo.id) == ["1"])
        #expect(model.layout == .map)
    }

    /// A map of photos with no location is an empty ocean; it is not offered.
    @Test func theMapIsOfferedOnlyWhenSomethingHasALocation() async throws {
        let model = try model()
        await model.open(.library(.videos, title: "Videos"))
        #expect(!model.availableLayouts.contains(.map))
        await model.open(.library(.all, title: "All photos"))
        #expect(model.availableLayouts.contains(.map))
    }

    @Test func anAlbumIsReadFromFlickrAndPagesOnDemand() async throws {
        let directory = FakeDirectory()
        let model = try model(nil, directory)
        await model.open(.remote(.album(id: "a1", ownerID: "me@N00"), title: "Athens"))
        #expect(model.items.map(\.photo.id) == ["r1", "r2"])
        #expect(model.canLoadMore)

        await model.loadMore()
        #expect(model.items.map(\.photo.id) == ["r1", "r2", "r3"])
        #expect(!model.canLoadMore)
        #expect(model.items.first?.figure == "someone")
    }

    @Test func theDirectoryListsYourAlbumsGroupsGalleriesAndContacts() async throws {
        let model = try model()
        await model.open(.albums)
        #expect(model.directory.albums.map(\.title) == ["Athens"])
        await model.open(.groups)
        #expect(model.directory.groups.map(\.name) == ["Mosaics"])
        await model.open(.galleries)
        #expect(model.directory.galleries.map(\.title) == ["Blue"])
        await model.open(.people)
        #expect(model.directory.contacts.map(\.displayName) == ["Cal"])
    }

    @Test func aGroupShowsYourPhotosInItsPool() async throws {
        let directory = FakeDirectory()
        let model = try model(nil, directory)
        await model.open(BrowseScope.pool(of: AccountGroup(id: "g1", name: "Mosaics", members: 1, photos: 1, isAdmin: false),
                                          accountID: "me@N00"))
        #expect(await directory.listed.first?.0 == .groupPool(groupID: "g1", contributorID: "me@N00"))
    }

    @Test func aFansPhotosAreThePhotosTheyFaved() async throws {
        let store = try library()
        try store.replaceFaves([Fave(nsid: "ann", username: "Ann", date: Date(timeIntervalSince1970: 5))], of: "2", readAt: now)
        let model = try model(store)
        await model.open(.favedBy(nsid: "ann", name: "Ann"))
        #expect(model.items.map(\.photo.id) == ["2"])
        await model.open(.people)
        #expect(model.fans.map(\.username) == ["Ann"])
    }

    @Test func goingBackReturnsToWhereTheBrowsingCameFrom() async throws {
        let model = try model()
        await model.open(.tags)
        await model.open(.library(.tagged("sea"), title: "sea"))
        #expect(model.canGoBack)
        await model.goBack()
        #expect(model.scope == .tags)
    }

    @Test func theLayoutIsRememberedPerKindOfScope() async throws {
        let model = try model()
        await model.open(.library(.all, title: "All photos"))
        model.layout = .grid
        await model.open(.ranking(.mostViewed))
        #expect(model.layout == .list)
        await model.open(.library(.tagged("sea"), title: "sea"))
        #expect(model.layout == .grid)
    }
}
