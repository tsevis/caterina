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
            photo.thumbnailURL, generation,
        ]
    }

    static let upsert = """
        INSERT OR REPLACE INTO photo
        (id, title, description, tags, license, isPublic, isFriend, isFamily, uploaded,
         lastUpdated, taken, views, media, latitude, longitude, accuracy, thumbnailURL, generation)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            thumbnailURL: row["thumbnailURL"])
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
            return (#"tags LIKE ? ESCAPE '\'"#, ["% \(escapeLike(tag.lowercased())) %"])
        case let .matching(text):
            let pattern = "%\(escapeLike(text))%"
            return (#"(title LIKE ? ESCAPE '\' OR description LIKE ? ESCAPE '\' OR tags LIKE ? ESCAPE '\')"#,
                    [pattern, pattern, pattern])
        }
    }

    static func orderClause(_ order: LibraryOrder) -> String {
        switch order {
        // Unknown dates last in both directions, then by id for a stable page.
        case .newestTaken: "taken IS NULL, taken DESC, id"
        case .oldestTaken: "taken IS NULL, taken ASC, id"
        case .newestUploaded: "uploaded IS NULL, uploaded DESC, id"
        case .mostViewed: "views DESC, id"
        }
    }

    /// Typed `%` and `_` are text, not wildcards.
    private static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
