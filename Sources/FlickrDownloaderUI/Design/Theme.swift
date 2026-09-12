import AppKit
import SwiftUI

/// The application's colours.
///
/// **Controls are not themed.** They use the system accent, so the window looks
/// right under whatever accent colour the person using it has chosen — which is
/// the macOS contract and the reason this is not a dark hand-rolled stylesheet
/// like the PyQt application it replaces.
///
/// What is defined here is the small identity palette: the tungsten amber of
/// the app icon's own tiles — `Scripts/make-icon.py`, `TUNGSTEN` — used for the
/// few places that are about *this* application rather than about a control, so
/// the interface and the icon in the Dock beside it agree. It is deliberately not Flickr's
/// blue or pink — this is not an official Flickr client and must not read as
/// one.
///
/// Every colour is a *dynamic* `NSColor` rather than a SwiftUI colour resolved
/// at read time. Appearance can change under a view that is already on screen —
/// the system switching at sunset, or a window dragged to another display — and
/// a value resolved once does not follow.
public enum Theme {

    // MARK: - Identity
    //
    // Measured, not guessed. The amber fill is 3.13:1 against white, which is
    // fine for a fill and not enough for type, so type *on* it is near-black
    // (5.44:1) and the amber used *as* type is a darker value on light
    // (5.60:1) and a lighter one on dark (8.10:1).

    /// The identity fill: the tungsten in the key art.
    public static let mark = dynamic(light: 0xC0863C, dark: 0xC0863C)
    /// Type on an amber fill. Near-black clears 5.44:1 on it; white does not.
    public static let markInk = dynamic(light: 0x1D1D1F, dark: 0x1D1D1F)
    /// The amber used as type, legible on either ground.
    public static let markText = dynamic(light: 0x8F5D18, dark: 0xE0A95C)

    // MARK: - Surfaces
    //
    // System materials wherever a material is right — `.bar`, `.regularMaterial`
    // and `windowBackgroundColor` all follow the appearance and the desktop
    // behind them. These are for the few surfaces that have to be a colour.

    public static let ground = Color(nsColor: .windowBackgroundColor)
    public static let panel = Color(nsColor: .controlBackgroundColor)
    /// The well a thumbnail sits in before its image arrives.
    public static let well = dynamicAlpha(light: (0x3C3C43, 0.08), dark: (0xEBEBF5, 0.08))
    public static let hairline = dynamicAlpha(light: (0x3C3C43, 0.16), dark: (0xEBEBF5, 0.13))

    // MARK: - Type

    public static let ink = Color(nsColor: .labelColor)

    /// **Not `secondaryLabelColor`.** Measured against the window background,
    /// Apple's is 3.82:1 in light — under the 4.5:1 that supporting text has to
    /// clear — and `tertiaryLabelColor` is 1.86:1, which is not legible text by
    /// any standard. Every word this application shows carries meaning, so the
    /// supporting ink is defined here and `ThemeContrastTests` holds it to the
    /// figure in both appearances.
    public static let inkSecondary = dynamic(light: 0x4A4A4A, dark: 0xABABAB)

    // MARK: - Metrics

    public enum Metrics {
        /// The grid's smallest comfortable thumbnail.
        public static let tileMinimum: CGFloat = 128
        public static let tileSpacing: CGFloat = 12
        public static let cornerRadius: CGFloat = 6
        public static let inspectorWidth: CGFloat = 260
        public static let sidebarWidth: CGFloat = 190
    }

    // MARK: - Building dynamic colours

    static func dynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(rgb: dark) : NSColor(rgb: light)
        })
    }

    static func dynamicAlpha(light: (Int, Double), dark: (Int, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let (value, alpha) = appearance.isDark ? dark : light
            return NSColor(rgb: value).withAlphaComponent(alpha)
        })
    }
}

extension NSAppearance {
    /// Whether this appearance is one of the dark ones, including the
    /// high-contrast and vibrant variants.
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

extension NSColor {
    convenience init(rgb: Int) {
        self.init(srgbRed: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
