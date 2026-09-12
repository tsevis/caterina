import Foundation

// MARK: - Variants

/// The eleven sizes Flickr publishes, each named by the `extras` field that
/// carries its URL.
///
/// One enum rather than two tables: the same eleven values are the download
/// menu, the `extras` list, the fallback chain and the size buckets, and the
/// reference application kept them in four places that drifted.
public enum PhotoVariant: String, CaseIterable, Sendable, Hashable, Identifiable {
    case square = "url_sq"
    case thumbnail = "url_t"
    case small = "url_s"
    case small320 = "url_n"
    case medium = "url_m"
    case medium640 = "url_z"
    case medium800 = "url_c"
    case large = "url_l"
    case large1600 = "url_h"
    case large2048 = "url_k"
    case original = "url_o"

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .square: return "Square"
        case .thumbnail: return "Thumbnail"
        case .small: return "Small"
        case .small320: return "Small 320"
        case .medium: return "Medium"
        case .medium640: return "Medium 640"
        case .medium800: return "Medium 800"
        case .large: return "Large"
        case .large1600: return "Large 1600"
        case .large2048: return "Large 2048"
        case .original: return "Original"
        }
    }

    public var pixelDescription: String {
        switch self {
        case .square: return "75×75"
        case .thumbnail: return "~100px"
        case .small: return "240px"
        case .small320: return "320px"
        case .medium: return "500px"
        case .medium640: return "640px"
        case .medium800: return "800px"
        case .large: return "1024px"
        case .large1600: return "1600px"
        case .large2048: return "2048px"
        case .original: return "full resolution"
        }
    }

    /// Largest first, so a fallback never silently downgrades more than it must.
    public static let descendingBySize: [PhotoVariant] = [
        .original, .large2048, .large1600, .large, .medium800,
        .medium640, .medium, .small320, .small, .thumbnail, .square,
    ]

    /// The default a fresh download starts on.
    public static let defaultDownload: PhotoVariant = .large

    /// What every listing request asks Flickr to include.
    public static let extrasParameter: String =
        (allCases.map(\.rawValue) + ["license", "owner"]).joined(separator: ",")
}

// MARK: - A photo

public struct Photo: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let owner: String?
    public let license: License?
    /// Only the variants Flickr actually published for this photo.
    public let variants: [PhotoVariant: String]

    public init(id: String, title: String = "", owner: String? = nil,
                license: License? = nil, variants: [PhotoVariant: String] = [:]) {
        self.id = id
        self.title = title
        self.owner = owner
        self.license = license
        self.variants = variants
    }

    public func url(for variant: PhotoVariant) -> String? { variants[variant] }

    /// The URL to download for `variant`, falling back to the largest variant
    /// that exists when the requested one does not.
    public func downloadURL(preferring variant: PhotoVariant) -> String? {
        if let exact = variants[variant] { return exact }
        for candidate in PhotoVariant.descendingBySize {
            if let url = variants[candidate] { return url }
        }
        return nil
    }

    /// The smallest variant that exists, for the grid.
    public func thumbnailURL() -> String? {
        for candidate in PhotoVariant.descendingBySize.reversed() {
            if let url = variants[candidate] { return url }
        }
        return nil
    }
}

// MARK: - A page of photos

public struct PhotoPage: Sendable, Equatable {
    public let page: Int
    public let pages: Int
    public let perPage: Int
    public let total: Int
    public let photos: [Photo]
    /// Entries Flickr sent that could not be read. Surfaced rather than hidden:
    /// a page that quietly shrank is worse than one that says why.
    public let skippedEntries: Int

    public init(page: Int, pages: Int, perPage: Int, total: Int,
                photos: [Photo], skippedEntries: Int = 0) {
        self.page = page
        self.pages = pages
        self.perPage = perPage
        self.total = total
        self.photos = photos
        self.skippedEntries = skippedEntries
    }

    public static let empty = PhotoPage(page: 1, pages: 1, perPage: 25,
                                        total: 0, photos: [])
}

// MARK: - Reading what Flickr sent

/// Decoding Flickr's JSON without trusting any of it.
///
/// Every field is read through a container that is allowed to fail: counts
/// arrive as strings about as often as numbers, `photo` entries can be null,
/// and a variant URL has been observed as an integer. A payload whose *shape*
/// is wrong — `photos` as a list, or no `photos` at all — becomes a message,
/// never a crash.
public enum FlickrResponse {

    public static func photoPage(from data: Data) throws -> PhotoPage {
        let decoder = JSONDecoder()

        // Status first, and separately: a `stat=fail` body carries no `photos`,
        // and reading it in the same pass would report the shape problem rather
        // than the error Flickr actually sent.
        let status: StatusEnvelope
        do {
            status = try decoder.decode(StatusEnvelope.self, from: data)
        } catch {
            throw FlickrError.malformedResponse(
                "Flickr sent a reply this version cannot read.")
        }
        if let failure = status.failure { throw failure }

        let envelope: PhotosEnvelope
        do {
            envelope = try decoder.decode(PhotosEnvelope.self, from: data)
        } catch {
            throw FlickrError.malformedResponse(
                "Flickr sent a list of photos in an unexpected shape.")
        }
        guard let container = envelope.photos else {
            throw FlickrError.malformedResponse("Flickr's reply contained no photos.")
        }
        return container.decodedPage()
    }

    // MARK: Envelopes

    struct StatusEnvelope: Decodable {
        let stat: String?
        let code: LooseInt?
        let message: String?

        var failure: FlickrError? {
            guard stat?.lowercased() == "fail" else { return nil }
            let code = code?.value ?? 0
            return .api(code: code,
                        message: message ?? "Unknown Flickr error",
                        transient: FlickrError.transientCodes.contains(code))
        }
    }

    struct PhotosEnvelope: Decodable {
        let photos: PhotosContainer?
    }

    struct PhotosContainer: Decodable {
        let page: LooseInt?
        let pages: LooseInt?
        let perpage: LooseInt?
        let total: LooseInt?
        let photo: [Lenient<PhotoEntry>]?

        func decodedPage() -> PhotoPage {
            let entries = photo ?? []
            let decoded = entries.compactMap(\.value)
            return PhotoPage(
                page: max(1, page?.value ?? 1),
                pages: max(1, pages?.value ?? 1),
                perPage: max(1, perpage?.value ?? 25),
                total: max(0, total?.value ?? 0),
                photos: decoded.map(\.photo),
                skippedEntries: entries.count - decoded.count)
        }
    }

    /// One entry, which is allowed to be unreadable without costing the page.
    struct Lenient<Wrapped: Decodable>: Decodable {
        let value: Wrapped?
        init(from decoder: Decoder) throws { value = try? Wrapped(from: decoder) }
    }

    struct PhotoEntry: Decodable {
        let photo: Photo

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicKey.self)

            // An entry with no id cannot be downloaded, named or deduplicated,
            // so there is nothing useful to show for it.
            guard let id = Self.text(container, "id")?
                .trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty
            else { throw FlickrError.malformedResponse("Photo entry with no id.") }

            var variants: [PhotoVariant: String] = [:]
            for variant in PhotoVariant.allCases {
                // A variant URL must be a string. One that is not is ignored
                // rather than coerced — `42` is not a URL.
                if let key = DynamicKey(stringValue: variant.rawValue),
                   let url = try? container.decode(String.self, forKey: key),
                   !url.isEmpty {
                    variants[variant] = url
                }
            }

            photo = Photo(
                id: id,
                title: Self.text(container, "title") ?? "",
                owner: Self.text(container, "owner"),
                license: Self.text(container, "license").flatMap(License.named),
                variants: variants)
        }

        /// A field Flickr documents as a string and sometimes sends as a number.
        private static func text(_ container: KeyedDecodingContainer<DynamicKey>,
                                 _ name: String) -> String? {
            guard let key = DynamicKey(stringValue: name) else { return nil }
            if let string = try? container.decode(String.self, forKey: key) { return string }
            if let number = try? container.decode(Int.self, forKey: key) { return String(number) }
            return nil
        }
    }

    /// An integer that may arrive as a number, as a string, or as neither.
    struct LooseInt: Decodable {
        let value: Int?

        init(from decoder: Decoder) throws {
            let container = try? decoder.singleValueContainer()
            if let container {
                if let number = try? container.decode(Int.self) { value = number; return }
                if let number = try? container.decode(Double.self) { value = Int(number); return }
                if let text = try? container.decode(String.self) { value = Int(text); return }
            }
            value = nil
        }
    }

    struct DynamicKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
