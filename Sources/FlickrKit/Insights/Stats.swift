import Foundation

/// A day as Flickr Stats counts it: midnight to midnight GMT, for everyone.
public struct StatsDay: Sendable, Hashable, Comparable, Codable {
    /// `yyyy-MM-dd`, the form Flickr takes and the form stored.
    public let text: String

    /// How long Flickr keeps daily stats.
    public static let retentionDays = 28

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    public init(containing date: Date) {
        text = Self.formatter.string(from: date)
    }

    public init?(_ text: String) {
        guard let date = Self.formatter.date(from: text), Self.formatter.string(from: date) == text else { return nil }
        self.text = text
    }

    /// Midnight GMT at the start of the day.
    public var start: Date { Self.formatter.date(from: text) ?? .distantPast }

    public var previous: StatsDay { StatsDay(containing: start.addingTimeInterval(-12 * 3600)) }

    public func days(until other: StatsDay) -> Int {
        Self.calendar.dateComponents([.day], from: start, to: other.start).day ?? 0
    }

    public static func < (lhs: StatsDay, rhs: StatsDay) -> Bool { lhs.text < rhs.text }

    /// Whole days Flickr still holds, newest first: yesterday back to 27 days
    /// ago. Today is not over; the 28th may be gone by the time it is asked for.
    public static func completeDaysAvailable(at now: Date) -> [StatsDay] {
        var day = StatsDay(containing: now).previous
        var days: [StatsDay] = []
        for _ in 1..<retentionDays {
            days.append(day)
            day = day.previous
        }
        return days
    }
}

/// One photo's numbers for one day.
public struct PhotoDayStats: Sendable, Equatable, Hashable {
    public let photoID: String
    public let title: String
    public let views: Int
    public let comments: Int
    public let faves: Int

    public init(photoID: String, title: String, views: Int, comments: Int, faves: Int) {
        self.photoID = photoID
        self.title = title
        self.views = views
        self.comments = comments
        self.faves = faves
    }
}

public struct PopularPage: Sendable, Equatable {
    public let page: Int
    public let pages: Int
    public let photos: [PhotoDayStats]

    public init(page: Int, pages: Int, photos: [PhotoDayStats]) {
        self.page = page
        self.pages = pages
        self.photos = photos
    }
}

/// Views across the account, for a day or all time.
public struct ViewTotals: Sendable, Equatable, Codable {
    public let total: Int
    public let photos: Int
    public let photostream: Int
    public let albums: Int
    public let collections: Int

    public init(total: Int, photos: Int, photostream: Int, albums: Int, collections: Int) {
        self.total = total
        self.photos = photos
        self.photostream = photostream
        self.albums = albums
        self.collections = collections
    }

    public static let zero = ViewTotals(total: 0, photos: 0, photostream: 0, albums: 0, collections: 0)
}

public struct Referral: Sendable, Equatable, Hashable {
    public let name: String
    public let views: Int
}

public struct Referrer: Sendable, Equatable, Hashable {
    public let url: String
    public let views: Int
    /// What was searched for, when the referrer is a search page.
    public let searchTerm: String?
}

extension FlickrError {
    /// From a `flickr.stats.*` call: the account has no stats — not Pro, or
    /// stats switched off.
    public var meansStatsUnavailable: Bool {
        if case .api(code: 1, _, _) = self { return true }
        return false
    }
}
