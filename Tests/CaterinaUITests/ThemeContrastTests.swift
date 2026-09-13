import AppKit
import SwiftUI
import Testing

@testable import CaterinaUI

/// Contrast, measured in both appearances rather than asserted in a comment.
///
/// The palette's ratios were worked out once, by hand, in a script that no
/// longer exists. That is not a guarantee: the next person to nudge the amber
/// a shade darker has nothing to fail. These resolve each colour under the
/// real light and dark appearances and apply the WCAG formula, so the claim
/// stands or falls with the code.
@MainActor
@Suite struct ThemeContrastTests {

    // MARK: - Measuring

    private func resolved(_ color: Color, dark: Bool) -> NSColor {
        let name: NSAppearance.Name = dark ? .darkAqua : .aqua
        var out = NSColor.black
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            out = NSColor(color).usingColorSpace(.sRGB) ?? .black
        }
        return out
    }

    /// Flatten a partly transparent colour onto what is behind it — a label at
    /// 55% alpha is not the colour it declares.
    private func flatten(_ colour: NSColor, over background: NSColor) -> NSColor {
        let alpha = colour.alphaComponent
        guard alpha < 1 else { return colour }
        return NSColor(
            srgbRed: colour.redComponent * alpha + background.redComponent * (1 - alpha),
            green: colour.greenComponent * alpha + background.greenComponent * (1 - alpha),
            blue: colour.blueComponent * alpha + background.blueComponent * (1 - alpha),
            alpha: 1)
    }

    /// WCAG 2.1 relative luminance.
    private func luminance(_ colour: NSColor) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(colour.redComponent)
            + 0.7152 * channel(colour.greenComponent)
            + 0.0722 * channel(colour.blueComponent)
    }

    private func contrast(_ foreground: Color, on background: Color, dark: Bool) -> Double {
        let ground = resolved(background, dark: dark)
        let ink = flatten(resolved(foreground, dark: dark), over: ground)
        let (high, low) = (max(luminance(ink), luminance(ground)),
                           min(luminance(ink), luminance(ground)))
        return (high + 0.05) / (low + 0.05)
    }

    // MARK: - Type on its ground

    @Test(arguments: [false, true])
    func bodyTextClearsAAAInBothAppearances(dark: Bool) {
        let ratio = contrast(Theme.ink, on: Theme.ground, dark: dark)
        #expect(ratio >= 7, "ink on ground is \(ratio) in \(dark ? "dark" : "light")")
    }

    /// The reason `Theme.inkSecondary` is defined rather than inherited:
    /// `secondaryLabelColor` measures 3.82:1 here, and `tertiaryLabelColor`
    /// 1.86:1.
    @Test(arguments: [false, true])
    func supportingTextClearsAAInBothAppearances(dark: Bool) {
        let ratio = contrast(Theme.inkSecondary, on: Theme.ground, dark: dark)
        #expect(ratio >= 4.5,
                "secondary ink on ground is \(ratio) in \(dark ? "dark" : "light")")
    }

    // MARK: - The identity amber

    /// The amber is a fill, not type: white on it is 3.1:1, which is why type
    /// *on* it is near-black instead.
    @Test(arguments: [false, true])
    func typeOnTheAmberFillIsLegible(dark: Bool) {
        let ratio = contrast(Theme.markInk, on: Theme.mark, dark: dark)
        #expect(ratio >= 4.5, "mark ink on mark is \(ratio) in \(dark ? "dark" : "light")")
    }

    @Test(arguments: [false, true])
    func theAmberUsedAsTypeIsLegibleOnItsOwnGround(dark: Bool) {
        let ratio = contrast(Theme.markText, on: Theme.ground, dark: dark)
        #expect(ratio >= 4.5, "mark text on ground is \(ratio) in \(dark ? "dark" : "light")")
    }

    /// Light and dark must actually differ, or one of them was never designed.
    @Test func theAmberUsedAsTypeChangesWithTheAppearance() {
        let light = resolved(Theme.markText, dark: false)
        let dark = resolved(Theme.markText, dark: true)
        #expect(abs(luminance(light) - luminance(dark)) > 0.05)
    }

    // MARK: - Not Flickr's

    /// This is not an official Flickr client and must not read as one, so the
    /// identity colour is kept well away from Flickr's own blue and pink.
    @Test func theIdentityColourIsNotFlickrsBranding() {
        let amber = resolved(Theme.mark, dark: false)
        for brand in [NSColor(srgbRed: 0x00 / 255, green: 0x63 / 255, blue: 0xDC / 255, alpha: 1),
                      NSColor(srgbRed: 0xFF / 255, green: 0x00 / 255, blue: 0x84 / 255, alpha: 1)] {
            let distance = sqrt(pow(amber.redComponent - brand.redComponent, 2)
                                + pow(amber.greenComponent - brand.greenComponent, 2)
                                + pow(amber.blueComponent - brand.blueComponent, 2))
            #expect(distance > 0.4, "too close to a Flickr brand colour")
        }
    }

    // MARK: - Surfaces

    @Test func everySurfaceResolvesDifferentlyInDarkMode() {
        for (name, colour) in [("well", Theme.well), ("hairline", Theme.hairline)] {
            let light = resolved(colour, dark: false)
            let dark = resolved(colour, dark: true)
            #expect(light != dark, "\(name) is the same in both appearances")
        }
    }
}
