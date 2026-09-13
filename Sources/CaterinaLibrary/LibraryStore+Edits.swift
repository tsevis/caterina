import Foundation
import GRDB

import FlickrKit

/// The edit record: every batch, and each photo's before and after.
extension LibraryStore {

    /// Record `edit` applied to `photos`, leaving out any it would not change.
    public func createBatch(title: String, edit: PhotoEdit, photos: [LibraryPhoto],
                            now: Date = Date()) throws -> EditBatch {
        let changes = photos.map { PhotoChange(before: $0, after: edit.applied(to: $0)) }
        return try createBatch(title: title, changes: changes, undoes: nil, now: now)
    }

    /// A new batch that writes back what `batchID` changed, for every photo
    /// it actually changed, last photo first.
    public func undoBatch(for batchID: String, now: Date = Date()) throws -> EditBatch {
        let original = try batch(batchID)
        let changes = try entries(in: batchID)
            .filter { $0.state == .applied }
            .reversed()
            .map(\.change.reversed)
        return try createBatch(title: "Undo \(original.title)", changes: changes,
                               undoes: batchID, now: now)
    }

    public func entries(in batchID: String) throws -> [EditEntry] {
        try read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM editEntry WHERE batchID = ? ORDER BY position",
                             arguments: [batchID]).map(Self.entry)
        }
    }

    public func summary(of batchID: String) throws -> EditBatch.Summary {
        try read { db in
            let counts = try Row.fetchAll(db, sql: """
                SELECT state, COUNT(*) AS n FROM editEntry WHERE batchID = ? GROUP BY state
                """, arguments: [batchID])
            let count = { (state: EditEntry.State) -> Int in
                counts.first { ($0["state"] as String) == state.rawValue }?["n"] ?? 0
            }
            return EditBatch.Summary(applied: count(.applied), failed: count(.failed), pending: count(.pending))
        }
    }

    public func recentBatches(limit: Int) throws -> [EditBatch] {
        try read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM editBatch ORDER BY createdAt DESC, rowid DESC LIMIT ?",
                             arguments: [limit]).map { try Self.batch($0, db) }
        }
    }

    /// Mark one entry, and when it was applied, keep the local copy in step.
    func record(_ entry: EditEntry, as state: EditEntry.State, message: String? = nil) throws {
        try write { db in
            try db.execute(sql: "UPDATE editEntry SET state = ?, message = ? WHERE batchID = ? AND position = ?",
                           arguments: [state.rawValue, message, entry.batchID, entry.position])
            guard state == .applied else { return }
            let row = try Row.fetchOne(db, sql: "SELECT * FROM photo WHERE id = ?", arguments: [entry.photoID])
            let local = row.map(LibrarySchema.photo)
            let photo = local.map { $0.withEditableFields(of: entry.change.after) } ?? entry.change.after
            try db.execute(sql: LibrarySchema.upsert,
                           arguments: LibrarySchema.arguments(photo.withCleanTags,
                                                              generation: row?["generation"] ?? 0))
        }
    }

    /// The entry with `change` in place of what was recorded: the same edit,
    /// laid over the photo as Flickr has it.
    func replaceChange(of entry: EditEntry, with change: PhotoChange) throws -> EditEntry {
        try write { db in
            try db.execute(sql: "UPDATE editEntry SET before = ?, after = ? WHERE batchID = ? AND position = ?",
                           arguments: [try Self.json(change.before), try Self.json(change.after),
                                       entry.batchID, entry.position])
        }
        return EditEntry(batchID: entry.batchID, position: entry.position, photoID: entry.photoID,
                         change: change, state: entry.state, message: entry.message)
    }

    // MARK: - Private

    private func createBatch(title: String, changes: [PhotoChange], undoes: String?,
                             now: Date) throws -> EditBatch {
        let kept = changes.filter { !$0.isEmpty }
        let id = UUID().uuidString
        try write { db in
            try db.execute(sql: "INSERT INTO editBatch (id, title, createdAt, undoes) VALUES (?, ?, ?, ?)",
                           arguments: [id, title, now.timeIntervalSince1970, undoes])
            for (position, change) in kept.enumerated() {
                try db.execute(sql: """
                    INSERT INTO editEntry (batchID, position, photoID, before, after, state)
                    VALUES (?, ?, ?, ?, ?, 'pending')
                    """, arguments: [id, position, change.after.id,
                                     try Self.json(change.before), try Self.json(change.after)])
            }
        }
        return try batch(id)
    }

    private func batch(_ id: String) throws -> EditBatch {
        try read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM editBatch WHERE id = ?", arguments: [id]) else {
                throw FlickrError.notFound("That edit is no longer in the history.")
            }
            return try Self.batch(row, db)
        }
    }

    private static func batch(_ row: Row, _ db: Database) throws -> EditBatch {
        let id: String = row["id"]
        let changes = try Row.fetchAll(db, sql: "SELECT * FROM editEntry WHERE batchID = ?", arguments: [id])
            .map(entry)
        return EditBatch(id: id, title: row["title"],
                         createdAt: Date(timeIntervalSince1970: row["createdAt"]),
                         undoes: row["undoes"],
                         // One read per photo, to lay the change over Flickr's copy.
                         calls: changes.reduce(0) { $0 + 1 + $1.change.writes.count })
    }

    private static func entry(_ row: Row) throws -> EditEntry {
        let decoder = JSONDecoder()
        let before = try decoder.decode(LibraryPhoto.self, from: Data((row["before"] as String).utf8))
        let after = try decoder.decode(LibraryPhoto.self, from: Data((row["after"] as String).utf8))
        return EditEntry(batchID: row["batchID"], position: row["position"], photoID: row["photoID"],
                         change: PhotoChange(before: before, after: after),
                         state: EditEntry.State(rawValue: row["state"]) ?? .pending,
                         message: row["message"])
    }

    private static func json(_ photo: LibraryPhoto) throws -> String {
        String(decoding: try JSONEncoder().encode(photo), as: UTF8.self)
    }
}
