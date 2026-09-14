import Foundation

/// A change to a photo that is not one of its fields: rotating, tagging a
/// person, deleting. Each carries its own undo, or says it has none.
public enum PhotoAction: Sendable, Equatable, Hashable, Codable {
    /// Clockwise: 90, 180 or 270.
    case rotate(degrees: Int)
    case addPerson(userID: String)
    case removePerson(userID: String)
    /// Cannot be undone, and needs Flickr's separate delete permission.
    case delete
    /// Someone else's photo, in one of your galleries.
    case addToGallery(galleryID: String, comment: String)
    case removeFromGallery(galleryID: String)

    /// A turn by any whole number of right angles; nil for none or an odd angle.
    public static func rotation(degrees: Int) -> PhotoAction? {
        let turn = ((degrees % 360) + 360) % 360
        return [90, 180, 270].contains(turn) ? .rotate(degrees: turn) : nil
    }

    public func write(photoID: String) -> FlickrWrite {
        switch self {
        case let .rotate(degrees):
            // Rotating twice turns twice: never repeated after a lost reply.
            FlickrWrite(method: "flickr.photos.transform.rotate",
                        arguments: ["photo_id": photoID, "degrees": String(degrees)], repeatable: false)
        case let .addPerson(user):
            FlickrWrite(method: "flickr.photos.people.add", arguments: ["photo_id": photoID, "user_id": user],
                        repeatable: true)
        case let .removePerson(user):
            FlickrWrite(method: "flickr.photos.people.delete", arguments: ["photo_id": photoID, "user_id": user],
                        repeatable: true)
        case .delete:
            FlickrWrite(method: "flickr.photos.delete", arguments: ["photo_id": photoID], repeatable: true,
                        permission: .delete)
        case let .addToGallery(gallery, comment):
            // Never repeated after a lost reply.
            FlickrWrite(method: "flickr.galleries.addPhoto",
                        arguments: ["photo_id": photoID, "gallery_id": gallery]
                            .merging(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [:] : ["comment": comment]) { $1 },
                        repeatable: false)
        case let .removeFromGallery(gallery):
            // Flickr lists full_response as required.
            FlickrWrite(method: "flickr.galleries.removePhoto",
                        arguments: ["photo_id": photoID, "gallery_id": gallery, "full_response": "0"], repeatable: true)
        }
    }

    public var undo: PhotoAction? {
        switch self {
        case let .rotate(degrees): .rotate(degrees: 360 - degrees)
        case let .addPerson(user): .removePerson(userID: user)
        case let .removePerson(user): .addPerson(userID: user)
        case .delete: nil
        case let .addToGallery(gallery, _): .removeFromGallery(galleryID: gallery)
        case let .removeFromGallery(gallery): .addToGallery(galleryID: gallery, comment: "")
        }
    }
}
