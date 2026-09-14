import Foundation

/// Rearranging photos in an album, worked out without Flickr.
public enum AlbumOrdering {

    public enum Sort: String, CaseIterable, Identifiable, Sendable {
        case dateTaken, title, views
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .dateTaken: "Date Taken"
            case .title: "Title"
            case .views: "Most Viewed"
            }
        }
    }

    /// `moved`, in their present order, placed just before `target`; at the
    /// end when there is no target. Dropping onto a moved photo changes
    /// nothing.
    public static func moving(_ moved: Set<String>, before target: String?, in order: [String]) -> [String] {
        guard target.map({ !moved.contains($0) }) ?? true else { return order }
        let moving = order.filter(moved.contains)
        let staying = order.filter { !moved.contains($0) }
        guard let target, let index = staying.firstIndex(of: target) else { return staying + moving }
        return Array(staying[..<index]) + moving + Array(staying[index...])
    }

    /// Photos missing from `photos` (not in the library copy) keep their
    /// place at the end.
    static func sorted(_ order: [String], by sort: Sort, photos: [String: LibraryPhotoFacts]) -> [String] {
        let known = order.filter { photos[$0] != nil }
        let unknown = order.filter { photos[$0] == nil }
        let sortedKnown = known.sorted { lhs, rhs in
            guard let a = photos[lhs], let b = photos[rhs] else { return false }
            switch sort {
            case .dateTaken: return (a.taken ?? "~") < (b.taken ?? "~")
            case .title: return a.title.localizedStandardCompare(b.title) == .orderedAscending
            case .views: return a.views > b.views
            }
        }
        return sortedKnown + unknown
    }

    struct LibraryPhotoFacts {
        let taken: String?
        let title: String
        let views: Int
    }
}
