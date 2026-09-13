import Foundation

extension FlickrClient {

    public func photoInfo(id: String) async throws -> PhotoInfo {
        try InsightsResponse.info(from: await call("flickr.photos.getInfo", ["photo_id": id]))
    }

    /// Flickr's largest page of faves is 50.
    public func favorites(photoID: String, page: Int) async throws -> FavePage {
        try await favorites(photoID: photoID, page: page, priority: .interactive)
    }

    public func favorites(photoID: String, page: Int, priority: CallPriority) async throws -> FavePage {
        try InsightsResponse.favorites(from: await call("flickr.photos.getFavorites",
                                                        ["photo_id": photoID, "page": String(page), "per_page": "50"],
                                                        priority: priority))
    }

    public func comments(photoID: String) async throws -> [PhotoComment] {
        try InsightsResponse.comments(from: await call("flickr.photos.comments.getList", ["photo_id": photoID]))
    }

    public func contexts(photoID: String) async throws -> PhotoContexts {
        try InsightsResponse.contexts(from: await call("flickr.photos.getAllContexts", ["photo_id": photoID]))
    }

    /// Camera data, or `PhotoExif.hidden` when the owner does not share it.
    public func exif(photoID: String) async throws -> PhotoExif {
        do {
            return try InsightsResponse.exif(from: await call("flickr.photos.getExif", ["photo_id": photoID]))
        } catch FlickrError.api(code: Self.exifPermissionDenied, _, _) {
            return .hidden
        }
    }

    /// Flickr's "Permission denied" for camera data the owner has hidden.
    static let exifPermissionDenied = 2

    /// A read, signed when signed in so private photos of your own are visible.
    func call(_ method: String, _ arguments: [String: String],
              priority: CallPriority = .interactive) async throws -> Data {
        try await send([OAuthParameter(name: "method", value: method)]
            + arguments.keys.sorted().map { OAuthParameter(name: $0, value: arguments[$0] ?? "") }
            + [OAuthParameter(name: "format", value: "json"), OAuthParameter(name: "nojsoncallback", value: "1")],
            priority: priority)
    }
}
