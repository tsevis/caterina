import Foundation

import FlickrKit

/// Which photos: the smart views Organize offers.
public enum LibraryFilter: Sendable, Equatable, Hashable {
    case all
    case untagged
    case withoutLocation
    case withLocation
    /// Exactly this tag, not a tag containing it.
    case tagged(String)
    /// Title, description or tags containing the text.
    case matching(String)
    /// Taken in a year (`2024`) or a month (`2024-06`).
    case takenIn(String)
    /// Posted in a month (`2024-06`, GMT).
    case uploadedIn(String)
    case licensed(License)
    case seenBy(Audience)
    case videos
    /// In no album, as `NotInAlbumIndex` last read it whole.
    case notInAlbum
}

/// Who can see a photo, as one choice rather than three flags.
public enum Audience: String, Sendable, Hashable, CaseIterable {
    case everyone, friendsOrFamily, onlyYou

    public var title: String {
        switch self {
        case .everyone: "Public"
        case .friendsOrFamily: "Friends & family"
        case .onlyYou: "Private"
        }
    }
}

public struct TagCount: Sendable, Equatable, Hashable, Identifiable {
    public var id: String { tag }
    public let tag: String
    public let count: Int

    public init(tag: String, count: Int) {
        self.tag = tag
        self.count = count
    }
}

public struct MonthCount: Sendable, Equatable, Hashable, Identifiable {
    public var id: String { month }
    /// `yyyy-MM`.
    public let month: String
    public let count: Int

    public init(month: String, count: Int) {
        self.month = month
        self.count = count
    }

    public var year: String { String(month.prefix(4)) }

    /// "June 2024".
    public var title: String {
        guard let date = Self.parser.date(from: month) else { return month }
        return Self.formatter.string(from: date)
    }

    private static let parser: DateFormatter = {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM"
        return parser
    }()

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
}

/// In what order.
public enum LibraryOrder: Sendable, Equatable, Hashable, CaseIterable {
    case newestTaken, oldestTaken, newestUploaded, mostViewed, recentlyUpdated
}

public struct LibrarySyncState: Sendable, Equatable {
    /// Bumped by each full sync; a photo it did not see is gone from Flickr.
    public let generation: Int
    public let lastFullSync: Date?
    /// Where the next incremental sync starts.
    public let changesSince: Date?
    /// When the last sync of either kind finished, for the window to show.
    public let lastSynced: Date?

    public init(generation: Int, lastFullSync: Date?, changesSince: Date?, lastSynced: Date? = nil) {
        self.generation = generation
        self.lastFullSync = lastFullSync
        self.changesSince = changesSince
        self.lastSynced = lastSynced
    }

    public static let never = LibrarySyncState(generation: 0, lastFullSync: nil, changesSince: nil)
}
