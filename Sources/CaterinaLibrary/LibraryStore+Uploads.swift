import Foundation
import GRDB

import FlickrKit

/// The upload queue, on disk so it outlives the app.
extension LibraryStore {

    public func createUploadBatch(items: [(file: URL, metadata: UploadMetadata)],
                                  album: UploadBatch.AlbumChoice, files: FileAccess,
                                  now: Date = Date()) throws -> UploadBatch {
        let id = UUID().uuidString
        let (kind, title, albumID): (String, String?, String?) = switch album {
        case .none: ("none", nil, nil)
        case let .new(title): ("new", title, nil)
        case let .existing(id): ("existing", nil, id)
        }
        try write { db in
            try db.execute(sql: "INSERT INTO uploadBatch (id, createdAt, albumKind, albumTitle, albumID) VALUES (?, ?, ?, ?, ?)",
                           arguments: [id, now.timeIntervalSince1970, kind, title, albumID])
            for (position, item) in items.enumerated() {
                try db.execute(sql: """
                    INSERT INTO uploadItem (batchID, position, path, bookmark, metadata, state)
                    VALUES (?, ?, ?, ?, ?, 'queued')
                    """, arguments: [id, position, item.file.path, files.bookmark(for: item.file),
                                     String(decoding: try JSONEncoder().encode(item.metadata), as: UTF8.self)])
            }
        }
        return try uploadBatch(id)
    }

    public func uploadBatch(_ id: String) throws -> UploadBatch {
        try read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM uploadBatch WHERE id = ?", arguments: [id]) else {
                throw FlickrError.notFound("That upload is no longer in the queue.")
            }
            let kind: String = row["albumKind"]
            let album: UploadBatch.AlbumChoice = switch kind {
            case "new": .new(title: row["albumTitle"] ?? "")
            case "existing": .existing(id: row["albumID"] ?? "")
            default: .none
            }
            return UploadBatch(id: id, createdAt: Date(timeIntervalSince1970: row["createdAt"]),
                               album: album, albumID: row["albumID"])
        }
    }

    public func uploadItems(in batchID: String, files: FileAccess = PlainFileAccess()) throws -> [UploadItem] {
        try read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM uploadItem WHERE batchID = ? ORDER BY position",
                             arguments: [batchID]).map { try Self.uploadItem($0, files: files) }
        }
    }

    public func uploadSummary(of batchID: String) throws -> UploadBatch.Summary {
        let states = try uploadItems(in: batchID).map(\.state)
        func count(_ matches: (UploadItem.State) -> Bool) -> Int { states.filter(matches).count }
        return UploadBatch.Summary(
            done: count { if case .done = $0 { true } else { false } },
            failed: count { if case .failed = $0 { true } else { false } },
            remaining: count { switch $0 { case .queued, .sending, .processing: true; default: false } },
            interrupted: count { $0 == .interrupted })
    }

    public func markUpload(_ item: UploadItem, _ state: UploadItem.State) throws {
        let (name, ticket, photoID, message): (String, String?, String?, String?) = switch state {
        case .queued: ("queued", nil, nil, nil)
        case .sending: ("sending", nil, nil, nil)
        case let .processing(ticket): ("processing", ticket, nil, nil)
        case let .done(photoID): ("done", nil, photoID, nil)
        case let .failed(message): ("failed", nil, nil, message)
        case .interrupted: ("interrupted", nil, nil, nil)
        case .alreadyOnFlickr: ("alreadyOnFlickr", nil, nil, nil)
        }
        try write { db in
            try db.execute(sql: """
                UPDATE uploadItem SET state = ?, ticket = ?, photoID = ?, message = ?
                WHERE batchID = ? AND position = ?
                """, arguments: [name, ticket, photoID, message, item.batchID, item.position])
        }
    }

    /// Mark a queued file as being sent, unless something else already has.
    /// The last line of defence against sending one file twice.
    func claimForSending(_ item: UploadItem) throws -> Bool {
        try write { db in
            try db.execute(sql: """
                UPDATE uploadItem SET state = 'sending'
                WHERE batchID = ? AND position = ? AND state = 'queued'
                """, arguments: [item.batchID, item.position])
            return db.changesCount == 1
        }
    }

    /// The person has checked Flickr and wants an interrupted or failed file
    /// sent again.
    public func resend(_ item: UploadItem) throws {
        try markUpload(item, .queued)
    }

    /// Anything still marked as sending belongs to a run that stopped.
    func interruptSending(in batchID: String) throws {
        try write { db in
            try db.execute(sql: "UPDATE uploadItem SET state = 'interrupted' WHERE batchID = ? AND state = 'sending'",
                           arguments: [batchID])
        }
    }

    func recordAlbum(_ albumID: String, for batchID: String) throws {
        try write { db in
            try db.execute(sql: "UPDATE uploadBatch SET albumID = ? WHERE id = ?", arguments: [albumID, batchID])
        }
    }

    func markInAlbum(_ item: UploadItem) throws {
        try write { db in
            try db.execute(sql: "UPDATE uploadItem SET inAlbum = 1 WHERE batchID = ? AND position = ?",
                           arguments: [item.batchID, item.position])
        }
    }

    private static func uploadItem(_ row: Row, files: FileAccess) throws -> UploadItem {
        let name: String = row["state"]
        let state: UploadItem.State = switch name {
        case "sending": .sending
        case "processing": .processing(ticket: row["ticket"] ?? "")
        case "done": .done(photoID: row["photoID"] ?? "")
        case "failed": .failed(row["message"] ?? "")
        case "interrupted": .interrupted
        case "alreadyOnFlickr": .alreadyOnFlickr
        default: .queued
        }
        return UploadItem(
            batchID: row["batchID"], position: row["position"],
            file: files.resolve(bookmark: row["bookmark"], path: row["path"]),
            metadata: try JSONDecoder().decode(UploadMetadata.self, from: Data((row["metadata"] as String).utf8)),
            state: state, inAlbum: row["inAlbum"])
    }
}

extension LibraryStore {
    /// Batches with work left: a file not yet sent or processed, an interrupted
    /// one waiting on the person, or a done photo not yet in its album. Newest
    /// first.
    public func unfinishedUploadBatchIDs() throws -> [String] {
        try read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT b.id FROM uploadBatch b JOIN uploadItem i ON i.batchID = b.id
                WHERE i.state IN ('queued', 'sending', 'processing', 'interrupted')
                   OR (i.state = 'done' AND i.inAlbum = 0 AND b.albumKind != 'none')
                ORDER BY b.createdAt DESC, b.rowid DESC
                """)
        }
    }
}
