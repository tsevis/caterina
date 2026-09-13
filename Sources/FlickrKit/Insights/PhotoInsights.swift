import Foundation

/// `flickr.photos.getInfo`: who, what, when, where, and how many views.
public struct PhotoInfo: Sendable, Equatable {
    public struct Owner: Sendable, Equatable {
        public let nsid: String
        public let username: String
        public let realName: String
    }

    public let id: String
    public let title: String
    public let description: String
    public let owner: Owner
    public let views: Int
    public let commentCount: Int
    public let license: License?
    /// As the photographer typed them, not Flickr's normalised form.
    public let tags: [String]
    public let posted: Date?
    public let taken: String?
    public let visibility: LibraryPhoto.Visibility
    public let location: LibraryPhoto.Location?
    /// "Orford, United Kingdom", from Flickr's reverse geocoding.
    public let place: String?
    public let pageURL: URL?
}

public struct Fave: Sendable, Equatable, Hashable {
    public let nsid: String
    public let username: String
    public let date: Date
}

public struct FavePage: Sendable, Equatable {
    public let page: Int
    public let pages: Int
    public let total: Int
    public let faves: [Fave]
}

public struct PhotoComment: Sendable, Equatable, Identifiable {
    public let id: String
    public let authorName: String
    public let date: Date
    public let text: String
}

/// The albums and group pools a photo is in.
public struct PhotoContexts: Sendable, Equatable {
    public struct Place: Sendable, Equatable, Hashable, Identifiable {
        public let id: String
        public let title: String
    }

    public let albums: [Place]
    public let groups: [Place]
}

public struct ExifField: Sendable, Equatable, Hashable {
    public let label: String
    public let value: String
}

public struct PhotoExif: Sendable, Equatable {
    public let camera: String?
    public let fields: [ExifField]
    /// The owner chose not to share camera data.
    public let isHidden: Bool

    public subscript(label: String) -> String? {
        fields.first { $0.label == label }?.value
    }

    static let hidden = PhotoExif(camera: nil, fields: [], isHidden: true)
}
