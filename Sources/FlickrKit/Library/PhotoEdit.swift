import Foundation

/// One thing a batch does to each photo in it.
///
/// Pure: it turns a photo into the photo it should become. What to send
/// Flickr is worked out afterwards by `PhotoChange`, from the difference.
public enum PhotoEdit: Sendable, Equatable {

    /// Where a photo stands in its batch, for `{n}` and `{count}`.
    public struct Context: Sendable, Equatable {
        /// From 1.
        public let position: Int
        public let count: Int

        public init(position: Int, count: Int) {
            self.position = position
            self.count = count
        }

        public static let single = Context(position: 1, count: 1)
    }

    /// Title and description text is a `TitlePattern`.
    case setTitle(String)
    case appendToTitle(String)
    case setDescription(String)
    case appendToDescription(String)
    case addTags([String])
    case removeTags([String])
    /// One tag respelled or renamed, wherever it is.
    case renameTag(from: String, to: String)
    /// These tags in place of the ones the photo had when the batch was made.
    /// Tags added on flickr.com since the last sync are kept: a batch is laid
    /// over Flickr's copy as additions and removals (`PhotoChange.rebased`).
    case replaceTags([String])
    case setVisibility(LibraryPhoto.Visibility)
    case setLicense(License)
    /// For a camera whose clock was set to the wrong time zone.
    case shiftTaken(seconds: Int)
    /// `yyyy-MM-dd HH:mm:ss`; check with `isValidTaken` first.
    case setTaken(String)
    case setLocation(LibraryPhoto.Location)
    case removeLocation
    case setPermissions(LibraryPhoto.Permissions)
    case setSafety(UploadMetadata.Safety)
    case setContentType(UploadMetadata.ContentType)
    case setHiddenFromSearch(Bool)
    case setGeoPermissions(LibraryPhoto.GeoPermissions)
    /// The date it shows as uploaded.
    case shiftPosted(seconds: Int)
    case setPosted(Date)

    public func applied(to photo: LibraryPhoto, context: Context = .single) -> LibraryPhoto {
        var edited = photo
        let render = { (pattern: String) in TitlePattern.render(pattern, photo: photo, context: context) }
        switch self {
        case let .setTitle(title): edited.title = render(title)
        case let .appendToTitle(suffix): edited.title = photo.title + render(suffix)
        case let .setDescription(description): edited.description = render(description)
        case let .appendToDescription(suffix): edited.description = photo.description + render(suffix)
        case let .addTags(tags): edited.tags = TagList.adding(tags, to: photo.tags)
        case let .removeTags(tags): edited.tags = TagList.removing(tags, from: photo.tags)
        case let .renameTag(tag, replacement): edited.tags = TagList.renaming(tag, to: replacement, in: photo.tags)
        case let .replaceTags(tags): edited.tags = TagList.replacing(with: tags)
        case let .setVisibility(visibility): edited.visibility = visibility
        case let .setLicense(license): edited.license = license
        case let .shiftTaken(seconds): edited.taken = photo.taken.flatMap { TakenDate.shift($0, by: seconds) }
        case let .setTaken(taken): edited.taken = TakenDate.isValid(taken) ? taken : photo.taken
        case let .setLocation(location): edited.location = location
        case .removeLocation: edited.location = nil
        case let .setPermissions(permissions): edited.permissions = permissions
        case let .setSafety(safety): edited.safety = safety
        case let .setContentType(contentType): edited.contentType = contentType
        case let .setHiddenFromSearch(hidden): edited.hiddenFromSearch = hidden
        case let .setGeoPermissions(permissions): edited.geoPermissions = permissions
        case let .shiftPosted(seconds): edited.uploaded = photo.uploaded?.addingTimeInterval(TimeInterval(seconds))
        case let .setPosted(date): edited.uploaded = date
        }
        return edited
    }

    /// Whether `taken` is a date Flickr takes: `yyyy-MM-dd HH:mm:ss`.
    public static func isValidTaken(_ taken: String) -> Bool { TakenDate.isValid(taken) }

    /// A tag the way Flickr stores it: lowercase letters and digits only, so
    /// "New York" is "newyork". A machine tag (`namespace:predicate=value`)
    /// keeps its structure, lowercased.
    public static func flickrTag(_ tag: String) -> String {
        let lowered = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowered.wholeMatch(of: /[a-z_][a-z0-9_]*:[a-z_][a-z0-9_]*=.+/) != nil { return lowered }
        return String(lowered.unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
    }
}

/// Flickr's date taken: `yyyy-MM-dd HH:mm:ss`, in no time zone.
enum TakenDate {
    /// The arithmetic is done in GMT only because GMT has no daylight saving
    /// to skip or repeat an hour; the text never gains a zone.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func isValid(_ taken: String) -> Bool {
        formatter.date(from: taken).map { formatter.string(from: $0) == taken } ?? false
    }

    static func shift(_ taken: String, by seconds: Int) -> String? {
        guard let date = formatter.date(from: taken) else { return nil }
        return formatter.string(from: date.addingTimeInterval(TimeInterval(seconds)))
    }
}
