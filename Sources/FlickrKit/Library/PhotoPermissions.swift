import Foundation

extension LibraryPhoto {

    /// Flickr's 0 to 3 for who may comment, or add notes and tags.
    public enum Audience: Int, Sendable, Codable, CaseIterable {
        case nobody = 0, friendsAndFamily = 1, contacts = 2, everybody = 3
    }

    /// `perm_comment` and `perm_addmeta`.
    public struct Permissions: Sendable, Equatable, Hashable, Codable {
        public let comment: Audience
        public let addMeta: Audience

        public init(comment: Audience, addMeta: Audience) {
            self.comment = comment
            self.addMeta = addMeta
        }
    }

    /// Who can see where a photo was taken.
    public struct GeoPermissions: Sendable, Equatable, Hashable, Codable {
        public let isPublic: Bool
        public let isContact: Bool
        public let isFriend: Bool
        public let isFamily: Bool

        public init(isPublic: Bool, isContact: Bool, isFriend: Bool, isFamily: Bool) {
            self.isPublic = isPublic
            self.isContact = isContact
            self.isFriend = isFriend
            self.isFamily = isFamily
        }
    }
}
