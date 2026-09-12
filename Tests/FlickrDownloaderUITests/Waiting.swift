import Foundation
import Testing

/// Waits for a thing to become true, rather than for a number of milliseconds.
///
/// **A fixed sleep is a bet on how busy the machine is.** These tests ran green
/// for days and then failed eight at a time when the suite happened to run
/// beside an Xcode build — not because anything was wrong, but because 60ms was
/// no longer enough scheduling. Polling a condition with a generous ceiling
/// fails only when the condition genuinely never arrives.
@MainActor
func waitUntil(_ description: String, within seconds: Double = 10,
               _ condition: @MainActor () async -> Bool,
               sourceLocation: SourceLocation = #_sourceLocation) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(15))
    }
    Issue.record("timed out waiting for \(description)", sourceLocation: sourceLocation)
}
