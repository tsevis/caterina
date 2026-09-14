import Foundation

/// One of your albums (Flickr's API calls them photosets).
public struct Album: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let description: String
    /// Photos and videos together.
    public let photoCount: Int
    public let coverPhotoID: String
    public let views: Int

    public init(id: String, title: String, description: String, photoCount: Int,
                coverPhotoID: String, views: Int) {
        self.id = id
        self.title = title
        self.description = description
        self.photoCount = photoCount
        self.coverPhotoID = coverPhotoID
        self.views = views
    }
}

public struct AlbumPage: Sendable, Equatable {
    public let page: Int
    public let pages: Int
    public let albums: [Album]

    public init(page: Int, pages: Int, albums: [Album]) {
        self.page = page
        self.pages = pages
        self.albums = albums
    }
}

/// The writes that change albums.
public enum AlbumWrites {
    /// Never repeated: a second attempt after a lost reply makes a second album.
    public static func create(title: String, description: String, coverPhotoID: String) -> FlickrWrite {
        var arguments = ["title": title, "primary_photo_id": coverPhotoID]
        if !description.isEmpty { arguments["description"] = description }
        return FlickrWrite(method: "flickr.photosets.create", arguments: arguments, repeatable: false)
    }

    /// Not retried inside one call: a retry's "already in set" would hide
    /// that this call added it. Upload treats "already in set" as done.
    public static func add(photoID: String, albumID: String) -> FlickrWrite {
        FlickrWrite(method: "flickr.photosets.addPhoto",
                    arguments: ["photoset_id": albumID, "photo_id": photoID], repeatable: false)
    }

    public static func editMeta(albumID: String, title: String, description: String) -> FlickrWrite {
        FlickrWrite(method: "flickr.photosets.editMeta",
                    arguments: ["photoset_id": albumID, "title": title, "description": description], repeatable: true)
    }

    /// Not retried inside one call, for the same reason as `add`.
    public static func remove(photoIDs: [String], albumID: String) -> FlickrWrite {
        FlickrWrite(method: "flickr.photosets.removePhotos",
                    arguments: ["photoset_id": albumID, "photo_ids": photoIDs.joined(separator: ",")], repeatable: false)
    }

    /// Photos left out keep their place after the ones listed.
    public static func reorder(photoIDs: [String], albumID: String) -> FlickrWrite {
        FlickrWrite(method: "flickr.photosets.reorderPhotos",
                    arguments: ["photoset_id": albumID, "photo_ids": photoIDs.joined(separator: ",")], repeatable: true)
    }

    /// Albums left out go to the end, ordered by id.
    public static func orderSets(_ albumIDs: [String]) -> FlickrWrite {
        FlickrWrite(method: "flickr.photosets.orderSets",
                    arguments: ["photoset_ids": albumIDs.joined(separator: ",")], repeatable: true)
    }

    public static func setPrimary(photoID: String, albumID: String) -> FlickrWrite {
        FlickrWrite(method: "flickr.photosets.setPrimaryPhoto",
                    arguments: ["photoset_id": albumID, "photo_id": photoID], repeatable: true)
    }

    /// Repeatable in effect: a second attempt finds nothing (code 1), which
    /// the runner takes as done. Needs only write permission.
    public static func delete(albumID: String) -> FlickrWrite {
        FlickrWrite(method: "flickr.photosets.delete", arguments: ["photoset_id": albumID], repeatable: true)
    }

    /// Flickr's "Photo already in set".
    static let alreadyInAlbum = 3
}

enum AlbumResponse {
    static func page(from data: Data) throws -> AlbumPage {
        struct Envelope: Decodable { let photosets: Container? }
        struct Container: Decodable {
            let page: FlickrResponse.LooseInt?
            let pages: FlickrResponse.LooseInt?
            let photoset: [FlickrResponse.Lenient<Entry>]?
        }
        struct Text: Decodable { let _content: String? }
        struct Entry: Decodable {
            let id: String
            let primary: String?
            let photos: FlickrResponse.LooseInt?
            let videos: FlickrResponse.LooseInt?
            let count_views: FlickrResponse.LooseInt?
            let title: Text?
            let description: Text?
        }
        guard let container = (try? JSONDecoder().decode(Envelope.self, from: data))?.photosets else {
            throw FlickrError.malformedResponse("Flickr sent your albums in an unexpected shape.")
        }
        let albums = (container.photoset ?? []).compactMap(\.value).map {
            Album(id: $0.id, title: $0.title?._content ?? "", description: $0.description?._content ?? "",
                  photoCount: ($0.photos?.value ?? 0) + ($0.videos?.value ?? 0),
                  coverPhotoID: $0.primary ?? "", views: $0.count_views?.value ?? 0)
        }
        return AlbumPage(page: max(1, container.page?.value ?? 1), pages: max(1, container.pages?.value ?? 1),
                         albums: albums)
    }

    struct Info { let title: String; let description: String; let coverPhotoID: String }

    static func info(from data: Data) throws -> Info {
        struct Envelope: Decodable { let photoset: Entry? }
        struct Text: Decodable { let _content: String? }
        struct Entry: Decodable { let primary: String?; let title: Text?; let description: Text? }
        try FlickrResponse.throwIfFailed(data)
        guard let entry = (try? JSONDecoder().decode(Envelope.self, from: data))?.photoset else {
            throw FlickrError.malformedResponse("Flickr sent the album's details in an unexpected shape.")
        }
        return Info(title: entry.title?._content ?? "", description: entry.description?._content ?? "",
                    coverPhotoID: entry.primary ?? "")
    }

    static func photoIDs(from data: Data) throws -> (ids: [String], pages: Int) {
        struct Envelope: Decodable { let photoset: Container? }
        struct Container: Decodable { let pages: FlickrResponse.LooseInt?; let photo: [FlickrResponse.Lenient<Entry>]? }
        struct Entry: Decodable { let id: String }
        try FlickrResponse.throwIfFailed(data)
        guard let container = (try? JSONDecoder().decode(Envelope.self, from: data))?.photoset else {
            throw FlickrError.malformedResponse("Flickr sent the album's photos in an unexpected shape.")
        }
        return ((container.photo ?? []).compactMap(\.value).map(\.id), max(1, container.pages?.value ?? 1))
    }

    static func createdID(from data: Data) throws -> String {
        struct Envelope: Decodable { let photoset: Created? }
        struct Created: Decodable { let id: String }
        guard let id = (try? JSONDecoder().decode(Envelope.self, from: data))?.photoset?.id, !id.isEmpty else {
            throw FlickrError.malformedResponse("Flickr made the album but did not say which it was.")
        }
        return id
    }
}
