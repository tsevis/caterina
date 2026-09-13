import Foundation

/// `flickr.photos.getInfo`: who, what, when, where, and how many views.
public struct PhotoInfo: Sendable, Equatable {
    public struct Owner: Sendable, Equatable {
        public let nsid: String
        public let username: String
        public let realName: String

        public init(nsid: String, username: String, realName: String) {
            self.nsid = nsid
            self.username = username
            self.realName = realName
        }
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

    public init(id: String, title: String, description: String, owner: Owner, views: Int, commentCount: Int,
                license: License?, tags: [String], posted: Date?, taken: String?,
                visibility: LibraryPhoto.Visibility, location: LibraryPhoto.Location?, place: String?, pageURL: URL?) {
        self.id = id
        self.title = title
        self.description = description
        self.owner = owner
        self.views = views
        self.commentCount = commentCount
        self.license = license
        self.tags = tags
        self.posted = posted
        self.taken = taken
        self.visibility = visibility
        self.location = location
        self.place = place
        self.pageURL = pageURL
    }
}

public struct Fave: Sendable, Equatable, Hashable {
    public let nsid: String
    public let username: String
    public let date: Date

    public init(nsid: String, username: String, date: Date) {
        self.nsid = nsid
        self.username = username
        self.date = date
    }
}

public struct FavePage: Sendable, Equatable {
    public let page: Int
    public let pages: Int
    public let total: Int
    public let faves: [Fave]

    public init(page: Int, pages: Int, total: Int, faves: [Fave]) {
        self.page = page
        self.pages = pages
        self.total = total
        self.faves = faves
    }
}

public struct PhotoComment: Sendable, Equatable, Identifiable {
    public let id: String
    public let authorName: String
    public let date: Date
    public let text: String

    public init(id: String, authorName: String, date: Date, text: String) {
        self.id = id
        self.authorName = authorName
        self.date = date
        self.text = text
    }
}

/// The albums and group pools a photo is in.
public struct PhotoContexts: Sendable, Equatable {
    public struct Place: Sendable, Equatable, Hashable, Identifiable {
        public let id: String
        public let title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    public let albums: [Place]
    public let groups: [Place]

    public init(albums: [Place], groups: [Place]) {
        self.albums = albums
        self.groups = groups
    }
}

public struct ExifField: Sendable, Equatable, Hashable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct PhotoExif: Sendable, Equatable {
    public let camera: String?
    public let fields: [ExifField]
    /// The owner chose not to share camera data.
    public let isHidden: Bool

    public init(camera: String?, fields: [ExifField], isHidden: Bool) {
        self.camera = camera
        self.fields = fields
        self.isHidden = isHidden
    }

    public subscript(label: String) -> String? {
        fields.first { $0.label == label }?.value
    }

    static let hidden = PhotoExif(camera: nil, fields: [], isHidden: true)
}
