import Foundation

extension PhotoChange {

    public enum Rebase: Sendable, Equatable {
        /// What to send: `before` is the photo as Flickr has it now.
        case change(PhotoChange)
        /// A field this change touches was changed on Flickr as well; the
        /// reason names it.
        case conflict(String)
    }

    /// This change laid over `live`, the photo as Flickr has it now.
    ///
    /// Fields the change does not touch come from `live`. A field it does
    /// touch is refused when Flickr's value is neither the one this change
    /// started from nor the one it ends at, because someone changed it since.
    /// Tags never conflict: what was added, removed or respelled is replayed
    /// on Flickr's list, keeping the spellings there.
    public func rebased(onto live: LibraryPhoto) -> Rebase {
        var rebased = live
        rebased.tags = rebasedTags(onto: live.tags)
        do {
            rebased.title = try field("title", \.title, live)
            rebased.description = try field("description", \.description, live)
            rebased.license = try field("licence", \.license, live)
            rebased.visibility = try field("who can see", \.visibility, live)
            rebased.taken = try field("date taken", \.taken, live)
            rebased.location = try field("location", \.location, live)
        } catch {
            return .conflict("The \(error.field) was changed on Flickr after this edit was made, so it was left as it is.")
        }
        return .change(PhotoChange(before: live, after: rebased))
    }

    private struct Conflict: Error { let field: String }

    private func field<Value: Equatable>(_ name: String, _ path: KeyPath<LibraryPhoto, Value>,
                                         _ live: LibraryPhoto) throws(Conflict) -> Value {
        let (from, to, now) = (before[keyPath: path], after[keyPath: path], live[keyPath: path])
        guard from != to else { return now }
        guard now == from || now == to else { throw Conflict(field: name) }
        return to
    }

    private func rebasedTags(onto live: [String]) -> [String] {
        let clean = { (tags: [String]) in Set(tags.map(PhotoEdit.flickrTag)) }
        let (from, to) = (clean(before.tags), clean(after.tags))
        let removed = before.tags.filter { !to.contains(PhotoEdit.flickrTag($0)) }
        let added = after.tags.filter { !from.contains(PhotoEdit.flickrTag($0)) }
        let respelled = after.tags.filter { tag in
            from.contains(PhotoEdit.flickrTag(tag)) && !before.tags.contains(tag)
        }
        let kept = TagList.removing(removed, from: live)
        let renamed = respelled.reduce(kept) { TagList.renaming($1, to: $1, in: $0) }
        return TagList.adding(added, to: renamed)
    }
}

extension LibraryPhoto {

    /// This photo with every field an edit can change taken from `other`,
    /// keeping what only this copy has: thumbnails, views, owner.
    public func withEditableFields(of other: LibraryPhoto) -> LibraryPhoto {
        var merged = self
        merged.title = other.title
        merged.description = other.description
        merged.tags = other.tags
        merged.license = other.license
        merged.visibility = other.visibility
        merged.taken = other.taken
        merged.location = other.location
        return merged
    }

    /// Tags in the form Flickr matches on, as the local copy stores them.
    public var withCleanTags: LibraryPhoto {
        var cleaned = self
        cleaned.tags = TagList.replacing(with: tags).map(PhotoEdit.flickrTag)
        return cleaned
    }
}
