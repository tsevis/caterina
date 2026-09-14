import Foundation
import Testing

@testable import FlickrKit

/// What an album edit sends, and what takes it back, worked out from the
/// album as Flickr had it just before.
///
/// **Undo comes from the snapshot, not from the edit.** Adding five photos
/// to an album that already held two of them is undone by removing three.
@Suite struct AlbumPlanTests {

    private let album = AlbumSnapshot(title: "Athens", description: "Spring", coverPhotoID: "1",
                                      photoIDs: ["1", "2", "3"], albumOrder: ["A", "B", "C"])

    private func methods(_ plan: AlbumPlan) -> [String] {
        plan.steps.map { step in
            switch step {
            case let .write(write): write.method
            case .createAlbum: "create"
            }
        }
    }

    @Test func addingSendsOnlyPhotosNotAlreadyThereAndUndoRemovesThose() throws {
        let plan = try AlbumEdit.addPhotos(albumID: "A", photoIDs: ["2", "4", "5", "4"]).plan(album)
        #expect(methods(plan) == ["flickr.photosets.addPhoto", "flickr.photosets.addPhoto"])
        #expect(plan.undo == [.removePhotos(albumID: "A", photoIDs: ["4", "5"])])
    }

    @Test func removingIsOneCallPerHundredAndUndoRestoresMembershipAndOrder() throws {
        let big = AlbumSnapshot(title: "", description: "", coverPhotoID: "0",
                                photoIDs: (0..<250).map(String.init), albumOrder: [])
        let removing = (1..<250).map(String.init)
        let plan = try AlbumEdit.removePhotos(albumID: "A", photoIDs: removing).plan(big)
        guard case let .write(first) = plan.steps.first else { Issue.record("no write"); return }
        #expect(plan.steps.count == 3)
        #expect(first.method == "flickr.photosets.removePhotos")
        #expect(first.arguments["photo_ids"]?.split(separator: ",").count == 100)
        #expect(plan.undo == [.addPhotos(albumID: "A", photoIDs: removing),
                              .reorderPhotos(albumID: "A", photoIDs: big.photoIDs)])
    }

    /// Flickr deletes an album left empty, and that cannot be undone by
    /// putting photos back into an album that no longer exists.
    @Test func removingEveryPhotoIsRefused() {
        #expect(throws: AlbumEdit.Refusal.self) {
            _ = try AlbumEdit.removePhotos(albumID: "A", photoIDs: ["1", "2", "3", "9"]).plan(album)
        }
    }

    @Test func titleCoverAndOrderUndoToWhatWasThere() throws {
        let meta = try AlbumEdit.editMeta(albumID: "A", title: "Piraeus", description: "").plan(album)
        #expect(meta.undo == [.editMeta(albumID: "A", title: "Athens", description: "Spring")])
        guard case let .write(write) = meta.steps.first else { Issue.record("no write"); return }
        #expect(write.arguments == ["photoset_id": "A", "title": "Piraeus", "description": ""])
        #expect(write.repeatable)

        #expect(try AlbumEdit.setCover(albumID: "A", photoID: "3").plan(album).undo
                == [.setCover(albumID: "A", photoID: "1")])
        #expect(try AlbumEdit.reorderPhotos(albumID: "A", photoIDs: ["3", "1", "2"]).plan(album).undo
                == [.reorderPhotos(albumID: "A", photoIDs: ["1", "2", "3"])])
        #expect(try AlbumEdit.orderAlbums(["C", "A", "B"]).plan(album).undo == [.orderAlbums(["A", "B", "C"])])
    }

    @Test func anAlbumNeedsATitle() {
        #expect(throws: AlbumEdit.Refusal.self) {
            _ = try AlbumEdit.editMeta(albumID: "A", title: "  ", description: "").plan(album)
        }
    }

    @Test func aCoverMustBeInTheAlbum() {
        #expect(throws: AlbumEdit.Refusal.self) {
            _ = try AlbumEdit.setCover(albumID: "A", photoID: "9").plan(album)
        }
    }

    /// Undoing a delete makes the album again, with its photos in order:
    /// a new album, since Flickr cannot bring back the old one.
    @Test func deletingIsUndoneByMakingTheAlbumAgain() throws {
        let plan = try AlbumEdit.delete(albumID: "A").plan(album)
        #expect(methods(plan) == ["flickr.photosets.delete"])
        #expect(plan.undo == [.create(title: "Athens", description: "Spring", coverPhotoID: "1",
                                      photoIDs: ["1", "2", "3"])])
    }

    /// Creating is never repeated; the photos after the cover go in by the
    /// new album's id once Flickr has said it.
    @Test func creatingMakesTheAlbumThenFillsAndOrdersIt() throws {
        let plan = try AlbumEdit.create(title: "Hydra", description: "", coverPhotoID: "2",
                                        photoIDs: ["1", "2", "3"]).plan(.empty)
        #expect(methods(plan) == ["create", "flickr.photosets.addPhoto", "flickr.photosets.addPhoto",
                                  "flickr.photosets.reorderPhotos"])
        guard case let .write(add) = plan.steps[1] else { Issue.record("no write"); return }
        #expect(add.arguments["photoset_id"] == AlbumEdit.createdAlbum)
        #expect(plan.undo == [.deleteMade(albumID: AlbumEdit.createdAlbum, photoIDs: ["1", "2", "3"])])
    }

    @Test func eachEditSaysWhatItNeedsToReadFirst() {
        #expect(AlbumEdit.create(title: "x", description: "", coverPhotoID: "1", photoIDs: ["1"]).reads == [])
        #expect(AlbumEdit.editMeta(albumID: "A", title: "x", description: "").reads == [.info])
        #expect(AlbumEdit.addPhotos(albumID: "A", photoIDs: []).reads == [.photos])
        #expect(AlbumEdit.delete(albumID: "A").reads == [.info, .photos])
        #expect(AlbumEdit.orderAlbums([]).reads == [.albumOrder])
    }

    @Test func theNewWritesHaveTheRightShape() {
        #expect(AlbumWrites.orderSets(["B", "A"]).arguments == ["photoset_ids": "B,A"])
        #expect(AlbumWrites.setPrimary(photoID: "3", albumID: "A").method == "flickr.photosets.setPrimaryPhoto")
        #expect(AlbumWrites.delete(albumID: "A").arguments == ["photoset_id": "A"])
        #expect(AlbumWrites.reorder(photoIDs: ["2", "1"], albumID: "A").arguments
                == ["photoset_id": "A", "photo_ids": "2,1"])
    }

    /// An edit is stored as JSON in the history and must read back.
    @Test func anEditRoundTripsThroughJSON() throws {
        let edit = AlbumEdit.create(title: "Hydra", description: "d", coverPhotoID: "1", photoIDs: ["1", "2"])
        let data = try JSONEncoder().encode(edit)
        #expect(try JSONDecoder().decode(AlbumEdit.self, from: data) == edit)
    }
}
