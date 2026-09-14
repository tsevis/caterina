import AppKit
import SwiftUI

/// Whose app this is, in the corner of the status bar.
///
/// The same compact, linked mark as Nino and Hipparchus: it names the maker
/// without competing with the library's status beside it.
struct TsevisMakersMark: View {
    @Environment(\.openURL) private var openURL

    static let link = URL(string: "https://tsevis.com")

    /// Two points taller than a status bar's standard symbol, measured from
    /// the configured symbol so the mark keeps its place if the system font
    /// size changes.
    static let height: CGFloat = {
        let symbol = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        let configured = symbol?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .regular))
        return (configured?.size.height ?? 16) + 2
    }()

    var body: some View {
        Button {
            guard let url = Self.link else { return }
            openURL(url)
        } label: {
            Image(nsImage: AboutView.logoImage)
                .resizable()
                .scaledToFit()
                .frame(height: Self.height)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("tsevis.com")
        .accessibilityLabel("Charis Tsevis — tsevis.com")
    }
}
