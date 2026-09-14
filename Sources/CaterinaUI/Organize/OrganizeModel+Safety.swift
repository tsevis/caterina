import Foundation

import CaterinaLibrary
import FlickrKit

/// A delete confirmed but held back, so it can still be taken back.
public struct PendingDelete: Sendable, Equatable {
    /// The tray as it was when Delete was confirmed.
    public let photoIDs: [String]
    public let deadline: Date
}

/// The ways back from a wrong selection: deleting waits before anything is
/// sent, and the last edit is offered for Undo.
extension OrganizeModel {

    /// Flickr has no trash, so this is the only time a delete can be taken back.
    public nonisolated static let defaultDeleteGrace: Duration = .seconds(30)

    // MARK: - Deleting, after a wait

    /// Every photo now in the tray, off Flickr for good once the grace runs
    /// out. Nothing is sent before then; quitting sends nothing.
    public func deleteTray() {
        guard !tray.isEmpty else { return }
        guard !isBusy else {
            problem = busyMessage
            return
        }
        pendingDelete = PendingDelete(photoIDs: tray, deadline: Date().addingTimeInterval(deleteGrace / .seconds(1)))
        let grace = deleteGrace
        deleteTask = Task { [weak self] in
            do {
                try await Task.sleep(for: grace)
            } catch {
                return  // Taken back.
            }
            await self?.sendPendingDelete()
        }
    }

    /// Keep the photos: nothing has been sent.
    public func cancelPendingDelete() {
        deleteTask?.cancel()
        deleteTask = nil
        pendingDelete = nil
    }

    /// Skip the rest of the wait.
    public func deletePendingNow() async {
        deleteTask?.cancel()
        await sendPendingDelete()
    }

    /// Asks Flickr for delete permission when the sign-in lacks it.
    private func sendPendingDelete() async {
        guard let pending = pendingDelete else { return }
        deleteTask = nil
        pendingDelete = nil
        await runActions(.delete, on: pending.photoIDs, title: "Delete \(Self.count(pending.photoIDs.count))")
    }

    // MARK: - Undo for the last edit

    /// The edit that just finished, while it can still be undone.
    public var lastEdit: BatchActivity? {
        guard let lastEditID else { return nil }
        return activity.first { $0.id == lastEditID && $0.canUndo }
    }

    public func dismissLastEdit() {
        lastEditID = nil
    }

    /// The newest edit in Activity that Undo can take back.
    public var newestUndoable: BatchActivity? {
        activity.first(where: \.canUndo)
    }

    /// Undo from the menu: a key is easy to press by mistake, so it asks.
    public func requestUndo() {
        undoRequest = isBusy ? nil : newestUndoable
    }

    public func cancelUndoRequest() {
        undoRequest = nil
    }

    public func confirmUndoRequest() async {
        guard let request = undoRequest else { return }
        undoRequest = nil
        await undo(request.id)
    }
}
