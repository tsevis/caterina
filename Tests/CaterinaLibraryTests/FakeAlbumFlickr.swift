import Foundation

import FlickrKit
@testable import CaterinaLibrary

/// Flickr's albums, kept in memory and changed by the writes the runner sends.
actor FakeAlbumFlickr: AlbumService {
    struct Album: Equatable { var title: String; var description: String; var cover: String; var photos: [String] }

    private(set) var albums: [String: Album]
    private(set) var order: [String]
    private(set) var sent: [String] = []
    private var failNext: [String: FlickrError] = [:]
    private var nextID = 100

    init(_ albums: [String: Album], order: [String]? = nil) {
        self.albums = albums
        self.order = order ?? albums.keys.sorted()
    }

    /// The next call to `method` fails with `error`, once.
    func fail(_ method: String, with error: FlickrError) { failNext[method] = error }

    func albumSnapshot(reading reads: [AlbumEdit.Read], albumID: String?, ownerID: String,
                       priority: CallPriority) async throws -> AlbumSnapshot {
        let album = albumID.flatMap { albums[$0] }
        if albumID != nil, !reads.isEmpty, album == nil, reads != [.albumOrder] {
            throw FlickrError.api(code: 1, message: "Photoset not found", transient: false)
        }
        return AlbumSnapshot(title: reads.contains(.info) ? album?.title ?? "" : "",
                             description: reads.contains(.info) ? album?.description ?? "" : "",
                             coverPhotoID: reads.contains(.info) ? album?.cover ?? "" : "",
                             photoIDs: reads.contains(.photos) ? album?.photos ?? [] : [],
                             albumOrder: reads.contains(.albumOrder) ? order : [])
    }

    func createAlbum(title: String, description: String, coverPhotoID: String,
                     priority: CallPriority) async throws -> String {
        sent.append("create")
        if let error = failNext.removeValue(forKey: "create") { throw error }
        nextID += 1
        let id = "N\(nextID)"
        albums[id] = Album(title: title, description: description, cover: coverPhotoID, photos: [coverPhotoID])
        order.insert(id, at: 0)
        return id
    }

    func perform(_ write: FlickrWrite, priority: CallPriority) async throws -> Data {
        sent.append(write.method)
        if let error = failNext.removeValue(forKey: write.method) { throw error }
        let args = write.arguments
        let id = args["photoset_id"] ?? ""
        let list = (args["photo_ids"] ?? "").split(separator: ",").map(String.init)
        switch write.method {
        case "flickr.photosets.addPhoto":
            guard var album = albums[id] else { throw FlickrError.api(code: 1, message: "Photoset not found", transient: false) }
            guard let photo = args["photo_id"], !album.photos.contains(photo) else {
                throw FlickrError.api(code: 3, message: "Photo already in set", transient: false)
            }
            album.photos.append(photo)
            albums[id] = album
        case "flickr.photosets.removePhotos":
            albums[id]?.photos.removeAll { list.contains($0) }
        case "flickr.photosets.reorderPhotos":
            if let album = albums[id] {
                albums[id]?.photos = list.filter(album.photos.contains) + album.photos.filter { !list.contains($0) }
            }
        case "flickr.photosets.editMeta":
            albums[id]?.title = args["title"] ?? ""
            albums[id]?.description = args["description"] ?? ""
        case "flickr.photosets.setPrimaryPhoto":
            albums[id]?.cover = args["photo_id"] ?? ""
        case "flickr.photosets.orderSets":
            let ids = (args["photoset_ids"] ?? "").split(separator: ",").map(String.init)
            order = ids + order.filter { !ids.contains($0) }.sorted()
        case "flickr.photosets.delete":
            guard albums.removeValue(forKey: id) != nil else {
                throw FlickrError.api(code: 1, message: "Photoset not found", transient: false)
            }
            order.removeAll { $0 == id }
        default:
            break
        }
        return Data(#"{"stat":"ok"}"#.utf8)
    }
}
