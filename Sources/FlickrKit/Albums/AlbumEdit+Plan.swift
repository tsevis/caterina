import Foundation

extension AlbumEdit {

    /// The calls for this edit and its undo, given the album as it was.
    public func plan(_ before: AlbumSnapshot) throws(Refusal) -> AlbumPlan {
        switch self {
        case let .create(title, description, cover, photos):
            return try createPlan(title: title, description: description, cover: cover, photos: photos)
        case let .editMeta(album, title, description):
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw Refusal(message: "An album needs a title.")
            }
            return AlbumPlan(steps: [.write(AlbumWrites.editMeta(albumID: album, title: title, description: description))],
                             undo: [.editMeta(albumID: album, title: before.title, description: before.description)])
        case let .addPhotos(album, photos):
            let added = Self.unique(photos).filter { !before.photoIDs.contains($0) }
            return AlbumPlan(steps: added.map { .write(AlbumWrites.add(photoID: $0, albumID: album)) },
                             undo: added.isEmpty ? [] : [.removePhotos(albumID: album, photoIDs: added)])
        case let .removePhotos(album, photos):
            return try removePlan(album: album, photos: photos, before: before)
        case let .setCover(album, photo):
            guard before.photoIDs.contains(photo) else {
                throw Refusal(message: "The cover must be a photo in the album.")
            }
            return AlbumPlan(steps: [.write(AlbumWrites.setPrimary(photoID: photo, albumID: album))],
                             undo: [.setCover(albumID: album, photoID: before.coverPhotoID)])
        case let .reorderPhotos(album, photos):
            return AlbumPlan(steps: [.write(AlbumWrites.reorder(photoIDs: photos, albumID: album))],
                             undo: [.reorderPhotos(albumID: album, photoIDs: before.photoIDs)])
        case let .orderAlbums(albums):
            return AlbumPlan(steps: [.write(AlbumWrites.orderSets(albums))], undo: [.orderAlbums(before.albumOrder)])
        case let .deleteMade(album, photos):
            guard before.photoIDs.allSatisfy(Set(photos).contains) else {
                throw Refusal(message: """
                    The album now holds photos this edit did not add, so it was left alone. \
                    Delete it yourself if that is what you want.
                    """)
            }
            return AlbumPlan(steps: [.write(AlbumWrites.delete(albumID: album))], undo: [])
        case let .delete(album):
            return AlbumPlan(steps: [.write(AlbumWrites.delete(albumID: album))],
                             undo: [.create(title: before.title, description: before.description,
                                            coverPhotoID: before.coverPhotoID, photoIDs: before.photoIDs)])
        }
    }

    private func createPlan(title: String, description: String, cover: String,
                            photos: [String]) throws(Refusal) -> AlbumPlan {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Refusal(message: "An album needs a title.")
        }
        guard !cover.isEmpty else { throw Refusal(message: "An album needs at least one photo.") }
        let wanted = Self.unique(photos.contains(cover) ? photos : [cover] + photos)
        let rest = wanted.filter { $0 != cover }
        // Made with the cover, then the rest appended: reorder only when that
        // is not already the order asked for.
        let reorder: [AlbumPlan.Step] = [cover] + rest == wanted
            ? [] : [.write(AlbumWrites.reorder(photoIDs: wanted, albumID: Self.createdAlbum))]
        return AlbumPlan(steps: [.createAlbum(title: title, description: description, coverPhotoID: cover)]
                            + rest.map { .write(AlbumWrites.add(photoID: $0, albumID: Self.createdAlbum)) } + reorder,
                         undo: [.deleteMade(albumID: Self.createdAlbum, photoIDs: wanted)])
    }

    private func removePlan(album: String, photos: [String], before: AlbumSnapshot) throws(Refusal) -> AlbumPlan {
        let asked = Set(photos)
        let removing = before.photoIDs.filter { asked.contains($0) }
        guard removing.count < before.photoIDs.count else {
            throw Refusal(message: "Flickr deletes an album left empty. Delete the album instead.")
        }
        let chunks = stride(from: 0, to: removing.count, by: Self.removeChunk).map {
            Array(removing[$0..<min($0 + Self.removeChunk, removing.count)])
        }
        return AlbumPlan(steps: chunks.map { .write(AlbumWrites.remove(photoIDs: $0, albumID: album)) },
                         undo: removing.isEmpty ? [] : [.addPhotos(albumID: album, photoIDs: removing),
                                                         .reorderPhotos(albumID: album, photoIDs: before.photoIDs)])
    }

    private static func unique(_ ids: [String]) -> [String] {
        ids.reduce(into: [String]()) { list, id in if !list.contains(id) { list.append(id) } }
    }
}
