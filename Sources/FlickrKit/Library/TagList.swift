import Foundation

/// A photo's tags as the photographer spelled them, compared the way Flickr
/// compares them.
///
/// Every operation matches on the clean form ("newyork") and keeps the raw
/// spelling ("New York"): the spelling already on the photo when it stays,
/// the spelling typed when it is new.
enum TagList {

    static func adding(_ tags: [String], to existing: [String]) -> [String] {
        var seen = Set(existing.map(PhotoEdit.flickrTag))
        var added: [String] = []
        for tag in tags {
            let clean = PhotoEdit.flickrTag(tag)
            guard !clean.isEmpty, seen.insert(clean).inserted else { continue }
            added.append(trimmed(tag))
        }
        return existing + added
    }

    static func removing(_ tags: [String], from existing: [String]) -> [String] {
        let removed = Set(tags.map(PhotoEdit.flickrTag))
        return existing.filter { !removed.contains(PhotoEdit.flickrTag($0)) }
    }

    /// `tag` respelled as `replacement` where it stood. When the photo already
    /// has `replacement`, the two become one.
    static func renaming(_ tag: String, to replacement: String, in existing: [String]) -> [String] {
        let clean = PhotoEdit.flickrTag(tag)
        let target = PhotoEdit.flickrTag(replacement)
        guard !clean.isEmpty, !target.isEmpty,
              let index = existing.firstIndex(where: { PhotoEdit.flickrTag($0) == clean }) else { return existing }
        let others = existing.enumerated().filter { $0.offset != index }.map(\.element)
        if clean != target, others.contains(where: { PhotoEdit.flickrTag($0) == target }) {
            return others
        }
        return existing.enumerated().map { $0.offset == index ? trimmed(replacement) : $0.element }
    }

    /// Exactly `tags`, less blanks and second spellings of one tag.
    static func replacing(with tags: [String]) -> [String] {
        adding(tags, to: [])
    }

    private static func trimmed(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
