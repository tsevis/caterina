import Foundation

/// A photo before and after an edit, and the Flickr calls between them.
///
/// **Undo is `reversed`.** Because the calls come from the difference, the
/// same difference the other way restores exactly what was there.
public struct PhotoChange: Sendable, Equatable {
    public let before: LibraryPhoto
    public let after: LibraryPhoto

    public init(before: LibraryPhoto, after: LibraryPhoto) {
        self.before = before
        self.after = after
    }

    public var reversed: PhotoChange { PhotoChange(before: after, after: before) }

    public var isEmpty: Bool { writes.isEmpty }

    /// In a fixed order, one call per group of fields that changed. Every one
    /// sets a value outright, so every one is safe to repeat.
    public var writes: [FlickrWrite] {
        [meta, tags, visibility, taken, license, location, geoPermissions, safety, contentType].compactMap { $0 }
    }

    private var id: String { after.id }

    func write(_ method: String, _ arguments: [String: String]) -> FlickrWrite {
        FlickrWrite(method: method, arguments: arguments.merging(["photo_id": id]) { new, _ in new },
                    repeatable: true)
    }

    /// Title and description go together: `setMeta` needs at least one, and an
    /// undo then restores both in the one call.
    private var meta: FlickrWrite? {
        guard before.title != after.title || before.description != after.description else { return nil }
        return write("flickr.photos.setMeta", ["title": after.title, "description": after.description])
    }

    /// The whole list, raw. Tags other people added are in the list Flickr
    /// reports and are sent back with it, so they stay — under the owner's
    /// name, which is the one thing `setTags` cannot avoid.
    private var tags: FlickrWrite? {
        guard before.tags != after.tags else { return nil }
        return write("flickr.photos.setTags", ["tags": UploadMetadata.tagList(after.tags)])
    }

    /// `setPerms` needs the three visibility flags even when only who may
    /// comment changes. Unknown comment and tag permissions are left out,
    /// which leaves Flickr's alone.
    private var visibility: FlickrWrite? {
        guard before.visibility != after.visibility || before.permissions != after.permissions else { return nil }
        var arguments = ["is_public": Self.flag(after.visibility.isPublic),
                         "is_friend": Self.flag(after.visibility.isFriend),
                         "is_family": Self.flag(after.visibility.isFamily)]
        if let permissions = after.permissions {
            arguments["perm_comment"] = String(permissions.comment.rawValue)
            arguments["perm_addmeta"] = String(permissions.addMeta.rawValue)
        }
        return write("flickr.photos.setPerms", arguments)
    }

    static func flag(_ on: Bool) -> String { on ? "1" : "0" }

    /// Flickr cannot be told a date is unknown, so going back to one is skipped.
    /// Taken and posted share `setDates`; each goes only when it changed.
    private var taken: FlickrWrite? {
        var arguments: [String: String] = [:]
        if before.taken != after.taken, let taken = after.taken {
            arguments["date_taken"] = taken
            arguments["date_taken_granularity"] = "0"
        }
        if before.uploaded != after.uploaded, let posted = after.uploaded {
            arguments["date_posted"] = String(Int(posted.timeIntervalSince1970))
        }
        return arguments.isEmpty ? nil : write("flickr.photos.setDates", arguments)
    }

    private var license: FlickrWrite? {
        guard before.license != after.license, let license = after.license else { return nil }
        return write("flickr.photos.licenses.setLicense", ["license_id": license.rawValue])
    }

    private var location: FlickrWrite? {
        guard before.location != after.location else { return nil }
        guard let location = after.location else {
            return write("flickr.photos.geo.removeLocation", [:])
        }
        var arguments = ["lat": String(location.latitude), "lon": String(location.longitude)]
        // Flickr takes 1 to 16; zero is "never said", and sending it is refused.
        if (1...16).contains(location.accuracy) { arguments["accuracy"] = String(location.accuracy) }
        return write("flickr.photos.geo.setLocation", arguments)
    }
}
