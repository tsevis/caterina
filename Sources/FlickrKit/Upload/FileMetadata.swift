import Foundation
import ImageIO

/// What a photo file says about itself: IPTC title, caption and keywords,
/// EXIF date taken, and GPS.
public struct FileMetadata: Sendable, Equatable {
    public let file: URL
    public let title: String?
    public let description: String?
    public let keywords: [String]
    /// In Flickr's `yyyy-MM-dd HH:mm:ss`, no zone, as the camera recorded it.
    public let taken: String?
    public let location: LibraryPhoto.Location?

    public init(file: URL, title: String?, description: String?, keywords: [String],
                taken: String?, location: LibraryPhoto.Location?) {
        self.file = file
        self.title = title
        self.description = description
        self.keywords = keywords
        self.taken = taken
        self.location = location
    }

    /// What Flickr would call the photo if nothing else did: its filename.
    public var suggestedTitle: String {
        title ?? file.deletingPathExtension().lastPathComponent
    }

    /// Reads without decoding the image. A file ImageIO cannot open reads as
    /// nothing, rather than failing the whole batch it is part of.
    public static func read(_ file: URL) -> FileMetadata {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return FileMetadata(file: file, title: nil, description: nil, keywords: [], taken: nil, location: nil)
        }
        let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        return FileMetadata(
            file: file,
            title: nonEmpty(iptc[kCGImagePropertyIPTCObjectName]),
            description: nonEmpty(iptc[kCGImagePropertyIPTCCaptionAbstract]),
            keywords: (iptc[kCGImagePropertyIPTCKeywords] as? [String] ?? [])
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            taken: nonEmpty(exif[kCGImagePropertyExifDateTimeOriginal]).flatMap(flickrDate),
            location: location(gps))
    }

    /// The upload this file makes under `preset`: the file's own words win,
    /// the preset fills what the file left blank, and tags are both.
    public func uploadMetadata(adding preset: UploadMetadata) -> UploadMetadata {
        UploadMetadata(title: title ?? preset.title,
                       description: description ?? preset.description,
                       tags: Self.merged(keywords, preset.tags),
                       visibility: preset.visibility, safety: preset.safety,
                       contentType: preset.contentType, hiddenFromSearch: preset.hiddenFromSearch)
    }

    private static func merged(_ first: [String], _ second: [String]) -> [String] {
        (first + second).reduce(into: [String]()) { list, tag in
            if !list.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { list.append(tag) }
        }
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    /// EXIF writes `2024:06:01 21:14:05`; Flickr wants dashes in the date.
    private static func flickrDate(_ exif: String) -> String? {
        let parts = exif.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let date = parts[0].replacingOccurrences(of: ":", with: "-")
        guard date.count == 10 else { return nil }
        return "\(date) \(parts[1])"
    }

    private static func location(_ gps: [CFString: Any]) -> LibraryPhoto.Location? {
        guard let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
              let longitude = gps[kCGImagePropertyGPSLongitude] as? Double else { return nil }
        let south = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() == "S"
        let west = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() == "W"
        // A camera's GPS fix is street level: Flickr's most precise accuracy.
        return LibraryPhoto.Location(latitude: south ? -latitude : latitude,
                                     longitude: west ? -longitude : longitude, accuracy: 16)
    }
}
