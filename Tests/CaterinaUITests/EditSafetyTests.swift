import Foundation
import Testing

import CaterinaLibrary
import FlickrKit
@testable import CaterinaUI

/// One wrong selection must not be the end: deleting waits and can be taken
/// back, the last edit offers Undo, and what cannot be undone always asks.
@MainActor
@Suite struct EditSafetyTests {

    private func setUp(grace: Duration = .seconds(60)) throws -> (OrganizeModel, FakeOrganizeFlickr) {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryPhoto(id: "1", title: "A"), LibraryPhoto(id: "2", title: "B")], generation: 1)
        let flickr = FakeOrganizeFlickr(store: store)
        let model = OrganizeModel(store: store, flickr: flickr, accountID: { "me" }, deleteGrace: grace)
        model.selectAll()
        model.addSelectionToTray()
        return (model, flickr)
    }

    // MARK: - Deleting waits

    @Test func deletingSendsNothingUntilTheGraceRunsOut() async throws {
        let (model, flickr) = try setUp()
        model.deleteTray()
        #expect(model.pendingDelete?.photoIDs == ["1", "2"])
        #expect(await flickr.sent.isEmpty)
        #expect(model.tray == ["1", "2"])
    }

    @Test func aDeleteTakenBackSendsNothing() async throws {
        let (model, flickr) = try setUp(grace: .milliseconds(30))
        model.deleteTray()
        model.cancelPendingDelete()
        #expect(model.pendingDelete == nil)
        // The claim is that nothing ever happens, so a wait past the grace is the test.
        try await Task.sleep(for: .milliseconds(250))
        #expect(await flickr.sent.isEmpty)
        #expect(model.tray == ["1", "2"])
    }

    @Test func aDeleteGoesAheadWhenTheGraceRunsOut() async throws {
        let (model, flickr) = try setUp(grace: .milliseconds(30))
        model.deleteTray()
        try await waitUntil("the delete to be sent") { await flickr.sent.count == 2 }
        try await waitUntil("the delete to finish") { !model.isRunning && model.pendingDelete == nil }
        #expect(model.tray.isEmpty)
    }

    /// The photos meant are the ones in the tray when Delete was confirmed.
    @Test func deleteNowDeletesWhatWasInTheTrayWhenAsked() async throws {
        let (model, flickr) = try setUp()
        model.deleteTray()
        model.removeFromTray(["2"])
        await model.deletePendingNow()
        #expect(await flickr.sent.map { $0.arguments["photo_id"] } == ["1", "2"])
        #expect(model.pendingDelete == nil)
    }

    @Test func noOtherEditStartsWhileADeleteIsWaiting() async throws {
        let (model, flickr) = try setUp()
        model.deleteTray()
        #expect(model.isBusy)
        await model.perform(.rotate(degrees: 90), title: "Rotate")
        #expect(await flickr.sent.isEmpty)
        #expect(model.problem != nil)
    }

    @Test func signingOutTakesBackAWaitingDelete() async throws {
        let (model, flickr) = try setUp(grace: .milliseconds(30))
        model.deleteTray()
        model.accountChanged()
        #expect(model.pendingDelete == nil)
        try await Task.sleep(for: .milliseconds(250))
        #expect(await flickr.sent.isEmpty)
    }

    // MARK: - The last edit offers Undo

    @Test func theLastEditOffersUndoUntilUndoneOrDismissed() async throws {
        let (model, _) = try setUp()
        await model.perform(.rotate(degrees: 90), title: "Rotate")
        let last = try #require(model.lastEdit)
        #expect(last.batch.title == "Rotate")
        model.dismissLastEdit()
        #expect(model.lastEdit == nil)

        await model.perform(.rotate(degrees: 90), title: "Rotate again")
        await model.undo(try #require(model.lastEdit).batch.id)
        #expect(model.lastEdit == nil)
    }

    @Test func aDeleteIsNeverOfferedAsTheLastEdit() async throws {
        let (model, _) = try setUp()
        model.deleteTray()
        await model.deletePendingNow()
        #expect(model.lastEdit == nil)
    }

    @Test func undoFromTheMenuAsksFirstThenUndoesTheNewestUndoableEdit() async throws {
        let (model, flickr) = try setUp()
        #expect(model.newestUndoable == nil)
        await model.perform(.rotate(degrees: 90), title: "Rotate")
        model.requestUndo()
        #expect(model.undoRequest?.batch.title == "Rotate")
        #expect(await flickr.sent.count == 2)

        await model.confirmUndoRequest()
        #expect(model.undoRequest == nil)
        #expect(await flickr.sent.count == 4)
        #expect(model.newestUndoable == nil)
    }

    // MARK: - Asking first

    @Test(arguments: [
        (photos: 3, unrestorable: [String](), expected: false),
        (photos: ApplyBar.confirmAbove + 1, unrestorable: [], expected: true),
        (photos: 1, unrestorable: ["safety level"], expected: true),
    ])
    func whatCannotBeUndoneAlwaysAsks(photos: Int, unrestorable: [String], expected: Bool) {
        let estimate = EditEstimate(photos: photos, unchanged: 0, calls: photos, duration: .zero,
                                    unrestorable: unrestorable)
        #expect(ApplyBar.needsConfirmation(estimate) == expected)
    }

    @Test func theQuestionSaysWhatUndoCannotDoAndSuggestsABackup() {
        let fields = EditEstimate(photos: 1, unchanged: 0, calls: 1, duration: .zero, unrestorable: ["safety level"])
        let plain = EditEstimate(photos: 30, unchanged: 0, calls: 30, duration: .zero, unrestorable: [])

        let partial = ApplyBar.confirmationMessage(title: "Set safety", estimate: fields, isDelete: false)
        #expect(partial.contains("cannot restore the safety level"))
        #expect(partial.contains(BackupTip.short))

        let undoable = ApplyBar.confirmationMessage(title: "Add tags", estimate: plain, isDelete: false)
        #expect(undoable.contains("undo it"))

        let deleting = ApplyBar.confirmationMessage(title: "Delete", estimate: plain, isDelete: true)
        #expect(deleting.contains("30 seconds"))
        #expect(deleting.contains("cannot be undone"))
    }
}
