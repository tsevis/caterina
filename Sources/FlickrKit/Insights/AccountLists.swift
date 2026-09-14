import Foundation

/// A list of photos somewhere on Flickr, read with the library's fields.
public enum PhotoList: Sendable, Hashable {
    case album(id: String, ownerID: String)
    /// Only `contributorID`'s photos in the pool.
    case groupPool(groupID: String, contributorID: String)
    case gallery(id: String)
    /// Photos you have faved.
    case yourFaves
    case photostream(userID: String)
    /// Photos someone is tagged in.
    case photosOf(userID: String)
    /// Photos someone is tagged in, taken by one owner.
    case photosOfIn(userID: String, ownerID: String)
    /// Flickr's Explore: today's most interesting.
    case explore
    /// Your photos in no album.
    case notInAlbum

    static let perPage = 500

    private var method: (name: String, arguments: [String: String]) {
        switch self {
        case let .album(id, owner): ("flickr.photosets.getPhotos", ["photoset_id": id, "user_id": owner])
        case let .groupPool(group, contributor): ("flickr.groups.pools.getPhotos", ["group_id": group, "user_id": contributor])
        case let .gallery(id): ("flickr.galleries.getPhotos", ["gallery_id": id])
        case .yourFaves: ("flickr.favorites.getList", [:])
        case let .photostream(user): ("flickr.people.getPhotos", ["user_id": user])
        case let .photosOf(user): ("flickr.people.getPhotosOf", ["user_id": user])
        case let .photosOfIn(user, owner): ("flickr.people.getPhotosOf", ["user_id": user, "owner_id": owner])
        case .explore: ("flickr.interestingness.getList", [:])
        case .notInAlbum: ("flickr.photos.getNotInSet", [:])
        }
    }

    /// Albums answer under `photoset`; the rest under `photos`.
    var container: String {
        if case .album = self { return "photoset" }
        return "photos"
    }

    func parameters(page: Int) -> [OAuthParameter] {
        let arguments = method.arguments.merging(
            ["page": String(page), "per_page": String(Self.perPage), "extras": LibraryQuery.extras]) { $1 }
        return [OAuthParameter(name: "method", value: method.name)]
            + arguments.keys.sorted().map { OAuthParameter(name: $0, value: arguments[$0] ?? "") }
            + [OAuthParameter(name: "format", value: "json"), OAuthParameter(name: "nojsoncallback", value: "1")]
    }
}

public struct AccountGroup: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let members: Int
    public let photos: Int
    public let isAdmin: Bool

    public init(id: String, name: String, members: Int, photos: Int, isAdmin: Bool) {
        self.id = id
        self.name = name
        self.members = members
        self.photos = photos
        self.isAdmin = isAdmin
    }
}

public struct Gallery: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let description: String
    /// Photos and videos together.
    public let itemCount: Int

    public init(id: String, title: String, description: String, itemCount: Int) {
        self.id = id
        self.title = title
        self.description = description
        self.itemCount = itemCount
    }
}

/// A collection: albums, and collections inside it.
public struct PhotoCollection: Sendable, Equatable, Hashable, Identifiable {
    public struct AlbumRef: Sendable, Equatable, Hashable, Identifiable {
        public let id: String
        public let title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    public let id: String
    public let title: String
    public let description: String
    public let albums: [AlbumRef]
    public let children: [PhotoCollection]

    public init(id: String, title: String, description: String, albums: [AlbumRef], children: [PhotoCollection]) {
        self.id = id
        self.title = title
        self.description = description
        self.albums = albums
        self.children = children
    }
}

public struct Contact: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let username: String
    public let realName: String
    public let isFriend: Bool
    public let isFamily: Bool

    public init(id: String, username: String, realName: String, isFriend: Bool, isFamily: Bool) {
        self.id = id
        self.username = username
        self.realName = realName
        self.isFriend = isFriend
        self.isFamily = isFamily
    }

    public var displayName: String { realName.isEmpty ? username : realName }
}

public struct ContactPage: Sendable, Equatable {
    public let page: Int
    public let pages: Int
    public let contacts: [Contact]

    public init(page: Int, pages: Int, contacts: [Contact]) {
        self.page = page
        self.pages = pages
        self.contacts = contacts
    }
}
