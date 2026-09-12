import AppKit
import SwiftUI
import Testing

import FlickrKit
@testable import FlickrDownloaderUI

/// Draws the states the grid spends its life in, offscreen, and leaves copies
/// to look at.
///
/// These are the views that are hardest to reach by hand — an error state needs
/// Flickr to fail, an empty state needs a search that matches nothing — and the
/// easiest to leave half-designed because nobody sees them during development.
@MainActor
@Suite struct StateRenderTests {

    private static let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("flickrdownloader-states", isDirectory: true)

    private func write<V: View>(_ view: V, _ name: String,
                                size: CGSize = CGSize(width: 640, height: 420)) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content:
            view.frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor)))
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))

        try FileManager.default.createDirectory(at: Self.outputDirectory,
                                                withIntermediateDirectories: true)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: Self.outputDirectory.appendingPathComponent("\(name).png"))
        return bitmap
    }

    /// Ink somewhere in the middle: a state view that renders nothing at all
    /// still lays out, and still passes every assertion about its existence.
    private func isNotBlank(_ bitmap: NSBitmapImageRep) -> Bool {
        var seen = Set<String>()
        for x in stride(from: 20, to: bitmap.pixelsWide - 20, by: 16) {
            for y in stride(from: 20, to: bitmap.pixelsHigh - 20, by: 16) {
                guard let colour = bitmap.colorAt(x: x, y: y) else { continue }
                seen.insert(String(format: "%.2f", colour.brightnessComponent))
            }
        }
        return seen.count > 2
    }

    @Test(arguments: PhotoSource.allCases)
    func everySourceHasADesignedEmptyState(source: PhotoSource) throws {
        let bitmap = try write(SourceStateView(source: source, status: .idle, retry: {}),
                               "idle-\(source.rawValue)")
        #expect(isNotBlank(bitmap))
    }

    @Test func theLoadingAndNoResultsStatesAreDrawn() throws {
        for (status, name) in [(SectionStatus.loading, "loading"), (.empty, "empty")] {
            #expect(isNotBlank(try write(
                SourceStateView(source: .search, status: status, retry: {}), name)))
        }
    }

    /// "Flickr is busy" and "that group does not exist" must not look the same.
    @Test func aBusyFlickrLooksDifferentFromARealError() throws {
        let busy = try write(SourceStateView(
            source: .search, status: .failed(.busy("Flickr is busy right now. Try again in a moment.")),
            retry: {}), "failed-busy")
        let real = try write(SourceStateView(
            source: .groups, status: .failed(.notFound("No Flickr group is named “Nightshots”.")),
            retry: {}), "failed-real")

        #expect(isNotBlank(busy))
        #expect(isNotBlank(real))
        // Different words, so different pixels.
        #expect(busy.representation(using: .png, properties: [:])
            != real.representation(using: .png, properties: [:]))
    }

    /// A tile, selected and unselected.
    ///
    /// The tile rather than the whole grid: `LazyVGrid` inside a `ScrollView`
    /// does not materialise its children offscreen, so rendering the grid comes
    /// back blank whether the tiles are right or not — an assertion that cannot
    /// fail either way is worse than no assertion.
    @Test(arguments: [false, true])
    func aTileDrawsItsFrameAndItsSelection(isSelected: Bool) throws {
        let photo = Photo(id: "1", title: "Harbour at dusk", license: .by,
                          variants: [.small320: "https://example.invalid/1.jpg"])
        let bitmap = try write(
            PhotoTile(photo: photo, isSelected: isSelected).padding(20),
            "tile-\(isSelected ? "selected" : "plain")",
            size: CGSize(width: 220, height: 220))
        #expect(isNotBlank(bitmap))
    }

    @Test func thePaginationBarSaysWhereYouAre() throws {
        let state = SectionState(source: .search, page: 3, totalPages: 160,
                                 perPage: 25, total: 4000, status: .ready,
                                 isPageCountClamped: true, skippedEntries: 2)
        let bitmap = try write(PaginationBar(state: state, onPrevious: {},
                                             onNext: {}, onPerPage: { _ in }),
                               "pagination", size: CGSize(width: 720, height: 44))
        #expect(isNotBlank(bitmap))
    }
}
