import AppKit
import SwiftUI
import Testing

@testable import FlickrDownloaderUI

/// Draws the splash offscreen and looks at the pixels.
///
/// **Headless, not hidden.** `ImageRenderer` rasterises a SwiftUI view without
/// a window, so this catches what assertions about layout cannot — a view that
/// lays out perfectly and draws nothing — without putting anything on the
/// screen of whoever is running the suite.
@MainActor
@Suite struct SplashRenderTests {

    private func render() -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: AboutView(close: {}))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let data = image.tiffRepresentation
        else { return nil }
        return NSBitmapImageRep(data: data)
    }

    @Test func theSplashRendersAtTheSizeItDeclares() throws {
        let bitmap = try #require(render())
        // 640 × 580 at 2x. A view that fails to size itself comes back tiny or
        // square, and every layout assertion still passes.
        #expect(bitmap.pixelsWide == 1280)
        #expect(bitmap.pixelsHigh == 1160)
    }

    /// The failure this exists for: the key art loading as an empty `NSImage`
    /// leaves a grey rectangle where the contact sheet should be, and nothing
    /// else notices.
    @Test func theKeyArtBandIsActuallyDrawn() throws {
        let bitmap = try #require(render())
        var colours = Set<String>()
        // Across the banner, below the title but above the body.
        for x in stride(from: 40, to: bitmap.pixelsWide - 40, by: 24) {
            for y in stride(from: 40, to: 300, by: 24) {
                guard let colour = bitmap.colorAt(x: x, y: y) else { continue }
                colours.insert(String(format: "%.2f,%.2f,%.2f",
                                      colour.redComponent, colour.greenComponent,
                                      colour.blueComponent))
            }
        }
        // A flat rectangle is one colour; a contact sheet is many.
        #expect(colours.count > 20)
    }

    @Test func theBodyAndFooterAreBelowTheBanner() throws {
        let bitmap = try #require(render())
        // The footer is a `.bar` material over the window background: whatever
        // it resolves to, it must not be the banner's near-black.
        let footer = try #require(bitmap.colorAt(x: 640, y: bitmap.pixelsHigh - 40))
        let banner = try #require(bitmap.colorAt(x: 640, y: 120))
        #expect(abs(footer.brightnessComponent - banner.brightnessComponent) > 0.15)
    }

    /// Written where a person can look at it, because a number is not a picture.
    @Test func aCopyIsLeftToLookAt() throws {
        let bitmap = try #require(render())
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flickrdownloader-splash.png")
        try png.write(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
