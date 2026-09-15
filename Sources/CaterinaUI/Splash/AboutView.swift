import AppKit
import SwiftUI

/// What this is, who made it, and what it owes.
///
/// Shown once at launch and reachable afterwards from the application menu. A
/// splash screen is unusual on macOS and this one earns its place by carrying
/// the thing a bulk downloader has to say out loud: the photographs are not
/// yours, and their licences travel with them.
///
/// The key art is a contact sheet, which is what the application makes — a page
/// of other people's frames, some of them still waiting for their bytes.
public struct AboutView: View {
    /// Dismisses the window. Supplied by whatever presented it.
    public var close: () -> Void

    public init(close: @escaping () -> Void) { self.close = close }

    @Environment(\.openURL) private var openURL
    @AppStorage(AboutWindowController.showOnLaunchKey) private var showOnLaunch = true

    /// **Loaded by URL rather than by asset name, and that is not a preference.**
    /// `Image("name", bundle: .module)` against a SwiftPM asset catalogue comes
    /// back empty: the splash renders as a grey rectangle with no picture on it
    /// and every assertion about the layout still passes. `resource(_:_:)`
    /// returns a real `NSImage` or nothing, and `SplashArtTests` fails if it is
    /// nothing.
    static func resource(_ name: String, _ extension: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: "Resources/\(name)",
                                          withExtension: `extension`)
            ?? Bundle.module.url(forResource: name, withExtension: `extension`)
        else { return nil }
        return NSImage(contentsOf: url)
    }

    static let keyArtImage = resource("ContactSheetAbout", "png") ?? NSImage()
    static let logoImage = resource("TVDLogo", "pdf") ?? NSImage()

    private static let version = Bundle.main
        .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"

    // MARK: - The lockup

    private static let titleSize: CGFloat = 36
    private static let subtitleSize: CGFloat = 13
    private static let keyArtHeight: CGFloat = 250

    /// Cap height of the title down to the baseline of the subtitle.
    ///
    /// The mark should read as the same object as the words beside it, which
    /// means matching the block the type actually occupies — not the line box,
    /// which hangs empty space above the capitals and below the last baseline.
    /// Measured from the fonts rather than guessed, so it stays right if either
    /// size changes.
    static let logoHeight: CGFloat = {
        let title = NSFont.systemFont(ofSize: titleSize, weight: .semibold)
        let subtitle = NSFont.systemFont(ofSize: subtitleSize)

        // A line box places the baseline `ascender` below its top, so the
        // capitals begin `ascender - capHeight` down from it.
        let titleCapInset = title.ascender - title.capHeight
        let titleLine = title.ascender - title.descender
        let subtitleBaseline = titleLine + subtitle.ascender

        return subtitleBaseline - titleCapInset
    }()

    /// How much of the mark's own bounds the drawn artwork fills.
    ///
    /// **The PDF carries a margin, and a frame is not a plate.** Setting the
    /// frame to `logoHeight` puts the mark's *box* on cap-height-to-baseline and
    /// draws a plate shorter than the words beside it. The lockup is supposed to
    /// read as one object, so what has to match the type is the ink, not the box.
    static let logoInkFraction: CGFloat = {
        let image = logoImage
        guard image.size.height > 0,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.height > 0,
              let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        else { return 1 }

        let rowBytes = cg.bytesPerRow
        let pixelBytes = cg.bitsPerPixel / 8
        // The alpha channel is where the margin is.
        let alphaOffset = pixelBytes - 1
        // The plate, not every mark on the artboard: a row counts only if it is
        // *mostly* inked, which the plate is and a registration mark never is.
        let solidEnough = cg.width * 2 / 5

        var top: Int?
        var bottom: Int?
        for y in 0..<cg.height {
            var inked = 0
            for x in 0..<cg.width
            where bytes[y * rowBytes + x * pixelBytes + alphaOffset] > 8 {
                inked += 1
            }
            if inked >= solidEnough {
                if top == nil { top = y }
                bottom = y
            }
        }
        guard let top, let bottom, bottom >= top else { return 1 }
        let fraction = CGFloat(bottom - top + 1) / CGFloat(cg.height)
        // A mark that fills its bounds needs no correction; a nonsense
        // measurement must not blow the lockup up.
        return fraction > 0.5 ? fraction : 1
    }()

    /// The frame that makes the *drawn* mark exactly as tall as the two lines of
    /// type beside it.
    static var logoFrameHeight: CGFloat { logoHeight / logoInkFraction }

    public var body: some View {
        VStack(spacing: 0) {
            keyArt
            body(of: Self.about)
            Spacer(minLength: 0)
            footer
        }
        .frame(width: 640, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - The contact sheet, full bleed

    private var keyArt: some View {
        ZStack(alignment: .bottomLeading) {
            Image(nsImage: Self.keyArtImage)
                .resizable()
                .scaledToFill()
                .frame(height: Self.keyArtHeight)
                .clipped()

            // A short scrim, so white type stays legible over the brightest
            // frames without dimming the whole sheet.
            LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.30)],
                           startPoint: .center, endPoint: .bottom)
                .frame(height: Self.keyArtHeight)

            // `.lastTextBaseline` puts the mark's bottom edge on the subtitle's
            // baseline — a view with no text of its own reports its bottom for
            // that guide — so the logo occupies exactly the block the two lines
            // of type describe, rather than a height picked by eye.
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Image(nsImage: Self.logoImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: Self.logoFrameHeight)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Caterina")
                        .font(.system(size: Self.titleSize, weight: .semibold))
                        .tracking(-0.6)
                    Text("Your Flickr library, whole")
                        .font(.system(size: Self.subtitleSize, weight: .regular))
                        .opacity(0.85)
                }
                Spacer()
                Text(Self.version)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
            .padding(.horizontal, 26)
            .padding(.bottom, 20)
        }
        .frame(height: Self.keyArtHeight)
        .accessibilityHidden(true)
    }

    // MARK: - The words

    private func body(of text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(.primary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 26)
            .padding(.top, 20)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            DisclosureGroup {
                ScrollView {
                    Text(Self.legal)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 110)
                .padding(.top, 6)
            } label: {
                Text("Licences and credits")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 12)

            Divider()

            HStack(spacing: 14) {
                Toggle("Show at launch", isOn: $showOnLaunch)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                link("tsevis.com", "https://tsevis.com")

                Button("Continue", action: close)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 12)

            Text("Created by Charis Tsevis, with the help of Claude Code.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 26)
                .padding(.bottom, 12)
        }
        .background(.bar)
    }

    private func link(_ label: String, _ address: String) -> some View {
        Button(label) {
            guard let url = URL(string: address) else { return }
            openURL(url)
        }
        .buttonStyle(.link)
        .font(.system(size: 11))
        .pointerStyle(.link)
    }

    // MARK: - The text

    static let about = """
    Named for Caterina Fake, who co-founded Flickr in 2004. It downloads from \
    Flickr at the size you pick, uploads with titles, tags and albums already \
    set, organizes your library in batches (tags, albums, groups, who can see \
    what) with every change undoable and a delete that waits a minute, and \
    browses the numbers behind your own photographs.

    The photographs are not yours. The licence shown beside a photo is the one \
    Flickr publishes for it: All Rights Reserved means exactly that, and a \
    Creative Commons licence still asks for attribution. This fetches files. It \
    does not grant permission, and it is not made by or affiliated with Flickr.

    \(FlickrTerms.notice)
    """

    static let legal = """
    Photographs, titles and licence information come from the Flickr API, \
    © the photographers who made them. Flickr is a trademark of SmugMug, Inc.; \
    this is an independent, free application. \(FlickrTerms.notice)

    \(FlickrTerms.privacy)

    Sign-in uses Flickr's own OAuth pages in a system browser window. Your API \
    key, secret and access token are kept in the macOS Keychain and are never \
    written to a file or sent anywhere but Flickr.

    Built with Swift and SwiftUI. The library copy is stored with GRDB \
    (MIT licence, © Gwendal Roué); no other third-party library is linked.

    GRDB.swift
    \(ThirdPartyLicences.grdb)
    """
}
