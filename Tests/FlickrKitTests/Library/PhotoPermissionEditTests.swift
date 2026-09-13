import Foundation
import Testing

@testable import FlickrKit

/// Who can see and do what: the edits beyond visibility.
@Suite struct PhotoPermissionEditTests {

    private let photo = LibraryPhoto(
        id: "3", visibility: .init(isPublic: true, isFriend: false, isFamily: false),
        location: .init(latitude: 1, longitude: 2, accuracy: 16),
        permissions: .init(comment: .everybody, addMeta: .contacts))

    private func writes(_ edit: PhotoEdit, on photo: LibraryPhoto? = nil) -> [FlickrWrite] {
        let before = photo ?? self.photo
        return PhotoChange(before: before, after: edit.applied(to: before)).writes
    }

    /// `setPerms` requires the three visibility flags even when only
    /// commenting changes, so they are sent as they stand.
    @Test func commentAndTagPermissionsGoWithTheVisibilityFlags() throws {
        let write = try #require(writes(.setPermissions(.init(comment: .nobody, addMeta: .friendsAndFamily))).first)
        #expect(write.method == "flickr.photos.setPerms")
        #expect(write.arguments == ["photo_id": "3", "is_public": "1", "is_friend": "0", "is_family": "0",
                                    "perm_comment": "0", "perm_addmeta": "1"])
        #expect(write.repeatable)
    }

    /// Unknown permissions are left out, which leaves Flickr's as they are.
    @Test func aVisibilityChangeWithUnknownPermissionsSendsOnlyTheFlags() throws {
        let unknown = LibraryPhoto(id: "3")
        let write = try #require(writes(.setVisibility(.init(isPublic: false, isFriend: true, isFamily: false)),
                                        on: unknown).first)
        #expect(write.arguments["perm_comment"] == nil)
        #expect(write.arguments["perm_addmeta"] == nil)
    }

    @Test func safetyAndHiddenShareOneMethod() throws {
        let both = PhotoEdit.setHiddenFromSearch(true).applied(to: PhotoEdit.setSafety(.restricted).applied(to: photo))
        let write = try #require(PhotoChange(before: photo, after: both).writes.first)
        #expect(write.method == "flickr.photos.setSafetyLevel")
        #expect(write.arguments == ["photo_id": "3", "safety_level": "3", "hidden": "1"])

        let unhide = try #require(writes(.setHiddenFromSearch(false)).first)
        #expect(unhide.arguments == ["photo_id": "3", "hidden": "0"])
    }

    @Test func contentTypeIncludesVirtualPhotography() throws {
        let write = try #require(writes(.setContentType(.virtualPhotography)).first)
        #expect(write.method == "flickr.photos.setContentType")
        #expect(write.arguments == ["photo_id": "3", "content_type": "4"])
    }

    /// `geo.setPerms` takes all four flags, every time.
    @Test func locationPermissionsSendAllFourFlags() throws {
        let write = try #require(writes(.setGeoPermissions(.init(isPublic: false, isContact: true,
                                                                 isFriend: true, isFamily: false))).first)
        #expect(write.method == "flickr.photos.geo.setPerms")
        #expect(write.arguments == ["photo_id": "3", "is_public": "0", "is_contact": "1",
                                    "is_friend": "1", "is_family": "0"])
    }

    /// Flickr does not report some values back (`photos.getInfo` has no
    /// content type), so there is nothing to put back. The change says which.
    @Test func aChangeNamesWhatItCannotPutBack() {
        let change = PhotoChange(before: photo, after: PhotoEdit.setContentType(.screenshot).applied(to: photo))
        #expect(change.unrestorable == ["content type"])
        #expect(change.reversed.writes.isEmpty)
        let known = PhotoChange(before: photo, after: PhotoEdit.setTitle("A").applied(to: photo))
        #expect(known.unrestorable.isEmpty)
    }

    @Test func eachNewFieldConflictsOnItsOwn() {
        let changedOnFlickr = PhotoEdit.setPermissions(.init(comment: .contacts, addMeta: .contacts)).applied(to: photo)
        let change = PhotoChange(before: photo,
                                 after: PhotoEdit.setPermissions(.init(comment: .nobody, addMeta: .nobody))
                                    .applied(to: photo))
        guard case let .conflict(reason) = change.rebased(onto: changedOnFlickr) else {
            Issue.record("Permissions changed on both sides must be refused")
            return
        }
        #expect(reason.contains("comment"))
    }

    /// The library copy never holds these, so "unknown" before is not a
    /// conflict with what Flickr reports; Flickr's value becomes the before,
    /// which is what lets undo put it back.
    @Test func anUnknownBeforeTakesFlickrsValue() throws {
        let local = LibraryPhoto(id: "3", location: photo.location)
        let change = PhotoChange(before: local,
                                 after: PhotoEdit.setPermissions(.init(comment: .nobody, addMeta: .nobody))
                                    .applied(to: local))
        guard case let .change(rebased) = change.rebased(onto: photo) else {
            Issue.record("An unknown before must not conflict")
            return
        }
        #expect(rebased.before.permissions == photo.permissions)
        #expect(rebased.unrestorable.isEmpty)
        #expect(rebased.reversed.writes.first?.arguments["perm_comment"] == "3")
    }

    @Test func getInfoPermissionsAreRead() throws {
        let data = Data(#"{"photo":{"id":"1","permissions":{"permcomment":"3","permaddmeta":2}},"stat":"ok"}"#.utf8)
        #expect(try InsightsResponse.info(from: data).libraryPhoto.permissions
                == .init(comment: .everybody, addMeta: .contacts))
    }

    /// A photo recorded before these fields existed still reads back.
    @Test func aPhotoStoredWithoutTheNewFieldsDecodes() throws {
        let json = #"{"id":"1","title":"","description":"","tags":[],"visibility":{"isPublic":true,"isFriend":false,"isFamily":false},"views":0,"media":"photo"}"#
        let photo = try JSONDecoder().decode(LibraryPhoto.self, from: Data(json.utf8))
        #expect(photo.permissions == nil)
        #expect(photo.contentType == nil)
    }
}
