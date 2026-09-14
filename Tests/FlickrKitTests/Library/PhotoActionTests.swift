import Foundation
import Testing

@testable import FlickrKit

/// Changes that are not a field of the photo: rotating, tagging people,
/// deleting. Each knows its own undo, or that it has none.
@Suite struct PhotoActionTests {

    /// Rotating twice turns the photo twice, so it is never sent again after
    /// a lost reply.
    @Test func rotatingIsNeverRepeatedAndUndoTurnsItBack() {
        let write = PhotoAction.rotate(degrees: 90).write(photoID: "7")
        #expect(write.method == "flickr.photos.transform.rotate")
        #expect(write.arguments == ["photo_id": "7", "degrees": "90"])
        #expect(!write.repeatable)
        #expect(PhotoAction.rotate(degrees: 90).undo == .rotate(degrees: 270))
        #expect(PhotoAction.rotate(degrees: 180).undo == .rotate(degrees: 180))
    }

    @Test func peopleAreAddedAndRemovedEachUndoingTheOther() {
        let add = PhotoAction.addPerson(userID: "12@N01").write(photoID: "7")
        #expect(add.method == "flickr.photos.people.add")
        #expect(add.arguments == ["photo_id": "7", "user_id": "12@N01"])
        #expect(add.repeatable)
        #expect(PhotoAction.addPerson(userID: "12@N01").undo == .removePerson(userID: "12@N01"))
        #expect(PhotoAction.removePerson(userID: "12@N01").write(photoID: "7").method == "flickr.photos.people.delete")
    }

    /// Delete needs Flickr's separate delete permission and has no undo.
    @Test func deletingNeedsDeletePermissionAndCannotBeUndone() {
        let write = PhotoAction.delete.write(photoID: "7")
        #expect(write.method == "flickr.photos.delete")
        #expect(write.permission == .delete)
        #expect(PhotoAction.delete.undo == nil)
    }

    @Test func onlyRightAnglesRotate() {
        #expect(PhotoAction.rotation(degrees: 450) == .rotate(degrees: 90))
        #expect(PhotoAction.rotation(degrees: -90) == .rotate(degrees: 270))
        #expect(PhotoAction.rotation(degrees: 360) == nil)
        #expect(PhotoAction.rotation(degrees: 45) == nil)
    }

    @Test func anActionRoundTripsThroughJSON() throws {
        for action in [PhotoAction.rotate(degrees: 90), .addPerson(userID: "a"), .removePerson(userID: "b"), .delete] {
            #expect(try JSONDecoder().decode(PhotoAction.self, from: JSONEncoder().encode(action)) == action)
        }
    }
}
