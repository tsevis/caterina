import AppKit

/// Lets a download finish being cancelled before the process goes away.
///
/// Quitting mid-download otherwise tore the process down with a transfer in
/// flight: the `.part` file survived in the user's folder and the report that
/// would have said "Saved 12 of 40" was never shown. `DownloadEngine` already
/// cleans up and reports on cancellation — it just needs to be allowed to.
@MainActor
public final class TerminationGuard: NSObject, NSApplicationDelegate {
    /// Set by the application once its model exists.
    public var beforeQuit: (@MainActor () async -> Void)?

    public func applicationShouldTerminate(
        _ application: NSApplication
    ) -> NSApplication.TerminateReply {
        guard let beforeQuit else { return .terminateNow }
        self.beforeQuit = nil
        Task {
            await beforeQuit()
            application.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// One window, and closing it means quitting — there is nothing left to
    /// look at without it.
    public func applicationShouldTerminateAfterLastWindowClosed(
        _ application: NSApplication
    ) -> Bool { true }
}
