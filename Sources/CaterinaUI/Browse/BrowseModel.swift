import Foundation
import Observation

import CaterinaLibrary
import FlickrKit

/// The Browse tab: every way into the account, laid out as a list, a grid, a
/// timeline or a map, and one photo's whole record.
@MainActor
@Observable
public final class BrowseModel {

    public enum RecordPhase: Sendable, Equatable {
        case none, loading
        case loaded(PhotoRecord)
        case failed(String)
    }

    public enum StatsPhase: Sendable, Equatable {
        case idle, saving
        case saved(days: Int)
        /// No Flickr Pro, or stats switched off.
        case unavailable
        case failed(String)
    }

    /// 500 faves is enough to draw the curve; a photo with 40,000 would
    /// otherwise cost 800 calls to open.
    nonisolated static let favePageLimit = 10
    nonisolated static let rowLimit = 500

    // MARK: What is showing

    public private(set) var scope: BrowseScope = .ranking(.mostViewed)
    public private(set) var items: [BrowseItem] = []
    public private(set) var isLoading = false
    public private(set) var problem: String?
    public private(set) var canLoadMore = false
    public private(set) var tags: [TagCount] = []
    public private(set) var months: [MonthCount] = []
    public private(set) var fans: [Fan] = []
    public private(set) var recentFaves: [FaveEvent] = []
    public let directory: AccountDirectory

    /// Remembered per kind of scope: a grid chosen for a tag stays the grid
    /// for the next tag, while rankings keep their list.
    public var layout: BrowseLayout {
        get { layouts[scope.layoutKind] ?? scope.defaultLayout }
        set { layouts[scope.layoutKind] = newValue }
    }

    public var availableLayouts: [BrowseLayout] {
        // Still arriving: offer everything rather than take away the chosen one.
        guard !items.isEmpty else { return BrowseLayout.allCases }
        return BrowseLayout.allCases.filter { layout in
            switch layout {
            case .list, .grid: true
            case .timeline: items.contains { $0.photo.taken != nil }
            case .map: items.contains { $0.photo.location != nil }
            }
        }
    }

    public var canGoBack: Bool { !history.isEmpty }

    // MARK: The chosen photo and stats

    public private(set) var selectedPhotoID: String?
    public private(set) var record: RecordPhase = .none
    public private(set) var statsPhase: StatsPhase = .idle
    public private(set) var accountHistory: [AccountPoint] = []

    let store: LibraryStore?
    let records: PhotoRecordSource
    let source: AccountDirectorySource
    let accountID: @Sendable () -> String?
    let now: @Sendable () -> Date
    private let snapshot: StatsSnapshot?
    private let fansIndex: FansIndex?
    private var layouts: [String: BrowseLayout] = [:]
    private var history: [BrowseScope] = []
    private var loadTask: Task<Void, Never>?
    var remotePage = 0
    /// Bumped by every change of scope; a reply for an older one is dropped.
    private(set) var generation = 0

    public init(store: LibraryStore?, records: PhotoRecordSource, stats: StatsSource,
                directory: AccountDirectorySource, faves: FaveSource = NoFaves(),
                accountID: @escaping @Sendable () -> String?,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.records = records
        self.source = directory
        self.accountID = accountID
        self.now = now
        self.snapshot = store.map { StatsSnapshot(source: stats, store: $0) }
        self.fansIndex = store.map { FansIndex(source: faves, store: $0) }
        self.directory = AccountDirectory(source: directory, accountID: accountID)
        accountHistory = (try? store?.accountHistory()) ?? []
        if let store {
            items = (try? Self.rankedItems(for: scope, store: store, now: now, rising: false)) ?? []
        }
    }

    /// Forget the account: signed out, or signed in as someone else.
    public func reset() {
        loadTask?.cancel()
        generation += 1
        history = []
        scope = .ranking(.mostViewed)
        items = []
        canLoadMore = false
        isLoading = false
        problem = nil
        tags = []
        months = []
        fans = []
        recentFaves = []
        selectedPhotoID = nil
        record = .none
        directory.reset()
    }

    // MARK: - Moving around

    /// Show `scope`, remembering where this came from.
    public func open(_ scope: BrowseScope) async {
        if scope != self.scope { history.append(self.scope) }
        await show(scope)
    }

    public func goBack() async {
        guard let previous = history.popLast() else { return }
        await show(previous)
    }

    /// Choosing from the sidebar starts afresh: Back is for drilling in.
    public func jump(to scope: BrowseScope) async {
        history = []
        await show(scope)
    }

    public func reload() async { await show(scope) }

    private func show(_ scope: BrowseScope) async {
        generation += 1
        let generation = self.generation
        self.scope = scope
        problem = nil
        canLoadMore = false
        isLoading = false
        remotePage = 0
        await fill(scope, generation: generation)
        guard isCurrent(generation) else { return }
        if !availableLayouts.contains(layout) { layout = .grid }
    }

    func isCurrent(_ generation: Int) -> Bool { generation == self.generation }

    // MARK: - One photo

    public func select(_ photoID: String?) async {
        loadTask?.cancel()
        selectedPhotoID = photoID
        guard let photoID else { record = .none; return }
        record = .loading
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await self.loadRecord(photoID)
                guard !Task.isCancelled, self.selectedPhotoID == photoID else { return }
                self.record = .loaded(loaded)
            } catch {
                guard !Task.isCancelled, self.selectedPhotoID == photoID else { return }
                self.record = .failed((error as? FlickrError)?.message ?? error.localizedDescription)
            }
        }
        loadTask = task
        await task.value
    }

    /// The thumbnail for the record's header: from what is showing, else the
    /// library.
    public func thumbnailURL(for photoID: String) -> String? {
        items.first { $0.photo.id == photoID }?.photo.thumbnailURL ?? (try? store?.photo(id: photoID))??.thumbnailURL
    }

    private func loadRecord(_ id: String) async throws -> PhotoRecord {
        let records = self.records
        async let info = records.photoInfo(id: id)
        async let faves = Self.faves(of: id, from: records)
        // Extras: a photo whose comments will not load still has a record.
        async let comments = (try? records.comments(photoID: id)) ?? []
        async let contexts = (try? records.contexts(photoID: id)) ?? PhotoContexts(albums: [], groups: [])
        async let exif = (try? records.exif(photoID: id)) ?? PhotoExif(camera: nil, fields: [], isHidden: false)
        let (allFaves, total) = await faves
        return PhotoRecord(info: try await info, faves: allFaves, faveTotal: total,
                           comments: await comments, contexts: await contexts, exif: await exif,
                           history: (try? store?.statsHistory(photoID: id)) ?? [])
    }

    /// As many pages as load: one failing page keeps the ones before it.
    private nonisolated static func faves(of id: String, from records: PhotoRecordSource) async -> ([Fave], Int) {
        guard let first = try? await records.favorites(photoID: id, page: 1) else { return ([], 0) }
        var faves = first.faves
        for page in stride(from: 2, through: min(first.pages, favePageLimit), by: 1) {
            guard !Task.isCancelled, let next = try? await records.favorites(photoID: id, page: page) else { break }
            faves += next.faves
        }
        return (faves, first.total)
    }

    // MARK: - Stats

    public func saveStats() async {
        guard let snapshot, statsPhase != .saving else { return }
        statsPhase = .saving
        do {
            switch try await snapshot.run(now: now()) {
            case let .saved(days): statsPhase = .saved(days: days)
            case .statsUnavailable: statsPhase = .unavailable
            }
        } catch {
            statsPhase = .failed((error as? FlickrError)?.message ?? error.localizedDescription)
        }
        accountHistory = (try? store?.accountHistory()) ?? accountHistory
        if case .ranking = scope { await reload() }
    }

    /// Read another batch of photos' faves into the fans index, in the
    /// background. Quiet on failure: it tries again next time.
    public func readFaves(photoLimit: Int = 200) async {
        guard let fansIndex else { return }
        _ = try? await fansIndex.run(now: now(), photoLimit: photoLimit)
        if scope == .people { await fill(.people, generation: generation) }
    }

    func setLoading(_ loading: Bool, generation: Int) {
        guard isCurrent(generation) else { return }
        isLoading = loading
    }
    func setProblem(_ message: String?) { problem = message }
    func setItems(_ items: [BrowseItem], more: Bool) { self.items = items; canLoadMore = more }
    func setIndexes(tags: [TagCount]? = nil, months: [MonthCount]? = nil, fans: [Fan]? = nil, recent: [FaveEvent]? = nil) {
        if let tags { self.tags = tags }
        if let months { self.months = months }
        if let fans { self.fans = fans }
        if let recent { self.recentFaves = recent }
    }
}

/// For a Browse without a fans index (tests of other things).
public struct NoFaves: FaveSource {
    public init() {}
    public func favorites(photoID: String, page: Int, priority: CallPriority) async throws -> FavePage {
        FavePage(page: 1, pages: 1, total: 0, faves: [])
    }
}
