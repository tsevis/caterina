import Foundation

import CaterinaLibrary
import FlickrKit

/// Rotating, tagging people and deleting the tray.
extension OrganizeModel {

    /// One call per photo in the tray.
    public func estimate(action: PhotoAction) -> EditEstimate {
        EditEstimate(photos: tray.count, unchanged: 0, calls: tray.count,
                     duration: budget.estimatedDuration(calls: tray.count, priority: .edit),
                     unrestorable: action.undo == nil ? ["photos"] : [])
    }

    public func perform(_ action: PhotoAction, title: String) async {
        guard action != .delete else { return deleteTray() }
        await runActions(action, title: title)
    }

    /// Who a name, address or NSID is, to show before tagging anyone.
    public func lookUpPerson(_ query: String) async -> FlickrPerson? {
        do {
            return try await flickr.lookUpPerson(query)
        } catch {
            problem = "Could not find “\(query)” on Flickr: \(Self.message(error))"
            return nil
        }
    }


    /// A photo from Browse, usually someone else's, into one of your galleries.
    public func addToGallery(photoID: String, galleryID: String, galleryTitle: String, comment: String) async {
        await runActions(.addToGallery(galleryID: galleryID, comment: comment), on: [photoID],
                         title: "Add a photo to gallery “\(galleryTitle)”")
    }

    private func runActions(_ action: PhotoAction, title: String) async {
        await runActions(action, on: tray, title: title)
    }

    func runActions(_ action: PhotoAction, on photoIDs: [String], title: String) async {
        guard !photoIDs.isEmpty else { return }
        guard let owner = accountID() else {
            problem = "Sign in to Flickr to change your photos."
            return
        }
        guard !isBusy else {
            problem = busyMessage
            return
        }
        do {
            let batch = try store.createActionBatch(title: title, action: action, photoIDs: photoIDs, accountID: owner)
            await runBatch(batch.id)
        } catch {
            problem = "Could not record the edit: \(Self.message(error))"
        }
    }
}
