import Foundation

/// Which modifiers were held when a photo was clicked.
///
/// Its own type rather than AppKit's `NSEvent.ModifierFlags`, so the rules
/// below can be decided — and tested — without a window, a mouse, or a UI
/// framework.
public struct ClickModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = ClickModifiers(rawValue: 1 << 0)
    public static let shift = ClickModifiers(rawValue: 1 << 1)
}

/// What is selected in the grid, and where a range would be measured from.
///
/// **These rules used to live inside the view**, where the only way to find out
/// whether ⇧-click extended from the right place was to click. The gestures
/// still belong to the view — whether a drag reaches the sweep surface is a
/// question for a running window — but what each gesture *means* is decided
/// here, where it can be checked.
public struct GridSelection: Sendable, Equatable {
    /// Photo ids.
    public let ids: Set<String>
    /// Where ⇧-click measures a range from. The last photo clicked without
    /// shift, which is not the same as "the last photo selected".
    public let anchor: String?
    /// What was selected when the anchor was last set.
    ///
    /// **Without this, ⇧-click cannot both extend and narrow.** Finder keeps
    /// whatever was ⌘-picked outside the range *and* lets a second ⇧-click
    /// pull the range back in — which only works if the range is recomputed
    /// against a fixed base each time rather than unioned into the last result.
    public let base: Set<String>

    public init(ids: Set<String> = [], anchor: String? = nil,
                base: Set<String>? = nil) {
        self.ids = ids
        self.anchor = anchor
        self.base = base ?? ids
    }

    public var isEmpty: Bool { ids.isEmpty }
    public var count: Int { ids.count }

    /// Click replaces, ⌘-click toggles, ⇧-click extends from the anchor.
    public func clicking(_ id: String, modifiers: ClickModifiers,
                         in order: [String]) -> GridSelection {
        guard order.contains(id) else { return self }

        // Shift wins over command: ⇧⌘-click is an extension in every Mac list,
        // and ⌘ alone is the toggle.
        if modifiers.contains(.shift), let anchor,
           let start = order.firstIndex(of: anchor),
           let end = order.firstIndex(of: id) {
            let span = start <= end ? start...end : end...start
            // The anchor and the base both stay put, so a second ⇧-click
            // re-measures from the same place — narrowing the range as readily
            // as widening it — while anything picked outside it survives.
            return GridSelection(ids: base.union(order[span]),
                                 anchor: anchor, base: base)
        }

        if modifiers.contains(.command) {
            var next = ids
            if next.contains(id) { next.remove(id) } else { next.insert(id) }
            return GridSelection(ids: next, anchor: id, base: next)
        }

        return GridSelection(ids: [id], anchor: id, base: [id])
    }

    /// What a marquee covered becomes the selection.
    public func sweeping(_ covered: Set<String>, in order: [String]) -> GridSelection {
        let present = covered.intersection(order)
        return GridSelection(ids: present,
                             anchor: anchor.flatMap { present.contains($0) ? $0 : nil },
                             base: present)
    }

    /// Arrow keys: one photo at a time, or a row at a time, stopping at the
    /// ends rather than wrapping — wrapping in a grid loses the reader's place.
    public func moving(by offset: Int, in order: [String]) -> GridSelection {
        guard !order.isEmpty else { return self }

        // With nothing selected, the first arrow press lands on the first
        // photo whichever way it points — the same as every Mac list.
        guard let current = anchor.flatMap({ order.firstIndex(of: $0) })
            ?? ids.compactMap({ order.firstIndex(of: $0) }).min()
        else {
            let id = order[0]
            return GridSelection(ids: [id], anchor: id, base: [id])
        }

        let next = min(max(0, current + offset), order.count - 1)
        let id = order[next]
        return GridSelection(ids: [id], anchor: id, base: [id])
    }

    /// Drop anything no longer on the page.
    ///
    /// A selected photo that is not on screen cannot be downloaded, and keeping
    /// it is how the count came to disagree with the grid.
    public func keeping(to order: [String]) -> GridSelection {
        let present = ids.intersection(order)
        return GridSelection(ids: present,
                             anchor: anchor.flatMap { order.contains($0) ? $0 : nil },
                             base: base.intersection(order))
    }

    public func selectingAll(in order: [String]) -> GridSelection {
        GridSelection(ids: Set(order), anchor: anchor ?? order.first, base: Set(order))
    }

    public func clearing() -> GridSelection {
        GridSelection(ids: [], anchor: anchor, base: [])
    }
}
