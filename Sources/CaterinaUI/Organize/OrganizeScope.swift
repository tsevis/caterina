import Foundation

import CaterinaLibrary
import FlickrKit

/// Where Organize is looking: the smart views in its sidebar.
public enum OrganizeScope: Sendable, Hashable, Codable {
    case all
    case notInAlbum
    case untagged
    case withoutLocation
    case withLocation
    case recentlyUpdated
    case videos
    case audience(Audience)
    case licence(License)
    /// `yyyy-MM`, taken.
    case month(String)
    /// `yyyy-MM`, posted.
    case postedMonth(String)
    case tag(String)
    /// Read from Flickr, in album order.
    case album(id: String, title: String)
    /// Title, description or tags containing the text.
    case search(String)

    var albumID: String? {
        if case let .album(id, _) = self { return id }
        return nil
    }

    /// The fixed views, in sidebar order.
    public static let smartViews: [OrganizeScope] = [
        .all, .notInAlbum, .untagged, .withoutLocation, .withLocation, .recentlyUpdated, .videos,
    ]

    var filter: LibraryFilter {
        switch self {
        case .all, .recentlyUpdated, .album: .all
        case let .search(text): .matching(text)
        case .notInAlbum: .notInAlbum
        case .untagged: .untagged
        case .withoutLocation: .withoutLocation
        case .withLocation: .withLocation
        case .videos: .videos
        case let .audience(audience): .seenBy(audience)
        case let .licence(licence): .licensed(licence)
        case let .month(month): .takenIn(month)
        case let .postedMonth(month): .uploadedIn(month)
        case let .tag(tag): .tagged(tag)
        }
    }

    var order: LibraryOrder {
        switch self {
        case .recentlyUpdated: .recentlyUpdated
        case .postedMonth: .newestUploaded
        default: .newestTaken
        }
    }

    public var title: String {
        switch self {
        case .all: "All Photos"
        case .notInAlbum: "Not in an Album"
        case .untagged: "Untagged"
        case .withoutLocation: "No Location"
        case .withLocation: "With Location"
        case .recentlyUpdated: "Recently Updated"
        case .videos: "Videos"
        case let .audience(audience): audience.title
        case let .licence(licence): licence.label
        case let .month(month): MonthCount(month: month, count: 0).title
        case let .postedMonth(month): "Posted in \(MonthCount(month: month, count: 0).title)"
        case let .tag(tag): tag
        case let .album(_, title): title
        case let .search(text): "“\(text)”"
        }
    }

    public var systemImage: String {
        switch self {
        case .all: "photo.on.rectangle"
        case .notInAlbum: "rectangle.stack.badge.minus"
        case .untagged: "tag.slash"
        case .withoutLocation: "location.slash"
        case .withLocation: "location"
        case .recentlyUpdated: "clock.arrow.circlepath"
        case .videos: "video"
        case .audience: "eye"
        case .licence: "c.circle"
        case .month: "calendar"
        case .postedMonth: "calendar.badge.clock"
        case .tag: "tag"
        case .album: "rectangle.stack"
        case .search: "magnifyingglass"
        }
    }
}

extension Audience: Codable {}

/// A view kept by name: it opens with the photos that match it now.
public struct SavedView: Sendable, Equatable, Identifiable, Codable {
    public var id: String { name }
    public let name: String
    public let scope: OrganizeScope
}
