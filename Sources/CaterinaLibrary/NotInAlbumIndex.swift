import Foundation
import GRDB

import FlickrKit

/// Where lists of photos come from. `FlickrClient` in the app.
public protocol PhotoListSource: Sendable {
    func photoList(_ list: PhotoList, page: Int) async throws -> LibraryPage
}

extension FlickrClient: PhotoListSource {}

/// Which of your photos are in no album.
///
/// Album membership is not a photo field, so the library copy cannot answer
/// it. `photos.getNotInSet` is read whole, 500 at a time, and replaces the
/// last answer only once every page is in.
public struct NotInAlbumIndex: Sendable {
    private let source: PhotoListSource
    private let store: LibraryStore

    public init(source: PhotoListSource, store: LibraryStore) {
        self.source = source
        self.store = store
    }

    /// How many photos are in no album.
    @discardableResult
    public func refresh(now: Date = Date()) async throws -> Int {
        var ids: [String] = []
        var page = 1
        var pages = 1
        repeat {
            try Task.checkCancellation()
            let reply = try await source.photoList(.notInAlbum, page: page)
            ids += reply.photos.map(\.id)
            pages = reply.pages
            page += 1
        } while page <= pages
        try store.replaceNotInAlbum(Set(ids), readAt: now)
        return Set(ids).count
    }
}

extension LibraryStore {

    func replaceNotInAlbum(_ ids: Set<String>, readAt: Date) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM notInAlbum")
            for id in ids {
                try db.execute(sql: "INSERT INTO notInAlbum (photoID) VALUES (?)", arguments: [id])
            }
            try db.execute(sql: "INSERT OR REPLACE INTO notInAlbumState (id, readAt) VALUES (1, ?)",
                           arguments: [readAt.timeIntervalSince1970])
        }
    }

    /// Photos just added to an album leave the view without waiting for the
    /// next read.
    public func markFiled(_ ids: [String]) throws {
        try write { db in
            for id in ids {
                try db.execute(sql: "DELETE FROM notInAlbum WHERE photoID = ?", arguments: [id])
            }
        }
    }

    /// Nil until the list has been read whole once.
    public func notInAlbumReadAt() throws -> Date? {
        try read { db in
            try Double.fetchOne(db, sql: "SELECT readAt FROM notInAlbumState WHERE id = 1")
                .map(Date.init(timeIntervalSince1970:))
        }
    }
}
