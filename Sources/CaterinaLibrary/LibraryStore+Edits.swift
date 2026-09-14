import Foundation
import GRDB

import FlickrKit

/// The edit record: every batch, and each photo's before and after.
extension LibraryStore {

    /// Record `changes`, leaving out any that change nothing. For edits that
    /// differ per photo; never for deleting, which cannot be undone.
    public func createBatch(title: String, changes: [PhotoChange], accountID: String? = nil,
                            now: Date = Date()) throws -> EditBatch {
        try createBatch(title: title, changes: changes, undoes: nil, accountID: accountID, now: now)
    }

    /// Record `edit` applied to `photos`, leaving out any it would not change.
    public func createBatch(title: String, edit: PhotoEdit, photos: [LibraryPhoto],
                            now: Date = Date()) throws -> EditBatch {
        let changes = photos.enumerated().map { index, photo in
            PhotoChange(before: photo,
                        after: edit.applied(to: photo, context: .init(position: index + 1, count: photos.count)))
        }
        return try createBatch(title: title, changes: changes, undoes: nil, accountID: nil, now: now)
    }

    /// A new batch that writes back what `batchID` changed, for every photo
    /// it actually changed, last photo first.
    public func undoBatch(for batchID: String, now: Date = Date()) throws -> EditBatch {
        let original = try batch(batchID)
        guard original.undoes == nil else { throw FlickrError.invalidInput("An undo is not undone; make the edit again.") }
        guard try !undoneBatchIDs().contains(batchID) else {
            throw FlickrError.invalidInput("That edit has already been undone.")
        }
        if original.kind == .albums { return try undoAlbumBatch(original, now: now) }
        if original.kind == .groups { return try undoGroupBatch(original, now: now) }
        if original.kind == .actions { return try undoActionBatch(original, now: now) }
        let changes = try entries(in: batchID)
            .filter { $0.state == .applied || $0.state == .partial }
            .reversed()
            .map(\.change.reversed)
        return try createBatch(title: "Undo \(original.title)", changes: changes,
                               undoes: batchID, accountID: original.accountID, now: now)
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
                SELECT state, COUNT(*) AS n FROM (
                    SELECT state FROM editEntry WHERE batchID = ?
                    UNION ALL SELECT state FROM albumEntry WHERE batchID = ?
                    UNION ALL SELECT state FROM groupEntry WHERE batchID = ?
                    UNION ALL SELECT state FROM actionEntry WHERE batchID = ?)
                GROUP BY state
                """, arguments: [batchID, batchID, batchID, batchID])
            let count = { (state: EditEntry.State) -> Int in
                counts.first { ($0["state"] as String) == state.rawValue }?["n"] ?? 0
            }
            return EditBatch.Summary(applied: count(.applied), failed: count(.failed) + count(.partial),
                                     pending: count(.pending))
        }
    }

    /// Every batch some undo takes back, however old: a limit on the list of
    /// recent batches must not make an undone batch offer Undo again.
    public func undoneBatchIDs() throws -> Set<String> {
        try read { db in Set(try String.fetchAll(db, sql: "SELECT undoes FROM editBatch WHERE undoes IS NOT NULL")) }
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
            guard state == .applied || state == .partial else { return }
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
            try db.execute(sql: """
                UPDATE editEntry SET before = ?, after = ?, rebased = 1 WHERE batchID = ? AND position = ?
                """,
                           arguments: [try Self.json(change.before), try Self.json(change.after),
                                       entry.batchID, entry.position])
        }
        return EditEntry(batchID: entry.batchID, position: entry.position, photoID: entry.photoID,
                         change: change, state: entry.state, message: entry.message, isRebased: true)
    }

    // MARK: - Private

    private func createBatch(title: String, changes: [PhotoChange], undoes: String?, accountID: String?,
                             now: Date) throws -> EditBatch {
        let kept = changes.filter { !$0.isEmpty }
        let id = UUID().uuidString
        try write { db in
            try db.execute(sql: "INSERT INTO editBatch (id, title, createdAt, undoes, accountID) VALUES (?, ?, ?, ?, ?)",
                           arguments: [id, title, now.timeIntervalSince1970, undoes, accountID])
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

    public func batch(_ id: String) throws -> EditBatch {
        try read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM editBatch WHERE id = ?", arguments: [id]) else {
                throw FlickrError.notFound("That edit is no longer in the history.")
            }
            return try Self.batch(row, db)
        }
    }

    private static func batch(_ row: Row, _ db: Database) throws -> EditBatch {
        let id: String = row["id"]
        let kind = EditBatch.Kind(rawValue: row["kind"]) ?? .photos
        let changes = try Row.fetchAll(db, sql: "SELECT * FROM editEntry WHERE batchID = ?", arguments: [id])
            .map(entry)
        let albumCalls = try Row.fetchAll(db, sql: "SELECT * FROM albumEntry WHERE batchID = ?", arguments: [id])
            .map(albumEntry).filter { $0.state == .pending }.reduce(0) { $0 + $1.estimatedCalls }
        let groupCalls = try Int.fetchOne(db, sql: """
            SELECT (SELECT COUNT(*) FROM groupEntry WHERE batchID = ?1 AND state = 'pending')
                 + (SELECT COUNT(*) FROM actionEntry WHERE batchID = ?1 AND state = 'pending')
            """, arguments: [id]) ?? 0
        return EditBatch(id: id, kind: kind, title: row["title"],
                         createdAt: Date(timeIntervalSince1970: row["createdAt"]),
                         undoes: row["undoes"], accountID: row["accountID"],
                         // One read per photo, to lay the change over Flickr's copy.
                         calls: groupCalls + albumCalls + changes.filter { $0.state == .pending }
                            .reduce(0) { $0 + $1.change.readCalls + $1.change.writes.count })
    }

    private static func entry(_ row: Row) throws -> EditEntry {
        let decoder = JSONDecoder()
        let before = try decoder.decode(LibraryPhoto.self, from: Data((row["before"] as String).utf8))
        let after = try decoder.decode(LibraryPhoto.self, from: Data((row["after"] as String).utf8))
        return EditEntry(batchID: row["batchID"], position: row["position"], photoID: row["photoID"],
                         change: PhotoChange(before: before, after: after),
                         state: EditEntry.State(rawValue: row["state"]) ?? .pending,
                         message: row["message"], isRebased: row["rebased"])
    }

    private static func json(_ photo: LibraryPhoto) throws -> String {
        String(decoding: try JSONEncoder().encode(photo), as: UTF8.self)
    }
}
