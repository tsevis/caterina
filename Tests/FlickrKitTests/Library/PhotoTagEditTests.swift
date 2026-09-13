import Foundation
import Testing

@testable import FlickrKit

/// Tag edits keep the photographer's spelling.
///
/// **Flickr keeps two forms of a tag**: the raw one someone typed ("New York")
/// and a clean one it matches on ("newyork"). `setTags` takes raw tags, so a
/// list built from clean ones overwrites every spelling it touches. Edits
/// compare by the clean form and write back the raw one.
@Suite struct PhotoTagEditTests {

    private let photo = LibraryPhoto(id: "7", tags: ["New York", "Brooklyn Bridge", "night"])

    @Test func anAddedTagKeepsTheSpellingItWasTypedWith() {
        #expect(PhotoEdit.addTags(["Hudson River"]).applied(to: photo).tags
                == ["New York", "Brooklyn Bridge", "night", "Hudson River"])
    }

    /// "new york" and "New York" are one tag to Flickr, so adding it again
    /// neither duplicates it nor respells the one already there.
    @Test func aTagAlreadyPresentInAnySpellingIsNotAddedAgain() {
        #expect(PhotoEdit.addTags(["new york", "NIGHT"]).applied(to: photo).tags == photo.tags)
    }

    @Test func removingMatchesAnySpelling() {
        #expect(PhotoEdit.removeTags(["newyork", "Night"]).applied(to: photo).tags == ["Brooklyn Bridge"])
    }

    @Test func renamingReplacesTheTagWhereItStood() {
        #expect(PhotoEdit.renameTag(from: "brooklynbridge", to: "Brooklyn-Bridge").applied(to: photo).tags
                == ["New York", "Brooklyn-Bridge", "night"])
    }

    /// Renaming onto a tag the photo already has merges the two.
    @Test func renamingOntoAnExistingTagLeavesOne() {
        #expect(PhotoEdit.renameTag(from: "night", to: "new york").applied(to: photo).tags
                == ["New York", "Brooklyn Bridge"])
    }

    @Test func renamingATagThePhotoDoesNotHaveChangesNothing() {
        #expect(PhotoEdit.renameTag(from: "paris", to: "Paris").applied(to: photo) == photo)
    }

    @Test func replacingSetsExactlyTheGivenTags() {
        #expect(PhotoEdit.replaceTags(["Athens", "athens", " ", "Acropolis"]).applied(to: photo).tags
                == ["Athens", "Acropolis"])
    }

    /// Flickr's syntax for one tag of several words is to quote it; unquoted,
    /// "New York" becomes two tags.
    @Test func aTagOfSeveralWordsIsQuotedInTheWrite() throws {
        let after = PhotoEdit.removeTags(["night"]).applied(to: photo)
        let write = try #require(PhotoChange(before: photo, after: after).writes.first)
        #expect(write.method == "flickr.photos.setTags")
        #expect(write.arguments["tags"] == #""New York" "Brooklyn Bridge""#)
    }

    /// Respelling alone is a change worth sending: it is what renaming to a
    /// different capitalisation is for.
    @Test func aChangeOfSpellingAloneIsWritten() {
        let after = PhotoEdit.renameTag(from: "night", to: "Night").applied(to: photo)
        #expect(after.tags == ["New York", "Brooklyn Bridge", "Night"])
        #expect(!PhotoChange(before: photo, after: after).isEmpty)
    }
}
