import Foundation

// MARK: - Size

/// How big a photo is, derived from the variants Flickr published for it.
///
/// **Flickr never upscales**, so the presence of a variant is a reliable lower
/// bound on the photo's longest edge. The defect this replaces asked whether a
/// *small* variant existed — which is true of every photo, because every photo
/// has a square thumbnail — and so classified everything as small.
public enum SizeBucket: String, CaseIterable, Sendable, Identifiable, Hashable {
    case small = "S"
    case medium = "M"
    case large = "L"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        // The boundaries are the variants, not round numbers: `url_l` is a
        // 1024px longest edge and lives in the Large bucket, so a Medium label
        // reading "up to 1024" described a photo it had put in the other one.
        case .small: return "Small (up to 500px)"
        case .medium: return "Medium (501 – 1023px)"
        case .large: return "Large (1024px and above)"
        }
    }

    var variants: [PhotoVariant] {
        switch self {
        case .large: return [.original, .large2048, .large1600, .large]
        case .medium: return [.medium800, .medium640, .medium]
        case .small: return [.small320, .small, .thumbnail, .square]
        }
    }

    /// Largest bucket first, so the answer is the biggest variant on offer.
    public static func of(_ photo: Photo) -> SizeBucket? {
        for bucket in [SizeBucket.large, .medium, .small]
        where bucket.variants.contains(where: { photo.url(for: $0) != nil }) {
            return bucket
        }
        return nil
    }
}

// MARK: - Sort

/// The sort values `flickr.photos.search` accepts, and nothing else.
///
/// **Flickr answers `stat=ok` for a sort value it does not recognise.** A typo
/// is therefore invisible in the response: the results come back in the default
/// order and nothing says so. The only defence is that no other value can be
/// expressed, which is what this enum is for. There is no size or licence sort.
public enum SortOrder: String, CaseIterable, Sendable, Identifiable, Hashable {
    case relevance = "relevance"
    case datePostedAscending = "date-posted-asc"
    case datePostedDescending = "date-posted-desc"
    case dateTakenAscending = "date-taken-asc"
    case dateTakenDescending = "date-taken-desc"
    case interestingnessAscending = "interestingness-asc"
    case interestingnessDescending = "interestingness-desc"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .relevance: return "Relevance"
        case .datePostedAscending: return "Oldest first"
        case .datePostedDescending: return "Date posted"
        case .dateTakenAscending: return "Date taken, oldest first"
        case .dateTakenDescending: return "Date taken"
        case .interestingnessAscending: return "Least interesting"
        case .interestingnessDescending: return "Interesting"
        }
    }

    /// What the filter panel offers — the three the reference application
    /// shipped. The remaining four are legal values and can be surfaced without
    /// a change to the type.
    public static let offered: [SortOrder] = [
        .relevance, .datePostedDescending, .interestingnessDescending,
    ]
}

// MARK: - Colour

public enum FlickrColor: String, CaseIterable, Sendable, Identifiable, Hashable {
    case red = "0"
    case orange = "1"
    case yellow = "2"
    case green = "3"
    case blue = "4"
    case purple = "5"
    case blackAndWhite = "6"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .blackAndWhite: return "Black and white"
        }
    }

    var number: Int { Int(rawValue) ?? 0 }
}

// MARK: - The filter set

/// What the inspector panel holds.
///
/// A value type: changing a filter returns a new set rather than mutating a
/// shared one, so a source's filters cannot be altered from under it by
/// another source's panel.
public struct SearchFilters: Sendable, Equatable, Hashable {
    public let licenses: Set<License>
    public let sizes: Set<SizeBucket>
    public let sort: SortOrder
    public let colors: Set<FlickrColor>

    public init(licenses: Set<License> = [], sizes: Set<SizeBucket> = [],
                sort: SortOrder = .relevance, colors: Set<FlickrColor> = []) {
        self.licenses = licenses
        self.sizes = sizes
        self.sort = sort
        self.colors = colors
    }

    /// The `license` query value, or `nil` for "do not filter".
    ///
    /// Licence 0 is included like any other: dropping it made a search for All
    /// Rights Reserved silently return every licence instead.
    public var licenseParameter: String? {
        guard !licenses.isEmpty else { return nil }
        return licenses.map(\.number).sorted().map(String.init).joined(separator: ",")
    }

    /// The `color_codes` query value, or `nil` for "do not filter".
    public var colorParameter: String? {
        guard !colors.isEmpty else { return nil }
        return colors.map(\.number).sorted().map(String.init).joined(separator: ",")
    }

    /// Whether any filter is doing anything, for the "filters inactive" notice.
    public var isFiltering: Bool {
        !licenses.isEmpty || !sizes.isEmpty || !colors.isEmpty || sort != .relevance
    }

    /// Keep the photos whose size bucket was asked for.
    ///
    /// The size filter has no Flickr parameter; it is applied to the results,
    /// which is why an empty selection must mean "keep everything" rather than
    /// "keep nothing".
    public func apply(to photos: [Photo]) -> [Photo] {
        guard !sizes.isEmpty else { return photos }
        return photos.filter { photo in
            guard let bucket = SizeBucket.of(photo) else { return false }
            return sizes.contains(bucket)
        }
    }

    public func with(licenses: Set<License>) -> SearchFilters {
        SearchFilters(licenses: licenses, sizes: sizes, sort: sort, colors: colors)
    }

    public func with(sizes: Set<SizeBucket>) -> SearchFilters {
        SearchFilters(licenses: licenses, sizes: sizes, sort: sort, colors: colors)
    }

    public func with(sort: SortOrder) -> SearchFilters {
        SearchFilters(licenses: licenses, sizes: sizes, sort: sort, colors: colors)
    }

    public func with(colors: Set<FlickrColor>) -> SearchFilters {
        SearchFilters(licenses: licenses, sizes: sizes, sort: sort, colors: colors)
    }
}
