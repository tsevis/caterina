import Foundation
import GRDB

import FlickrKit

/// One rotation, person or deletion for one photo, and how it went.
public struct ActionEntry: Sendable, Equatable {
    public let batchID: String
    public let position: Int
    public let photoID: String
    public let action: PhotoAction
    public let state: EditEntry.State
    public let message: String?
    /// Sent and not yet recorded: it may have happened.
    public let isSending: Bool
}

extension LibraryStore {

    /// Deleting is never mixed with anything else: it has no undo.
    public func createActionBatch(title: String, action: PhotoAction, photoIDs: [String], accountID: String?,
                                  now: Date = Date()) throws -> EditBatch {
        try createActionBatch(title: title, entries: photoIDs.map { ($0, action) }, accountID: accountID,
                              undoes: nil, now: now)
    }

    public func actionEntries(in batchID: String) throws -> [ActionEntry] {
        try read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM actionEntry WHERE batchID = ? ORDER BY position",
                             arguments: [batchID]).map { row in
                ActionEntry(batchID: row["batchID"], position: row["position"], photoID: row["photoID"],
                            action: try JSONDecoder().decode(PhotoAction.self, from: Data((row["action"] as String).utf8)),
                            state: EditEntry.State(rawValue: row["state"]) ?? .pending, message: row["message"],
                            isSending: row["sending"])
            }
        }
    }

    /// Whether any applied entry has an undo. False for deleting.
    public func canUndo(_ batchID: String) throws -> Bool {
        try actionEntries(in: batchID).contains { $0.state == .applied && $0.action.undo != nil }
    }

    /// Just before a call whose reply might be lost.
    public func markSending(_ entry: ActionEntry) throws {
        try write { db in
            try db.execute(sql: "UPDATE actionEntry SET sending = 1 WHERE batchID = ? AND position = ?",
                           arguments: [entry.batchID, entry.position])
        }
    }

    func recordAction(_ entry: ActionEntry, as state: EditEntry.State, message: String? = nil) throws {
        try write { db in
            try db.execute(sql: "UPDATE actionEntry SET state = ?, message = ?, sending = 0 WHERE batchID = ? AND position = ?",
                           arguments: [state.rawValue, message, entry.batchID, entry.position])
            if state == .applied, entry.action == .delete {
                try db.execute(sql: "DELETE FROM photo WHERE id = ?", arguments: [entry.photoID])
            }
        }
    }

    func undoActionBatch(_ original: EditBatch, now: Date) throws -> EditBatch {
        let entries = try actionEntries(in: original.id).filter { $0.state == .applied }.reversed()
        let undos = entries.compactMap { entry in entry.action.undo.map { (entry.photoID, $0) } }
        guard !undos.isEmpty else {
            throw FlickrError.invalidInput("Deleted photos cannot be brought back.")
        }
        return try createActionBatch(title: "Undo \(original.title)", entries: undos, accountID: original.accountID,
                                     undoes: original.id, now: now)
    }

    private func createActionBatch(title: String, entries: [(String, PhotoAction)], accountID: String?,
                                   undoes: String?, now: Date) throws -> EditBatch {
        let id = UUID().uuidString
        let encoder = JSONEncoder()
        try write { db in
            try db.execute(sql: """
                INSERT INTO editBatch (id, kind, title, createdAt, undoes, accountID) VALUES (?, 'actions', ?, ?, ?, ?)
                """, arguments: [id, title, now.timeIntervalSince1970, undoes, accountID])
            for (position, (photo, action)) in entries.enumerated() {
                try db.execute(sql: """
                    INSERT INTO actionEntry (batchID, position, photoID, action, state) VALUES (?, ?, ?, ?, 'pending')
                    """, arguments: [id, position, photo, String(decoding: try encoder.encode(action), as: UTF8.self)])
            }
        }
        return try batch(id)
    }
}
