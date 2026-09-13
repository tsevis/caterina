import Foundation
import GRDB

import FlickrKit

/// Where faves come from. `FlickrClient` in the app.
public protocol FaveSource: Sendable {
    func favorites(photoID: String, page: Int, priority: CallPriority) async throws -> FavePage
}

extension FlickrClient: FaveSource {}

public struct Fan: Sendable, Equatable, Hashable, Identifiable {
    public var id: String { nsid }
    public let nsid: String
    public let username: String
    /// How many of your photos they have faved.
    public let faveCount: Int
    public let lastFaved: Date
}

public struct FaveEvent: Sendable, Equatable, Hashable, Identifiable {
    public var id: String { "\(photoID)-\(nsid)" }
    public let photoID: String
    public let nsid: String
    public let username: String
    public let date: Date
}

/// Who faves your photos, built a photo at a time in the background.
///
/// Flickr has no call for "everyone who faved anything of mine": each photo's
/// faves are one list. So this reads them most-viewed first, re-reads each
/// weekly, and keeps the answer, from which Browse ranks your fans.
public actor FansIndex {

    public struct Outcome: Sendable, Equatable {
        public let photosRead: Int
        public let favesSaved: Int

        public init(photosRead: Int, favesSaved: Int) {
            self.photosRead = photosRead
            self.favesSaved = favesSaved
        }
    }

    /// 1,000 faves per photo: enough to know the fans, without 800 calls for
    /// one very popular photo.
    public static let pageCap = 20
    public static let rereadAfter: TimeInterval = 7 * 86_400

    private let source: FaveSource
    private let store: LibraryStore

    public init(source: FaveSource, store: LibraryStore) {
        self.source = source
        self.store = store
    }

    public func run(now: Date = Date(), photoLimit: Int = 200) async throws -> Outcome {
        var read = 0
        var saved = 0
        for photoID in try store.photosNeedingFaves(before: now.addingTimeInterval(-Self.rereadAfter), limit: photoLimit) {
            try Task.checkCancellation()
            let faves = try await allFaves(of: photoID)
            try store.replaceFaves(faves, of: photoID, readAt: now)
            read += 1
            saved += faves.count
        }
        return Outcome(photosRead: read, favesSaved: saved)
    }

    private func allFaves(of photoID: String) async throws -> [Fave] {
        var faves: [Fave] = []
        var page = 1
        var pages = 1
        repeat {
            let reply = try await source.favorites(photoID: photoID, page: page, priority: .background)
            faves += reply.faves
            pages = min(reply.pages, Self.pageCap)
            page += 1
        } while page <= pages
        return faves
    }
}

extension LibraryStore {

    /// Photos never read, then those read before `cutoff`, most viewed first.
    func photosNeedingFaves(before cutoff: Date, limit: Int) throws -> [String] {
        try read { db in
            try String.fetchAll(db, sql: """
                SELECT p.id FROM photo p LEFT JOIN faveScan s ON s.photoID = p.id
                WHERE s.readAt IS NULL OR s.readAt < ?
                ORDER BY s.readAt IS NOT NULL, p.views DESC, p.id LIMIT ?
                """, arguments: [cutoff.timeIntervalSince1970, limit])
        }
    }

    func replaceFaves(_ faves: [Fave], of photoID: String, readAt: Date) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM fave WHERE photoID = ?", arguments: [photoID])
            for fave in faves {
                try db.execute(sql: "INSERT OR REPLACE INTO fave (photoID, nsid, username, date) VALUES (?, ?, ?, ?)",
                               arguments: [photoID, fave.nsid, fave.username, fave.date.timeIntervalSince1970])
            }
            try db.execute(sql: "INSERT OR REPLACE INTO faveScan (photoID, readAt) VALUES (?, ?)",
                           arguments: [photoID, readAt.timeIntervalSince1970])
        }
    }

    public func topFans(limit: Int) throws -> [Fan] {
        try read { db in
            try Row.fetchAll(db, sql: """
                SELECT nsid, MAX(username) AS username, COUNT(*) AS n, MAX(date) AS last
                FROM fave GROUP BY nsid ORDER BY n DESC, last DESC LIMIT ?
                """, arguments: [limit]).map {
                Fan(nsid: $0["nsid"], username: $0["username"], faveCount: $0["n"],
                    lastFaved: Date(timeIntervalSince1970: $0["last"]))
            }
        }
    }

    public func recentFaves(limit: Int) throws -> [FaveEvent] {
        try read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM fave ORDER BY date DESC LIMIT ?", arguments: [limit]).map {
                FaveEvent(photoID: $0["photoID"], nsid: $0["nsid"], username: $0["username"],
                          date: Date(timeIntervalSince1970: $0["date"]))
            }
        }
    }

    public func photoIDs(favedBy nsid: String) throws -> [String] {
        try read { db in
            try String.fetchAll(db, sql: "SELECT photoID FROM fave WHERE nsid = ? ORDER BY date DESC", arguments: [nsid])
        }
    }

    /// How many photos have had their faves read, for the People view to say.
    public func fansCoverage() throws -> (read: Int, total: Int) {
        try read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM faveScan") ?? 0,
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo") ?? 0)
        }
    }
}
