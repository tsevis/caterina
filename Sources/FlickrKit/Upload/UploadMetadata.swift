import Foundation

/// What a photo goes to Flickr with.
public struct UploadMetadata: Sendable, Equatable, Hashable, Codable {

    public enum Safety: Int, Sendable, Codable, CaseIterable {
        case safe = 1, moderate = 2, restricted = 3
    }

    public enum ContentType: Int, Sendable, Codable, CaseIterable {
        case photo = 1, screenshot = 2, other = 3
    }

    public let title: String
    public let description: String
    public let tags: [String]
    public let visibility: LibraryPhoto.Visibility
    /// Left to the account's default when nil.
    public let safety: Safety?
    /// Left to the account's default when nil.
    public let contentType: ContentType?
    public let hiddenFromSearch: Bool

    public init(title: String = "", description: String = "", tags: [String] = [],
                visibility: LibraryPhoto.Visibility = .init(isPublic: true, isFriend: false, isFamily: false),
                safety: Safety? = nil, contentType: ContentType? = nil, hiddenFromSearch: Bool = false) {
        self.title = title
        self.description = description
        self.tags = tags
        self.visibility = visibility
        self.safety = safety
        self.contentType = contentType
        self.hiddenFromSearch = hiddenFromSearch
    }

    /// The fields of the upload form, every one of which is signed. Always
    /// asynchronous: Flickr answers with a ticket at once instead of holding
    /// the connection open while it processes the file.
    var parameters: [OAuthParameter] {
        var fields: [(String, String)] = []
        if !title.isEmpty { fields.append(("title", title)) }
        if !description.isEmpty { fields.append(("description", description)) }
        if !tags.isEmpty { fields.append(("tags", Self.tagList(tags))) }
        fields += [("is_public", flag(visibility.isPublic)), ("is_friend", flag(visibility.isFriend)),
                   ("is_family", flag(visibility.isFamily)),
                   ("hidden", hiddenFromSearch ? "2" : "1"), ("async", "1")]
        if let safety { fields.append(("safety_level", String(safety.rawValue))) }
        if let contentType { fields.append(("content_type", String(contentType.rawValue))) }
        return fields.map { OAuthParameter(name: $0.0, value: $0.1) }
    }

    /// Space-separated, with a tag that contains a space in double quotes —
    /// Flickr's own syntax for one tag of several words.
    static func tagList(_ tags: [String]) -> String {
        tags.map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.contains(" ") ? "\"\($0)\"" : $0 }
            .joined(separator: " ")
    }

    private func flag(_ on: Bool) -> String { on ? "1" : "0" }
}
