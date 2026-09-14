import Foundation

/// One change to your albums, as the history keeps it.
public enum AlbumEdit: Sendable, Equatable, Hashable, Codable {
    /// Flickr has no empty album, so the cover goes in when it is made.
    case create(title: String, description: String, coverPhotoID: String, photoIDs: [String])
    case editMeta(albumID: String, title: String, description: String)
    case addPhotos(albumID: String, photoIDs: [String])
    case removePhotos(albumID: String, photoIDs: [String])
    case setCover(albumID: String, photoID: String)
    case reorderPhotos(albumID: String, photoIDs: [String])
    case orderAlbums([String])
    case delete(albumID: String)
    /// Undoing a made album: deleted only while it holds no photo but these.
    case deleteMade(albumID: String, photoIDs: [String])

    /// Stands for the id of the album a `create` makes, until Flickr says it.
    public static let createdAlbum = "{created-album}"

    /// Flickr's `removePhotos` takes a list; a hundred keeps each call short.
    public static let removeChunk = 100

    public enum Read: Sendable, Equatable { case info, photos, albumOrder }

    /// Why an edit will not be sent, in words for the person.
    public struct Refusal: Error, Equatable, Sendable {
        public let message: String
    }

    /// What must be read from Flickr before the edit, for its undo.
    public var reads: [Read] {
        switch self {
        case .create: []
        case .editMeta: [.info]
        case .addPhotos, .removePhotos, .reorderPhotos: [.photos]
        case .setCover: [.info, .photos]
        case .orderAlbums: [.albumOrder]
        case .delete: [.info, .photos]
        case .deleteMade: [.photos]
        }
    }

    /// The album this edit is about, when it is about one.
    public var albumID: String? {
        switch self {
        case .create, .orderAlbums: nil
        case let .editMeta(id, _, _), let .addPhotos(id, _), let .removePhotos(id, _),
             let .setCover(id, _), let .reorderPhotos(id, _), let .delete(id), let .deleteMade(id, _): id
        }
    }

    /// The same edit without `photos` in what it adds or removes: photos found
    /// already as asked, which this batch did not change.
    public func excluding(_ photos: Set<String>) -> AlbumEdit? {
        guard !photos.isEmpty else { return self }
        switch self {
        case let .addPhotos(album, ids):
            let kept = ids.filter { !photos.contains($0) }
            return kept.isEmpty ? nil : .addPhotos(albumID: album, photoIDs: kept)
        case let .removePhotos(album, ids):
            let kept = ids.filter { !photos.contains($0) }
            return kept.isEmpty ? nil : .removePhotos(albumID: album, photoIDs: kept)
        case let .reorderPhotos(album, ids):
            return .reorderPhotos(albumID: album, photoIDs: ids.filter { !photos.contains($0) })
        default:
            return self
        }
    }

    /// The same edit with the created-album placeholder filled in.
    public func resolving(createdAlbum id: String) -> AlbumEdit {
        let fill = { (albumID: String) in albumID == Self.createdAlbum ? id : albumID }
        switch self {
        case .create, .orderAlbums: return self
        case let .editMeta(album, title, description): return .editMeta(albumID: fill(album), title: title, description: description)
        case let .addPhotos(album, photos): return .addPhotos(albumID: fill(album), photoIDs: photos)
        case let .removePhotos(album, photos): return .removePhotos(albumID: fill(album), photoIDs: photos)
        case let .setCover(album, photo): return .setCover(albumID: fill(album), photoID: photo)
        case let .reorderPhotos(album, photos): return .reorderPhotos(albumID: fill(album), photoIDs: photos)
        case let .delete(album): return .delete(albumID: fill(album))
        case let .deleteMade(album, photos): return .deleteMade(albumID: fill(album), photoIDs: photos)
        }
    }
}

/// An album as Flickr had it just before an edit. Only what the edit's
/// `reads` asked for is filled in.
public struct AlbumSnapshot: Sendable, Equatable, Codable {
    public let title: String
    public let description: String
    public let coverPhotoID: String
    /// In album order.
    public let photoIDs: [String]
    /// Every album's id, in the order they are arranged.
    public let albumOrder: [String]

    public init(title: String, description: String, coverPhotoID: String, photoIDs: [String], albumOrder: [String]) {
        self.title = title
        self.description = description
        self.coverPhotoID = coverPhotoID
        self.photoIDs = photoIDs
        self.albumOrder = albumOrder
    }

    public static let empty = AlbumSnapshot(title: "", description: "", coverPhotoID: "", photoIDs: [], albumOrder: [])
}

/// The calls, in order, and the edits that take them back.
public struct AlbumPlan: Sendable, Equatable {
    public enum Step: Sendable, Equatable {
        case write(FlickrWrite)
        /// Never repeated; its reply names the album later steps refer to.
        case createAlbum(title: String, description: String, coverPhotoID: String)
    }

    public let steps: [Step]
    public let undo: [AlbumEdit]
}
