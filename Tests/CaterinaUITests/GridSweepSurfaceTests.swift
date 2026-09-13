import AppKit
import SwiftUI
import Testing

import FlickrKit
@testable import CaterinaUI

/// The empty band below the last row is still the grid.
@MainActor
@Suite struct GridSweepSurfaceTests {

    private func grid(photos: [Photo]) -> PhotoGridView {
        PhotoGridView(photos: photos, selection: [],
                      onClick: { _, _ in }, onSweep: { _ in },
                      onMove: { _ in }, onPreview: { _ in })
    }

    /// The defect, found by dragging: the sweep surface is a `Color.clear`
    /// inside a `ZStack`, and a stack is only as tall as its tallest child. With
    /// a handful of photos in a tall window everything below the last row
    /// belonged to the `ScrollView`, not to the stack — so a marquee begun in
    /// that band, which is the obvious place to begin one, drew nothing and
    /// selected nothing. A sweep begun *between* the tiles worked, which is why
    /// the arithmetic in `MarqueeTests` passed throughout.
    @Test func theSweepSurfaceFillsAViewportTallerThanTheTiles() throws {
        let photos = (1...3).map { Photo(id: "\($0)", title: "Photo \($0)") }
        let renderer = ImageRenderer(content:
            grid(photos: photos).content(viewport: 900).frame(width: 600))
        let image = try #require(renderer.nsImage)
        #expect(image.size.height == 900)
    }

    /// ...and does not truncate a page that is taller than the window, which is
    /// what a plain `.frame(height:)` would have done.
    @Test func contentTallerThanTheViewportKeepsItsOwnHeight() throws {
        let photos = (1...40).map { Photo(id: "\($0)", title: "Photo \($0)") }
        let renderer = ImageRenderer(content:
            grid(photos: photos).content(viewport: 200).frame(width: 600))
        let image = try #require(renderer.nsImage)
        #expect(image.size.height > 200)
    }
}
