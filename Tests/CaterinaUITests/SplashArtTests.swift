import AppKit
import SwiftUI
import Testing

@testable import CaterinaUI

/// The splash's pictures, checked without drawing a window.
///
/// `Image("name", bundle: .module)` against a SwiftPM asset catalogue comes back
/// empty, and a splash with no picture on it still lays out perfectly — so the
/// only assertion that catches it is one about the bytes.
@Suite struct SplashArtTests {

    @Test func theContactSheetIsActuallyThere() {
        let art = AboutView.keyArtImage
        #expect(art.size.width > 0)
        #expect(art.size.height > 0)
    }

    @Test func theContactSheetIsTheShapeTheBannerNeeds() {
        let art = AboutView.keyArtImage
        // 640 × 250, the full-bleed banner. Anything else is letterboxed or
        // cropped by `scaledToFill`, which is not visible in a layout test.
        #expect(abs(art.size.width / art.size.height - 640.0 / 250.0) < 0.01)
    }

    @Test func theMarkIsActuallyThere() {
        #expect(AboutView.logoImage.size.height > 0)
    }

    /// The lockup's height comes from font metrics, not from a number someone
    /// liked the look of.
    @Test func theLogoIsAsTallAsTheTwoLinesOfTypeBesideIt() {
        // 36pt semibold over 13pt regular currently measures about 48pt.
        #expect(AboutView.logoHeight > 40)
        #expect(AboutView.logoHeight < 60)
    }

    /// The mark is measured by its ink, so a PDF with a margin is corrected
    /// rather than drawn short.
    @Test func theFrameIsGrownToCompensateForTheMarksOwnMargin() {
        #expect(AboutView.logoInkFraction > 0.5)
        #expect(AboutView.logoInkFraction <= 1)
        #expect(AboutView.logoFrameHeight >= AboutView.logoHeight)
    }

    @Test func theWordsSayWhatTheApplicationDoesAndWhatItDoesNot() {
        #expect(AboutView.about.contains("Flickr"))
        #expect(AboutView.about.contains("licence"))
        #expect(AboutView.about.contains("not made by or affiliated with Flickr"))
        #expect(AboutView.legal.contains("Keychain"))
    }
}

/// The studio mark in the corner of the window's status bar, as Nino and
/// Hipparchus have it.
@MainActor
@Suite struct MakersMarkTests {
    /// Two points taller than a status-bar symbol, measured from the system
    /// font so it follows the user's text size.
    @Test func theMarkIsASymbolAndTwoPointsTall() {
        #expect(TsevisMakersMark.height > 14)
        #expect(TsevisMakersMark.height < 24)
        #expect(TsevisMakersMark.link == URL(string: "https://tsevis.com"))
    }

    /// Drawn, not a blank frame: the PDF loads and puts ink in the corner.
    @Test func theStatusBarDrawsTheMarkAtItsLeft() throws {
        let renderer = ImageRenderer(content: TsevisMakersMark().padding(4)
            .background(Color.white))
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var inked = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                if let colour = bitmap.colorAt(x: x, y: y), colour.brightnessComponent < 0.8 { inked += 1 }
            }
        }
        #expect(inked > 20)
    }
}
