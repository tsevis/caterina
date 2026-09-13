import Foundation

import FlickrKit

/// Tidying up after Quick Look and drag-out.
///
/// Both write a real file so the system has something to open or copy, and
/// neither can delete it at the time — Quick Look may still be showing it, and
/// the Finder copies a promised file whenever it likes. So they are cleaned up
/// on the next launch instead, which bounds them to one session's worth rather
/// than leaving a growing pile of other people's photographs in the container.
enum TemporaryFiles {
    /// Names this application creates in the temporary directory.
    static let prefixes = ["drag-", "Quick Look_", UploadRequest.bodyFolderName]

    /// Old enough that nothing can still be using it.
    static let staleAfter: TimeInterval = 60 * 60

    static func sweep(in directory: URL = FileManager.default.temporaryDirectory,
                      now: Date = Date(),
                      staleAfter: TimeInterval = staleAfter) {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else { return }

        for entry in entries where prefixes.contains(where: {
            entry.lastPathComponent.hasPrefix($0)
        }) {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            guard now.timeIntervalSince(modified) > staleAfter else { continue }
            try? manager.removeItem(at: entry)
        }
    }
}
