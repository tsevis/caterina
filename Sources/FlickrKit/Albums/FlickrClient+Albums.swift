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
