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

    /// Search as you type: every word, in titles, descriptions or tags.
    /// Clearing the text goes back to the view you were in.
    public func search(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            guard case .search = scope else { return }
            await open(scopeBeforeSearch ?? .all)
            return
        }
        if case .search = scope {} else { scopeBeforeSearch = scope }
        await open(.search(query))
    }

    /// Every photo of yours `person` is tagged in, into the tray. Returns how
    /// many; photos not in the library copy yet are left out.
    @discardableResult
    public func addPhotosOf(_ person: FlickrPerson) async -> Int {
        guard let owner = accountID() else {
            problem = "Sign in to Flickr to find photos of people."
            return 0
        }
        do {
            var ids: [String] = []
            var page = 1
            var pages = 1
            repeat {
                let reply = try await flickr.photoList(.photosOfIn(userID: person.nsid, ownerID: owner), page: page)
                ids += reply.photos.map(\.id)
                pages = reply.pages
                page += 1
            } while page <= pages
            let mine = try store.photos(ids: ids).map(\.id)
            let known = Set(tray)
            tray += mine.filter { !known.contains($0) }
            refreshTray()
            return mine.count
        } catch {
            problem = "Could not find photos of \(person.username): \(Self.message(error))"
            return 0
        }
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
        guard !isBusy else {
            problem = busyMessage
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
