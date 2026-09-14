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
        guard action != .delete else { return await deleteTray() }
        await runActions(action, title: title)
    }

    /// The person is looked up by name first; nothing is sent if not found.
    public func tagPerson(_ query: String, removing: Bool, title: String) async {
        do {
            let id = try await flickr.resolveUser(from: query)
            await runActions(removing ? .removePerson(userID: id) : .addPerson(userID: id), title: title)
        } catch {
            problem = "Could not find “\(query)” on Flickr: \(Self.message(error))"
        }
    }

    /// Every photo in the tray, off Flickr for good. Asks Flickr for delete
    /// permission when the sign-in lacks it; never part of another edit.
    public func deleteTray() async {
        await runActions(.delete, title: "Delete \(Self.count(tray.count))")
    }

    private func runActions(_ action: PhotoAction, title: String) async {
        guard !tray.isEmpty else { return }
        guard let owner = accountID() else {
            problem = "Sign in to Flickr to change your photos."
            return
        }
        guard !isRunning else {
            problem = "Wait for the edit that is running to finish."
            return
        }
        do {
            let batch = try store.createActionBatch(title: title, action: action, photoIDs: tray, accountID: owner)
            await runBatch(batch.id)
        } catch {
            problem = "Could not record the edit: \(Self.message(error))"
        }
    }
}
