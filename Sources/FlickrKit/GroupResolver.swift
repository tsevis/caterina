import Foundation

/// One result from `flickr.groups.search`.
public struct GroupSummary: Sendable, Equatable, Hashable, Identifiable {
    public let nsid: String
    public let name: String

    public init(nsid: String, name: String) {
        self.nsid = nsid
        self.name = name
    }

    public var id: String { nsid }
}

/// Turning what the user typed into a group to list.
///
/// Listing a pool and searching inside it are two different API methods with
/// different filter support, and the resolution path has three steps because no
/// single one is reliable: `flickr.urls.lookupGroup` handles a URL or slug,
/// `flickr.groups.getInfo` confirms an NSID, and `flickr.groups.search` is a
/// *fuzzy* name search whose first result is frequently an unrelated group.
public enum GroupResolver {

    /// The group slug or NSID from a Flickr group URL or raw input.
    public static func identifier(from text: String) throws -> String {
        let value = text.trimmed
        guard !value.isEmpty else {
            throw FlickrError.invalidInput("Enter a Flickr group URL or name.")
        }
        guard value.lowercased().contains("flickr.com") else { return value }

        let normalised = value.contains("//") ? value : "//" + value
        let path = URLComponents(string: normalised)?.path ?? ""
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "groups", !parts[1].isEmpty else {
            throw FlickrError.invalidInput(
                "That does not look like a Flickr group URL. Expected something "
                + "like https://www.flickr.com/groups/groupname/")
        }
        return parts[1]
    }

    /// True when the value already looks like a Flickr group NSID.
    public static func isNSID(_ value: String) -> Bool { value.contains("@") }

    /// The canonical group URL, for `flickr.urls.lookupGroup`.
    public static func lookupURL(for identifier: String) -> String {
        "https://www.flickr.com/groups/\(identifier)/"
    }

    /// The NSID of the group whose name matches `identifier` exactly.
    ///
    /// Returns `nil` when nothing matches confidently — an exact match or
    /// nothing is the safer contract than a fuzzy search's first hit.
    public static func exactMatch(in groups: [GroupSummary],
                                  identifier: String) -> String? {
        let target = comparable(identifier)
        guard !target.isEmpty else { return nil }
        return groups.first { comparable($0.name) == target }?.nsid
    }

    /// A blank query lists the pool; a typed one searches inside it.
    public static func query(groupID: String, text: String) -> PhotoQuery {
        let trimmed = text.trimmed
        return trimmed.isEmpty
            ? .groupPool(groupID: groupID)
            : .groupSearch(groupID: groupID, text: trimmed)
    }

    /// Whether two group names are the same name.
    ///
    /// Flickr sends names HTML-escaped — `Black &amp; White Done Right !.` is a
    /// real one — so comparing the raw strings compares the escaping as much as
    /// the name.
    public static func namesMatch(_ one: String, _ other: String) -> Bool {
        let left = comparable(one)
        return !left.isEmpty && left == comparable(other)
    }

    /// Normalise a group name for comparison: unescaped, spaceless, casefolded.
    private static func comparable(_ name: String) -> String {
        unescapingHTML(name)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .lowercased()
    }

    /// The handful of entities Flickr puts in group names.
    ///
    /// Hand-rolled because the Foundation route to HTML decoding is
    /// `NSAttributedString`, which lives in AppKit — and FlickrKit links no UI
    /// framework, because that is what makes it testable headlessly.
    static func unescapingHTML(_ text: String) -> String {
        var result = text
        for (entity, replacement) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                                      ("&quot;", "\""), ("&apos;", "'"),
                                      ("&#39;", "'"), ("&nbsp;", " ")] {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}
