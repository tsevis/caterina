import Foundation

import CaterinaLibrary
import FlickrKit

/// Albums: reading them, and every change Organizr makes to them.
extension OrganizeModel {

    public func loadAlbums() async {
        do {
            var page = 1
            var pages = 1
            var found: [Album] = []
            repeat {
                let reply = try await flickr.albums(page: page)
                found += reply.albums
                pages = reply.pages
                page += 1
            } while page <= pages
            albums = found
        } catch {
            problem = "Could not read your albums: \(Self.message(error))"
        }
    }

    /// For showing only: the API cannot change collections.
    public func loadCollections() async {
        do {
            collections = try await flickr.collections()
        } catch {
            problem = "Could not read your collections: \(Self.message(error))"
        }
    }

    func readAlbum(_ albumID: String, generation: Int) async {
        guard let owner = accountID() else {
            problem = "Sign in to Flickr to see your albums."
            return
        }
        do {
            let ids = try await flickr.albumPhotoIDs(albumID: albumID, ownerID: owner, priority: .interactive)
            guard generation == self.generation else { return }
            albumOrder = ids
            showAlbumPhotos()
        } catch {
            guard generation == self.generation else { return }
            problem = "Could not read the album: \(Self.message(error))"
        }
    }

    func showAlbumPhotos() {
        do {
            photos = try store.photos(ids: albumOrder)
            canLoadMore = false
            selection = selection.keeping(to: photos.map(\.id))
        } catch {
            problem = "Could not read the library copy: \(Self.message(error))"
        }
    }

    // MARK: - Changes

    public func addTray(toAlbum albumID: String) async {
        let title = albums.first { $0.id == albumID }?.title ?? "album"
        await runAlbumEdits([.addPhotos(albumID: albumID, photoIDs: tray)],
                            title: "Add \(Self.count(tray.count)) to “\(title)”")
    }

    /// The tray's first photo is the cover; Flickr has no empty album.
    public func createAlbum(title: String, description: String) async {
        guard let cover = tray.first else {
            problem = "Put photos in the tray first: an album cannot be empty."
            return
        }
        await runAlbumEdits([.create(title: title, description: description, coverPhotoID: cover, photoIDs: tray)],
                            title: "Make album “\(title)”")
    }

    public func removeSelectionFromAlbum() async {
        guard let albumID = scope.albumID, !selection.isEmpty else { return }
        let ids = albumOrder.filter(selection.ids.contains)
        guard !ids.isEmpty else { return }
        await runAlbumEdits([.removePhotos(albumID: albumID, photoIDs: ids)],
                            title: "Remove \(Self.count(ids.count)) from “\(scope.title)”")
    }

    public func setCoverToSelection() async {
        guard let albumID = scope.albumID, selection.count == 1, let photo = selection.ids.first else { return }
        await runAlbumEdits([.setCover(albumID: albumID, photoID: photo)], title: "Set the cover of “\(scope.title)”")
    }

    public func movePhotos(_ moved: Set<String>, before target: String?) async {
        guard let albumID = scope.albumID else { return }
        let order = AlbumOrdering.moving(moved, before: target, in: albumOrder)
        guard order != albumOrder else { return }
        await runAlbumEdits([.reorderPhotos(albumID: albumID, photoIDs: order)], title: "Reorder “\(scope.title)”")
    }

    public func sortAlbum(by sort: AlbumOrdering.Sort) async {
        guard let albumID = scope.albumID else { return }
        let facts = Dictionary(uniqueKeysWithValues: photos.map {
            ($0.id, AlbumOrdering.LibraryPhotoFacts(taken: $0.taken, title: $0.title, views: $0.views))
        })
        let order = AlbumOrdering.sorted(albumOrder, by: sort, photos: facts)
        guard order != albumOrder else { return }
        await runAlbumEdits([.reorderPhotos(albumID: albumID, photoIDs: order)],
                            title: "Sort “\(scope.title)” by \(sort.title.lowercased())")
    }

    public func moveAlbums(from source: IndexSet, to destination: Int) async {
        var order = albums.map(\.id)
        order.move(fromOffsets: source, toOffset: destination)
        guard order != albums.map(\.id) else { return }
        await runAlbumEdits([.orderAlbums(order)], title: "Reorder albums")
    }

    public func editAlbum(_ albumID: String, title: String, description: String) async {
        await runAlbumEdits([.editMeta(albumID: albumID, title: title, description: description)],
                            title: "Rename album to “\(title)”")
    }

    public func deleteAlbum(_ albumID: String) async {
        let title = albums.first { $0.id == albumID }?.title ?? "album"
        await runAlbumEdits([.delete(albumID: albumID)], title: "Delete album “\(title)”")
        if scope.albumID == albumID, !albums.contains(where: { $0.id == albumID }) { await open(.all) }
    }

    private func runAlbumEdits(_ edits: [AlbumEdit], title: String) async {
        guard let owner = accountID() else {
            problem = "Sign in to Flickr to change your albums."
            return
        }
        guard !isBusy else {
            problem = busyMessage
            return
        }
        do {
            let batch = try store.createAlbumBatch(title: title, edits: edits, accountID: owner)
            await runBatch(batch.id)
            try filed(try store.albumEntries(in: batch.id))
        } catch {
            problem = "Could not record the album edit: \(Self.message(error))"
        }
    }

    /// Photos put in an album leave "Not in an Album" at once, when the
    /// edit that put them there went through.
    private func filed(_ entries: [AlbumEntry]) throws {
        let ids = entries.filter { $0.state == .applied }.flatMap { entry -> [String] in
            switch entry.edit {
            case let .addPhotos(_, photos), let .create(_, _, _, photos): photos
            default: []
            }
        }
        guard !ids.isEmpty else { return }
        try store.markFiled(ids)
        if scope == .notInAlbum { reloadPhotos() }
        refreshIndexes()
    }

    /// After an album batch: albums and the open album as Flickr has them.
    func afterAlbumBatch() async {
        await loadAlbums()
        if let albumID = scope.albumID { await readAlbum(albumID, generation: generation) }
    }

    static func count(_ photos: Int) -> String { "\(photos.formatted()) \(photos == 1 ? "photo" : "photos")" }
}
