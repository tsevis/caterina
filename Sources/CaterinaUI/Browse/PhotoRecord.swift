import Foundation

import CaterinaLibrary
import FlickrKit

/// What the photo record reads. `FlickrClient` in the app.
public protocol PhotoRecordSource: Sendable {
    func photoInfo(id: String) async throws -> PhotoInfo
    func favorites(photoID: String, page: Int) async throws -> FavePage
    func comments(photoID: String) async throws -> [PhotoComment]
    func contexts(photoID: String) async throws -> PhotoContexts
    func exif(photoID: String) async throws -> PhotoExif
}

extension FlickrClient: PhotoRecordSource {}

/// Everything known about one photo, gathered for the record panel.
public struct PhotoRecord: Sendable, Equatable {
    public struct FaveCount: Sendable, Equatable, Identifiable {
        /// The running count, which is unique where a date may not be.
        public var id: Int { count }
        public let date: Date
        public let count: Int
    }

    public let info: PhotoInfo
    /// Newest first, as Flickr lists them; at most `BrowseModel.favePageLimit` pages.
    public let faves: [Fave]
    /// Every fave, including any beyond the pages read.
    public let faveTotal: Int
    public let comments: [PhotoComment]
    public let contexts: PhotoContexts
    public let exif: PhotoExif
    /// Daily numbers saved on this Mac, oldest first.
    public let history: [StatsPoint]

    /// The running total of faves by date, oldest first, for a chart. When
    /// only the latest were read, the count starts from those before them.
    public static func cumulativeFaves(_ faves: [Fave], total: Int) -> [FaveCount] {
        let before = max(0, total - faves.count)
        return faves.sorted { $0.date < $1.date }.enumerated()
            .map { FaveCount(date: $1.date, count: before + $0 + 1) }
    }
}
