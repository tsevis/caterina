import Foundation

/// Asking Flickr for your library: all of it, or what changed.
public enum LibraryQuery: Sendable, Hashable {
    /// Every photo, for a first sync or a full reconcile.
    case everything(page: Int)
    /// Photos whose title, tags, permissions or anything else changed since.
    case updated(since: Date, page: Int)

    /// Flickr's largest page.
    public static let pageSize = 500

    static let extras = [
        "description", "license", "date_upload", "date_taken", "last_update",
        "views", "tags", "geo", "media", "url_q",
    ].joined(separator: ",")

    var parameters: [OAuthParameter] {
        var fields: [(String, String)]
        switch self {
        case let .everything(page):
            fields = [("method", "flickr.people.getPhotos"), ("user_id", "me"), ("page", String(page))]
        case let .updated(since, page):
            fields = [("method", "flickr.photos.recentlyUpdated"),
                      ("min_date", String(Int(since.timeIntervalSince1970))),
                      ("page", String(page))]
        }
        fields += [("extras", Self.extras), ("per_page", String(Self.pageSize)),
                   ("format", "json"), ("nojsoncallback", "1")]
        return fields.map { OAuthParameter(name: $0.0, value: $0.1) }
    }
}
