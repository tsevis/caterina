import Foundation
import GRDB

import FlickrKit

/// Every photo in your library, in SQLite.
///
/// A copy, never the truth: Flickr is. It exists so Organize can filter twenty
/// thousand photos without twenty thousand calls, and so history can be kept
/// that Flickr itself discards.
public final class LibraryStore: Sendable {
    private let database: DatabaseQueue

    /// The copy on disk, created with its folder if it is not there yet.
    public convenience init(file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try self.init(database: DatabaseQueue(path: file.path))
    }

    public static func inMemory() throws -> LibraryStore {
        try LibraryStore(database: DatabaseQueue())
    }

    init(database: DatabaseQueue) throws {
        self.database = database
        try LibrarySchema.migrator.migrate(database)
    }

    /// Where the app keeps it: its own Application Support folder, which the
    /// sandbox puts inside the app's container.
    public static func defaultFile() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Library.sqlite")
    }

    func read<T>(_ work: (Database) throws -> T) throws -> T {
        try database.read(work)
    }

    func write<T>(_ work: (Database) throws -> T) throws -> T {
        try database.write(work)
    }

    // MARK: - Writing

    /// Insert or replace, marking each photo as seen by `generation`.
    public func save(_ photos: [LibraryPhoto], generation: Int) throws {
        try database.write { db in
            let statement = try db.cachedStatement(sql: LibrarySchema.upsert)
            for photo in photos {
                try statement.execute(arguments: LibrarySchema.arguments(photo, generation: generation))
            }
        }
    }

    /// Remove photos the full sync numbered `generation` did not see. Returns
    /// how many.
    @discardableResult
    public func removePhotos(olderThan generation: Int) throws -> Int {
        try database.write { db in
            try db.execute(sql: "DELETE FROM photo WHERE generation < ?", arguments: [generation])
            return db.changesCount
        }
    }

    public func save(_ state: LibrarySyncState) throws {
        try database.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO syncState (id, generation, lastFullSync, changesSince, lastSynced)
                VALUES (1, ?, ?, ?, ?)
                """, arguments: [state.generation, state.lastFullSync?.timeIntervalSince1970,
                                 state.changesSince?.timeIntervalSince1970,
                                 state.lastSynced?.timeIntervalSince1970])
        }
    }

    // MARK: - Reading

    public func photos(_ filter: LibraryFilter, order: LibraryOrder = .newestTaken,
                       limit: Int? = nil, offset: Int = 0) throws -> [LibraryPhoto] {
        let condition = LibrarySchema.condition(filter)
        var sql = "SELECT * FROM photo WHERE \(condition.sql) ORDER BY \(LibrarySchema.orderClause(order))"
        var arguments = condition.arguments
        if let limit {
            sql += " LIMIT ? OFFSET ?"
            arguments += [limit, offset]
        }
        return try database.read { db in
            try Row.fetchAll(db, sql: sql, arguments: arguments).map(LibrarySchema.photo)
        }
    }

    /// Every tag with how many photos carry it, most used first.
    public func tagCounts() throws -> [TagCount] {
        let lists = try database.read { db in try String.fetchAll(db, sql: "SELECT tags FROM photo WHERE tags != ''") }
        let counts = lists.reduce(into: [String: Int]()) { counts, list in
            for tag in list.split(separator: " ") { counts[String(tag), default: 0] += 1 }
        }
        return counts.map { TagCount(tag: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    }

    /// Months photos were taken in, newest first. Undated photos are in none.
    public func monthCounts() throws -> [MonthCount] {
        try database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT substr(taken, 1, 7) AS month, COUNT(*) AS n FROM photo
                WHERE taken IS NOT NULL GROUP BY month ORDER BY month DESC
                """).map { MonthCount(month: $0["month"], count: $0["n"]) }
        }
    }

    /// Months photos were posted in (GMT), newest first.
    public func uploadedMonthCounts() throws -> [MonthCount] {
        try database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT strftime('%Y-%m', uploaded, 'unixepoch') AS month, COUNT(*) AS n FROM photo
                WHERE uploaded IS NOT NULL GROUP BY month ORDER BY month DESC
                """).map { MonthCount(month: $0["month"], count: $0["n"]) }
        }
    }

    /// Photos by id, in the order given; ids not in the copy are left out.
    public func photos(ids: [String]) throws -> [LibraryPhoto] {
        guard !ids.isEmpty else { return [] }
        let found = try database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM photo WHERE id IN (\(databaseQuestionMarks(count: ids.count)))",
                             arguments: StatementArguments(ids)).map(LibrarySchema.photo)
        }
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    public func photo(id: String) throws -> LibraryPhoto? {
        try database.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM photo WHERE id = ?", arguments: [id]).map(LibrarySchema.photo)
        }
    }

    public func count(_ filter: LibraryFilter) throws -> Int {
        let condition = LibrarySchema.condition(filter)
        return try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo WHERE \(condition.sql)",
                             arguments: condition.arguments) ?? 0
        }
    }

    public func syncState() throws -> LibrarySyncState {
        try database.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM syncState WHERE id = 1") else {
                return .never
            }
            return LibrarySyncState(
                generation: row["generation"],
                lastFullSync: (row["lastFullSync"] as Double?).map(Date.init(timeIntervalSince1970:)),
                changesSince: (row["changesSince"] as Double?).map(Date.init(timeIntervalSince1970:)),
                lastSynced: (row["lastSynced"] as Double?).map(Date.init(timeIntervalSince1970:)))
        }
    }
}
