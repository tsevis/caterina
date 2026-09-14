import Foundation
import Observation

import CaterinaLibrary
import FlickrKit

/// Every photo id in an album, in album order.
public protocol AlbumContents: Sendable {
    func albumPhotoIDs(albumID: String, ownerID: String, priority: CallPriority) async throws -> [String]
}

extension FlickrClient: AlbumContents {}

/// Flickr, as Organize needs it.
public typealias OrganizeFlickr = PhotoWriter & LivePhotoReader & PhotoListSource & AlbumService & AlbumLister
    & AlbumContents & GroupPoolWriter

/// The Organize tab: find photos, gather them in a tray, change them in a
/// batch, and take the batch back.
@MainActor
@Observable
public final class OrganizeModel {

    public enum RunPhase: Sendable, Equatable {
        case idle
        case running(batchID: String, summary: EditBatch.Summary)
        case needsPermission(FlickrPermission, batchID: String)
        /// Flickr unreachable or busy; the rest is still pending.
        case paused(batchID: String, message: String)
    }

    nonisolated static let pageSize = 600

    // MARK: Finding

    public private(set) var scope: OrganizeScope = .all
    public internal(set) var photos: [LibraryPhoto] = []
    public internal(set) var canLoadMore = false
    public private(set) var isReadingNotInAlbum = false
    public private(set) var notInAlbumReadAt: Date?
    public private(set) var tags: [TagCount] = []
    public private(set) var months: [MonthCount] = []
    public private(set) var counts: [OrganizeScope: Int] = [:]
    public internal(set) var problem: String?
    public internal(set) var albums: [Album] = []
    /// The open album's photo ids, in album order.
    var albumOrder: [String] = []

    // MARK: Choosing

    public internal(set) var selection = GridSelection()
    /// Photo ids, in the order they went in. Kept across views.
    public private(set) var tray: [String] = []
    public private(set) var trayPhotos: [LibraryPhoto] = []

    // MARK: Changing

    public internal(set) var run: RunPhase = .idle
    public internal(set) var activity: [BatchActivity] = []

    let store: LibraryStore
    let flickr: any OrganizeFlickr
    let budget: CallBudget
    let accountID: @Sendable () -> String?
    var runTask: Task<Void, Never>?
    /// Bumped by every change of view; a reply for an older one is dropped.
    var generation = 0

    public init(store: LibraryStore, flickr: any OrganizeFlickr, budget: CallBudget = .standard,
                accountID: @escaping @Sendable () -> String? = { nil }) {
        self.store = store
        self.flickr = flickr
        self.budget = budget
        self.accountID = accountID
        do {
            notInAlbumReadAt = try store.notInAlbumReadAt()
        } catch {
            problem = "Could not read the library copy: \(Self.message(error))"
        }
        reloadPhotos()
        refreshIndexes()
        refreshActivity()
    }

    // MARK: - Views

    public func open(_ scope: OrganizeScope) async {
        generation += 1
        let generation = self.generation
        self.scope = scope
        selection = GridSelection()
        problem = nil
        albumOrder = []
        reloadPhotos()
        if let albumID = scope.albumID {
            await readAlbum(albumID, generation: generation)
        }
        if scope == .notInAlbum, notInAlbumReadAt == nil {
            await readNotInAlbum(generation: generation)
        }
    }

    /// Read which photos are in no album again, from Flickr.
    public func refreshNotInAlbum() async {
        await readNotInAlbum(generation: generation)
    }

    public func loadMore() {
        guard !isRunning else { return }
        do {
            let more = try store.photos(scope.filter, order: scope.order, limit: Self.pageSize, offset: photos.count)
            photos += more
            canLoadMore = more.count == Self.pageSize
        } catch {
            problem = "Could not read the library copy: \(Self.message(error))"
        }
    }

    public func count(of scope: OrganizeScope) -> Int? { counts[scope] }

    /// The library copy changed underneath: a sync finished.
    public func libraryChanged() {
        reloadPhotos()
        refreshTray()
        refreshIndexes()
    }

    private func readNotInAlbum(generation: Int) async {
        guard !isReadingNotInAlbum else { return }
        isReadingNotInAlbum = true
        defer { isReadingNotInAlbum = false }
        do {
            _ = try await NotInAlbumIndex(source: flickr, store: store).refresh()
            notInAlbumReadAt = try store.notInAlbumReadAt()
            refreshIndexes()
            // Whichever open of the view is current, it wants this answer.
            if scope == .notInAlbum { reloadPhotos() }
        } catch {
            guard generation == self.generation else { return }
            problem = "Could not read which photos are in no album: \(Self.message(error))"
        }
    }

    /// As many photos as were showing, so a batch or sync does not throw
    /// away what Load More brought in.
    func reloadPhotos() {
        let shown = max(Self.pageSize, photos.count)
        if scope.albumID != nil {
            showAlbumPhotos()
            return
        }
        do {
            photos = try store.photos(scope.filter, order: scope.order, limit: shown, offset: 0)
            canLoadMore = photos.count == shown
            selection = selection.keeping(to: photos.map(\.id))
        } catch {
            photos = []
            problem = "Could not read the library copy: \(Self.message(error))"
        }
    }

    func refreshIndexes() {
        do {
            tags = try store.tagCounts()
            months = try store.monthCounts()
            let views = OrganizeScope.smartViews + Audience.allCases.map(OrganizeScope.audience)
                + License.allCases.map(OrganizeScope.licence)
            counts = Dictionary(uniqueKeysWithValues: try views.map { ($0, try store.count($0.filter)) })
        } catch {
            problem = "Could not count the library copy: \(Self.message(error))"
        }
    }

    // MARK: - Selection

    public func click(_ id: String, modifiers: ClickModifiers) {
        selection = selection.clicking(id, modifiers: modifiers, in: photos.map(\.id))
    }

    public func sweep(_ covered: Set<String>) {
        selection = selection.sweeping(covered, in: photos.map(\.id))
    }

    public func move(by offset: Int) {
        selection = selection.moving(by: offset, in: photos.map(\.id))
    }

    public func selectAll() { selection = selection.selectingAll(in: photos.map(\.id)) }
    public func clearSelection() { selection = selection.clearing() }

    // MARK: - Tray

    /// The selection, in grid order, after whatever is already in the tray.
    public func addSelectionToTray() {
        let known = Set(tray)
        tray += photos.map(\.id).filter { selection.ids.contains($0) && !known.contains($0) }
        refreshTray()
    }

    public func removeFromTray(_ ids: Set<String>) {
        tray = tray.filter { !ids.contains($0) }
        refreshTray()
    }

    public func clearTray() {
        tray = []
        refreshTray()
    }

    func refreshTray() {
        let found: [LibraryPhoto]
        do {
            found = try store.photos(ids: tray)
        } catch {
            // Keep the tray: an unreadable copy is not a reason to empty it.
            problem = "Could not read the tray's photos: \(Self.message(error))"
            return
        }
        let byID = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
        // A photo gone from the library copy leaves the tray with it.
        tray = tray.filter { byID[$0] != nil }
        trayPhotos = tray.compactMap { byID[$0] }
    }

    nonisolated static func message(_ error: Error) -> String {
        (error as? FlickrError)?.message ?? error.localizedDescription
    }
}
