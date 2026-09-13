import Foundation

import CaterinaLibrary
import FlickrKit

/// Filling a scope: from the library copy, from Flickr, or an index.
extension BrowseModel {

    nonisolated static let pageSize = 500

    func fill(_ scope: BrowseScope, generation: Int) async {
        switch scope {
        case .tags:
            let tags = await read { try $0.tagCounts() } ?? []
            guard isCurrent(generation) else { return }
            setIndexes(tags: tags)
        case .timeline:
            let months = await read { try $0.monthCounts() } ?? []
            guard isCurrent(generation) else { return }
            setIndexes(months: months)
        case .people:
            let fans = await read { try $0.topFans(limit: 200) } ?? []
            let recent = await read { try $0.recentFaves(limit: 100) } ?? []
            guard isCurrent(generation) else { return }
            setIndexes(fans: fans, recent: recent)
            await directory.load(.people)
        case .albums, .collections, .galleries, .groups:
            setLoading(true, generation: generation)
            await directory.load(scope)
            setLoading(false, generation: generation)
            if isCurrent(generation) { setProblem(directory.problem) }
        default:
            setItems([], more: false)
            await loadMore()
        }
    }

    /// The next page, from Flickr or the library copy.
    public func loadMore() async {
        let generation = self.generation
        guard !isLoading || items.isEmpty else { return }
        setLoading(true, generation: generation)
        defer { setLoading(false, generation: generation) }
        do {
            let (added, more) = try await nextPage(for: scope, after: items.count)
            guard isCurrent(generation) else { return }
            setItems(items + added, more: more)
        } catch {
            guard isCurrent(generation) else { return }
            setProblem((error as? FlickrError)?.message ?? error.localizedDescription)
        }
    }

    private func nextPage(for scope: BrowseScope, after offset: Int) async throws -> ([BrowseItem], Bool) {
        switch scope {
        case let .remote(list, _):
            let page = try await source.photoList(list, page: remotePage + 1)
            remotePage = page.page
            return (page.photos.map { BrowseItem(photo: $0, figure: Self.byline(for: $0)) }, page.page < page.pages)
        case .ranking:
            // Rankings are a top list; 500 is the list.
            guard offset == 0, let store else { return ([], false) }
            let now = self.now
            let rising = hasHistory(for: .rising)
            return (try await Task.detached { try Self.rankedItems(for: scope, store: store, now: now, rising: rising) }.value, false)
        default:
            guard let store else { return ([], false) }
            let size = Self.pageSize
            let photos = try await Task.detached { try Self.libraryPage(scope, store: store, offset: offset, size: size) }.value
            return (photos.map(Self.dated), photos.count == size)
        }
    }

    private func read<T: Sendable>(_ work: @escaping @Sendable (LibraryStore) throws -> T) async -> T? {
        guard let store else { return nil }
        return try? await Task.detached { try work(store) }.value
    }

    private nonisolated static func libraryPage(_ scope: BrowseScope, store: LibraryStore,
                                                offset: Int, size: Int) throws -> [LibraryPhoto] {
        switch scope {
        case let .library(filter, _):
            return try store.photos(filter, order: .newestTaken, limit: size, offset: offset)
        case .places:
            return try store.photos(.withLocation, order: .newestTaken, limit: size, offset: offset)
        case let .favedBy(nsid, _):
            let ids = try store.photoIDs(favedBy: nsid)
            return try store.photos(ids: Array(ids.dropFirst(offset).prefix(size)))
        default:
            return []
        }
    }

    /// Whether saved history covers what `ranking` compares.
    public func hasHistory(for ranking: Ranking) -> Bool {
        guard ranking == .rising else { return true }
        let saved = (try? store?.savedStatsDays()) ?? []
        return sequence(first: StatsDay(containing: now()).previous) { $0.previous }.prefix(14).allSatisfy(saved.contains)
    }

    nonisolated static func rankedItems(for scope: BrowseScope, store: LibraryStore,
                                        now: @Sendable () -> Date, rising: Bool) throws -> [BrowseItem] {
        guard case let .ranking(ranking) = scope else { return [] }
        let yesterday = StatsDay(containing: now()).previous
        let back = { (days: Int) in Array(sequence(first: yesterday) { $0.previous }.prefix(days)).last ?? yesterday }
        let ranked = { (photo: LibraryPhoto?, id: String, figure: String) in
            BrowseItem(photo: photo ?? LibraryPhoto(id: id), figure: figure)
        }
        switch ranking {
        case .mostViewed:
            return try store.photos(.all, order: .mostViewed, limit: pageSize).map {
                BrowseItem(photo: $0, figure: count($0.views, "view"))
            }
        case .recentUploads:
            return try store.photos(.all, order: .newestUploaded, limit: pageSize).map {
                BrowseItem(photo: $0, figure: $0.uploaded.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "")
            }
        case .topThisWeek:
            return try store.topPhotos(from: back(7), through: yesterday, by: .views, limit: pageSize).map {
                ranked($0.photo, $0.photoID, count($0.total, "view") + " this week")
            }
        case .mostFavedThisMonth:
            return try store.topPhotos(from: back(28), through: yesterday, by: .faves, limit: pageSize).map {
                ranked($0.photo, $0.photoID, count($0.total, "fave") + " in 28 days")
            }
        case .rising:
            guard rising else { return [] }
            return try store.risingPhotos(endingOn: yesterday, limit: pageSize).map {
                ranked($0.photo, $0.photoID, "\($0.weekBefore.formatted()) → \($0.thisWeek.formatted()) views a week")
            }
        }
    }

    private nonisolated static func dated(_ photo: LibraryPhoto) -> BrowseItem {
        BrowseItem(photo: photo, figure: photo.taken.map { String($0.prefix(10)) } ?? count(photo.views, "view"))
    }

    private nonisolated static func byline(for photo: LibraryPhoto) -> String {
        photo.ownerName ?? photo.taken.map { String($0.prefix(10)) } ?? ""
    }

    nonisolated static func count(_ value: Int, _ noun: String) -> String {
        "\(value.formatted(.number.locale(Locale(identifier: "en_US")))) \(noun)\(value == 1 ? "" : "s")"
    }
}
