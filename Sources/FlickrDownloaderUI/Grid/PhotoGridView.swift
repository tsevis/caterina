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
    /// A click and what was held with it. The *meaning* of the click is
    /// `GridSelection`'s business, not this view's.
    public let onClick: (String, ClickModifiers) -> Void
    public let onSweep: (Set<String>) -> Void
    public let onMove: (Int) -> Void
    public let onPreview: (Photo) -> Void

    /// What the download sheet's size picker is set to, so a dragged photo is
    /// the same file a downloaded one would be.
    let dragVariant: PhotoVariant
    @State private var marquee: MarqueeState?
    @State private var frames: [String: CGRect] = [:]

    public init(photos: [Photo], selection: Set<String>,
                onClick: @escaping (String, ClickModifiers) -> Void,
                onSweep: @escaping (Set<String>) -> Void,
                onMove: @escaping (Int) -> Void,
                onPreview: @escaping (Photo) -> Void,
                dragVariant: PhotoVariant = .defaultDownload) {
        self.photos = photos
        self.selection = selection
        self.onClick = onClick
        self.onSweep = onSweep
        self.onMove = onMove
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
        // The ring the system draws for this goes around the *scroll content*,
        // which is one row tall when there are two photos — a blue rectangle
        // across the window with the tiles sitting inside it. What is focused
        // in a grid is a photo, and the accent border on the selected tile is
        // already saying so.
        .focusEffectDisabled()
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
                    .onTapGesture { onClick(photo.id, Self.modifiers()) }
                    .onDrag {
                        // Dragging an unselected photo drags that one; dragging
                        // a selected one drags the selection, which is what
                        // every Mac list does.
                        if !selection.contains(photo.id) { onClick(photo.id, []) }
                        return PhotoDrag.provider(for: photo, variant: dragVariant)
                    }
                    .contextMenu { menu(for: photo) }
            }
        }
        .padding(Theme.Metrics.tileSpacing)
    }

    private static let space = "photo-grid"

    // MARK: - Clicks

    /// What the keyboard is holding right now.
    ///
    /// Read from `NSEvent` at the moment of the tap rather than taken from
    /// three gesture recognisers: a plain `.onTapGesture` also fires on a
    /// ⌘-click, so modifier gestures beside it ran two handlers for every
    /// modified click, each computing its answer from the same stale selection.
    private static func modifiers() -> ClickModifiers {
        var held: ClickModifiers = []
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) { held.insert(.command) }
        if flags.contains(.shift) { held.insert(.shift) }
        return held
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
        photos.first { selection.contains($0.id) }
    }

    private var columnCount: Int { Marquee.columnCount(in: frames) }

    private func move(by offset: Int) -> KeyPress.Result {
        guard !photos.isEmpty else { return .ignored }
        onMove(offset)
        return .handled
    }

    // MARK: - Marquee

    private struct MarqueeState: Equatable {
        var start: CGPoint
        var current: CGPoint

        var rect: CGRect { Marquee.rect(from: start, to: current) }
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
                        onSweep(swept(in: state.rect))
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
        Marquee.covered(frames, by: rect)
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
