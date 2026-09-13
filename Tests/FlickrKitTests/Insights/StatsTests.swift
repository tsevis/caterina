import Foundation
import Testing

@testable import FlickrKit

/// Flickr Pro statistics: a day at a time, for the last 28 days.
@Suite struct StatsTests {

    private func client(_ transport: ScriptedTransport) -> FlickrClient {
        FlickrClient(credentials: Fixtures.credentials, transport: transport, budget: .unspaced,
                     sleep: SleepRecorder().sleep)
    }

    // MARK: - Days

    /// A Flickr stats day starts at midnight GMT for everyone, wherever the
    /// Mac is.
    @Test func aStatsDayIsTheGMTDate() {
        let lateInAthens = Date(timeIntervalSince1970: 1_717_283_700) // 2024-06-01 23:15 GMT, 02:15 in Athens
        #expect(StatsDay(containing: lateInAthens).text == "2024-06-01")
        #expect(StatsDay(containing: lateInAthens).previous.text == "2024-05-31")
        #expect(StatsDay("2024-03-01")?.previous.text == "2024-02-29")
        #expect(StatsDay("2024-13-01") == nil)
    }

    /// Only whole days Flickr still has: yesterday back to 27 days ago.
    /// Today is not over, and day 28 may already be gone by the time it is asked.
    @Test func theDaysWorthKeepingAreYesterdayBack() {
        let now = Date(timeIntervalSince1970: 1_717_243_200) // 2024-06-01 12:00 GMT
        let days = StatsDay.completeDaysAvailable(at: now)
        #expect(days.count == 27)
        #expect(days.first?.text == "2024-05-31")
        #expect(days.last?.text == "2024-05-05")
    }

    @Test func daysSortAndCountBetween() throws {
        let a = try #require(StatsDay("2024-05-30"))
        let b = try #require(StatsDay("2024-06-02"))
        #expect(a < b)
        #expect(a.days(until: b) == 3)
    }

    // MARK: - Replies

    @Test func popularPhotosCarryTheirDaysNumbers() async throws {
        let transport = ScriptedTransport(always: """
        {"photos":{"page":2,"pages":89,"perpage":100,"total":881,"photo":[
          {"id":"2636","owner":"47058503995@N01","title":"test_04","ispublic":1,"stats":{"views":941,"comments":18,"favorites":2}},
          {"id":"2635","title":"test_03","stats":{"views":"141","comments":"1","favorites":"2"}}]},"stat":"ok"}
        """)
        let day = try #require(StatsDay("2024-06-01"))

        let page = try await client(transport).popularPhotos(on: day, page: 2)

        #expect(page.pages == 89)
        #expect(page.photos == [
            PhotoDayStats(photoID: "2636", title: "test_04", views: 941, comments: 18, faves: 2),
            PhotoDayStats(photoID: "2635", title: "test_03", views: 141, comments: 1, faves: 2),
        ])
        let asked = await transport.lastQueryItems
        #expect(asked["method"] == "flickr.stats.getPopularPhotos")
        #expect(asked["date"] == "2024-06-01")
        #expect(asked["per_page"] == "100")
        #expect(asked["sort"] == "views")
    }

    @Test func accountTotalsForADay() async throws {
        let transport = ScriptedTransport(always: """
        {"stats":{"total":{"views":469},"photos":{"views":"386"},"photostream":{"views":72},
          "sets":{"views":11},"galleries":{"views":0},"collections":{"views":0}},"stat":"ok"}
        """)
        let totals = try await client(transport).totalViews(on: StatsDay("2024-06-01"))
        #expect(totals == ViewTotals(total: 469, photos: 386, photostream: 72, albums: 11, collections: 0))
    }

    @Test func allTimeTotalsLeaveTheDateOut() async throws {
        let transport = ScriptedTransport(always: #"{"stats":{"total":{"views":1000000}},"stat":"ok"}"#)
        let totals = try await client(transport).totalViews(on: nil)
        #expect(totals.total == 1_000_000)
        #expect(await transport.lastQueryItems["date"] == nil)
    }

    @Test func oneDayOfOnePhoto() async throws {
        let transport = ScriptedTransport(always: #"{"stats":{"views":24,"comments":4,"favorites":1},"stat":"ok"}"#)
        let stats = try await client(transport).photoStats(photoID: "9", on: #require(StatsDay("2024-06-01")))
        #expect(stats == PhotoDayStats(photoID: "9", title: "", views: 24, comments: 4, faves: 1))
    }

    @Test func whereViewsCameFrom() async throws {
        let transport = ScriptedTransport([
            .body(#"{"domains":{"page":1,"pages":1,"total":2,"domain":[{"name":"images.google.com","views":70},{"name":"flickr.com","views":"122"}]},"stat":"ok"}"#),
            .body(#"{"domain":{"page":1,"pages":1,"name":"flickr.com","referrer":[{"url":"http://flickr.com/search/?q=stats+api","views":2,"searchterm":"stats api"},{"url":"http://flickr.com/","views":11}]},"stat":"ok"}"#),
        ])
        let day = try #require(StatsDay("2024-06-01"))

        let domains = try await client(transport).referringDomains(on: day, photoID: "9")
        #expect(domains == [Referral(name: "images.google.com", views: 70), Referral(name: "flickr.com", views: 122)])

        let referrers = try await client(transport).referrers(on: day, domain: "flickr.com", photoID: "9")
        #expect(referrers == [Referrer(url: "http://flickr.com/search/?q=stats+api", views: 2, searchTerm: "stats api"),
                              Referrer(url: "http://flickr.com/", views: 11, searchTerm: nil)])
    }

    /// No Pro, or stats switched off: one clear state for the window to show.
    @Test func statsNotEnabledIsRecognised() {
        #expect(FlickrError.api(code: 1, message: "User does not have stats", transient: false).meansStatsUnavailable)
        #expect(!FlickrError.api(code: 2, message: "No stats for that date", transient: false).meansStatsUnavailable)
    }
}
