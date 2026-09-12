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
    /// `owner_name` is asked for so a download can be credited: an NSID is not
    /// a photographer's name, and without it a folder of Creative Commons
    /// photographs cannot be attributed without re-finding every one by hand.
    public static let extrasParameter: String =
        (allCases.map(\.rawValue) + ["license", "owner", "owner_name"])
            .joined(separator: ",")
}

// MARK: - A photo

public struct Photo: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let owner: String?
    /// The photographer's display name. Asked for in `extras`, because an NSID
    /// is not a credit.
    public let ownerName: String?
    public let license: License?
    /// Only the variants Flickr actually published for this photo.
    public let variants: [PhotoVariant: String]

    public init(id: String, title: String = "", owner: String? = nil,
                ownerName: String? = nil, license: License? = nil,
                variants: [PhotoVariant: String] = [:]) {
        self.id = id
        self.title = title
        self.owner = owner
        self.ownerName = ownerName
        self.license = license
        self.variants = variants
    }

    /// Where Flickr serves photographs from.
    ///
    /// Defence in depth: the scheme check already refuses `file:` and `data:`,
    /// and it takes a broken TLS connection to get a tampered reply this far.
    /// But a reply does not get to name an arbitrary host either, and the live
    /// tests download real photographs — so if Flickr ever serves from
    /// somewhere new, a test fails rather than a user's downloads silently
    /// stopping.
    public static let servingHosts = ["staticflickr.com", "flickr.com"]

    public func url(for variant: PhotoVariant) -> String? { variants[variant] }

    /// The photo's page on Flickr — where the photographer, the licence and the
    /// terms actually are.
    ///
    /// Not the bare JPEG on the CDN: a credit has to point at something a
    /// person can read, and "Open in Browser" opening an image file told nobody
    /// anything about who made it.
    public var pageURL: String? {
        guard let owner, !owner.isEmpty else { return nil }
        return "https://www.flickr.com/photos/\(owner)/\(id)"
    }

    /// Who to credit, in the order a credit would name them.
    public var photographer: String? {
        if let ownerName, !ownerName.isEmpty { return ownerName }
        if let owner, !owner.isEmpty { return owner }
        return nil
    }

    /// The URL to download for `variant`.
    ///
    /// **A fallback downgrades; it never upgrades.** The requested size is a
    /// ceiling: someone who picks Small 320 for three hundred photos is asking
    /// for a small folder, and handing them Originals because a photo has no
    /// `url_n` is gigabytes they did not ask for. Only when nothing smaller
    /// exists is a larger file better than no file at all.
    public func downloadURL(preferring variant: PhotoVariant) -> String? {
        if let exact = variants[variant] { return exact }

        guard let position = PhotoVariant.descendingBySize.firstIndex(of: variant) else {
            return nil
        }
        // Downwards from the requested size: the largest that is no larger.
        for candidate in PhotoVariant.descendingBySize[position...] {
            if let url = variants[candidate] { return url }
        }
        // Nothing smaller exists — take the smallest of what is left.
        for candidate in PhotoVariant.descendingBySize[..<position].reversed() {
            if let url = variants[candidate] { return url }
        }
        return nil
    }

    /// The smallest variant that exists.
    public func thumbnailURL() -> String? {
        for candidate in PhotoVariant.descendingBySize.reversed() {
            if let url = variants[candidate] { return url }
        }
        return nil
    }

    /// What the grid should draw.
    ///
    /// Not the *smallest* variant: that is the 75×75 square, which every photo
    /// has, so every tile in a 128pt grid was a 75px image scaled up. This asks
    /// for something the grid can show at its own size and falls back downwards
    /// only when there is nothing better.
    public func gridThumbnailURL() -> String? {
        let preferred: [PhotoVariant] = [.small320, .medium, .small, .thumbnail, .square]
        for candidate in preferred {
            if let url = variants[candidate] { return url }
        }
        return thumbnailURL()
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
                   Self.isPublishedPhotoURL(url) {
                    variants[variant] = url
                }
            }

            photo = Photo(
                id: id,
                title: Self.text(container, "title") ?? "",
                owner: Self.text(container, "owner"),
                ownerName: Self.text(container, "ownername"),
                license: Self.text(container, "license").flatMap(License.named),
                variants: variants)
        }

        /// Whether a variant URL is one worth handing to `URLSession`.
        ///
        /// **The reply does not get to name its own scheme.** Flickr publishes
        /// photographs over https; a `file:` or `data:` URL in a variant field
        /// is not a photograph, and fetching one would be trusting a network
        /// reply to choose what this process reads. It takes a broken TLS
        /// connection to get one here, which is exactly the case worth being
        /// unhelpful in.
        static func isPublishedPhotoURL(_ address: String) -> Bool {
            guard !address.isEmpty,
                  let url = URL(string: address),
                  url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased(), !host.isEmpty
            else { return false }
            return Photo.servingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
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

// MARK: - The smaller replies

extension FlickrResponse {

    /// Throw if the payload is a `stat=fail` envelope. Used before decoding, so
    /// a transient failure can be retried rather than reported as malformed.
    static func throwIfFailed(_ data: Data) throws {
        let status: StatusEnvelope
        do {
            status = try JSONDecoder().decode(StatusEnvelope.self, from: data)
        } catch {
            throw FlickrError.malformedResponse(
                "Flickr sent a reply this version cannot read.")
        }
        if let failure = status.failure { throw failure }
    }

    /// `flickr.people.findByUsername`
    public static func userID(from data: Data) throws -> String {
        try throwIfFailed(data)
        guard let envelope = try? JSONDecoder().decode(UserEnvelope.self, from: data),
              let id = envelope.user?.id, !id.isEmpty
        else { throw FlickrError.notFound("Flickr has no user by that name.") }
        return id
    }

    /// `flickr.urls.lookupGroup`
    public static func groupID(from data: Data) throws -> String {
        try throwIfFailed(data)
        guard let envelope = try? JSONDecoder().decode(GroupEnvelope.self, from: data),
              let id = envelope.group?.id, !id.isEmpty
        else { throw FlickrError.notFound("Flickr has no group at that address.") }
        return id
    }

    /// `flickr.groups.getInfo`
    public static func groupInfo(from data: Data) throws -> ResolvedGroup {
        try throwIfFailed(data)
        guard let envelope = try? JSONDecoder().decode(GroupEnvelope.self, from: data),
              let group = envelope.group, let id = group.id, !id.isEmpty
        else { throw FlickrError.notFound("Flickr has no group at that address.") }
        let name = group.name?.text ?? group.groupname?.text ?? id
        return ResolvedGroup(nsid: id, name: GroupResolver.unescapingHTML(name))
    }

    /// `flickr.groups.search`
    public static func groups(from data: Data) throws -> [GroupSummary] {
        try throwIfFailed(data)
        guard let envelope = try? JSONDecoder().decode(GroupsEnvelope.self, from: data) else {
            throw FlickrError.malformedResponse("Flickr sent an unreadable group list.")
        }
        return (envelope.groups?.group ?? []).compactMap(\.value).compactMap { entry in
            guard let nsid = entry.nsid, !nsid.isEmpty else { return nil }
            return GroupSummary(nsid: nsid, name: entry.name ?? "")
        }
    }

    /// `flickr.photos.licenses.getInfo` — id to name.
    public static func licenses(from data: Data) throws -> [String: String] {
        try throwIfFailed(data)
        guard let envelope = try? JSONDecoder().decode(LicensesEnvelope.self, from: data) else {
            throw FlickrError.malformedResponse("Flickr sent an unreadable licence list.")
        }
        let entries = (envelope.licenses?.license ?? []).compactMap(\.value)
        return Dictionary(entries.compactMap { entry -> (String, String)? in
            guard let id = entry.id?.text, let name = entry.name else { return nil }
            return (id, name)
        }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Shapes

    /// Flickr wraps some strings in `{"_content": "…"}` and sends others bare.
    struct Wrapped: Decodable {
        let text: String?
        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer() {
                if let bare = try? single.decode(String.self) {
                    text = bare
                    return
                }
                if let number = try? single.decode(Int.self) {
                    text = String(number)
                    return
                }
            }
            let keyed = try? decoder.container(keyedBy: DynamicKey.self)
            if let keyed, let key = DynamicKey(stringValue: "_content") {
                text = try? keyed.decode(String.self, forKey: key)
            } else {
                text = nil
            }
        }
    }

    struct UserEnvelope: Decodable {
        struct User: Decodable {
            let id: String?
            let nsid: String?
        }
        let user: User?
    }

    struct GroupEnvelope: Decodable {
        struct Group: Decodable {
            let id: String?
            let name: Wrapped?
            let groupname: Wrapped?
        }
        let group: Group?
    }

    struct LicensesEnvelope: Decodable {
        struct Entry: Decodable {
            /// Flickr sends the id as a number here and as a string elsewhere.
            let id: Wrapped?
            let name: String?
        }
        struct Container: Decodable {
            let license: [Lenient<Entry>]?
        }
        let licenses: Container?
    }

    struct GroupsEnvelope: Decodable {
        struct Entry: Decodable {
            let nsid: String?
            let name: String?
        }
        struct Container: Decodable {
            let group: [Lenient<Entry>]?
        }
        let groups: Container?
    }
}
