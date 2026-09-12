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
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius)
                .fill(Theme.well)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if didFail {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(Theme.inkTertiary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
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

    @ViewBuilder
    private var licenceBadge: some View {
        if let licence = photo.license, licence != .allRightsReserved {
            Text(licence.allowsCommercialUse ? "CC" : "CC-NC")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.markInk)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Theme.mark, in: Capsule())
                .padding(5)
                .accessibilityHidden(true)
        }
    }

    private var accessibilityLabel: String {
        let title = photo.title.isEmpty ? "Untitled photo" : photo.title
        let licence = photo.license?.label ?? "licence not stated"
        return "\(title). \(licence)."
    }

    private func load() async {
        guard let address = photo.thumbnailURL() else {
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
