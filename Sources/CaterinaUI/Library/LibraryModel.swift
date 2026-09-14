import Foundation
import Observation

import CaterinaLibrary
import FlickrKit

/// The local copy of your library, as the window shows it.
@MainActor
@Observable
public final class LibraryModel {

    public enum Phase: Equatable, Sendable {
        case idle
        case syncing(fetched: Int, total: Int)
        case failed(String)
        /// The copy could not be opened on disk.
        case unavailable
    }

    public private(set) var photoCount = 0
    public private(set) var lastSynced: Date?
    public private(set) var phase: Phase = .idle

    let store: LibraryStore?
    private let sync: LibrarySync?
    private let now: @Sendable () -> Date

    public init(store: LibraryStore?, source: LibrarySource,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.now = now
        self.sync = store.map { LibrarySync(source: source, store: $0, now: now) }
        refresh()
    }

    /// Open the copy in the app's own folder, or nil when the disk refuses —
    /// the window then says the library is unavailable rather than failing to
    /// launch.
    public static func openDefaultStore() -> LibraryStore? {
        do {
            return try LibraryStore(file: LibraryStore.defaultFile())
        } catch {
            NSLog("Caterina: could not open the library copy: %@", String(describing: error))
            return nil
        }
    }

    public func sync(signedIn: Bool) async {
        guard let sync else { phase = .unavailable; return }
        guard signedIn else {
            phase = .failed("Sign in to Flickr to keep a copy of your library.")
            return
        }
        guard !isSyncing else { return }
        phase = .syncing(fetched: 0, total: 0)
        do {
            _ = try await sync.run { [weak self] progress in
                Task { @MainActor in self?.show(progress) }
            }
            refresh()
            phase = .idle
        } catch is CancellationError {
            refresh()
            phase = .idle
        } catch {
            refresh()
            phase = .failed((error as? FlickrError)?.message ?? error.localizedDescription)
        }
    }

    public var isSyncing: Bool {
        if case .syncing = phase { return true }
        return false
    }

    public var statusLine: String {
        Self.status(count: photoCount, lastSynced: lastSynced, at: now())
    }

    static func status(count: Int, lastSynced: Date?, at instant: Date) -> String {
        let photos = "\(count.formatted(.number.locale(Self.locale))) \(count == 1 ? "photo" : "photos")"
        guard let lastSynced else { return "\(photos) · never synced" }
        // Under a minute, and a clock a moment ahead, read as now.
        guard instant.timeIntervalSince(lastSynced) >= 60 else { return "\(photos) · synced just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Self.locale
        formatter.unitsStyle = .full
        return "\(photos) · synced \(formatter.localizedString(for: lastSynced, relativeTo: instant))"
    }

    /// The window's words are English, so its numbers and dates are too.
    private static let locale = Locale(identifier: "en_US")

    private func show(_ progress: LibrarySync.Progress) {
        guard isSyncing else { return }
        phase = .syncing(fetched: progress.fetched, total: progress.total)
    }

    private func refresh() {
        guard let store else {
            photoCount = 0
            lastSynced = nil
            phase = .unavailable
            return
        }
        do {
            photoCount = try store.count(.all)
            lastSynced = try store.syncState().lastSynced
        } catch {
            phase = .failed("Could not read the library copy: \(error.localizedDescription)")
        }
    }
}
