import Foundation

import FlickrKit

/// Files going to Flickr together, and the album they go into.
public struct UploadBatch: Sendable, Equatable, Identifiable {

    public enum AlbumChoice: Sendable, Equatable {
        case none
        case new(title: String)
        case existing(id: String)
    }

    public struct Summary: Sendable, Equatable {
        public let done: Int
        public let failed: Int
        /// Queued, sending, or being processed by Flickr.
        public let remaining: Int
        /// Being sent when the app stopped; waiting for the person to decide.
        public let interrupted: Int

        public init(done: Int, failed: Int, remaining: Int, interrupted: Int) {
            self.done = done
            self.failed = failed
            self.remaining = remaining
            self.interrupted = interrupted
        }
    }

    public let id: String
    public let createdAt: Date
    public let album: AlbumChoice
    /// The album photos go into: the existing one, or the new one once made.
    public let albumID: String?
}

public struct UploadItem: Sendable, Equatable {

    public enum State: Sendable, Equatable {
        case queued
        case sending
        /// Flickr has the file and is processing it.
        case processing(ticket: String)
        case done(photoID: String)
        case failed(String)
        case interrupted
        /// Interrupted, and the person found it on Flickr: nothing more to do.
        case alreadyOnFlickr
    }

    public let batchID: String
    public let position: Int
    public let file: URL
    public let metadata: UploadMetadata
    public let state: State
    public let inAlbum: Bool

    public var photoID: String? {
        if case let .done(photoID) = state { return photoID }
        return nil
    }

    public var message: String? {
        if case let .failed(message) = state { return message }
        return nil
    }
}
