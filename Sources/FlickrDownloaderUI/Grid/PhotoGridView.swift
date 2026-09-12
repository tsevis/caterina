import AppKit
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

    /// Where ⇧-click measures from, and where the arrow keys are.
    @State private var anchor: String?
    /// What the download sheet's size picker is set to, so a dragged photo is
    /// the same file a downloaded one would be.
    let dragVariant: PhotoVariant
    @State private var marquee: MarqueeState?
    @State private var frames: [String: CGRect] = [:]

    public init(photos: [Photo], selection: Set<String>,
                onSelect: @escaping (Set<String>) -> Void,
                onPreview: @escaping (Photo) -> Void,
                dragVariant: PhotoVariant = .defaultDownload) {
        self.photos = photos
        self.selection = selection
        self.onSelect = onSelect
        self.onPreview = onPreview
        self.dragVariant = dragVariant
    }

    public var body: some View {
        ScrollView {
            // One coordinate space for the whole content, declared *above* both
            // the tiles that report their frames and the surface that reads the
            // drag. They were in different spaces before, so a sweep two rows
            // down the scroll selected tiles two rows up.
            ZStack(alignment: .topLeading) {
                sweepSurface
                grid
                marqueeRectangle
            }
            .coordinateSpace(name: Self.space)
        }
        .onPreferenceChange(TileFramePreference.self) { frames = $0 }
        .focusable()
        .onKeyPress(.space) {
            guard let photo = focused else { return .ignored }
            onPreview(photo)
            return .handled
        }
        .onKeyPress(.leftArrow) { move(by: -1) }
        .onKeyPress(.rightArrow) { move(by: 1) }
        .onKeyPress(.upArrow) { move(by: -columnCount) }
        .onKeyPress(.downArrow) { move(by: columnCount) }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.Metrics.tileMinimum),
                                     spacing: Theme.Metrics.tileSpacing)],
                  spacing: Theme.Metrics.tileSpacing) {
            ForEach(photos) { photo in
                PhotoTile(photo: photo, isSelected: selection.contains(photo.id))
                    .background(frameReader(for: photo.id))
                    // **One tap handler, not three.** A plain `.onTapGesture`
                    // also recognises a ⌘-click, so adding modifier gestures
                    // beside it ran two handlers for every modified click —
                    // each computing its answer from the same stale selection,
                    // and the last writer won.
                    .onTapGesture { click(photo, modifiers: NSEvent.modifierFlags) }
                    .onDrag {
                        // Dragging an unselected photo drags that one; dragging
                        // a selected one drags the selection, which is what
                        // every Mac list does.
                        if !selection.contains(photo.id) { click(photo, modifiers: []) }
                        return PhotoDrag.provider(for: photo, variant: dragVariant)
                    }
                    .contextMenu { menu(for: photo) }
            }
        }
        .padding(Theme.Metrics.tileSpacing)
    }

    private static let space = "photo-grid"

    // MARK: - Clicks

    /// Click replaces, ⌘-click toggles, ⇧-click extends from the anchor.
    private func click(_ photo: Photo, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            anchor = photo.id
            var next = selection
            if next.contains(photo.id) { next.remove(photo.id) } else { next.insert(photo.id) }
            onSelect(next)
            return
        }

        if modifiers.contains(.shift),
           let anchor,
           let start = photos.firstIndex(where: { $0.id == anchor }),
           let end = photos.firstIndex(where: { $0.id == photo.id }) {
            // The anchor stays where it was, so a second ⇧-click re-measures
            // from the same place rather than from the last one.
            let range = start <= end ? start...end : end...start
            onSelect(selection.union(photos[range].map(\.id)))
            return
        }

        anchor = photo.id
        onSelect([photo.id])
    }

    @ViewBuilder
    private func menu(for photo: Photo) -> some View {
        Button("Quick Look") { onPreview(photo) }
        if let address = photo.downloadURL(preferring: .original),
           let url = URL(string: address) {
            Link("Open in Browser", destination: url)
        }
    }

    // MARK: - Keyboard

    private var focused: Photo? {
        if let anchor, let photo = photos.first(where: { $0.id == anchor }) { return photo }
        return photos.first { selection.contains($0.id) }
    }

    /// How many tiles are on a row, measured from where they actually are.
    ///
    /// The grid's columns are adaptive, so the number depends on the window's
    /// width — computing it from the tile frames means the arrow keys follow
    /// the rows the user can see rather than a number fixed in code.
    private var columnCount: Int {
        guard let top = frames.values.map(\.minY).min() else { return 1 }
        return max(1, frames.values.filter { abs($0.minY - top) < 1 }.count)
    }

    private func move(by offset: Int) -> KeyPress.Result {
        guard !photos.isEmpty else { return .ignored }
        let current = focused.flatMap { photo in photos.firstIndex { $0.id == photo.id } } ?? 0
        let next = min(max(0, current + offset), photos.count - 1)
        guard next != current || focused == nil else { return .handled }
        click(photos[next], modifiers: [])
        return .handled
    }

    // MARK: - Marquee

    private struct MarqueeState: Equatable {
        var start: CGPoint
        var current: CGPoint

        /// Rebuilt from the two live corners every time. The previous version
        /// unioned the new point into the *old* rectangle, so the selection
        /// only ever grew: sweeping out to twenty tiles and back to three left
        /// twenty selected under a rectangle drawn around three.
        var rect: CGRect {
            CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                   width: abs(start.x - current.x), height: abs(start.y - current.y))
        }
    }

    /// The surface behind the tiles takes the drag, so a drag that begins on a
    /// tile is a click and a drag that begins between them is a sweep.
    private var sweepSurface: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        let state = MarqueeState(start: value.startLocation,
                                                 current: value.location)
                        marquee = state
                        onSelect(swept(in: state.rect))
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
