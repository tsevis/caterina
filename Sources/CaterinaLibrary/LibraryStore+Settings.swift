import Foundation
import GRDB

/// Small values kept beside the library copy, such as saved views.
extension LibraryStore {

    public func setting(_ key: String) throws -> Data? {
        try read { db in try Data.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key]) }
    }

    public func setSetting(_ key: String, to value: Data) throws {
        try write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO setting (key, value) VALUES (?, ?)", arguments: [key, value])
        }
    }
}
