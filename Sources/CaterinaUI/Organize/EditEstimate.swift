import Foundation

import FlickrKit

/// What an edit on the tray will cost, shown before it runs.
public struct EditEstimate: Sendable, Equatable {
    /// Photos the edit changes.
    public let photos: Int
    /// Photos in the tray it leaves as they are.
    public let unchanged: Int
    /// A read per photo, then its writes.
    public let calls: Int
    public let duration: Duration
    /// Fields whose earlier value Flickr does not report, so undo cannot
    /// restore them.
    public let unrestorable: [String]

    public init(photos: Int, unchanged: Int, calls: Int, duration: Duration, unrestorable: [String]) {
        self.photos = photos
        self.unchanged = unchanged
        self.calls = calls
        self.duration = duration
        self.unrestorable = unrestorable
    }

    static func of(_ changes: [PhotoChange], budget: CallBudget) -> EditEstimate {
        let changing = changes.filter { !$0.isEmpty }
        let calls = changing.reduce(0) { $0 + $1.readCalls + $1.writes.count }
        let unrestorable = changing.flatMap(\.unrestorable).reduce(into: [String]()) { list, field in
            if !list.contains(field) { list.append(field) }
        }
        return EditEstimate(photos: changing.count, unchanged: changes.count - changing.count, calls: calls,
                            duration: budget.estimatedDuration(calls: calls, priority: .edit),
                            unrestorable: unrestorable)
    }

    /// "800 photos · 1,600 calls · about 27 minutes".
    public var summary: String {
        let number = { (count: Int) in count.formatted(.number.locale(Locale(identifier: "en_US"))) }
        let photoWord = photos == 1 ? "photo" : "photos"
        let callWord = calls == 1 ? "call" : "calls"
        return "\(number(photos)) \(photoWord) · \(number(calls)) \(callWord) · "
            + Self.describe(seconds: Int(duration.components.seconds))
    }

    static func describe(seconds: Int) -> String {
        guard seconds > 0 else { return "a moment" }
        guard seconds >= 60 else { return "under a minute" }
        let minutes = Int((Double(seconds) / 60).rounded())
        let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
        let plural = { (count: Int, unit: String) in "\(count) \(unit)\(count == 1 ? "" : "s")" }
        switch (hours, rest) {
        case (0, _): return "about \(plural(rest, "minute"))"
        case (_, 0): return "about \(plural(hours, "hour"))"
        default: return "about \(plural(hours, "hour")) \(plural(rest, "minute"))"
        }
    }
}
