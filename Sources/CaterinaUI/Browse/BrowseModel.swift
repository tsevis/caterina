import Foundation
import Observation

import CaterinaLibrary
import FlickrKit

/// The Browse tab: rankings of your photos, and one photo's whole record.
@MainActor
@Observable
public final class BrowseModel {

    public enum Ranking: String, CaseIterable, Identifiable, Sendable {
        case mostViewed, topThisWeek, mostFavedThisMonth, rising, recentUploads

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .mostViewed: "Most viewed"
            case .topThisWeek: "Top this week"
            case .mostFavedThisMonth: "Most faved, 28 days"
            case .rising: "Rising"
            case .recentUploads: "Recent uploads"
            }
        }

        public var systemImage: String {
            switch self {
            case .mostViewed: "eye"
            case .topThisWeek: "chart.bar"
            case .mostFavedThisMonth: "star"
            case .rising: "arrow.up.right"
            case .recentUploads: "clock"
            }
        }
    }

    public struct Row: Sendable, Equatable, Identifiable {
        public var id: String { photoID }
        public let photoID: String
        public let title: String
        public let thumbnailURL: String?
        public let figure: String
    }

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
    nonisolated static let rowLimit = 200

    public private(set) var ranking: Ranking = .mostViewed
    public private(set) var rows: [Row] = []
    public private(set) var selectedPhotoID: String?
    public private(set) var record: RecordPhase = .none
    public private(set) var statsPhase: StatsPhase = .idle
    public private(set) var accountHistory: [AccountPoint] = []

    private let store: LibraryStore?
    private let records: PhotoRecordSource
    private let snapshot: StatsSnapshot?
    private let now: @Sendable () -> Date

    public init(store: LibraryStore?, records: PhotoRecordSource, stats: StatsSource,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.records = records
        self.snapshot = store.map { StatsSnapshot(source: stats, store: $0) }
        self.now = now
        reloadRows()
        accountHistory = (try? store?.accountHistory()) ?? []
    }

    public func show(_ ranking: Ranking) {
        self.ranking = ranking
        reloadRows()
    }

    public func reloadRows() {
        rows = (try? makeRows()) ?? []
    }

    // MARK: - One photo

    public func select(_ photoID: String?) async {
        selectedPhotoID = photoID
        guard let photoID else { record = .none; return }
        record = .loading
        do {
            let loaded = try await load(photoID)
            guard selectedPhotoID == photoID else { return }
            record = .loaded(loaded)
        } catch {
            guard selectedPhotoID == photoID else { return }
            record = .failed((error as? FlickrError)?.message ?? error.localizedDescription)
        }
    }

    private func load(_ id: String) async throws -> PhotoRecord {
        let records = self.records
        async let info = records.photoInfo(id: id)
        async let faves = Self.faves(of: id, from: records)
        // The rest are extras: a photo whose comments will not load still
        // has a record worth showing.
        async let comments = (try? records.comments(photoID: id)) ?? []
        async let contexts = (try? records.contexts(photoID: id)) ?? PhotoContexts(albums: [], groups: [])
        async let exif = (try? records.exif(photoID: id)) ?? PhotoExif(camera: nil, fields: [], isHidden: false)
        let (allFaves, total) = (try? await faves) ?? ([], 0)
        return PhotoRecord(info: try await info, faves: allFaves, faveTotal: total,
                           comments: await comments, contexts: await contexts, exif: await exif,
                           history: (try? store?.statsHistory(photoID: id)) ?? [])
    }

    private nonisolated static func faves(of id: String, from records: PhotoRecordSource) async throws -> ([Fave], Int) {
        let first = try await records.favorites(photoID: id, page: 1)
        var faves = first.faves
        for page in stride(from: 2, through: min(first.pages, favePageLimit), by: 1) {
            faves += try await records.favorites(photoID: id, page: page).faves
        }
        return (faves, first.total)
    }

    // MARK: - Stats

    /// Save whatever whole days Flickr holds that this Mac does not.
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
        reloadRows()
    }

    // MARK: - Rows

    private func makeRows() throws -> [Row] {
        guard let store else { return [] }
        let yesterday = StatsDay(containing: now()).previous
        switch ranking {
        case .mostViewed:
            return try store.photos(.all, order: .mostViewed, limit: Self.rowLimit).map {
                row($0.id, $0, figure: Self.count($0.views, "view"))
            }
        case .recentUploads:
            return try store.photos(.all, order: .newestUploaded, limit: Self.rowLimit).map {
                row($0.id, $0, figure: $0.uploaded.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "")
            }
        case .topThisWeek:
            let start = Array(sequence(first: yesterday) { $0.previous }.prefix(7)).last ?? yesterday
            return try store.topPhotos(from: start, through: yesterday, by: .views, limit: Self.rowLimit).map {
                row($0.photoID, $0.photo, figure: Self.count($0.total, "view") + " this week")
            }
        case .mostFavedThisMonth:
            let start = StatsDay.completeDaysAvailable(at: now()).last ?? yesterday
            return try store.topPhotos(from: start, through: yesterday, by: .faves, limit: Self.rowLimit).map {
                row($0.photoID, $0.photo, figure: Self.count($0.total, "fave") + " in 28 days")
            }
        case .rising:
            return try store.risingPhotos(endingOn: yesterday, limit: Self.rowLimit).map {
                row($0.photoID, $0.photo, figure: "\($0.weekBefore.formatted()) → \($0.thisWeek.formatted()) views a week")
            }
        }
    }

    private func row(_ id: String, _ photo: LibraryPhoto?, figure: String) -> Row {
        let title = photo?.title ?? ""
        return Row(photoID: id, title: title.isEmpty ? "Untitled" : title,
                   thumbnailURL: photo?.thumbnailURL, figure: figure)
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        "\(value.formatted(.number.locale(Locale(identifier: "en_US")))) \(noun)\(value == 1 ? "" : "s")"
    }
}
