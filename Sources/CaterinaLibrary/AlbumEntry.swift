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
    /// A step was sent and not yet recorded: it may have happened.
    public let isSending: Bool
    /// Photos found already as asked (already in, already out).
    public let unchanged: Set<String>

    /// Calls still to make: the plan's steps once read, else a guess.
    var estimatedCalls: Int {
        if let snapshot, let plan = try? edit.plan(snapshot) { return max(0, plan.steps.count - done) }
        let writes: Int = switch edit {
        case let .create(_, _, cover, photos): Set(photos + [cover]).count + (photos.count > 1 ? 1 : 0)
        case let .addPhotos(_, photos): Set(photos).count
        case let .removePhotos(_, photos): max(1, (photos.count + AlbumEdit.removeChunk - 1) / AlbumEdit.removeChunk)
        case .editMeta, .setCover, .reorderPhotos, .orderAlbums, .delete, .deleteMade: 1
        }
        return edit.reads.count + max(0, writes - done)
    }

    /// The edits that take this one back, with a created album named and
    /// photos this batch did not change left out.
    func undo() throws -> [AlbumEdit] {
        guard let snapshot else { return [] }
        return try edit.plan(snapshot).undo
            .map { $0.resolving(createdAlbum: createdAlbumID ?? AlbumEdit.createdAlbum) }
            .compactMap { $0.excluding(unchanged) }
    }
}
