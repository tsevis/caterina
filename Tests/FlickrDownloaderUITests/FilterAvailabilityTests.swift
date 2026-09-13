import SwiftUI
import Testing

import FlickrKit
@testable import FlickrDownloaderUI

/// Which filter sections a source can use.
///
/// **An ancestor's `.disabled(true)` cannot be undone by a child's
/// `.disabled(false)`.** The inspector disabled the whole `Form` for a
/// photostream and marked the Size section `.disabled(false)` to keep it
/// usable — and it was greyed out with the rest, although size is applied to
/// the results here and works on every source.
@MainActor
@Suite struct FilterAvailabilityTests {

    /// The trap itself, so nobody puts the gate back on the `Form`.
    @Test func aChildCannotReEnableWhatItsParentDisabled() throws {
        let seen = EnabledProbe.Seen()
        let renderer = ImageRenderer(content:
            VStack { EnabledProbe(seen: seen).disabled(false) }.disabled(true))
        _ = renderer.nsImage
        #expect(seen.value == false)
    }

    @Test func sizeIsUsableOnEverySource() {
        #expect(FilterAvailability.isEnabled(.size, supportsFilters: false))
        #expect(FilterAvailability.isEnabled(.size, supportsFilters: true))
    }

    @Test func searchFiltersFollowTheQuery() {
        for section in [FilterSection.sort, .colour, .licence] {
            #expect(!FilterAvailability.isEnabled(section, supportsFilters: false))
            #expect(FilterAvailability.isEnabled(section, supportsFilters: true))
        }
    }

    /// Clearing has to reach a size filter set on a photostream.
    @Test func clearingIsAlwaysAvailable() {
        #expect(FilterAvailability.isEnabled(.clear, supportsFilters: false))
    }
}

private struct EnabledProbe: View {
    final class Seen { var value: Bool? }
    let seen: Seen
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        seen.value = isEnabled
        return Color.clear.frame(width: 4, height: 4)
    }
}
