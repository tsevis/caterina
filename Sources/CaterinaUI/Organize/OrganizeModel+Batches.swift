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
        guard canStart() else { return }
        do {
            let batch = try store.createBatch(title: title, changes: changes(for: edits), accountID: accountID())
            await runBatch(batch.id)
        } catch {
            problem = "Could not record the edit: \(Self.message(error))"
        }
    }

    /// Carry on with a batch that stopped: after approving on Flickr, once
    /// Flickr is reachable again, or after Stop.
    public func resume(_ batchID: String) async {
        guard canStart(), belongsToThisAccount(batchID) else { return }
        await runBatch(batchID)
    }

    public func undo(_ batchID: String) async {
        guard canStart(), belongsToThisAccount(batchID) else { return }
        do {
            let undo = try store.undoBatch(for: batchID)
            await runBatch(undo.id)
        } catch {
            problem = "Could not undo: \(Self.message(error))"
        }
    }

    /// Stop after the photo being changed; the rest stay pending.
    public func stop() {
        runTask?.cancel()
    }

    /// Signed out, or signed in as someone else: stop, and forget the tray.
    public func accountChanged() {
        stop()
        clearTray()
        refreshActivity()
    }

    private func canStart() -> Bool {
        guard !isRunning else {
            problem = "Wait for the edit that is running to finish."
            return false
        }
        return true
    }

    private func belongsToThisAccount(_ batchID: String) -> Bool {
        let owner = activity.first { $0.batch.id == batchID }?.batch.accountID
            ?? (try? store.recentBatches(limit: Self.activityLimit))?.first { $0.id == batchID }?.accountID
        guard let owner, owner != accountID() else { return true }
        problem = "That edit was made by another Flickr account."
        return false
    }

    private func changes(for edits: [PhotoEdit]) -> [PhotoChange] {
        trayPhotos.enumerated().map { index, photo in
            let context = PhotoEdit.Context(position: index + 1, count: trayPhotos.count)
            return PhotoChange(before: photo, after: edits.reduce(photo) { $1.applied(to: $0, context: context) })
        }
    }

    func runBatch(_ batchID: String) async {
        let kind: EditBatch.Kind
        do {
            kind = try store.batch(batchID).kind
        } catch {
            problem = "Could not read the edit: \(Self.message(error))"
            return
        }
        let (flickr, store, owner) = (self.flickr, self.store, accountID() ?? "")
        run = .running(batchID: batchID, summary: (try? store.summary(of: batchID)) ?? .init(applied: 0, failed: 0, pending: 0))
        refreshActivity()
        // The model is main-actor isolated, so holding it for the length of
        // the run is safe; the run ends when the task does.
        let task = Task {
            do {
                let progress: @Sendable (EditBatch.Summary) -> Void = { summary in
                    Task { @MainActor in self.showProgress(batchID, summary) }
                }
                switch kind {
                case .photos: try await BatchRunner(writer: flickr, store: store).run(batchID, progress: progress)
                case .albums: try await AlbumRunner(flickr: flickr, store: store, ownerID: owner).run(batchID, progress: progress)
                case .groups: try await GroupShareRunner(flickr: flickr, store: store).run(batchID, progress: progress)
                case .actions: try await PhotoActionRunner(writer: flickr, store: store).run(batchID, progress: progress)
                }
                self.run = .idle
            } catch FlickrError.permissionNeeded(let permission) {
                self.run = .needsPermission(permission, batchID: batchID)
            } catch is CancellationError {
                self.run = .idle
            } catch {
                self.run = .paused(batchID: batchID, message: Self.message(error))
            }
        }
        runTask = task
        await task.value
        runTask = nil
        afterBatch()
        if kind == .albums { await afterAlbumBatch() }
        if kind == .groups { forgetGroupRules(of: batchID) }
    }

    /// Progress hops here in separate tasks, which need not arrive in order;
    /// a count that goes backwards is a late one.
    private func showProgress(_ batchID: String, _ summary: EditBatch.Summary) {
        guard case let .running(id, shown) = run, id == batchID, summary.pending <= shown.pending else { return }
        run = .running(batchID: batchID, summary: summary)
    }

    private func afterBatch() {
        libraryChanged()
        refreshActivity()
    }

    func refreshActivity() {
        let runningID: String? = if case let .running(id, _) = run { id } else { nil }
        do {
            activity = try BatchActivity.rows(from: store, limit: Self.activityLimit, runningID: runningID,
                                              accountID: accountID())
        } catch {
            problem = "Could not read the edit history: \(Self.message(error))"
        }
    }
}

extension OrganizeModel {
    /// A group batch used some of each group's room: read the rules again next time.
    func forgetGroupRules(of batchID: String) {
        do {
            try store.forgetGroupProfiles(Array(Set(try store.groupEntries(in: batchID).map(\.pair.groupID))))
        } catch {
            problem = "Could not update the groups' rules: \(Self.message(error))"
        }
    }
}
