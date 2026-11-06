import Foundation

import CaterinaLibrary

/// The order photos appear in, chosen from the Sort menu and remembered.
extension OrganizeModel {

    static let sortKey = "organize.sort"

    /// An album has its own order on Flickr, and Recently Updated is an order.
    public var canSort: Bool { scope.albumID == nil && scope != .recentlyUpdated }

    public var order: LibraryOrder {
        canSort ? chosenOrder ?? scope.order : scope.order
    }

    public func sort(by order: LibraryOrder) {
        do {
            try store.setSetting(Self.sortKey, to: Data(order.rawValue.utf8))
        } catch {
            problem = "Could not remember the sort: \(Self.message(error))"
        }
        chosenOrder = order
        reloadPhotos()
    }

    func readChosenOrder() -> LibraryOrder? {
        do {
            guard let data = try store.setting(Self.sortKey) else { return nil }
            return LibraryOrder(rawValue: String(decoding: data, as: UTF8.self))
        } catch {
            problem = "Could not read the sort you chose: \(Self.message(error))"
            return nil
        }
    }
}

extension LibraryOrder {
    var sortTitle: String {
        switch self {
        case .newestUploaded: "Newest Posted"
        case .oldestUploaded: "Oldest Posted"
        case .newestTaken: "Newest Taken"
        case .oldestTaken: "Oldest Taken"
        case .mostViewed: "Most Viewed"
        case .recentlyUpdated: "Recently Updated"
        case .title: "Title A\u{2013}Z"
        }
    }
}
