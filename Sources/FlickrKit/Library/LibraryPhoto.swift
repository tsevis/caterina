import Foundation

/// One of your own photos, with everything the app sorts, filters and edits.
///
/// Distinct from `Photo`, which is a search result someone may download: this
/// is a record of your library, kept locally and changed by Organize.
public struct LibraryPhoto: Sendable, Equatable, Hashable, Identifiable, Codable {

    public struct Visibility: Sendable, Equatable, Hashable, Codable {
        public let isPublic: Bool
        public let isFriend: Bool
        public let isFamily: Bool

        public init(isPublic: Bool, isFriend: Bool, isFamily: Bool) {
            self.isPublic = isPublic
            self.isFriend = isFriend
            self.isFamily = isFamily
        }
    }

    public struct Location: Sendable, Equatable, Hashable, Codable {
        public let latitude: Double
        public let longitude: Double
        /// Flickr's 1 (world) to 16 (street).
        public let accuracy: Int

        public init(latitude: Double, longitude: Double, accuracy: Int) {
            self.latitude = latitude
            self.longitude = longitude
            self.accuracy = accuracy
        }
    }

    public enum Media: String, Sendable, Codable {
        case photo, video
    }

    public let id: String
    public internal(set) var title: String
    public internal(set) var description: String
    public internal(set) var tags: [String]
    public internal(set) var license: License?
    public internal(set) var visibility: Visibility
    public internal(set) var uploaded: Date?
    public internal(set) var lastUpdated: Date?
    /// As Flickr gives it, `yyyy-MM-dd HH:mm:ss` in the camera's own time with
    /// no zone. Kept as text: it sorts correctly, and turning it into a `Date`
    /// would invent a time zone the camera never recorded.
    public internal(set) var taken: String?
    public internal(set) var views: Int
    public internal(set) var media: Media
    public internal(set) var location: Location?
    public internal(set) var thumbnailURL: String?

    public init(id: String, title: String = "", description: String = "", tags: [String] = [],
                license: License? = nil,
                visibility: Visibility = Visibility(isPublic: true, isFriend: false, isFamily: false),
                uploaded: Date? = nil, lastUpdated: Date? = nil, taken: String? = nil,
                views: Int = 0, media: Media = .photo, location: Location? = nil,
                thumbnailURL: String? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.tags = tags
        self.license = license
        self.visibility = visibility
        self.uploaded = uploaded
        self.lastUpdated = lastUpdated
        self.taken = taken
        self.views = views
        self.media = media
        self.location = location
        self.thumbnailURL = thumbnailURL
    }
}

public struct LibraryPage: Sendable, Equatable {
    public let page: Int
    public let pages: Int
    public let total: Int
    public let photos: [LibraryPhoto]
    public let skippedEntries: Int

    public init(page: Int, pages: Int, total: Int, photos: [LibraryPhoto], skippedEntries: Int) {
        self.page = page
        self.pages = pages
        self.total = total
        self.photos = photos
        self.skippedEntries = skippedEntries
    }
}
