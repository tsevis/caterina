import Foundation
import Testing

@testable import FlickrKit

/// The selection rules a Mac user expects, as arithmetic rather than as
/// gestures.
///
/// These lived inside the grid view, where nothing could reach them: the only
/// way to find out whether ⇧-click extended from the right place was to click.
/// The gesture plumbing still cannot be exercised here — whether a drag reaches
/// the sweep surface is a question for a running window — but what each gesture
/// *means* is decided here, and that part is now checked.
@Suite struct GridSelectionTests {

    private let order = ["a", "b", "c", "d", "e", "f"]

    // MARK: - Clicking

    @Test func aPlainClickReplacesTheSelection() {
        let selection = GridSelection(ids: ["a", "b"], anchor: "a")
            .clicking("e", modifiers: [], in: order)
        #expect(selection.ids == ["e"])
        #expect(selection.anchor == "e")
    }

    @Test func commandClickAddsAndRemovesOne() {
        let added = GridSelection(ids: ["a"], anchor: "a")
            .clicking("c", modifiers: .command, in: order)
        #expect(added.ids == ["a", "c"])

        let removed = added.clicking("a", modifiers: .command, in: order)
        #expect(removed.ids == ["c"])
    }

    @Test func commandClickMovesTheAnchorToWhatWasClicked() {
        let selection = GridSelection(ids: ["a"], anchor: "a")
            .clicking("c", modifiers: .command, in: order)
            .clicking("e", modifiers: .shift, in: order)
        // The range runs from the ⌘-clicked tile, not from the first one.
        #expect(selection.ids == ["a", "c", "d", "e"])
    }

    @Test func shiftClickExtendsARangeFromTheAnchor() {
        let selection = GridSelection(ids: ["b"], anchor: "b")
            .clicking("e", modifiers: .shift, in: order)
        #expect(selection.ids == ["b", "c", "d", "e"])
    }

    @Test func shiftClickExtendsBackwardsJustAsWell() {
        let selection = GridSelection(ids: ["e"], anchor: "e")
            .clicking("b", modifiers: .shift, in: order)
        #expect(selection.ids == ["b", "c", "d", "e"])
    }

    /// The anchor stays put, so a second ⇧-click re-measures from the same
    /// place rather than from wherever the last one landed.
    @Test func theAnchorSurvivesAShiftClickSoARangeCanBeRedrawn() {
        let first = GridSelection(ids: ["b"], anchor: "b")
            .clicking("e", modifiers: .shift, in: order)
        #expect(first.anchor == "b")

        let narrowed = first.clicking("c", modifiers: .shift, in: order)
        #expect(narrowed.ids == ["b", "c"])
    }

    @Test func shiftClickWithNoAnchorIsJustAClick() {
        let selection = GridSelection(ids: [], anchor: nil)
            .clicking("d", modifiers: .shift, in: order)
        #expect(selection.ids == ["d"])
        #expect(selection.anchor == "d")
    }

    @Test func bothModifiersAtOnceExtendsRatherThanToggles() {
        // ⇧⌘-click is an extension in every Mac list; ⌘ alone is the toggle.
        let selection = GridSelection(ids: ["b"], anchor: "b")
            .clicking("d", modifiers: [.command, .shift], in: order)
        #expect(selection.ids == ["b", "c", "d"])
    }

    @Test func clickingSomethingNotOnThePageChangesNothing() {
        let start = GridSelection(ids: ["a"], anchor: "a")
        #expect(start.clicking("zzz", modifiers: [], in: order) == start)
    }

    // MARK: - Sweeping

    @Test func aSweepReplacesTheSelectionWithWhatItCovers() {
        let selection = GridSelection(ids: ["a"], anchor: "a")
            .sweeping(["c", "d"], in: order)
        #expect(selection.ids == ["c", "d"])
    }

    @Test func aSweepThatCoversNothingSelectsNothing() {
        #expect(GridSelection(ids: ["a", "b"], anchor: "a")
            .sweeping([], in: order).ids.isEmpty)
    }

    @Test func aSweepCannotSelectAPhotoThatIsNotThere() {
        #expect(GridSelection().sweeping(["a", "ghost"], in: order).ids == ["a"])
    }

    // MARK: - Arrow keys

    @Test func arrowKeysMoveOneAtATime() {
        let start = GridSelection(ids: ["c"], anchor: "c")
        #expect(start.moving(by: 1, in: order).ids == ["d"])
        #expect(start.moving(by: -1, in: order).ids == ["b"])
    }

    @Test func movingByARowJumpsThatManyAtOnce() {
        let start = GridSelection(ids: ["a"], anchor: "a")
        #expect(start.moving(by: 3, in: order).ids == ["d"])
    }

    @Test func arrowKeysStopAtTheEndsRatherThanWrapping() {
        #expect(GridSelection(ids: ["a"], anchor: "a").moving(by: -1, in: order).ids == ["a"])
        #expect(GridSelection(ids: ["f"], anchor: "f").moving(by: 1, in: order).ids == ["f"])
        // A whole row past the end lands on the last photo, not nowhere.
        #expect(GridSelection(ids: ["e"], anchor: "e").moving(by: 4, in: order).ids == ["f"])
    }

    @Test func anArrowKeyWithNothingSelectedStartsAtTheBeginning() {
        #expect(GridSelection().moving(by: 1, in: order).ids == ["a"])
        #expect(GridSelection().moving(by: -1, in: order).ids == ["a"])
    }

    @Test func arrowKeysOnAnEmptyPageDoNothing() {
        #expect(GridSelection().moving(by: 1, in: []).ids.isEmpty)
    }

    @Test func movingAlwaysLeavesExactlyOneSelected() {
        let wide = GridSelection(ids: ["a", "b", "c"], anchor: "b")
        #expect(wide.moving(by: 1, in: order).ids.count == 1)
    }

    // MARK: - Keeping in step with the page

    @Test func aSelectionIsTrimmedToThePhotosActuallyShown() {
        let selection = GridSelection(ids: ["a", "gone"], anchor: "gone")
            .keeping(to: order)
        #expect(selection.ids == ["a"])
        #expect(selection.anchor == nil)
    }

    @Test func selectAllAndClear() {
        #expect(GridSelection().selectingAll(in: order).ids.count == order.count)
        #expect(GridSelection(ids: ["a"], anchor: "a").clearing().ids.isEmpty)
    }
}
