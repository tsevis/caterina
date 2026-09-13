import Foundation

import CaterinaLibrary
import FlickrKit

/// Filling a scope: from the library copy, from Flickr, or an index.
extension BrowseModel {

    func fill(_ scope: BrowseScope) async {
        switch scope {
        case .remote:
            setItems([], more: false)
            await loadMore()
        case .tags:
            setIndexes(tags: (try? store?.tagCounts()) ?? [])
        case .timeline:
            setIndexes(months: (try? store?.monthCounts()) ?? [])
        case .people:
            setIndexes(fans: (try? store?.topFans(limit: 200)) ?? [], recent: (try? store?.recentFaves(limit: 100)) ?? [])
            await directory.load(.people)
        case .albums, .collections, .galleries, .groups:
            setLoading(true)
            await directory.load(scope)
            setLoading(false)
            setProblem(directory.problem)
        default:
            do {
                setItems(try localItems(for: scope), more: false)
            } catch {
                setProblem("Could not read the library copy: \(error.localizedDescription)")
            }
        }
    }

    /// The next page of a Flickr list.
    public func loadMore() async {
        guard case let .remote(list, _) = scope else { return }
        let requested = scope
        setLoading(true)
        defer { setLoading(false) }
        do {
            let page = try await source.photoList(list, page: remotePage + 1)
            guard scope == requested else { return }
            remotePage = page.page
            let added = page.photos.map { BrowseItem(photo: $0, figure: Self.byline(for: $0)) }
            setItems(items + added, more: page.page < page.pages)
        } catch {
            guard scope == requested else { return }
            setProblem((error as? FlickrError)?.message ?? error.localizedDescription)
        }
    }

    func localItems(for scope: BrowseScope) throws -> [BrowseItem] {
        guard let store else { return [] }
        switch scope {
        case let .ranking(ranking):
            return try rankedItems(ranking, store: store)
        case let .library(filter, _):
            return try store.photos(filter, order: .newestTaken, limit: Self.rowLimit).map(Self.dated)
        case .places:
            return try store.photos(.withLocation, order: .newestTaken, limit: 5_000).map(Self.dated)
        case let .favedBy(nsid, _):
            return try store.photoIDs(favedBy: nsid).compactMap { try store.photo(id: $0) }.map(Self.dated)
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

    private func rankedItems(_ ranking: Ranking, store: LibraryStore) throws -> [BrowseItem] {
        let yesterday = StatsDay(containing: now()).previous
        let back = { (days: Int) in Array(sequence(first: yesterday) { $0.previous }.prefix(days)).last ?? yesterday }
        switch ranking {
        case .mostViewed:
            return try store.photos(.all, order: .mostViewed, limit: Self.rowLimit).map {
                BrowseItem(photo: $0, figure: Self.count($0.views, "view"))
            }
        case .recentUploads:
            return try store.photos(.all, order: .newestUploaded, limit: Self.rowLimit).map {
                BrowseItem(photo: $0, figure: $0.uploaded.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "")
            }
        case .topThisWeek:
            return try store.topPhotos(from: back(7), through: yesterday, by: .views, limit: Self.rowLimit).map {
                BrowseItem(photo: $0.photo ?? LibraryPhoto(id: $0.photoID), figure: Self.count($0.total, "view") + " this week")
            }
        case .mostFavedThisMonth:
            return try store.topPhotos(from: back(28), through: yesterday, by: .faves, limit: Self.rowLimit).map {
                BrowseItem(photo: $0.photo ?? LibraryPhoto(id: $0.photoID), figure: Self.count($0.total, "fave") + " in 28 days")
            }
        case .rising:
            guard hasHistory(for: .rising) else { return [] }
            return try store.risingPhotos(endingOn: yesterday, limit: Self.rowLimit).map {
                BrowseItem(photo: $0.photo ?? LibraryPhoto(id: $0.photoID),
                           figure: "\($0.weekBefore.formatted()) → \($0.thisWeek.formatted()) views a week")
            }
        }
    }

    private static func dated(_ photo: LibraryPhoto) -> BrowseItem {
        BrowseItem(photo: photo, figure: photo.taken.map { String($0.prefix(10)) } ?? count(photo.views, "view"))
    }

    private static func byline(for photo: LibraryPhoto) -> String {
        photo.ownerName ?? photo.taken.map { String($0.prefix(10)) } ?? ""
    }

    static func count(_ value: Int, _ noun: String) -> String {
        "\(value.formatted(.number.locale(Locale(identifier: "en_US")))) \(noun)\(value == 1 ? "" : "s")"
    }
}
