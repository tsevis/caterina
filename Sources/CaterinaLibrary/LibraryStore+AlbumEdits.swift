import Foundation
import GRDB

import FlickrKit

/// Album edits in the edit record, beside photo batches.
extension LibraryStore {

    public func createAlbumBatch(title: String, edits: [AlbumEdit], accountID: String?,
                                 undoes: String? = nil, now: Date = Date()) throws -> EditBatch {
        let id = UUID().uuidString
        try write { db in
            try db.execute(sql: """
                INSERT INTO editBatch (id, kind, title, createdAt, undoes, accountID) VALUES (?, 'albums', ?, ?, ?, ?)
                """, arguments: [id, title, now.timeIntervalSince1970, undoes, accountID])
            for (position, edit) in edits.enumerated() {
                try db.execute(sql: """
                    INSERT INTO albumEntry (batchID, position, edit, state) VALUES (?, ?, ?, 'pending')
                    """, arguments: [id, position, try Self.json(edit)])
            }
        }
        return try batch(id)
    }

    public func albumEntries(in batchID: String) throws -> [AlbumEntry] {
        try read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM albumEntry WHERE batchID = ? ORDER BY position",
                             arguments: [batchID]).map(Self.albumEntry)
        }
    }

    /// Every edit that changed something, taken back last first.
    func undoAlbumBatch(_ original: EditBatch, now: Date) throws -> EditBatch {
        let edits = try albumEntries(in: original.id)
            .filter { $0.done > 0 || $0.state == .applied }
            .reversed()
            .flatMap { try $0.undo() }
        return try createAlbumBatch(title: "Undo \(original.title)", edits: edits, accountID: original.accountID,
                                    undoes: original.id, now: now)
    }

    func recordSnapshot(_ snapshot: AlbumSnapshot, for entry: AlbumEntry) throws -> AlbumEntry {
        try update(entry, sql: "snapshot = ?", [try Self.json(snapshot)])
        return try albumEntry(entry)
    }

    func recordStep(_ entry: AlbumEntry, createdAlbumID: String? = nil) throws -> AlbumEntry {
        try update(entry, sql: "done = done + 1, createdAlbumID = COALESCE(?, createdAlbumID)", [createdAlbumID])
        return try albumEntry(entry)
    }

    func recordAlbum(_ entry: AlbumEntry, as state: EditEntry.State, message: String? = nil) throws {
        try update(entry, sql: "state = ?, message = ?", [state.rawValue, message])
    }

    private func update(_ entry: AlbumEntry, sql: String, _ values: [(any DatabaseValueConvertible)?]) throws {
        try write { db in
            try db.execute(sql: "UPDATE albumEntry SET \(sql) WHERE batchID = ? AND position = ?",
                           arguments: StatementArguments(values + [entry.batchID, entry.position]))
        }
    }

    private func albumEntry(_ entry: AlbumEntry) throws -> AlbumEntry {
        try read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM albumEntry WHERE batchID = ? AND position = ?",
                                             arguments: [entry.batchID, entry.position]) else {
                throw FlickrError.notFound("That album edit is no longer in the history.")
            }
            return try Self.albumEntry(row)
        }
    }

    static func albumEntry(_ row: Row) throws -> AlbumEntry {
        let decoder = JSONDecoder()
        let snapshot = try (row["snapshot"] as String?).map {
            try decoder.decode(AlbumSnapshot.self, from: Data($0.utf8))
        }
        return AlbumEntry(batchID: row["batchID"], position: row["position"],
                          edit: try decoder.decode(AlbumEdit.self, from: Data((row["edit"] as String).utf8)),
                          snapshot: snapshot, done: row["done"], createdAlbumID: row["createdAlbumID"],
                          state: EditEntry.State(rawValue: row["state"]) ?? .pending, message: row["message"])
    }

    private static func json<Value: Encodable>(_ value: Value) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
}
