import Foundation

import CaterinaLibrary
import FlickrKit

/// Rankings of your photos, from the library copy and saved history.
public enum Ranking: String, CaseIterable, Identifiable, Sendable {
    case mostViewed, topThisWeek, mostFavedThisMonth, rising, recentUploads

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mostViewed: "Most viewed"
        case .topThisWeek: "Top this week"
        case .mostFavedThisMonth: "Most faved, 28 days"
        case .rising: "Rising"
        case .recentUploads: "Recent uploads"
        }
    }

    public var systemImage: String {
        switch self {
        case .mostViewed: "eye"
        case .topThisWeek: "chart.bar"
        case .mostFavedThisMonth: "star"
        case .rising: "arrow.up.right"
        case .recentUploads: "clock"
        }
    }
}

/// What Browse is showing: a set of photos, or an index that leads to some.
public enum BrowseScope: Hashable, Sendable {
    case ranking(Ranking)
    /// Your photos, from the library copy.
    case library(LibraryFilter, title: String)
    /// Photos read from Flickr: an album, a pool, a gallery, faves, a stream.
    case remote(PhotoList, title: String)
    /// Your photos a person faved, from the fans index.
    case favedBy(nsid: String, name: String)
    /// Your located photos, on a map.
    case places
    case tags, timeline, people, albums, collections, galleries, groups

    public var title: String {
        switch self {
        case let .ranking(ranking): ranking.title
        case let .library(_, title), let .remote(_, title): title
        case let .favedBy(_, name): "Faved by \(name)"
        case .places: "Places"
        case .tags: "Tags"
        case .timeline: "Timeline"
        case .people: "People"
        case .albums: "Albums"
        case .collections: "Collections"
        case .galleries: "Galleries"
        case .groups: "Groups"
        }
    }

    /// An index lists things to open; everything else lists photos.
    public var isIndex: Bool {
        switch self {
        case .tags, .timeline, .people, .albums, .collections, .galleries, .groups: true
        default: false
        }
    }

    /// Scopes of one kind share a remembered layout.
    var layoutKind: String {
        switch self {
        case .ranking: "ranking"
        case .places: "places"
        default: "photos"
        }
    }

    var defaultLayout: BrowseLayout {
        switch self {
        case .ranking: .list
        case .places: .map
        default: .grid
        }
    }

    public static func album(_ album: Album, accountID: String) -> BrowseScope {
        .remote(.album(id: album.id, ownerID: accountID), title: album.title)
    }

    public static func pool(of group: AccountGroup, accountID: String) -> BrowseScope {
        .remote(.groupPool(groupID: group.id, contributorID: accountID), title: "Yours in \(group.name)")
    }

    public static func gallery(_ gallery: Gallery) -> BrowseScope {
        .remote(.gallery(id: gallery.id), title: gallery.title)
    }

    public static func photostream(of contact: Contact) -> BrowseScope {
        .remote(.photostream(userID: contact.id), title: contact.displayName)
    }
}

/// How a set of photos is laid out.
public enum BrowseLayout: String, CaseIterable, Identifiable, Sendable {
    case list, grid, timeline, map

    public var id: String { rawValue }

    public var title: String { rawValue.capitalized }

    public var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.3x3"
        case .timeline: "calendar"
        case .map: "map"
        }
    }
}

/// A photo in a set, with the one figure its set is about.
public struct BrowseItem: Sendable, Equatable, Identifiable {
    public var id: String { photo.id }
    public let photo: LibraryPhoto
    public let figure: String
}
