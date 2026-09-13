import Foundation

extension FlickrClient {

    /// Your photos with any activity on `day`, most viewed first, 100 a page.
    public func popularPhotos(on day: StatsDay, page: Int,
                              priority: CallPriority = .background) async throws -> PopularPage {
        let data = try await call("flickr.stats.getPopularPhotos",
                                  ["date": day.text, "sort": "views", "per_page": "100", "page": String(page)],
                                  priority: priority)
        struct Envelope: Decodable { let photos: Photos }
        struct Photos: Decodable {
            let page: FlickrResponse.LooseInt?; let pages: FlickrResponse.LooseInt?
            let photo: [FlickrResponse.Lenient<Photo>]?
        }
        struct Photo: Decodable { let id: String; let title: String?; let stats: Counts? }
        let photos = try InsightsResponse.decode(Envelope.self, data, "your popular photos").photos
        return PopularPage(page: max(1, photos.page?.value ?? 1), pages: max(1, photos.pages?.value ?? 1),
                           photos: (photos.photo ?? []).compactMap(\.value).map {
                               ($0.stats ?? Counts()).day(photoID: $0.id, title: $0.title ?? "")
                           })
    }

    /// Views across your account on `day`, or all time when `day` is nil.
    public func totalViews(on day: StatsDay?, priority: CallPriority = .background) async throws -> ViewTotals {
        let data = try await call("flickr.stats.getTotalViews", day.map { ["date": $0.text] } ?? [:], priority: priority)
        struct Envelope: Decodable { let stats: Totals }
        struct Totals: Decodable {
            let total: Views?; let photos: Views?; let photostream: Views?; let sets: Views?; let collections: Views?
        }
        struct Views: Decodable { let views: FlickrResponse.LooseInt? }
        let stats = try InsightsResponse.decode(Envelope.self, data, "your total views").stats
        let count = { (views: Views?) in views?.views?.value ?? 0 }
        return ViewTotals(total: count(stats.total), photos: count(stats.photos), photostream: count(stats.photostream),
                          albums: count(stats.sets), collections: count(stats.collections))
    }

    public func photoStats(photoID: String, on day: StatsDay,
                           priority: CallPriority = .interactive) async throws -> PhotoDayStats {
        let data = try await call("flickr.stats.getPhotoStats", ["date": day.text, "photo_id": photoID],
                                  priority: priority)
        struct Envelope: Decodable { let stats: Counts }
        return try InsightsResponse.decode(Envelope.self, data, "the photo's stats").stats
            .day(photoID: photoID, title: "")
    }

    /// The sites views came from on `day`, for one photo or all of them.
    public func referringDomains(on day: StatsDay, photoID: String? = nil) async throws -> [Referral] {
        var arguments = ["date": day.text, "per_page": "100"]
        arguments["photo_id"] = photoID
        let data = try await call("flickr.stats.getPhotoDomains", arguments)
        struct Envelope: Decodable { let domains: Domains }
        struct Domains: Decodable { let domain: [FlickrResponse.Lenient<Domain>]? }
        struct Domain: Decodable { let name: String; let views: FlickrResponse.LooseInt? }
        return (try InsightsResponse.decode(Envelope.self, data, "where views came from").domains.domain ?? [])
            .compactMap(\.value).map { Referral(name: $0.name, views: $0.views?.value ?? 0) }
    }

    /// The pages on `domain` that sent views on `day`.
    public func referrers(on day: StatsDay, domain: String, photoID: String? = nil) async throws -> [Referrer] {
        var arguments = ["date": day.text, "domain": domain, "per_page": "100"]
        arguments["photo_id"] = photoID
        let data = try await call("flickr.stats.getPhotoReferrers", arguments)
        struct Envelope: Decodable { let domain: Domain }
        struct Domain: Decodable { let referrer: [FlickrResponse.Lenient<Entry>]? }
        struct Entry: Decodable { let url: String; let views: FlickrResponse.LooseInt?; let searchterm: String? }
        return (try InsightsResponse.decode(Envelope.self, data, "the referring pages").domain.referrer ?? [])
            .compactMap(\.value).map { Referrer(url: $0.url, views: $0.views?.value ?? 0, searchTerm: $0.searchterm) }
    }
}

/// `{"views": 941, "comments": 18, "favorites": 2}`, numbers or strings.
private struct Counts: Decodable {
    var views: FlickrResponse.LooseInt?
    var comments: FlickrResponse.LooseInt?
    var favorites: FlickrResponse.LooseInt?

    init() {}

    func day(photoID: String, title: String) -> PhotoDayStats {
        PhotoDayStats(photoID: photoID, title: title, views: views?.value ?? 0,
                      comments: comments?.value ?? 0, faves: favorites?.value ?? 0)
    }
}
