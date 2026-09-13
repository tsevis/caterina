import Foundation

extension PhotoChange {

    /// Fields this change sets whose earlier value Flickr never reported, so
    /// undo cannot put them back. Named for the person reading the warning.
    public var unrestorable: [String] {
        [("safety level", before.safety == nil && after.safety != nil),
         ("content type", before.contentType == nil && after.contentType != nil),
         ("hidden from search", before.hiddenFromSearch == nil && after.hiddenFromSearch != nil),
         ("who can comment and add tags", before.permissions == nil && after.permissions != nil),
         ("who can see the location", before.geoPermissions == nil && after.geoPermissions != nil)]
            .filter(\.1).map(\.0)
    }

    /// `photos.getInfo` does not report who can see a location, so a change
    /// to it costs a second read.
    public var readsGeoPermissions: Bool { before.geoPermissions != after.geoPermissions }

    /// Reads before writing: `photos.getInfo`, and `geo.getPerms` when needed.
    public var readCalls: Int { readsGeoPermissions ? 2 : 1 }

    /// Flickr refuses this for a photo with no location; that photo alone
    /// fails.
    var geoPermissions: FlickrWrite? {
        guard before.geoPermissions != after.geoPermissions, let permissions = after.geoPermissions else { return nil }
        return write("flickr.photos.geo.setPerms", ["is_public": Self.flag(permissions.isPublic),
                                                    "is_contact": Self.flag(permissions.isContact),
                                                    "is_friend": Self.flag(permissions.isFriend),
                                                    "is_family": Self.flag(permissions.isFamily)])
    }

    /// Safety level and hidden from search share `setSafetyLevel`; each is
    /// sent only when it changed, so the other stays as Flickr has it.
    var safety: FlickrWrite? {
        var arguments: [String: String] = [:]
        if before.safety != after.safety, let safety = after.safety {
            arguments["safety_level"] = String(safety.rawValue)
        }
        if before.hiddenFromSearch != after.hiddenFromSearch, let hidden = after.hiddenFromSearch {
            arguments["hidden"] = Self.flag(hidden)
        }
        return arguments.isEmpty ? nil : write("flickr.photos.setSafetyLevel", arguments)
    }

    var contentType: FlickrWrite? {
        guard before.contentType != after.contentType, let contentType = after.contentType else { return nil }
        return write("flickr.photos.setContentType", ["content_type": String(contentType.rawValue)])
    }
}

extension LibraryPhoto {
    public func with(geoPermissions: GeoPermissions?) -> LibraryPhoto {
        var photo = self
        photo.geoPermissions = geoPermissions
        return photo
    }
}
