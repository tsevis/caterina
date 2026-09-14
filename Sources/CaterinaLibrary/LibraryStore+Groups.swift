import Foundation
import GRDB

import FlickrKit

/// Group batches, saved group sets, and group rules read recently.
extension LibraryStore {

    public func createGroupBatch(title: String, adding pairs: [GroupPair], accountID: String?,
                                 undoes: String? = nil, now: Date = Date()) throws -> EditBatch {
        try createGroupBatch(title: title, pairs: pairs.map { ($0, .add) }, accountID: accountID, undoes: undoes, now: now)
    }

    public func createGroupBatch(title: String, removing pairs: [GroupPair], accountID: String?,
                                 undoes: String? = nil, now: Date = Date()) throws -> EditBatch {
        try createGroupBatch(title: title, pairs: pairs.map { ($0, .remove) }, accountID: accountID, undoes: undoes, now: now)
    }

    public func groupEntries(in batchID: String) throws -> [GroupEntry] {
        try read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM groupEntry WHERE batchID = ? ORDER BY position",
                             arguments: [batchID]).map(Self.groupEntry)
        }
    }

    public func groupShareReport(of batchID: String) throws -> [GroupShareReport.Row] {
        GroupShareReport.rows(try groupEntries(in: batchID))
    }

    func recordGroup(_ entry: GroupEntry, _ outcome: GroupShareOutcome) throws {
        let data = String(decoding: try JSONEncoder().encode(outcome), as: UTF8.self)
        try write { db in
            try db.execute(sql: "UPDATE groupEntry SET state = ?, outcome = ?, sending = 0 WHERE batchID = ? AND position = ?",
                           arguments: [outcome.isSuccess ? "applied" : "failed", data, entry.batchID, entry.position])
        }
    }

    /// Just before a call whose reply might be lost.
    public func markSending(_ entry: GroupEntry) throws {
        try write { db in
            try db.execute(sql: "UPDATE groupEntry SET sending = 1 WHERE batchID = ? AND position = ?",
                           arguments: [entry.batchID, entry.position])
        }
    }

    /// Rules to read again: a batch just used some of each group's room.
    /// Names stay, for reports.
    public func forgetGroupProfiles(_ ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try write { db in
            try db.execute(sql: "UPDATE groupProfile SET readAt = 0 WHERE id IN (\(databaseQuestionMarks(count: ids.count)))",
                           arguments: StatementArguments(ids))
        }
    }

    /// What was placed comes out; what was removed goes back. Last first.
    func undoGroupBatch(_ original: EditBatch, now: Date) throws -> EditBatch {
        let entries = try groupEntries(in: original.id).reversed()
        let pairs = entries.compactMap { entry -> (GroupPair, GroupEntry.Action)? in
            guard let outcome = entry.outcome else { return nil }
            if entry.action == .add, outcome.placedByThisBatch { return (entry.pair, .remove) }
            if entry.action == .remove, outcome.removedByThisBatch { return (entry.pair, .add) }
            return nil
        }
        return try createGroupBatch(title: "Undo \(original.title)", pairs: pairs, accountID: original.accountID,
                                    undoes: original.id, now: now)
    }

    // MARK: - Group sets

    public func saveGroupSet(named name: String, groupIDs: [String]) throws {
        let ids = String(decoding: try JSONEncoder().encode(groupIDs), as: UTF8.self)
        try write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO groupSet (name, groupIDs) VALUES (?, ?)", arguments: [name, ids])
        }
    }

    public func groupSets() throws -> [GroupSet] {
        try read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM groupSet ORDER BY name COLLATE NOCASE").map { row in
                GroupSet(name: row["name"],
                         groupIDs: try JSONDecoder().decode([String].self, from: Data((row["groupIDs"] as String).utf8)))
            }
        }
    }

    public func deleteGroupSet(named name: String) throws {
        try write { db in try db.execute(sql: "DELETE FROM groupSet WHERE name = ?", arguments: [name]) }
    }

    // MARK: - Group rules

    public func saveGroupProfiles(_ profiles: [GroupProfile], readAt: Date) throws {
        let encoder = JSONEncoder()
        try write { db in
            for profile in profiles {
                try db.execute(sql: "INSERT OR REPLACE INTO groupProfile (id, profile, readAt) VALUES (?, ?, ?)",
                               arguments: [profile.id, String(decoding: try encoder.encode(profile), as: UTF8.self),
                                           readAt.timeIntervalSince1970])
            }
        }
    }

    /// Those read after `freshAfter`; the rest need reading again.
    public func groupProfiles(ids: [String], freshAfter: Date) throws -> [GroupProfile] {
        guard !ids.isEmpty else { return [] }
        return try read { db in
            try Row.fetchAll(db, sql: """
                SELECT profile FROM groupProfile WHERE readAt > ? AND id IN (\(databaseQuestionMarks(count: ids.count)))
                """, arguments: StatementArguments([freshAfter.timeIntervalSince1970] + ids)).map {
                try JSONDecoder().decode(GroupProfile.self, from: Data(($0["profile"] as String).utf8))
            }
        }
    }

    // MARK: - Private

    private func createGroupBatch(title: String, pairs: [(GroupPair, GroupEntry.Action)], accountID: String?,
                                  undoes: String?, now: Date) throws -> EditBatch {
        let id = UUID().uuidString
        try write { db in
            try db.execute(sql: """
                INSERT INTO editBatch (id, kind, title, createdAt, undoes, accountID) VALUES (?, 'groups', ?, ?, ?, ?)
                """, arguments: [id, title, now.timeIntervalSince1970, undoes, accountID])
            for (position, (pair, action)) in pairs.enumerated() {
                try db.execute(sql: """
                    INSERT INTO groupEntry (batchID, position, photoID, groupID, action, state)
                    VALUES (?, ?, ?, ?, ?, 'pending')
                    """, arguments: [id, position, pair.photoID, pair.groupID, action.rawValue])
            }
        }
        return try batch(id)
    }

    private static func groupEntry(_ row: Row) throws -> GroupEntry {
        let outcome = try (row["outcome"] as String?).map {
            try JSONDecoder().decode(GroupShareOutcome.self, from: Data($0.utf8))
        }
        return GroupEntry(batchID: row["batchID"], position: row["position"],
                          pair: GroupPair(photoID: row["photoID"], groupID: row["groupID"]),
                          action: GroupEntry.Action(rawValue: row["action"]) ?? .add,
                          state: EditEntry.State(rawValue: row["state"]) ?? .pending, outcome: outcome,
                          isSending: row["sending"])
    }
}
