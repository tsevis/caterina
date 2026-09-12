import CoreGraphics

/// The geometry behind a sweep, separated from the gesture that drives it.
///
/// The gesture itself can only be judged by dragging in a real window. What it
/// *computes* — which rectangle two points describe, which tiles that covers,
/// how many tiles are on a row — is arithmetic, and two of the three were wrong
/// in ways that a test would have caught: the rectangle only ever grew, and the
/// frames it was measured against were in a different coordinate space.
enum Marquee {

    /// The rectangle two corners describe.
    ///
    /// **Built from the two live corners every time.** The first version unioned
    /// each new point into the *previous* rectangle, so sweeping out to twenty
    /// tiles and back to three left twenty selected under a rectangle drawn
    /// around three.
    static func rect(from start: CGPoint, to current: CGPoint) -> CGRect {
        CGRect(x: min(start.x, current.x),
               y: min(start.y, current.y),
               width: abs(start.x - current.x),
               height: abs(start.y - current.y))
    }

    /// Which tiles a sweep covers. Touching counts, as it does in the Finder.
    static func covered(_ frames: [String: CGRect], by rect: CGRect) -> Set<String> {
        Set(frames.filter { $0.value.intersects(rect) }.keys)
    }

    /// How many tiles are on a row, measured from where they actually are.
    ///
    /// The grid's columns are adaptive, so the number depends on the window's
    /// width. Counting the tiles that share the topmost row means the arrow
    /// keys follow the rows a person can see rather than a number fixed in
    /// code.
    static func columnCount(in frames: [String: CGRect]) -> Int {
        guard let top = frames.values.map(\.minY).min() else { return 1 }
        // A tolerance, because a row's tiles are laid out at the same y only to
        // within rounding.
        return max(1, frames.values.filter { abs($0.minY - top) < 1 }.count)
    }
}
