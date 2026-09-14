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
        }
    }

    public var undo: PhotoAction? {
        switch self {
        case let .rotate(degrees): .rotate(degrees: 360 - degrees)
        case let .addPerson(user): .removePerson(userID: user)
        case let .removePerson(user): .addPerson(userID: user)
        case .delete: nil
        }
    }
}
