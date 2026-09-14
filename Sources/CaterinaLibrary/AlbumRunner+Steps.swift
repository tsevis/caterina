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
        } catch {
            // Refused, or never sent (permission, Stop): nothing was made.
            try store.clearSending(entry)
            throw error
        }
    }

    /// A write, with Flickr's "already so" replies noted so undo leaves
    /// those photos alone, unless a previous run sent this step and lost the
    /// reply: then "already so" was this batch.
    func write(_ write: FlickrWrite, for entry: AlbumEntry) async throws -> AlbumEntry {
        let resumedAfterSending = entry.isSending
        try store.markSending(entry)
        do {
            _ = try await flickr.perform(write, priority: .edit)
            return try store.recordStep(entry)
        } catch let error as FlickrError {
            guard case let .api(code, _, _) = error else {
                if !error.isTransient { try store.clearSending(entry) }
                throw error
            }
            let photos = Set((write.arguments["photo_ids"] ?? write.arguments["photo_id"] ?? "")
                .split(separator: ",").map(String.init))
            switch (write.method, code) {
            case ("flickr.photosets.addPhoto", 3):
                return try store.recordStep(entry, unchanged: resumedAfterSending ? [] : photos)
            case ("flickr.photosets.removePhotos", 2):
                return try await removeOneByOne(write, photos: photos, for: entry, resumed: resumedAfterSending)
            case ("flickr.photosets.delete", 1):
                return try store.recordStep(entry)
            default:
                try store.clearSending(entry)
                throw error
            }
        } catch {
            try store.clearSending(entry)
            throw error
        }
    }

    /// A list refused because a photo in it is not in the album: each photo
    /// is removed on its own, and those Flickr says are not there are noted.
    private func removeOneByOne(_ write: FlickrWrite, photos: Set<String>, for entry: AlbumEntry,
                                resumed: Bool) async throws -> AlbumEntry {
        let album = write.arguments["photoset_id"] ?? ""
        var absent: Set<String> = []
        for photo in photos.sorted() {
            do {
                _ = try await flickr.perform(AlbumWrites.remove(photoIDs: [photo], albumID: album), priority: .edit)
            } catch FlickrError.api(code: 2, _, _) {
                absent.insert(photo)
            }
        }
        return try store.recordStep(entry, unchanged: resumed ? [] : absent)
    }
}

/// The step recorded its own failure; move on to the next entry.
struct StepStopped: Error {}
