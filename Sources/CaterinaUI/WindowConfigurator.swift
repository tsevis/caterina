import AppKit
import SwiftUI

/// Settings that belong to the `NSWindow` rather than to the view inside it.
///
/// **The frame is saved explicitly rather than left to the scene.** SwiftUI
/// restores a `Window` scene's frame on its own, but only as long as its state
/// restoration survives — and a window that forgets where it was every time the
/// system decides to discard that is a small daily annoyance with no visible
/// cause. An autosave name is the durable version of the same promise.
struct WindowConfigurator: NSViewRepresentable {
    let autosaveName: String
    let minimum: NSSize

    func makeNSView(context: Context) -> NSView {
        Probe(autosaveName: autosaveName, minimum: minimum)
    }

    func updateNSView(_ view: NSView, context: Context) {}

    /// A view that exists only to be able to reach its window.
    private final class Probe: NSView {
        private let autosaveName: String
        private let minimum: NSSize

        init(autosaveName: String, minimum: NSSize) {
            self.autosaveName = autosaveName
            self.minimum = minimum
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not from a nib") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.minSize = minimum
            // Setting it again on every appearance would reset the saved frame.
            if window.frameAutosaveName != autosaveName {
                window.setFrameAutosaveName(autosaveName)
            }
        }
    }
}
