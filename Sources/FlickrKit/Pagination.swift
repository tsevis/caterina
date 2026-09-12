import Foundation

/// How far into a result set Flickr will actually let you walk.
///
/// Flickr reports a page count for the whole result set but serves at most
/// about 4000 results from a search; paging beyond that returns photos already
/// seen. Reporting the number Flickr claims invites the user to page into
/// duplicates, so the reachable count is clamped — and the clamp is explained
/// rather than left to look like a bug.
public enum Pagination {
    public static let resultCap = 4000

    public static let explanation =
        "Flickr serves at most \(resultCap.formatted()) results for one search, "
        + "so the pages beyond that repeat photos you have already seen."

    public static func reachablePages(reported: Int, perPage: Int) -> Int {
        let perPage = max(1, perPage)
        let servable = (resultCap + perPage - 1) / perPage
        return max(1, min(max(reported, 1), servable))
    }

    public static func isClamped(reported: Int, perPage: Int) -> Bool {
        reachablePages(reported: reported, perPage: perPage) < reported
    }
}
