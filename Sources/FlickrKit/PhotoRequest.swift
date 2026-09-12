import Foundation

/// What a section is asking Flickr for.
public enum PhotoQuery: Sendable, Equatable, Hashable {
    /// A text search across Flickr.
    case search(text: String)
    /// One person's photostream, by NSID.
    case userPhotos(userID: String)
    /// The signed-in user's own photostream.
    case myPhotos
    /// A group's pool, listed.
    case groupPool(groupID: String)
    /// A text search *within* a group's pool.
    case groupSearch(groupID: String, text: String)

    var method: String {
        switch self {
        case .search, .groupSearch: return "flickr.photos.search"
        case .userPhotos, .myPhotos: return "flickr.people.getPhotos"
        case .groupPool: return "flickr.groups.pools.getPhotos"
        }
    }

    /// Whether the filters in Search Settings do anything for this query.
    ///
    /// `flickr.groups.pools.getPhotos` and `flickr.people.getPhotos` accept no
    /// licence, sort or colour parameter. Sending them anyway is worse than not
    /// offering them: Flickr ignores the parameter and the interface goes on
    /// claiming a filter is applied.
    public var supportsFilters: Bool {
        switch self {
        case .search, .groupSearch: return true
        case .userPhotos, .myPhotos, .groupPool: return false
        }
    }

    /// Only the signed-in user's own stream needs a token.
    public var requiresAuthentication: Bool {
        if case .myPhotos = self { return true }
        return false
    }

    /// What identifies this query, for deciding whether the page should reset.
    var identity: String {
        switch self {
        case let .search(text): return "search:\(text.trimmed)"
        case let .userPhotos(userID): return "user:\(userID)"
        case .myPhotos: return "me"
        case let .groupPool(groupID): return "pool:\(groupID)"
        case let .groupSearch(groupID, text): return "group:\(groupID):\(text.trimmed)"
        }
    }
}

/// One listing request, ready to be signed and sent.
public struct PhotoRequest: Sendable, Equatable {
    public static let defaultPerPage = 25

    public let query: PhotoQuery
    public let filters: SearchFilters
    public let page: Int
    public let perPage: Int

    public init(query: PhotoQuery, filters: SearchFilters = SearchFilters(),
                page: Int = 1, perPage: Int = PhotoRequest.defaultPerPage) {
        self.query = query
        self.filters = filters
        self.page = max(1, page)
        self.perPage = max(1, perPage)
    }

    public var supportsFilters: Bool { query.supportsFilters }
    public var requiresAuthentication: Bool { query.requiresAuthentication }

    /// The parameters that go on the wire.
    ///
    /// This — not the response — is what the tests assert on. Flickr answers
    /// `stat=ok` for a sort it does not recognise and silently ignores a filter
    /// the method does not support, so a response proves nothing about what was
    /// asked for.
    public func parameters() -> [OAuthParameter] {
        var sent: [(String, String)] = [
            ("method", query.method),
            ("page", String(page)),
            ("per_page", String(perPage)),
            ("extras", PhotoVariant.extrasParameter),
            ("format", "json"),
            ("nojsoncallback", "1"),
        ]

        switch query {
        case let .search(text):
            sent.append(("text", text.trimmed))
        case let .userPhotos(userID):
            sent.append(("user_id", userID))
        case .myPhotos:
            sent.append(("user_id", "me"))
        case let .groupPool(groupID):
            sent.append(("group_id", groupID))
        case let .groupSearch(groupID, text):
            sent.append(("group_id", groupID))
            sent.append(("text", text.trimmed))
        }

        if query.supportsFilters {
            sent.append(("sort", filters.sort.rawValue))
            if let license = filters.licenseParameter { sent.append(("license", license)) }
            if let colors = filters.colorParameter { sent.append(("color_codes", colors)) }
        }

        return sent.map { OAuthParameter(name: $0.0, value: $0.1) }
    }

    public func onPage(_ page: Int) -> PhotoRequest {
        PhotoRequest(query: query, filters: filters, page: page, perPage: perPage)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
