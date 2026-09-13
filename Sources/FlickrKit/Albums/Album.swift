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
}

/// The writes that change albums.
public enum AlbumWrites {
    /// Never repeated: a second attempt after a lost reply makes a second album.
    public static func create(title: String, description: String, coverPhotoID: String) -> FlickrWrite {
        var arguments = ["title": title, "primary_photo_id": coverPhotoID]
        if !description.isEmpty { arguments["description"] = description }
        return FlickrWrite(method: "flickr.photosets.create", arguments: arguments, repeatable: false)
    }

    public static func add(photoID: String, albumID: String) -> FlickrWrite {
        FlickrWrite(method: "flickr.photosets.addPhoto",
                    arguments: ["photoset_id": albumID, "photo_id": photoID], repeatable: true)
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

    static func createdID(from data: Data) throws -> String {
        struct Envelope: Decodable { let photoset: Created? }
        struct Created: Decodable { let id: String }
        guard let id = (try? JSONDecoder().decode(Envelope.self, from: data))?.photoset?.id, !id.isEmpty else {
            throw FlickrError.malformedResponse("Flickr made the album but did not say which it was.")
        }
        return id
    }
}
