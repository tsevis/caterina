import SwiftUI

import FlickrKit

/// One photo in the grid.
public struct PhotoTile: View {
    public let photo: Photo
    public let isSelected: Bool

    @State private var image: NSImage?
    @State private var didFail = false
    @State private var isHovering = false

    public init(photo: Photo, isSelected: Bool) {
        self.photo = photo
        self.isSelected = isSelected
    }

    public var body: some View {
        // **The photo must not have a say in how big the tile is.**
        // As a `ZStack` child, a `.resizable().scaledToFill()` image reports the
        // size it wants to fill at — larger than the cell in one dimension for
        // any photo that is not square — and the stack grew to match, so a
        // landscape photo spilled out of its column and over the tile beside
        // it. An empty square decides the layout; the artwork is an overlay,
        // which by definition cannot change it, and the clip crops it.
        PhotoTileLayout { TileArtwork(image: image, didFail: didFail) }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius)
                .strokeBorder(border, lineWidth: isSelected ? 3 : 1)
        }
        // A pointer over a tile should say so before it is clicked; the lift is
        // small because a grid of them all moving at once is a fairground.
        .scaleEffect(isHovering && !isSelected ? 1.015 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .overlay(alignment: .bottomLeading) { licenceBadge }
        .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
        // `.task(id:)` is the cancellation: when the tile is recycled onto a
        // different photo, or scrolled away, the fetch for the old one is
        // cancelled rather than left to draw into the wrong cell.
        .task(id: photo.id) { await load() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isImage, .isSelected] : .isImage)
        .help(photo.title.isEmpty ? "Untitled" : photo.title)
    }

    private var border: Color {
        if isSelected { return .accentColor }
        return isHovering ? Color.accentColor.opacity(0.55) : Theme.hairline
    }

    /// **Every photo gets a badge, and no two licences share one.**
    /// Collapsing sixteen licences into "CC" and "CC-NC" told someone holding a
    /// No-Derivatives photograph the same thing it told someone holding a CC0
    /// one, and showed nothing at all for All Rights Reserved — which is not
    /// the same as a photo whose licence Flickr never stated.
    @ViewBuilder
    private var licenceBadge: some View {
        Text(photo.license?.badge ?? "?")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(badgeInk)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(badgeGround, in: Capsule())
            .padding(5)
            .help(photo.license?.label ?? "Flickr did not state a licence for this photo.")
            .accessibilityHidden(true)
    }

    /// Reusable is the app's own amber; everything else is a material, so the
    /// eye is drawn to what can be used rather than to what cannot.
    private var badgeGround: AnyShapeStyle {
        switch photo.license?.reuse {
        case .permitted: return AnyShapeStyle(Theme.mark)
        default: return AnyShapeStyle(.thinMaterial)
        }
    }

    private var badgeInk: Color {
        photo.license?.reuse == .permitted ? Theme.markInk : Theme.ink
    }

    private var accessibilityLabel: String {
        let title = photo.title.isEmpty ? "Untitled photo" : photo.title
        guard let licence = photo.license else {
            return "\(title). Flickr did not state a licence."
        }
        let reuse: String
        switch licence.reuse {
        case .permitted: reuse = "reusable"
        case .nonCommercialOnly: reuse = "non-commercial use only"
        case .reserved: reuse = "all rights reserved"
        case .unclear: reuse = "rights not cleared"
        }
        return "\(title). \(licence.label), \(reuse)."
    }

    private func load() async {
        guard let address = photo.gridThumbnailURL() else {
            didFail = true
            return
        }
        image = nil
        didFail = false
        let loaded = await ThumbnailStore.shared.image(for: address)
        guard !Task.isCancelled else { return }
        image = loaded
        didFail = loaded == nil
    }
}

/// A square cell that its contents cannot resize.
///
/// **The photo must not have a say in how big the tile is.** As a `ZStack`
/// child, a `.resizable().scaledToFill()` image reports the size it wants to
/// fill at — larger than the cell in one dimension for any photo that is not
/// square — and the stack grew to match, so a landscape photo spilled out of
/// its column and drew over the tile beside it. An empty square decides the
/// layout; the artwork is an overlay, which by definition cannot change it,
/// and the clip crops it.
struct PhotoTileLayout<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { content }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
    }
}

/// What is drawn inside a tile, given no say in how large the tile is.
///
/// Separate from `PhotoTile` so the sizing rule above can be tested with an
/// image in hand, rather than only with one the network happens to deliver.
struct TileArtwork: View {
    let image: NSImage?
    let didFail: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.well)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if didFail {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }
}
