import Foundation
import Observation

import CaterinaLibrary
import FlickrKit

/// What the account's structures are read from. `FlickrClient` in the app.
public protocol AccountDirectorySource: Sendable {
    func albums(page: Int) async throws -> AlbumPage
    func groups(of userID: String) async throws -> [AccountGroup]
    func galleries() async throws -> [Gallery]
    func collections() async throws -> [PhotoCollection]
    func contacts(page: Int) async throws -> ContactPage
    func photoList(_ list: PhotoList, page: Int) async throws -> LibraryPage
}

extension FlickrClient: AccountDirectorySource {}

/// Albums, collections, galleries, groups and contacts, each read once and
/// kept until refreshed.
@MainActor
@Observable
public final class AccountDirectory {
    public private(set) var albums: [Album] = []
    public private(set) var collections: [PhotoCollection] = []
    public private(set) var galleries: [Gallery] = []
    public private(set) var groups: [AccountGroup] = []
    public private(set) var contacts: [Contact] = []
    public private(set) var problem: String?

    private var loaded: Set<BrowseScope> = []
    private let source: AccountDirectorySource
    private let accountID: @Sendable () -> String?

    init(source: AccountDirectorySource, accountID: @escaping @Sendable () -> String?) {
        self.source = source
        self.accountID = accountID
    }

    func reset() {
        albums = []
        collections = []
        galleries = []
        groups = []
        contacts = []
        problem = nil
        loaded = []
    }

    /// Read what `scope` lists, unless already read. `refresh` reads again.
    func load(_ scope: BrowseScope, refresh: Bool = false) async {
        guard refresh || !loaded.contains(scope) else { return }
        problem = nil
        do {
            switch scope {
            case .albums: albums = try await allPages { try await self.source.albums(page: $0) }
            case .collections: collections = try await source.collections()
            case .galleries: galleries = try await source.galleries()
            case .groups:
                guard let id = accountID() else {
                    problem = "Sign in to Flickr to see your groups."
                    return
                }
                groups = try await source.groups(of: id).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            case .people: contacts = try await allContacts()
            default: return
            }
            loaded.insert(scope)
        } catch {
            problem = (error as? FlickrError)?.message ?? error.localizedDescription
        }
    }

    private func allPages(_ read: @escaping (Int) async throws -> AlbumPage) async throws -> [Album] {
        let first = try await read(1)
        var albums = first.albums
        for page in stride(from: 2, through: first.pages, by: 1) { albums += try await read(page).albums }
        return albums
    }

    private func allContacts() async throws -> [Contact] {
        let first = try await source.contacts(page: 1)
        var contacts = first.contacts
        for page in stride(from: 2, through: first.pages, by: 1) { contacts += try await source.contacts(page: page).contacts }
        return contacts
    }
}
