import Foundation

/// One thing a batch does to each photo in it.
///
/// Pure: it turns a photo into the photo it should become. What to send
/// Flickr is worked out afterwards by `PhotoChange`, from the difference.
public enum PhotoEdit: Sendable, Equatable {
    case setTitle(String)
    case appendToTitle(String)
    case setDescription(String)
    case addTags([String])
    case removeTags([String])
    case setVisibility(LibraryPhoto.Visibility)
    case setLicense(License)
    /// For a camera whose clock was set to the wrong time zone.
    case shiftTaken(seconds: Int)
    case setLocation(LibraryPhoto.Location)
    case removeLocation

    public func applied(to photo: LibraryPhoto) -> LibraryPhoto {
        var edited = photo
        switch self {
        case let .setTitle(title): edited.title = title
        case let .appendToTitle(suffix): edited.title = photo.title + suffix
        case let .setDescription(description): edited.description = description
        case let .addTags(tags): edited.tags = Self.adding(tags, to: photo.tags)
        case let .removeTags(tags):
            let removed = Set(tags.map(Self.flickrTag))
            edited.tags = photo.tags.filter { !removed.contains($0) }
        case let .setVisibility(visibility): edited.visibility = visibility
        case let .setLicense(license): edited.license = license
        case let .shiftTaken(seconds): edited.taken = photo.taken.flatMap { TakenDate.shift($0, by: seconds) }
        case let .setLocation(location): edited.location = location
        case .removeLocation: edited.location = nil
        }
        return edited
    }

    /// A tag the way Flickr stores it: lowercase letters and digits only, so
    /// "New York" is "newyork".
    public static func flickrTag(_ tag: String) -> String {
        String(tag.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
    }

    private static func adding(_ tags: [String], to existing: [String]) -> [String] {
        tags.map(flickrTag).filter { !$0.isEmpty }.reduce(existing) { list, tag in
            list.contains(tag) ? list : list + [tag]
        }
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

    static func shift(_ taken: String, by seconds: Int) -> String? {
        guard let date = formatter.date(from: taken) else { return nil }
        return formatter.string(from: date.addingTimeInterval(TimeInterval(seconds)))
    }
}
