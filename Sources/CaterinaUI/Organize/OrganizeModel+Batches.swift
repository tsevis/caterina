import Foundation

import CaterinaLibrary
import FlickrKit

/// Changing the tray's photos, and taking changes back.
extension OrganizeModel {

    nonisolated static let activityLimit = 30

    public var isRunning: Bool {
        if case .running = run { return true }
        return false
    }

    /// What `edit` would do to the tray, before anything is sent.
    public func estimate(_ edit: PhotoEdit) -> EditEstimate { estimate([edit]) }

    /// What `edits`, one after another, would do to the tray.
    public func estimate(_ edits: [PhotoEdit]) -> EditEstimate {
        EditEstimate.of(changes(for: edits), budget: budget)
    }

    public func apply(_ edit: PhotoEdit, title: String) async { await apply([edit], title: title) }

    /// Record `edits` on the tray as one batch and run it.
    public func apply(_ edits: [PhotoEdit], title: String) async {
        guard !isRunning else {
            problem = "Wait for the edit that is running to finish."
            return
        }
        do {
            let batch = try store.createBatch(title: title, changes: changes(for: edits))
            await runBatch(batch.id)
        } catch {
            problem = "Could not record the edit: \(Self.message(error))"
        }
    }

    /// Carry on with a batch that stopped: after approving on Flickr, or once
    /// Flickr is reachable again.
    public func resume(_ batchID: String) async {
        guard !isRunning else { return }
        await runBatch(batchID)
    }

    public func undo(_ batchID: String) async {
        guard !isRunning else {
            problem = "Wait for the edit that is running to finish."
            return
        }
        do {
            let undo = try store.undoBatch(for: batchID)
            await runBatch(undo.id)
        } catch {
            problem = "Could not undo: \(Self.message(error))"
        }
    }

    private func changes(for edits: [PhotoEdit]) -> [PhotoChange] {
        trayPhotos.enumerated().map { index, photo in
            let context = PhotoEdit.Context(position: index + 1, count: trayPhotos.count)
            return PhotoChange(before: photo, after: edits.reduce(photo) { $1.applied(to: $0, context: context) })
        }
    }

    private func runBatch(_ batchID: String) async {
        let runner = BatchRunner(writer: flickr, store: store)
        run = .running(batchID: batchID, summary: (try? store.summary(of: batchID)) ?? .init(applied: 0, failed: 0, pending: 0))
        refreshActivity()
        do {
            try await runner.run(batchID) { summary in
                Task { @MainActor [weak self] in self?.showProgress(batchID, summary) }
            }
            run = .idle
        } catch FlickrError.permissionNeeded(let permission) {
            run = .needsPermission(permission, batchID: batchID)
        } catch {
            run = .paused(batchID: batchID, message: Self.message(error))
        }
        afterBatch()
    }

    private func showProgress(_ batchID: String, _ summary: EditBatch.Summary) {
        guard case .running(batchID, _) = run else { return }
        run = .running(batchID: batchID, summary: summary)
    }

    private func afterBatch() {
        reloadPhotos()
        refreshTray()
        refreshIndexes()
        refreshActivity()
    }

    func refreshActivity() {
        let runningID: String? = if case let .running(id, _) = run { id } else { nil }
        do {
            activity = try BatchActivity.rows(from: store, limit: Self.activityLimit, runningID: runningID)
        } catch {
            problem = "Could not read the edit history: \(Self.message(error))"
        }
    }
}
