import Foundation

/// What a Flickr sign-in allows, from least to most.
///
/// **Each level includes the ones below it**, and each is a separate trip to
/// Flickr's authorisation page that issues a new token. Caterina asks for more
/// only when something the user just asked for needs it.
public enum FlickrPermission: String, Codable, CaseIterable, Comparable, Sendable {
    case read, write, delete

    public static func < (lhs: FlickrPermission, rhs: FlickrPermission) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .read: 0
        case .write: 1
        case .delete: 2
        }
    }

    /// Why Caterina is asking, in the words the approval sheet uses.
    public var reason: String {
        switch self {
        case .read:
            "Sign in to Flickr to see your own photos."
        case .write:
            "Uploading and editing need permission to change your Flickr account. Flickr will ask you to approve it."
        case .delete:
            "Deleting photos needs its own permission from Flickr. A deleted photo cannot be restored."
        }
    }
}
