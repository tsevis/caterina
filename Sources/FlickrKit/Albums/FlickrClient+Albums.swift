import Foundation

extension FlickrClient {

    /// A page of your albums, in the order you arranged them on Flickr.
    public func albums(page: Int) async throws -> AlbumPage {
        guard hasToken else { throw FlickrError.permissionNeeded(.read) }
        let data = try await send([
            OAuthParameter(name: "method", value: "flickr.photosets.getList"),
            OAuthParameter(name: "page", value: String(page)),
            OAuthParameter(name: "per_page", value: "500"),
            OAuthParameter(name: "format", value: "json"),
            OAuthParameter(name: "nojsoncallback", value: "1"),
        ])
        return try AlbumResponse.page(from: data)
    }

    /// Make an album with `coverPhotoID` in it — Flickr has no empty album.
    public func createAlbum(title: String, description: String, coverPhotoID: String,
                            priority: CallPriority = .upload) async throws -> String {
        let data = try await perform(AlbumWrites.create(title: title, description: description,
                                                        coverPhotoID: coverPhotoID), priority: priority)
        return try AlbumResponse.createdID(from: data)
    }

    public func addToAlbum(photoID: String, albumID: String, priority: CallPriority = .upload) async throws {
        do {
            _ = try await perform(AlbumWrites.add(photoID: photoID, albumID: albumID), priority: priority)
        } catch FlickrError.api(code: AlbumWrites.alreadyInAlbum, _, _) {
            return
        }
    }
}

extension FlickrClient {

    /// The album as it stands, reading only what `reads` asks for.
    public func albumSnapshot(reading reads: [AlbumEdit.Read], albumID: String?, ownerID: String,
                              priority: CallPriority) async throws -> AlbumSnapshot {
        var (title, description, cover) = ("", "", "")
        var photos: [String] = []
        var order: [String] = []
        if reads.contains(.info), let albumID {
            let info = try AlbumResponse.info(from: await call("flickr.photosets.getInfo",
                                                               ["photoset_id": albumID, "user_id": ownerID],
                                                               priority: priority))
            (title, description, cover) = (info.title, info.description, info.coverPhotoID)
        }
        if reads.contains(.photos), let albumID {
            photos = try await albumPhotoIDs(albumID: albumID, ownerID: ownerID, priority: priority)
        }
        if reads.contains(.albumOrder) {
            order = try await albumOrder(priority: priority)
        }
        return AlbumSnapshot(title: title, description: description, coverPhotoID: cover,
                             photoIDs: photos, albumOrder: order)
    }

    /// Every photo id in the album, in album order.
    public func albumPhotoIDs(albumID: String, ownerID: String, priority: CallPriority) async throws -> [String] {
        var ids: [String] = []
        var page = 1
        var pages = 1
        repeat {
            let data = try await call("flickr.photosets.getPhotos",
                                      ["photoset_id": albumID, "user_id": ownerID, "page": String(page),
                                       "per_page": "500"], priority: priority)
            let reply = try AlbumResponse.photoIDs(from: data)
            ids += reply.ids
            pages = reply.pages
            page += 1
        } while page <= pages
        return ids
    }

    private func albumOrder(priority: CallPriority) async throws -> [String] {
        var ids: [String] = []
        var page = 1
        var pages = 1
        repeat {
            let data = try await call("flickr.photosets.getList", ["page": String(page), "per_page": "500"],
                                      priority: priority)
            let reply = try AlbumResponse.page(from: data)
            ids += reply.albums.map(\.id)
            pages = reply.pages
            page += 1
        } while page <= pages
        return ids
    }
}
