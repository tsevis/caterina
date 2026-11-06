import Foundation
import UniformTypeIdentifiers

import CaterinaLibrary
import FlickrKit

/// A photo about to go to groups: what the rules look at, and enough to show
/// the person which photo it is.
public struct ShareSubject: Identifiable, Sendable, Equatable {
    public var id: String { photo.id }
    public let photo: SharePhoto
    public let title: String
    /// Nil straight after an upload: Flickr's address is not known yet.
    public let thumbnailURL: String?

    public init(_ photo: LibraryPhoto) {
        self.photo = SharePhoto(id: photo.id, isVideo: photo.media == .video, hasLocation: photo.location != nil)
        self.title = photo.title
        self.thumbnailURL = photo.thumbnailURL
    }

    public init(uploaded file: URL, photoID: String, title: String) {
        let isVideo = UTType(filenameExtension: file.pathExtension)?.conforms(to: .movie) ?? false
        // Whether Flickr kept the file's location is not known yet. Assuming it
        // did lets Flickr judge a location rule rather than skipping on a guess.
        self.photo = SharePhoto(id: photoID, isVideo: isVideo, hasLocation: true)
        self.title = title.isEmpty ? file.lastPathComponent : title
        self.thumbnailURL = nil
    }
}
