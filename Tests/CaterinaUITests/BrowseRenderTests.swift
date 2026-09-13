import AppKit
import SwiftUI
import Testing

import CaterinaLibrary
import FlickrKit
@testable import CaterinaUI

/// The record's charts, drawn offscreen, with copies left to look at.
@MainActor
@Suite struct BrowseRenderTests {

    static let output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("caterina-browse", isDirectory: true)

    private func render<V: View>(_ view: V, _ name: String, size: CGSize) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).padding(12)
            .background(Color(nsColor: .windowBackgroundColor)))
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: Self.output.appendingPathComponent("\(name).png"))
        return bitmap
    }

    /// Amber somewhere: the marks were drawn, not just the axes.
    private func hasMarks(_ bitmap: NSBitmapImageRep) -> Bool {
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if c.redComponent > 0.6, c.greenComponent > 0.4, c.greenComponent < 0.6, c.blueComponent < 0.35 { return true }
            }
        }
        return false
    }

    @Test func viewsPerDayDrawsItsBars() throws {
        var day = StatsDay("2024-05-04")!
        var points: [(day: StatsDay, views: Int)] = []
        for index in 0..<27 {
            day = StatsDay(containing: day.start.addingTimeInterval(36 * 3600))
            points.append((day, 40 + (index * 37) % 90))
        }
        #expect(hasMarks(try render(ViewsPerDayChart(points: points), "views-per-day", size: CGSize(width: 520, height: 160))))
    }

    @Test func favesOverTimeDrawsItsLine() throws {
        let faves = (0..<30).map { Fave(nsid: "\($0)", username: "", date: Date(timeIntervalSince1970: 1_600_000_000 + Double($0 * $0) * 86_400)) }
        #expect(hasMarks(try render(FavesOverTimeChart(counts: PhotoRecord.cumulativeFaves(faves, total: faves.count)), "faves-over-time",
                                    size: CGSize(width: 520, height: 140))))
    }
}
