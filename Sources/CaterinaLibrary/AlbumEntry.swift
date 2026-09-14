import Foundation

import FlickrKit

/// One album edit in a batch, and how far it has got.
public struct AlbumEntry: Sendable, Equatable {
    public let batchID: String
    public let position: Int
    public let edit: AlbumEdit
    /// Nil until read, just before the first call.
    public let snapshot: AlbumSnapshot?
    /// Plan steps already sent.
    public let done: Int
    public let createdAlbumID: String?
    public let state: EditEntry.State
    public let message: String?

    /// Before anything is read: one call per read, and the writes the edit
    /// is likely to take.
    var estimatedCalls: Int {
        let reads = snapshot == nil ? edit.reads.count : 0
        let writes: Int = switch edit {
        case let .create(_, _, _, photos): photos.count + 1
        case let .addPhotos(_, photos): photos.count
        case let .removePhotos(_, photos): max(1, (photos.count + AlbumEdit.removeChunk - 1) / AlbumEdit.removeChunk)
        case .editMeta, .setCover, .reorderPhotos, .orderAlbums, .delete: 1
        }
        return reads + max(0, writes - done)
    }

    /// The edits that take this one back, with a created album named.
    func undo() throws -> [AlbumEdit] {
        guard let snapshot else { return [] }
        let plan = try edit.plan(snapshot)
        return plan.undo.map { $0.resolving(createdAlbum: createdAlbumID ?? AlbumEdit.createdAlbum) }
    }
}
