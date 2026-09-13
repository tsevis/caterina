import Foundation
import GRDB

import FlickrKit

public struct StatsPoint: Sendable, Equatable {
    public let day: StatsDay
    public let views: Int
    public let comments: Int
    public let faves: Int
}

public struct AccountPoint: Sendable, Equatable {
    public let day: StatsDay
    public let totals: ViewTotals
}

public enum StatsMeasure: String, Sendable, CaseIterable {
    case views, faves, comments
}

public struct RankedPhoto: Sendable, Equatable, Identifiable {
    public var id: String { photoID }
    public let photoID: String
    /// Nil when the photo is not in the library copy (yet, or any more).
    public let photo: LibraryPhoto?
    public let total: Int
}

public struct RisingPhoto: Sendable, Equatable, Identifiable {
    public var id: String { photoID }
    public let photoID: String
    public let photo: LibraryPhoto?
    public let thisWeek: Int
    public let weekBefore: Int
}

/// Daily stats, kept for as long as the library copy is.
extension LibraryStore {

    /// One day, all or nothing.
    public func saveStatsDay(_ day: StatsDay, photos: [PhotoDayStats], totals: ViewTotals) throws {
        try write { db in
            let statement = try db.cachedStatement(sql: """
                INSERT OR REPLACE INTO photoDay (photoID, day, views, comments, faves) VALUES (?, ?, ?, ?, ?)
                """)
            for stats in photos {
                try statement.execute(arguments: [stats.photoID, day.text, stats.views, stats.comments, stats.faves])
            }
            try db.execute(sql: """
                INSERT OR REPLACE INTO accountDay (day, total, photos, photostream, albums, collections)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [day.text, totals.total, totals.photos, totals.photostream,
                                 totals.albums, totals.collections])
        }
    }

    public func savedStatsDays() throws -> Set<StatsDay> {
        try read { db in Set(try String.fetchAll(db, sql: "SELECT day FROM accountDay").compactMap(StatsDay.init)) }
    }

    public func statsHistory(photoID: String) throws -> [StatsPoint] {
        try read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM photoDay WHERE photoID = ? ORDER BY day", arguments: [photoID])
                .compactMap { row in
                    StatsDay(row["day"] as String).map {
                        StatsPoint(day: $0, views: row["views"], comments: row["comments"], faves: row["faves"])
                    }
                }
        }
    }

    public func accountHistory() throws -> [AccountPoint] {
        try read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM accountDay ORDER BY day").compactMap { row in
                StatsDay(row["day"] as String).map {
                    AccountPoint(day: $0, totals: ViewTotals(total: row["total"], photos: row["photos"],
                                                             photostream: row["photostream"], albums: row["albums"],
                                                             collections: row["collections"]))
                }
            }
        }
    }

    public func topPhotos(from start: StatsDay, through end: StatsDay, by measure: StatsMeasure,
                          limit: Int) throws -> [RankedPhoto] {
        try read { db in
            try Row.fetchAll(db, sql: """
                SELECT d.photoID AS photoID, SUM(d.\(measure.rawValue)) AS total, p.*
                FROM photoDay d LEFT JOIN photo p ON p.id = d.photoID
                WHERE d.day BETWEEN ? AND ?
                GROUP BY d.photoID HAVING total > 0
                ORDER BY total DESC, d.photoID LIMIT ?
                """, arguments: [start.text, end.text, limit]).map { row in
                RankedPhoto(photoID: row["photoID"], photo: Self.optionalPhoto(row), total: row["total"])
            }
        }
    }

    /// Views gained in the seven days ending `day` over the seven before.
    public func risingPhotos(endingOn day: StatsDay, limit: Int) throws -> [RisingPhoto] {
        let days = sequence(first: day) { $0.previous }.prefix(14).map(\.text)
        let (recentStart, earlierStart) = (days[6], days[13])
        return try read { db in
            try Row.fetchAll(db, sql: """
                SELECT d.photoID AS photoID,
                       SUM(CASE WHEN d.day >= ? THEN d.views ELSE 0 END) AS thisWeek,
                       SUM(CASE WHEN d.day < ? THEN d.views ELSE 0 END) AS weekBefore, p.*
                FROM photoDay d LEFT JOIN photo p ON p.id = d.photoID
                WHERE d.day BETWEEN ? AND ?
                GROUP BY d.photoID HAVING thisWeek > weekBefore
                ORDER BY thisWeek - weekBefore DESC, d.photoID LIMIT ?
                """, arguments: [recentStart, recentStart, earlierStart, day.text, limit]).map { row in
                RisingPhoto(photoID: row["photoID"], photo: Self.optionalPhoto(row),
                            thisWeek: row["thisWeek"], weekBefore: row["weekBefore"])
            }
        }
    }

    /// The joined photo columns, when the LEFT JOIN found one.
    private static func optionalPhoto(_ row: Row) -> LibraryPhoto? {
        (row["id"] as String?) == nil ? nil : LibrarySchema.photo(row)
    }
}
