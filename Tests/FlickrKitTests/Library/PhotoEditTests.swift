import Foundation
import Testing

@testable import FlickrKit

/// A batch edit, as a change from one photo to another.
///
/// **The writes come from the difference, so undo is the difference the other
/// way.** Nothing has to remember what an edit meant; the before and after are
/// enough to redo it or take it back exactly.
@Suite struct PhotoEditTests {

    private let photo = LibraryPhoto(
        id: "42", title: "Harbour", description: "Looking west", tags: ["piraeus", "dusk"],
        license: .allRightsReserved,
        visibility: .init(isPublic: true, isFriend: false, isFamily: false),
        taken: "2024-06-01 21:14:05", views: 10,
        location: .init(latitude: 37.9421, longitude: 23.6465, accuracy: 16))

    private func fields(_ write: FlickrWrite) -> [String: String] { write.arguments }

    // MARK: - Applying

    @Test func tagsAreAddedOnceAndRemovedWherePresent() {
        #expect(PhotoEdit.addTags(["dusk", "sea"]).applied(to: photo).tags == ["piraeus", "dusk", "sea"])
        #expect(PhotoEdit.removeTags(["piraeus", "absent"]).applied(to: photo).tags == ["dusk"])
    }

    /// Flickr matches tags lowercased without spaces; comparing any other way
    /// adds "Dusk" beside "dusk". A new tag keeps the spelling it was typed
    /// with (`PhotoTagEditTests`).
    @Test func tagsCompareTheWayFlickrStoresThem() {
        #expect(PhotoEdit.addTags(["Dusk", "New York"]).applied(to: photo).tags
                == ["piraeus", "dusk", "New York"])
    }

    @Test func aTakenDateShiftsByWholeSeconds() {
        #expect(PhotoEdit.shiftTaken(seconds: 3 * 3600).applied(to: photo).taken == "2024-06-02 00:14:05")
        #expect(PhotoEdit.shiftTaken(seconds: -60).applied(to: photo).taken == "2024-06-01 21:13:05")
        let undated = LibraryPhoto(id: "1")
        #expect(PhotoEdit.shiftTaken(seconds: 60).applied(to: undated).taken == nil)
    }

    @Test func aTitleCanBeReplacedOrAppendedTo() {
        #expect(PhotoEdit.setTitle("Piraeus").applied(to: photo).title == "Piraeus")
        #expect(PhotoEdit.appendToTitle(" · 2024").applied(to: photo).title == "Harbour · 2024")
    }

    // MARK: - Writes from the difference

    @Test func aTitleChangeSendsTitleAndDescriptionTogether() throws {
        let writes = PhotoChange(before: photo, after: PhotoEdit.setTitle("Piraeus").applied(to: photo)).writes
        let write = try #require(writes.first)
        #expect(writes.count == 1)
        #expect(write.method == "flickr.photos.setMeta")
        #expect(fields(write) == ["photo_id": "42", "title": "Piraeus", "description": "Looking west"])
        #expect(write.repeatable)
    }

    @Test func tagsAreSetAsTheWholeList() throws {
        let change = PhotoChange(before: photo, after: PhotoEdit.addTags(["sea"]).applied(to: photo))
        let write = try #require(change.writes.first)
        #expect(write.method == "flickr.photos.setTags")
        #expect(fields(write) == ["photo_id": "42", "tags": "piraeus dusk sea"])
    }

    @Test func visibilitySendsAllThreeFlags() throws {
        let after = PhotoEdit.setVisibility(.init(isPublic: false, isFriend: true, isFamily: true)).applied(to: photo)
        let write = try #require(PhotoChange(before: photo, after: after).writes.first)
        #expect(write.method == "flickr.photos.setPerms")
        #expect(fields(write) == ["photo_id": "42", "is_public": "0", "is_friend": "1", "is_family": "1"])
    }

    @Test func licenceLocationAndDateEachHaveTheirMethod() {
        let after = PhotoEdit.setLicense(.by).applied(to:
            PhotoEdit.shiftTaken(seconds: 60).applied(to:
                PhotoEdit.setLocation(.init(latitude: 40.7128, longitude: -74.006, accuracy: 11)).applied(to: photo)))
        let writes = PhotoChange(before: photo, after: after).writes
        #expect(writes.map(\.method) == ["flickr.photos.setDates",
                                         "flickr.photos.licenses.setLicense",
                                         "flickr.photos.geo.setLocation"])
        #expect(writes[0].arguments == ["photo_id": "42", "date_taken": "2024-06-01 21:15:05",
                                        "date_taken_granularity": "0"])
        #expect(writes[1].arguments == ["photo_id": "42", "license_id": "4"])
        #expect(writes[2].arguments == ["photo_id": "42", "lat": "40.7128", "lon": "-74.006", "accuracy": "11"])
    }

    @Test func removingALocationIsItsOwnMethod() throws {
        let after = PhotoEdit.removeLocation.applied(to: photo)
        let write = try #require(PhotoChange(before: photo, after: after).writes.first)
        #expect(write.method == "flickr.photos.geo.removeLocation")
        #expect(fields(write) == ["photo_id": "42"])
    }

    /// Accuracy zero means Flickr never said; sending it would be refused.
    @Test func anUnknownAccuracyIsLeftOut() throws {
        let after = PhotoEdit.setLocation(.init(latitude: 1, longitude: 2, accuracy: 0)).applied(to: photo)
        let write = try #require(PhotoChange(before: photo, after: after).writes.first)
        #expect(fields(write)["accuracy"] == nil)
    }

    @Test func anEditThatChangesNothingSendsNothing() {
        #expect(PhotoChange(before: photo, after: PhotoEdit.addTags(["dusk"]).applied(to: photo)).isEmpty)
        #expect(PhotoChange(before: photo, after: PhotoEdit.setLicense(.allRightsReserved).applied(to: photo)).writes.isEmpty)
    }

    // MARK: - Undo

    @Test func undoIsTheSameChangeTheOtherWay() throws {
        let after = PhotoEdit.setTitle("Piraeus").applied(to: PhotoEdit.removeTags(["dusk"]).applied(to: photo))
        let change = PhotoChange(before: photo, after: after)
        let undo = change.reversed

        #expect(undo.after == photo)
        #expect(undo.writes.map(\.method) == ["flickr.photos.setMeta", "flickr.photos.setTags"])
        #expect(undo.writes[1].arguments["tags"] == "piraeus dusk")
    }

    /// A photo whose date was never known cannot have that restored: Flickr
    /// has no way to set "unknown".
    @Test func aDateThatWasUnknownIsNotWrittenBack() {
        let undated = LibraryPhoto(id: "1", taken: nil)
        let dated = LibraryPhoto(id: "1", taken: "2024-01-01 00:00:00")
        #expect(PhotoChange(before: dated, after: undated).writes.isEmpty)
    }
}

@Suite struct SetTakenTests {
    @Test func aDateTakenIsSetOutrightAndWrittenWithSetDates() throws {
        let photo = LibraryPhoto(id: "1", taken: "2020-01-01 00:00:00")
        let after = PhotoEdit.setTaken("2024-06-01 21:14:05").applied(to: photo)
        #expect(after.taken == "2024-06-01 21:14:05")
        let write = try #require(PhotoChange(before: photo, after: after).writes.first)
        #expect(write.arguments == ["photo_id": "1", "date_taken": "2024-06-01 21:14:05", "date_taken_granularity": "0"])
    }
}

/// The date a photo appears to have been uploaded, which Organizr can change.
@Suite struct PostedDateTests {
    private let photo = LibraryPhoto(id: "1", uploaded: Date(timeIntervalSince1970: 1_700_000_000))

    @Test func postedIsShiftedOrSetAndWrittenAsUnixTime() throws {
        let shifted = PhotoEdit.shiftPosted(seconds: -3600).applied(to: photo)
        #expect(shifted.uploaded == Date(timeIntervalSince1970: 1_699_996_400))
        let write = try #require(PhotoChange(before: photo, after: shifted).writes.first)
        #expect(write.method == "flickr.photos.setDates")
        #expect(write.arguments == ["photo_id": "1", "date_posted": "1699996400"])

        let set = PhotoEdit.setPosted(Date(timeIntervalSince1970: 1_600_000_000)).applied(to: photo)
        #expect(set.uploaded == Date(timeIntervalSince1970: 1_600_000_000))
    }

    /// Both dates changing go in one call.
    @Test func takenAndPostedShareOneCall() throws {
        let taken = LibraryPhoto(id: "1", uploaded: photo.uploaded, taken: "2020-01-01 00:00:00")
        let after = PhotoEdit.shiftPosted(seconds: 60).applied(to: PhotoEdit.shiftTaken(seconds: 60).applied(to: taken))
        let writes = PhotoChange(before: taken, after: after).writes
        #expect(writes.count == 1)
        #expect(writes.first?.arguments["date_posted"] == "1700000060")
        #expect(writes.first?.arguments["date_taken"] == "2020-01-01 00:01:00")
    }

    /// Flickr keeps whole seconds; a fraction kept here would never match
    /// Flickr's value again, and undo would find a conflict every time.
    @Test func aPostedDateIsWholeSeconds() {
        #expect(PhotoEdit.setPosted(Date(timeIntervalSince1970: 1_600_000_000.7)).applied(to: photo).uploaded
                == Date(timeIntervalSince1970: 1_600_000_000))
        let fractional = LibraryPhoto(id: "1", uploaded: Date(timeIntervalSince1970: 1_700_000_000.25))
        #expect(PhotoEdit.shiftPosted(seconds: 60).applied(to: fractional).uploaded == Date(timeIntervalSince1970: 1_700_000_060))
    }

    @Test func aPostedDateChangedOnFlickrIsAConflict() {
        let change = PhotoChange(before: photo, after: PhotoEdit.shiftPosted(seconds: 60).applied(to: photo))
        let moved = PhotoEdit.shiftPosted(seconds: 999).applied(to: photo)
        guard case let .conflict(reason) = change.rebased(onto: moved) else {
            Issue.record("expected a conflict")
            return
        }
        #expect(reason.contains("date posted"))
    }
}
