import AppKit
import SwiftUI

/// Puts `AboutView` in a window of its own.
///
/// A plain `NSWindow` rather than a SwiftUI scene because it has to be
/// summonable from the application menu *and* shown once at launch, and a
/// `Window` scene gives no clean way to do the second without leaving a stale
/// entry in the Window menu.
@MainActor
public final class AboutWindowController: NSObject {
    /// Whether the splash appears at launch. A defaults key rather than an item
    /// in Settings: it is a one-line preference about a window, not about how
    /// photos are downloaded.
    public static let showOnLaunchKey = "ShowAboutOnLaunch"

    private var window: NSWindow?

    /// Run when the splash goes away, whether by the button or the close box.
    private var onDismiss: (() -> Void)?

    public override init() { super.init() }

    /// Show the splash if it is wanted, and run `then` once it is out of the
    /// way — immediately if it was never shown.
    public func showOnLaunchIfWanted(then next: @escaping () -> Void) {
        let defaults = UserDefaults.standard
        // Absent means yes: the first launch is exactly when what this does to
        // other people's photographs is worth reading.
        if defaults.object(forKey: Self.showOnLaunchKey) == nil {
            defaults.set(true, forKey: Self.showOnLaunchKey)
        }
        guard defaults.bool(forKey: Self.showOnLaunchKey) else {
            next()
            return
        }
        onDismiss = next
        show()
    }

    public func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            window.center()
            return
        }

        let window = NSWindow(
            // Vestigial: the root view carries `.frame(width: 640, height: 580)`
            // and `NSHostingView` sizes the window to it, so the window that
            // appears is 640 × 580 whatever is written here.
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 580),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self

        // **The window is sized here, not by the view.** Left to itself,
        // `NSHostingView` sets the window's *content* size to the root view's
        // 640 × 580 and macOS adds a title bar on top, so the frame becomes
        // 640 × 608 and the key art starts 28pt down — with a grey strip above
        // it, which is exactly what `.fullSizeContentView` and a transparent
        // title bar exist to avoid. Sizing the frame instead puts the contact
        // sheet under the traffic lights, where it belongs.
        let hosting = NSHostingView(
            rootView: AboutView(close: { [weak self] in self?.window?.close() }))
        hosting.sizingOptions = []
        // **And SwiftUI has to be told to ignore the title bar.** Measured:
        // with `.fullSizeContentView` the content view really does span the
        // whole 640 × 580 frame, but `contentLayoutRect` is 640 × 552 and
        // SwiftUI lays out inside *that* safe area — so the contact sheet
        // started 28pt down and the attribution line fell off the bottom.
        hosting.safeAreaRegions = []
        window.contentView = hosting
        window.setFrame(NSRect(x: 0, y: 0, width: 640, height: 580), display: false)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}

extension AboutWindowController: NSWindowDelegate {
    /// Whatever was waiting on the splash runs when it closes — by the Continue
    /// button or by the close box, which have to mean the same thing, and it
    /// runs once.
    public func windowWillClose(_ notification: Notification) {
        let next = onDismiss
        onDismiss = nil
        next?()
    }
}
