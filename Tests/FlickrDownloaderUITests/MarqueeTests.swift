import CoreGraphics
import Testing

@testable import FlickrDownloaderUI

/// Sweeping, as arithmetic.
@Suite struct MarqueeTests {

    /// Three tiles across, two rows, 100pt cells with 10pt gaps.
    private let frames: [String: CGRect] = [
        "a": CGRect(x: 0, y: 0, width: 100, height: 100),
        "b": CGRect(x: 110, y: 0, width: 100, height: 100),
        "c": CGRect(x: 220, y: 0, width: 100, height: 100),
        "d": CGRect(x: 0, y: 110, width: 100, height: 100),
        "e": CGRect(x: 110, y: 110, width: 100, height: 100),
        "f": CGRect(x: 220, y: 110, width: 100, height: 100),
    ]

    // MARK: - The rectangle

    @Test func aRectangleIsBuiltFromWhicheverWayTheDragWent() {
        let downRight = Marquee.rect(from: CGPoint(x: 10, y: 10),
                                     to: CGPoint(x: 50, y: 90))
        let upLeft = Marquee.rect(from: CGPoint(x: 50, y: 90),
                                  to: CGPoint(x: 10, y: 10))
        #expect(downRight == upLeft)
        #expect(downRight == CGRect(x: 10, y: 10, width: 40, height: 80))
    }

    /// The defect: the rectangle only ever grew, so dragging back left twenty
    /// tiles selected under a rectangle drawn around three.
    @Test func draggingBackShrinksTheRectangle() {
        let start = CGPoint(x: 0, y: 0)
        let far = Marquee.rect(from: start, to: CGPoint(x: 300, y: 300))
        let back = Marquee.rect(from: start, to: CGPoint(x: 50, y: 50))
        #expect(back.width < far.width)
        #expect(back == CGRect(x: 0, y: 0, width: 50, height: 50))
    }

    @Test func aClickWithNoDragIsAnEmptyRectangle() {
        let point = CGPoint(x: 20, y: 20)
        #expect(Marquee.rect(from: point, to: point).isEmpty)
    }

    // MARK: - What it covers

    @Test func aSweepCoversEveryTileItTouches() {
        // Across the top row, clipping the first two.
        let rect = Marquee.rect(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 150, y: 60))
        #expect(Marquee.covered(frames, by: rect) == ["a", "b"])
    }

    @Test func aSweepDownTheGridTakesBothRows() {
        let rect = Marquee.rect(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 115, y: 115))
        #expect(Marquee.covered(frames, by: rect) == ["a", "b", "d", "e"])
    }

    @Test func aSweepThroughAGapCoversNothing() {
        // Between the first and second columns, and between the rows.
        let rect = Marquee.rect(from: CGPoint(x: 102, y: 102), to: CGPoint(x: 108, y: 108))
        #expect(Marquee.covered(frames, by: rect).isEmpty)
    }

    @Test func aSweepOverEverythingCoversEverything() {
        let rect = Marquee.rect(from: .zero, to: CGPoint(x: 400, y: 400))
        #expect(Marquee.covered(frames, by: rect).count == frames.count)
    }

    @Test func anEmptyGridSweepsToNothing() {
        #expect(Marquee.covered([:], by: CGRect(x: 0, y: 0, width: 99, height: 99)).isEmpty)
    }

    // MARK: - Counting columns

    @Test func theColumnCountComesFromTheTopRow() {
        #expect(Marquee.columnCount(in: frames) == 3)
    }

    @Test func aSingleRowIsAllColumns() {
        let oneRow = frames.filter { $0.value.minY == 0 }
        #expect(Marquee.columnCount(in: oneRow) == 3)
    }

    @Test func roundingWithinARowDoesNotSplitIt() {
        let wobbly: [String: CGRect] = [
            "a": CGRect(x: 0, y: 0, width: 100, height: 100),
            "b": CGRect(x: 110, y: 0.4, width: 100, height: 100),
            "c": CGRect(x: 220, y: 0.7, width: 100, height: 100),
        ]
        #expect(Marquee.columnCount(in: wobbly) == 3)
    }

    @Test func anEmptyGridStillHasAColumn() {
        // Never zero: the arrow keys divide by this.
        #expect(Marquee.columnCount(in: [:]) == 1)
    }
}
