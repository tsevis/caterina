import Foundation
import Testing

/// **No test in this package may put a window on screen.**
///
/// The suite runs on the author's own desktop, inside their GUI session: a test
/// that constructs a real window puts it in front of whatever they are doing,
/// and a full run doing it repeatedly is disruptive. Withdrawing the window is
/// not enough — it still flashes, and a run that creates many can leave orphans.
///
/// Anything that genuinely needs a window is tagged `.gui` *and* gated on
/// `FD_RUN_GUI_TESTS=1`, so a plain `swift test` stays silent:
///
/// ```swift
/// @Test(.tags(.gui), .enabled(if: Tag.guiTestsRequested))
/// func theWindowOpensWhereItShould() { … }
/// ```
///
/// There are none at the time of writing. Everything the splash and the model
/// need checking for — that the artwork loads, that the lockup is measured from
/// font metrics, that a load writes back into the right source — is checked
/// without drawing anything.
extension Tag {
    @Tag static var gui: Self
}

extension Tag {
    static var guiTestsRequested: Bool {
        ProcessInfo.processInfo.environment["FD_RUN_GUI_TESTS"] == "1"
    }
}
