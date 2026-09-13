import Foundation
import GRDB

import FlickrKit

/// The tables, and turning rows into photos and back.
enum LibrarySchema {

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-photos") { db in
            try db.create(table: "photo") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("description", .text).notNull()
                // Space-wrapped (" sea blue "), so a whole tag is `LIKE '% sea %'`.
                t.column("tags", .text).notNull()
                t.column("license", .text)
                t.column("isPublic", .boolean).notNull()
                t.column("isFriend", .boolean).notNull()
                t.column("isFamily", .boolean).notNull()
                t.column("uploaded", .double)
                t.column("lastUpdated", .double)
                t.column("taken", .text).indexed()
                t.column("views", .integer).notNull().indexed()
                t.column("media", .text).notNull()
                t.column("latitude", .double)
                t.column("longitude", .double)
                t.column("accuracy", .integer)
                t.column("thumbnailURL", .text)
                t.column("generation", .integer).notNull().indexed()
            }
            try db.create(table: "syncState") { t in
                t.primaryKey("id", .integer)
                t.column("generation", .integer).notNull()
                t.column("lastFullSync", .double)
                t.column("changesSince", .double)
                t.column("lastSynced", .double)
            }
        }
        migrator.registerMigration("v2-edit-batches") { db in
            try db.create(table: "editBatch") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("createdAt", .double).notNull().indexed()
                t.column("undoes", .text)
            }
            try db.create(table: "editEntry") { t in
                t.column("batchID", .text).notNull().references("editBatch", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.column("photoID", .text).notNull()
                // The whole photo before and after, as JSON: undo needs nothing else.
                t.column("before", .text).notNull()
                t.column("after", .text).notNull()
                t.column("state", .text).notNull()
                t.column("message", .text)
                t.primaryKey(["batchID", "position"])
            }
        }
        migrator.registerMigration("v3-uploads") { db in
            try db.create(table: "uploadBatch") { t in
                t.primaryKey("id", .text)
                t.column("createdAt", .double).notNull().indexed()
                // "none", "new" or "existing"; with the title or id it needs.
                t.column("albumKind", .text).notNull()
                t.column("albumTitle", .text)
                // For "new", filled in once the album has been made.
                t.column("albumID", .text)
            }
            try db.create(table: "uploadItem") { t in
                t.column("batchID", .text).notNull().references("uploadBatch", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.column("path", .text).notNull()
                // A security-scoped bookmark, so a relaunch can still read a
                // file that was dropped on the window.
                t.column("bookmark", .blob)
                t.column("metadata", .text).notNull()
                t.column("state", .text).notNull()
                t.column("ticket", .text)
                t.column("photoID", .text)
                t.column("inAlbum", .boolean).notNull().defaults(to: false)
                t.column("message", .text)
                t.primaryKey(["batchID", "position"])
            }
        }
        migrator.registerMigration("v4-stats-history") { db in
            // A photo's numbers for a day it had any. A day saved with no row
            // for a photo is a day that photo had none.
            try db.create(table: "photoDay") { t in
                t.column("photoID", .text).notNull()
                t.column("day", .text).notNull().indexed()
                t.column("views", .integer).notNull()
                t.column("comments", .integer).notNull()
                t.column("faves", .integer).notNull()
                t.primaryKey(["photoID", "day"])
            }
            // Written last, in the same transaction as the day's photos: a
            // row here is what makes a day saved.
            try db.create(table: "accountDay") { t in
                t.primaryKey("day", .text)
                t.column("total", .integer).notNull()
                t.column("photos", .integer).notNull()
                t.column("photostream", .integer).notNull()
                t.column("albums", .integer).notNull()
                t.column("collections", .integer).notNull()
            }
        }
        migrator.registerMigration("v5-medium-thumbnails") { db in
            try db.alter(table: "photo") { t in t.add(column: "mediumURL", .text) }
            // Rows synced before this have no larger thumbnail: make the next
            // sync a full one so every photo gets it.
            try db.execute(sql: "UPDATE syncState SET lastFullSync = NULL")
        }
        migrator.registerMigration("v6-fans") { db in
            // Who faved which of your photos, and when: the People view.
            try db.create(table: "fave") { t in
                t.column("photoID", .text).notNull()
                t.column("nsid", .text).notNull().indexed()
                t.column("username", .text).notNull()
                t.column("date", .double).notNull().indexed()
                t.primaryKey(["photoID", "nsid"])
            }
            try db.create(table: "faveScan") { t in
                t.primaryKey("photoID", .text)
                t.column("readAt", .double).notNull()
            }
        }
        migrator.registerMigration("v7-not-in-album") { db in
            try db.create(table: "notInAlbum") { t in
                t.primaryKey("photoID", .text)
            }
            try db.create(table: "notInAlbumState") { t in
                t.primaryKey("id", .integer)
                t.column("readAt", .double).notNull()
            }
        }
        return migrator
    }

    static func arguments(_ photo: LibraryPhoto, generation: Int) -> StatementArguments {
        [
            photo.id, photo.title, photo.description,
            photo.tags.isEmpty ? "" : " \(photo.tags.joined(separator: " ")) ",
            photo.license?.rawValue,
            photo.visibility.isPublic, photo.visibility.isFriend, photo.visibility.isFamily,
            photo.uploaded?.timeIntervalSince1970, photo.lastUpdated?.timeIntervalSince1970,
            photo.taken, photo.views, photo.media.rawValue,
            photo.location?.latitude, photo.location?.longitude, photo.location?.accuracy,
            photo.thumbnailURL, generation, photo.mediumURL,
        ]
    }

    static let upsert = """
        INSERT OR REPLACE INTO photo
        (id, title, description, tags, license, isPublic, isFriend, isFamily, uploaded,
         lastUpdated, taken, views, media, latitude, longitude, accuracy, thumbnailURL, generation, mediumURL)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

    static func photo(_ row: Row) -> LibraryPhoto {
        let tags: String = row["tags"]
        let latitude: Double? = row["latitude"]
        let longitude: Double? = row["longitude"]
        return LibraryPhoto(
            id: row["id"], title: row["title"], description: row["description"],
            tags: tags.split(separator: " ").map(String.init),
            license: (row["license"] as String?).flatMap(License.init(rawValue:)),
            visibility: .init(isPublic: row["isPublic"], isFriend: row["isFriend"],
                              isFamily: row["isFamily"]),
            uploaded: (row["uploaded"] as Double?).map(Date.init(timeIntervalSince1970:)),
            lastUpdated: (row["lastUpdated"] as Double?).map(Date.init(timeIntervalSince1970:)),
            taken: row["taken"], views: row["views"],
            media: LibraryPhoto.Media(rawValue: row["media"]) ?? .photo,
            location: latitude.flatMap { latitude in
                longitude.map { .init(latitude: latitude, longitude: $0, accuracy: row["accuracy"] ?? 0) }
            },
            thumbnailURL: row["thumbnailURL"],
            mediumURL: row["mediumURL"])
    }

    /// The `WHERE` clause and its arguments for `filter`.
    static func condition(_ filter: LibraryFilter) -> (sql: String, arguments: StatementArguments) {
        switch filter {
        case .all:
            return ("1", [])
        case .untagged:
            return ("tags = ''", [])
        case .withoutLocation:
            return ("latitude IS NULL", [])
        case .withLocation:
            return ("latitude IS NOT NULL", [])
        case let .tagged(tag):
            return (#"tags LIKE ? ESCAPE '\'"#, ["% \(escapeLike(PhotoEdit.flickrTag(tag))) %"])
        case let .takenIn(period):
            return (#"taken LIKE ? ESCAPE '\'"#, ["\(escapeLike(period))%"])
        case let .licensed(license):
            return ("license = ?", [license.rawValue])
        case let .seenBy(audience):
            switch audience {
            case .everyone: return ("isPublic = 1", [])
            case .friendsOrFamily: return ("isPublic = 0 AND (isFriend = 1 OR isFamily = 1)", [])
            case .onlyYou: return ("isPublic = 0 AND isFriend = 0 AND isFamily = 0", [])
            }
        case .videos:
            return ("media = 'video'", [])
        case .notInAlbum:
            return ("id IN (SELECT photoID FROM notInAlbum)", [])
        case let .matching(text):
            // SQLite's LIKE folds case for ASCII only; GRDB's Swift lowercase
            // does every alphabet, so both sides are lowered by it.
            let pattern = "%\(escapeLike(text.lowercased()))%"
            return (#"""
                (swiftLowercaseString(title) LIKE ? ESCAPE '\'
                 OR swiftLowercaseString(description) LIKE ? ESCAPE '\'
                 OR tags LIKE ? ESCAPE '\')
                """#, [pattern, pattern, pattern])
        }
    }

    static func orderClause(_ order: LibraryOrder) -> String {
        switch order {
        // Unknown dates last in both directions, then by id for a stable page.
        case .newestTaken: "taken IS NULL, taken DESC, id"
        case .oldestTaken: "taken IS NULL, taken ASC, id"
        case .newestUploaded: "uploaded IS NULL, uploaded DESC, id"
        case .mostViewed: "views DESC, id"
        case .recentlyUpdated: "lastUpdated IS NULL, lastUpdated DESC, id"
        }
    }

    /// Typed `%` and `_` are text, not wildcards.
    private static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
