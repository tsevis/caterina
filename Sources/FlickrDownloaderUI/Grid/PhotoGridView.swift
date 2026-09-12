import SwiftUI

import FlickrKit

/// The grid, and the selection behaviour a Mac user expects from one.
///
/// Click replaces the selection, ⌘-click toggles one, ⇧-click extends a range,
/// ⌘A selects the page and a drag on the background sweeps a marquee. Not
/// per-tile checkboxes: a checkbox in every cell is a web idiom, and it costs a
/// quarter of every thumbnail.
public struct PhotoGridView: View {
    public let photos: [Photo]
    public let selection: Set<String>
    public let onSelect: (Set<String>) -> Void
    public let onPreview: (Photo) -> Void

    /// Where ⇧-click measures from.
    @State private var anchor: String?
    @State private var marquee: MarqueeState?
    @State private var frames: [String: CGRect] = [:]

    public init(photos: [Photo], selection: Set<String>,
                onSelect: @escaping (Set<String>) -> Void,
                onPreview: @escaping (Photo) -> Void) {
        self.photos = photos
        self.selection = selection
        self.onSelect = onSelect
        self.onPreview = onPreview
    }

    public var body: some View {
        GeometryReader { _ in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.Metrics.tileMinimum),
                                             spacing: Theme.Metrics.tileSpacing)],
                          spacing: Theme.Metrics.tileSpacing) {
                    ForEach(photos) { photo in
                        PhotoTile(photo: photo, isSelected: selection.contains(photo.id))
                            .background(frameReader(for: photo.id))
                            .onTapGesture { click(photo) }
                            .simultaneousGesture(TapGesture().modifiers(.command)
                                .onEnded { commandClick(photo) })
                            .simultaneousGesture(TapGesture().modifiers(.shift)
                                .onEnded { shiftClick(photo) })
                            .contextMenu { menu(for: photo) }
                    }
                }
                .padding(Theme.Metrics.tileSpacing)
                .coordinateSpace(name: Self.space)
            }
            .background(marqueeCatcher)
            .overlay(alignment: .topLeading) { marqueeRectangle }
        }
        .onPreferenceChange(TileFramePreference.self) { frames = $0 }
        .focusable()
        .onKeyPress(.space) {
            if let photo = photos.first(where: { selection.contains($0.id) }) {
                onPreview(photo)
                return .handled
            }
            return .ignored
        }
    }

    private static let space = "photo-grid"

    // MARK: - Clicks

    private func click(_ photo: Photo) {
        anchor = photo.id
        onSelect([photo.id])
    }

    private func commandClick(_ photo: Photo) {
        anchor = photo.id
        var next = selection
        if next.contains(photo.id) { next.remove(photo.id) } else { next.insert(photo.id) }
        onSelect(next)
    }

    private func shiftClick(_ photo: Photo) {
        guard let anchor,
              let start = photos.firstIndex(where: { $0.id == anchor }),
              let end = photos.firstIndex(where: { $0.id == photo.id })
        else {
            click(photo)
            return
        }
        let range = start <= end ? start...end : end...start
        onSelect(selection.union(photos[range].map(\.id)))
    }

    @ViewBuilder
    private func menu(for photo: Photo) -> some View {
        Button("Quick Look") { onPreview(photo) }
        if let address = photo.downloadURL(preferring: .original),
           let url = URL(string: address) {
            Link("Open in Browser", destination: url)
        }
    }

    // MARK: - Marquee

    private struct MarqueeState: Equatable {
        var start: CGPoint
        var current: CGPoint
        var base: Set<String>

        var rect: CGRect {
            CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                   width: abs(start.x - current.x), height: abs(start.y - current.y))
        }
    }

    /// The background takes the drag, so a drag that begins on a tile is a
    /// click and a drag that begins between them is a sweep.
    private var marqueeCatcher: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        let state = marquee ?? MarqueeState(start: value.startLocation,
                                                            current: value.location,
                                                            base: [])
                        marquee = MarqueeState(start: state.start,
                                               current: value.location,
                                               base: state.base)
                        onSelect(swept(in: state.rect.union(
                            CGRect(origin: value.location, size: .zero))))
                    }
                    .onEnded { _ in marquee = nil }
            )
    }

    @ViewBuilder
    private var marqueeRectangle: some View {
        if let marquee {
            Rectangle()
                .fill(Color.accentColor.opacity(0.15))
                .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.6)))
                .frame(width: marquee.rect.width, height: marquee.rect.height)
                .offset(x: marquee.rect.minX, y: marquee.rect.minY)
                .allowsHitTesting(false)
        }
    }

    private func swept(in rect: CGRect) -> Set<String> {
        Set(frames.filter { $0.value.intersects(rect) }.keys)
    }

    private func frameReader(for id: String) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key: TileFramePreference.self,
                                   value: [id: geometry.frame(in: .named(Self.space))])
        }
    }
}

/// Where each tile is, so a marquee can be hit-tested against them.
struct TileFramePreference: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
