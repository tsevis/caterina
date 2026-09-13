import Foundation
import Testing

@testable import FlickrKit

/// A clock that moves only when something waits on it.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Duration = .zero
    private var waits: [Duration] = []

    var now: Duration { lock.lock(); defer { lock.unlock() }; return current }
    var slept: [Duration] { lock.lock(); defer { lock.unlock() }; return waits }

    var reader: @Sendable () -> Duration { { [self] in now } }
    var sleeper: Sleeper {
        { [self] duration in record(duration) }
    }

    private func record(_ duration: Duration) {
        lock.lock(); defer { lock.unlock() }
        waits.append(duration)
        current += duration
    }

    func advance(by duration: Duration) {
        lock.lock(); defer { lock.unlock() }
        current += duration
    }
}

/// Flickr allows 3,600 calls an hour per API key, shared by everything the app
/// does.
///
/// **What the person is looking at must never wait behind a batch.** Each
/// priority stops short of the limit by the headroom kept for the priorities
/// above it, and batch work is spread at one call a second — the rate that
/// can run all day without reaching the limit at all.
@Suite struct CallBudgetTests {

    private func budget(_ clock: FakeClock, limit: Int = 10) -> CallBudget {
        CallBudget(limits: CallBudget.Limits(interactive: limit, upload: limit - 2,
                                             edit: limit - 4, background: limit - 6),
                   window: .seconds(3600), spacing: .seconds(1),
                   now: clock.reader, sleep: clock.sleeper)
    }

    @Test func aCallWithRoomGoesStraightAway() async throws {
        let clock = FakeClock()
        let budget = budget(clock)
        try await budget.acquire(.interactive)
        #expect(clock.slept.isEmpty)
        #expect(await budget.used == 1)
    }

    @Test func batchWorkIsSpacedAtOneCallASecond() async throws {
        let clock = FakeClock()
        let budget = budget(clock)
        for _ in 0..<3 { try await budget.acquire(.edit) }
        #expect(clock.slept == [.seconds(1), .seconds(1)])
    }

    @Test func interactiveCallsAreNotSpaced() async throws {
        let clock = FakeClock()
        let budget = budget(clock)
        for _ in 0..<5 { try await budget.acquire(.interactive) }
        #expect(clock.slept.isEmpty)
    }

    /// Background stops at 4 of 10; the person's own call still goes.
    @Test func aFullBackgroundAllowanceLeavesRoomForThePerson() async throws {
        let clock = FakeClock()
        let budget = budget(clock)
        for _ in 0..<4 { try await budget.acquire(.background) }
        let sleptBefore = clock.slept.count

        try await budget.acquire(.interactive)
        #expect(clock.slept.count == sleptBefore)
        #expect(await budget.used == 5)
    }

    /// At its limit a priority waits exactly until the oldest call in the
    /// window is an hour old, not a second more.
    @Test func atTheLimitACallWaitsForTheOldestToLeaveTheWindow() async throws {
        let clock = FakeClock()
        let budget = budget(clock, limit: 3)
        try await budget.acquire(.interactive)          // t = 0
        clock.advance(by: .seconds(100))
        try await budget.acquire(.interactive)          // t = 100
        try await budget.acquire(.interactive)          // t = 100, now full

        try await budget.acquire(.interactive)
        #expect(clock.slept == [.seconds(3500)])
        #expect(await budget.used == 3)
    }

    @Test func remainingIsWhatThePersonCanStillSpend() async throws {
        let clock = FakeClock()
        let budget = budget(clock)
        try await budget.acquire(.interactive)
        try await budget.acquire(.interactive)
        #expect(await budget.remaining == 8)
    }

    /// "Adding tags to 800 photos takes about 14 minutes."
    @Test func aBatchCanSayHowLongItWillTake() {
        #expect(CallBudget.standard.estimatedDuration(calls: 800, priority: .edit)
                == .seconds(799))
        #expect(CallBudget.standard.estimatedDuration(calls: 0, priority: .edit) == .zero)
        #expect(CallBudget.standard.estimatedDuration(calls: 50, priority: .interactive) == .zero)
    }

    @Test func theStandardLimitsStayUnderFlickrs() {
        let limits = CallBudget.Limits.standard
        #expect(limits.interactive <= 3600)
        #expect(limits.background < limits.edit)
        #expect(limits.edit < limits.upload)
        #expect(limits.upload < limits.interactive)
    }

    @Test func aCancelledWaitThrows() async throws {
        let budget = CallBudget(limits: .init(interactive: 1, upload: 1, edit: 1, background: 1),
                                window: .seconds(3600), spacing: .zero,
                                now: { .zero },
                                sleep: { try await Task.sleep(for: $0) })
        try await budget.acquire(.interactive)
        let waiting = Task { try await budget.acquire(.interactive) }
        waiting.cancel()
        await #expect(throws: CancellationError.self) { try await waiting.value }
    }
}

/// The client spends the budget: one call per attempt.
@Suite struct ClientSpendsTheBudgetTests {
    @Test func everyAttemptIncludingRetriesIsCounted() async throws {
        let transport = ScriptedTransport([
            .body(Fixtures.failure(code: 201)),
            .body(Fixtures.page(ids: ["1"])),
        ])
        let budget = CallBudget.unspaced
        let client = FlickrClient(credentials: Fixtures.credentials, transport: transport,
                                  budget: budget, sleep: SleepRecorder().sleep)
        _ = try await client.photos(PhotoRequest(query: .search(text: "x")))
        #expect(await budget.used == 2)
    }
}
