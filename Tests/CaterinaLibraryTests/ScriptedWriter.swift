import Foundation

import FlickrKit
@testable import CaterinaLibrary

/// Flickr, from a script: sends writes and remembers them, and reads a photo
/// back from `live` when given, otherwise from the local copy as it stands.
actor ScriptedWriter: PhotoWriter, LivePhotoReader {
    private let store: LibraryStore
    private let failures: [String: FlickrError]
    private let readFailures: [String: FlickrError]
    private let live: [String: LibraryPhoto]
    private(set) var sent: [FlickrWrite] = []
    private let geo: [String: LibraryPhoto.GeoPermissions]
    private(set) var read: [String] = []
    private(set) var geoRead: [String] = []

    /// `failures` and `readFailures` are keyed on photo id.
    init(store: LibraryStore, failing failures: [String: FlickrError] = [:],
         failingReads readFailures: [String: FlickrError] = [:], live: [String: LibraryPhoto] = [:],
         geoPermissions geo: [String: LibraryPhoto.GeoPermissions] = [:]) {
        self.geo = geo
        self.store = store
        self.failures = failures
        self.readFailures = readFailures
        self.live = live
    }

    func perform(_ write: FlickrWrite, priority: CallPriority) async throws -> Data {
        sent.append(write)
        if let failure = failures[write.arguments["photo_id"] ?? ""] { throw failure }
        return Data(#"{"stat":"ok"}"#.utf8)
    }

    func livePhoto(id: String, priority: CallPriority) async throws -> LibraryPhoto {
        read.append(id)
        if let failure = readFailures[id] { throw failure }
        if let photo = live[id] { return photo }
        guard let photo = try store.photos(ids: [id]).first else {
            throw FlickrError.api(code: 1, message: "Photo not found", transient: false)
        }
        return photo
    }

    func geoPermissions(photoID: String, priority: CallPriority) async throws -> LibraryPhoto.GeoPermissions? {
        geoRead.append(photoID)
        return geo[photoID]
    }
}
