import Foundation

import FlickrKit

extension AlbumRunner {

    static let mayHaveMadeAlbum = """
        Caterina stopped while making this album, so it may have been made. Look on flickr.com before trying again.
        """

    /// Make the album, never twice: a create found already sent fails.
    func create(title: String, description: String, cover: String, for entry: AlbumEntry) async throws -> AlbumEntry {
        guard !entry.isSending else {
            try store.recordAlbum(entry, as: .failed, message: Self.mayHaveMadeAlbum)
            throw StepStopped()
        }
        try store.markSending(entry)
        do {
            let id = try await flickr.createAlbum(title: title, description: description, coverPhotoID: cover, priority: .edit)
            return try store.recordStep(entry, createdAlbumID: id)
        } catch let error as FlickrError where error.isTransient {
            try store.recordAlbum(entry, as: .failed, message: Self.mayHaveMadeAlbum)
            throw error
        }
    }

    /// A write, with Flickr's "already so" replies noted so undo leaves
    /// those photos alone.
    func write(_ write: FlickrWrite, for entry: AlbumEntry) async throws -> AlbumEntry {
        do {
            _ = try await flickr.perform(write, priority: .edit)
            return try store.recordStep(entry)
        } catch let error as FlickrError {
            guard case let .api(code, _, _) = error else { throw error }
            let photos = Set((write.arguments["photo_ids"] ?? write.arguments["photo_id"] ?? "")
                .split(separator: ",").map(String.init))
            switch (write.method, code) {
            case ("flickr.photosets.addPhoto", 3):
                return try store.recordStep(entry, unchanged: photos)
            case ("flickr.photosets.removePhotos", 2):
                return try await removeWhatIsLeft(write, photos: photos, for: entry)
            case ("flickr.photosets.delete", 1):
                return try store.recordStep(entry)
            default:
                throw error
            }
        }
    }

    /// A list refused because one photo had already gone: read the album and
    /// remove the ones still there.
    private func removeWhatIsLeft(_ write: FlickrWrite, photos: Set<String>, for entry: AlbumEntry) async throws -> AlbumEntry {
        let album = write.arguments["photoset_id"] ?? ""
        let current = Set(try await flickr.albumSnapshot(reading: [.photos], albumID: album, ownerID: ownerID,
                                                         priority: .edit).photoIDs)
        let left = photos.intersection(current)
        if !left.isEmpty, left != photos {
            _ = try await flickr.perform(AlbumWrites.remove(photoIDs: left.sorted(), albumID: album), priority: .edit)
        }
        return try store.recordStep(entry, unchanged: photos.subtracting(left))
    }
}

/// The step recorded its own failure; move on to the next entry.
struct StepStopped: Error {}
