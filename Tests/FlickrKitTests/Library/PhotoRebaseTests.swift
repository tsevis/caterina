import Foundation
import Testing

@testable import FlickrKit

/// A change worked out from the local copy, laid over the photo as Flickr has
/// it now.
///
/// **The local copy can be behind.** A title edited on flickr.com since the
/// last sync must not be silently written over, and a tag added there must
/// not be dropped by a tag edit made here. `rebased(onto:)` keeps what this
/// change touches, takes everything else from Flickr, and refuses a field
/// that was changed on both sides.
@Suite struct PhotoRebaseTests {

    private let local = LibraryPhoto(
        id: "9", title: "Harbour", description: "West", tags: ["newyork", "night"],
        license: .allRightsReserved, visibility: .init(isPublic: true, isFriend: false, isFamily: false),
        taken: "2024-06-01 21:14:05", location: .init(latitude: 37.9421, longitude: 23.6465, accuracy: 16),
        thumbnailURL: "https://live.staticflickr.com/t.jpg")

    /// As `photos.getInfo` gives it: raw tags, and nothing about thumbnails.
    private var live: LibraryPhoto {
        LibraryPhoto(id: "9", title: "Harbour", description: "West", tags: ["New York", "night"],
                     license: .allRightsReserved,
                     visibility: .init(isPublic: true, isFriend: false, isFamily: false),
                     taken: "2024-06-01 21:14:05",
                     location: .init(latitude: 37.9421, longitude: 23.6465, accuracy: 16))
    }

    private func change(_ edit: PhotoEdit) -> PhotoChange {
        PhotoChange(before: local, after: edit.applied(to: local))
    }

    private func rebased(_ edit: PhotoEdit, onto photo: LibraryPhoto) throws -> PhotoChange {
        guard case let .change(change) = change(edit).rebased(onto: photo) else {
            Issue.record("Expected a change for \(edit)")
            throw FlickrError.invalidInput("conflict")
        }
        return change
    }

    @Test func aTagEditKeepsTheSpellingFlickrHas() throws {
        let rebased = try rebased(.addTags(["sea"]), onto: live)
        #expect(rebased.before == live)
        #expect(rebased.after.tags == ["New York", "night", "sea"])
        #expect(rebased.writes.first?.arguments["tags"] == #""New York" night sea"#)
    }

    @Test func aTagAddedOnFlickrSinceTheSyncSurvivesATagEdit() throws {
        let edited = LibraryPhoto(id: "9", title: "Harbour", description: "West",
                                  tags: ["New York", "night", "Piraeus Port"], license: .allRightsReserved,
                                  visibility: live.visibility, taken: live.taken, location: live.location)
        let rebased = try rebased(.removeTags(["night"]), onto: edited)
        #expect(rebased.after.tags == ["New York", "Piraeus Port"])
    }

    @Test func aTitleChangedOnFlickrSinceTheSyncIsNotWrittenOver() {
        let edited = LibraryPhoto(id: "9", title: "Renamed on flickr.com", description: "West",
                                  tags: live.tags, license: .allRightsReserved, visibility: live.visibility,
                                  taken: live.taken, location: live.location)
        guard case let .conflict(reason) = change(.setTitle("Piraeus")).rebased(onto: edited) else {
            Issue.record("A title changed on both sides must be refused")
            return
        }
        #expect(reason.contains("title"))
    }

    /// A field the change does not touch is Flickr's to keep: an edit to the
    /// licence says nothing about the title someone changed on flickr.com.
    @Test func aFieldChangedOnlyOnFlickrIsKept() throws {
        let edited = LibraryPhoto(id: "9", title: "Renamed on flickr.com", description: "West",
                                  tags: live.tags, license: .allRightsReserved, visibility: live.visibility,
                                  taken: live.taken, location: live.location)
        let rebased = try rebased(.setLicense(.by), onto: edited)
        #expect(rebased.after.title == "Renamed on flickr.com")
        #expect(rebased.after.license == .by)
        #expect(rebased.writes.map(\.method) == ["flickr.photos.licenses.setLicense"])
    }

    /// Already done on Flickr, by hand or by an earlier run cut off before it
    /// was recorded: nothing left to send.
    @Test func aChangeFlickrAlreadyHasSendsNothing() throws {
        let done = PhotoEdit.setVisibility(.init(isPublic: false, isFriend: true, isFamily: true)).applied(to: live)
        guard case let .change(rebased) = change(.setVisibility(done.visibility)).rebased(onto: done) else {
            Issue.record("Flickr already matching the change is not a conflict")
            return
        }
        #expect(rebased.isEmpty)
    }

    @Test func eachScalarFieldIsCheckedOnItsOwn() {
        let cases: [(PhotoEdit, LibraryPhoto, String)] = [
            (.setDescription("East"),
             LibraryPhoto(id: "9", title: "Harbour", description: "Changed", tags: live.tags,
                          license: .allRightsReserved, visibility: live.visibility, taken: live.taken,
                          location: live.location), "description"),
            (.setLicense(.by), PhotoEdit.setLicense(.byNc).applied(to: live), "licence"),
            (.setVisibility(.init(isPublic: false, isFriend: false, isFamily: false)),
             PhotoEdit.setVisibility(.init(isPublic: false, isFriend: true, isFamily: false)).applied(to: live),
             "who can see"),
            (.shiftTaken(seconds: 60), PhotoEdit.shiftTaken(seconds: 3600).applied(to: live), "date taken"),
            (.removeLocation, PhotoEdit.setLocation(.init(latitude: 1, longitude: 2, accuracy: 3)).applied(to: live),
             "location"),
        ]
        for (edit, photo, field) in cases {
            guard case let .conflict(reason) = change(edit).rebased(onto: photo) else {
                Issue.record("\(field) changed on both sides must be refused")
                continue
            }
            #expect(reason.contains(field))
        }
    }

    /// Undo is a change too, and rebases the same way: it will not put back a
    /// title someone has since changed again.
    @Test func undoIsRefusedWhereThePhotoHasMovedOn() throws {
        let applied = try rebased(.setTitle("Piraeus"), onto: live)
        let movedOn = PhotoEdit.setTitle("Third title").applied(to: applied.after)
        guard case .conflict = applied.reversed.rebased(onto: movedOn) else {
            Issue.record("Undo over a newer title must be refused")
            return
        }
    }
}
