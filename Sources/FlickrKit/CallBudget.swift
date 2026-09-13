import Foundation

/// Who is waiting for a Flickr call, most urgent first.
public enum CallPriority: Sendable, CaseIterable {
    /// Something the person just asked to see.
    case interactive
    case upload
    /// A batch edit from Organize.
    case edit
    /// Library sync and stats snapshots.
    case background

    /// Batch work is spread out; what someone is watching is not.
    var isSpaced: Bool { self == .edit || self == .background }
}

/// Flickr's 3,600 calls an hour per API key, shared by the whole app.
///
/// **What the person is looking at must never wait behind a batch.** Each
/// priority stops short of the limit by the headroom kept for the ones above
/// it. Batch work is also spaced at one call a second, which is the hourly
/// limit's own average: a batch paced that way can run all day and still never
/// reach the ceiling.
///
/// The window slides. A call leaves it exactly an hour after it was made, so a
/// full budget frees up one call at a time rather than all at once on the hour.
public actor CallBudget {

    public struct Limits: Sendable, Equatable {
        public let interactive: Int
        public let upload: Int
        public let edit: Int
        public let background: Int

        public init(interactive: Int, upload: Int, edit: Int, background: Int) {
            self.interactive = interactive
            self.upload = upload
            self.edit = edit
            self.background = background
        }

        /// A hundred short of Flickr's 3,600, for the calls this app cannot
        /// see: the same key used by a live test, or a second copy of the app.
        public static let standard = Limits(interactive: 3_500, upload: 3_300,
                                            edit: 3_000, background: 2_500)

        func limit(for priority: CallPriority) -> Int {
            switch priority {
            case .interactive: interactive
            case .upload: upload
            case .edit: edit
            case .background: background
            }
        }
    }

    public static let flickrWindow: Duration = .seconds(3_600)
    public static let batchSpacing: Duration = .seconds(1)

    /// The one budget every client in the app shares.
    public static let standard = CallBudget()

    private let limits: Limits
    private let window: Duration
    private let spacing: Duration
    private let now: @Sendable () -> Duration
    private let sleep: Sleeper

    /// When each call in the window was made, oldest first.
    private var calls: [Duration] = []
    private var lastSpacedCall: Duration?

    public init(limits: Limits = .standard,
                window: Duration = CallBudget.flickrWindow,
                spacing: Duration = CallBudget.batchSpacing,
                now: @escaping @Sendable () -> Duration = CallBudget.monotonicNow,
                sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }) {
        self.limits = limits
        self.window = window
        self.spacing = spacing
        self.now = now
        self.sleep = sleep
    }

    /// Calls made in the last hour.
    public var used: Int {
        prune(at: now())
        return calls.count
    }

    /// What an interactive call could still spend this hour.
    public var remaining: Int {
        max(0, limits.interactive - used)
    }

    /// Wait until `priority` may make one call, then count it.
    public func acquire(_ priority: CallPriority) async throws {
        while true {
            try Task.checkCancellation()
            let instant = now()
            let wait = delay(for: priority, at: instant)
            guard wait > .zero else {
                record(priority, at: instant)
                return
            }
            // Re-checked after waking: another caller may have taken the slot.
            try await sleep(wait)
        }
    }

    /// How long `calls` calls at `priority` take from an empty budget.
    ///
    /// Spaced calls fill the hour's limit, then each block of `limit` waits
    /// for the first call of the block before it to leave the window.
    public nonisolated func estimatedDuration(calls: Int, priority: CallPriority) -> Duration {
        guard priority.isSpaced, calls > 1 else { return .zero }
        let limit = limits.limit(for: priority)
        guard limit > 0, spacing * limit < window else { return spacing * (calls - 1) }
        let (blocks, remainder) = (calls - 1).quotientAndRemainder(dividingBy: limit)
        return window * blocks + spacing * remainder
    }

    private func delay(for priority: CallPriority, at instant: Duration) -> Duration {
        prune(at: instant)
        var wait = Duration.zero

        let limit = limits.limit(for: priority)
        if calls.count >= limit {
            // The call whose leaving brings the count under this limit.
            let freeing = calls[calls.count - limit]
            wait = max(wait, freeing + window - instant)
        }
        if priority.isSpaced, let lastSpacedCall {
            wait = max(wait, lastSpacedCall + spacing - instant)
        }
        return wait
    }

    private func record(_ priority: CallPriority, at instant: Duration) {
        calls.append(instant)
        if priority.isSpaced { lastSpacedCall = instant }
    }

    private func prune(at instant: Duration) {
        calls.removeAll { $0 + window <= instant }
    }

    /// Time since an arbitrary fixed point, unaffected by the wall clock
    /// changing under a sleeping Mac.
    public static let monotonicNow: @Sendable () -> Duration = {
        ContinuousClock.now - CallBudget.origin
    }

    private static let origin = ContinuousClock.now
}
