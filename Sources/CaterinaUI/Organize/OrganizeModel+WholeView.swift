import Foundation

import CaterinaLibrary
import FlickrKit

/// Working on a whole view or a whole tag, not only the photos loaded.
extension OrganizeModel {

    /// Every photo the open view holds: the album's photos, or every match in
    /// the library copy.
    public var viewCount: Int {
        if scope.albumID != nil { return albumOrder.count }
        return counts[scope] ?? (try? store.count(scope.filter)) ?? photos.count
    }

    /// Every photo in the view, in the view's order, after what the tray
    /// already holds.
    public func addEntireViewToTray() async {
        let ids: [String]
        if scope.albumID != nil {
            ids = albumOrder
        } else {
            do {
                ids = try store.photos(scope.filter, order: scope.order).map(\.id)
            } catch {
                problem = "Could not read the view: \(Self.message(error))"
                return
            }
        }
        let known = Set(tray)
        tray += ids.filter { !known.contains($0) }
        refreshTray()
    }

    /// What removing `tag` from every photo carrying it would cost.
    public func estimateRemovingEverywhere(_ tag: String) -> EditEstimate {
        EditEstimate.of(tagRemovalChanges(tag), budget: budget)
    }

    /// `tag`, in any spelling, off every photo in the library that has it.
    /// The tray is left as it is.
    public func removeTagEverywhere(_ tag: String) async {
        let changes = tagRemovalChanges(tag).filter { !$0.isEmpty }
        guard !changes.isEmpty else { return }
        guard let owner = accountID() else {
            problem = "Sign in to Flickr to change your photos."
            return
        }
        guard !isRunning else {
            problem = "Wait for the edit that is running to finish."
            return
        }
        do {
            let batch = try store.createBatch(title: "Remove tag “\(tag)” from \(Self.count(changes.count))",
                                              changes: changes, accountID: owner)
            await runBatch(batch.id)
        } catch {
            problem = "Could not record the edit: \(Self.message(error))"
        }
    }

    private func tagRemovalChanges(_ tag: String) -> [PhotoChange] {
        guard !PhotoEdit.flickrTag(tag).isEmpty else { return [] }
        do {
            return try store.photos(.tagged(tag)).map {
                PhotoChange(before: $0, after: PhotoEdit.removeTags([tag]).applied(to: $0))
            }
        } catch {
            problem = "Could not read the library copy: \(Self.message(error))"
            return []
        }
    }
}
