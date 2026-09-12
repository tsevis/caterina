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
        window.contentView = NSHostingView(
            rootView: AboutView(close: { [weak self] in self?.window?.close() })
        )
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
