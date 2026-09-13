import Foundation

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
}

/// In what order.
public enum LibraryOrder: Sendable, Equatable, Hashable, CaseIterable {
    case newestTaken, oldestTaken, newestUploaded, mostViewed
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
