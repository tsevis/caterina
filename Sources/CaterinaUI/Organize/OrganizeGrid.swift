import AppKit
import SwiftUI

import CaterinaLibrary
import FlickrKit

/// Your photos as tiles, with the selection a Mac grid has: click, ⌘-click,
/// ⇧-click, ⌘A, arrows, and a marquee swept from the background.
///
/// The sweep follows `PhotoGridView`'s hard-won rules: one coordinate space
/// above both the tiles and the surface, and the viewport's height as a
/// floor so a sweep can begin below the last row.
struct OrganizeGrid: View {
    let organize: OrganizeModel
    @AppStorage("OrganizeTileSize") private var tileSize = 150.0
    @State private var marquee: CGRect?
    @State private var frames: [String: CGRect] = [:]

    private static let space = "organize-grid"

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        sweepSurface
                        tiles
                        marqueeRectangle
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                    .coordinateSpace(name: Self.space)
                }
                .onPreferenceChange(TileFramePreference.self) { frames = $0 }
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.leftArrow) { move(-1) }
                .onKeyPress(.rightArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-Marquee.columnCount(in: frames)) }
                .onKeyPress(.downArrow) { move(Marquee.columnCount(in: frames)) }
                // Not a hidden ⌘A button: that would take Select All from
                // every text field in the window.
                .onKeyPress(keys: ["a"]) { press in
                    guard press.modifiers == .command else { return .ignored }
                    organize.selectAll()
                    return .handled
                }
            }
            TileSizeBar(tileSize: $tileSize)
        }
    }

    private var tiles: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: tileSize), spacing: 8)], spacing: 8) {
                ForEach(organize.photos) { photo in
                    BrowseTile(item: BrowseItem(photo: photo, figure: organize.tray.contains(photo.id) ? "In tray" : ""),
                               isSelected: organize.selection.ids.contains(photo.id))
                        .background(frameReader(photo.id))
                        // One tap handler: modifier gestures beside it ran two
                        // handlers per ⌘-click (see PhotoGridView).
                        .onTapGesture { organize.click(photo.id, modifiers: Self.modifiers()) }
                        .contextMenu { menu(for: photo) }
                }
            }
            if organize.canLoadMore {
                Button("Load More") { organize.loadMore() }.disabled(organize.isRunning)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func menu(for photo: LibraryPhoto) -> some View {
        if !organize.selection.ids.contains(photo.id) {
            Button("Add to Tray") {
                organize.click(photo.id, modifiers: [])
                organize.addSelectionToTray()
            }
        } else {
            Button("Add \(organize.selection.count) to Tray") { organize.addSelectionToTray() }
        }
        if organize.tray.contains(photo.id) {
            Button("Remove from Tray") { organize.removeFromTray([photo.id]) }
        }
    }

    private func move(_ offset: Int) -> KeyPress.Result {
        guard !organize.photos.isEmpty else { return .ignored }
        organize.move(by: offset)
        return .handled
    }

    private static func modifiers() -> ClickModifiers {
        let flags = NSEvent.modifierFlags
        var held: ClickModifiers = []
        if flags.contains(.command) { held.insert(.command) }
        if flags.contains(.shift) { held.insert(.shift) }
        return held
    }

    private var sweepSurface: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        let rect = Marquee.rect(from: value.startLocation, to: value.location)
                        marquee = rect
                        organize.sweep(Marquee.covered(frames, by: rect))
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
                .frame(width: marquee.width, height: marquee.height)
                .offset(x: marquee.minX, y: marquee.minY)
                .allowsHitTesting(false)
        }
    }

    private func frameReader(_ id: String) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key: TileFramePreference.self, value: [id: geometry.frame(in: .named(Self.space))])
        }
    }
}
