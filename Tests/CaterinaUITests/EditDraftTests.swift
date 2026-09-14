import Foundation
import Testing

import FlickrKit
@testable import CaterinaUI

/// What the edit form says, turned into edits. Validated here, at the
/// boundary, before anything is recorded or sent.
@Suite struct EditDraftTests {

    @Test func tagsAreSeparatedByCommasSoATagCanHaveSpaces() {
        var draft = EditDraft(kind: .tags)
        draft.tagText = "New York, dusk ,, sea "
        #expect(draft.edits == [.addTags(["New York", "dusk", "sea"])])
        #expect(draft.batchTitle == "Add tags: New York, dusk, sea")
        draft.tagMode = .remove
        #expect(draft.edits == [.removeTags(["New York", "dusk", "sea"])])
        draft.tagMode = .replace
        #expect(draft.edits == [.replaceTags(["New York", "dusk", "sea"])])
    }

    @Test func renamingNeedsBothNames() {
        var draft = EditDraft(kind: .tags)
        draft.tagMode = .rename
        draft.renameFrom = "nyc"
        #expect(draft.edits == nil)
        #expect(draft.problem == "Enter the tag to rename and its new name.")
        draft.renameTo = "New York"
        #expect(draft.edits == [.renameTag(from: "nyc", to: "New York")])
        #expect(draft.batchTitle == "Rename tag nyc to New York")
    }

    @Test func anEmptyTagListIsNotAnEdit() {
        var draft = EditDraft(kind: .tags)
        draft.tagText = " , "
        #expect(draft.edits == nil)
        #expect(draft.problem == "Enter at least one tag.")
    }

    @Test func titlesAreSetOrAppended() {
        var draft = EditDraft(kind: .title)
        draft.text = "Athens {nn}"
        #expect(draft.edits == [.setTitle("Athens {nn}")])
        draft.textMode = .append
        #expect(draft.edits == [.appendToTitle("Athens {nn}")])
        var description = EditDraft(kind: .description)
        description.text = "Shot on film"
        #expect(description.edits == [.setDescription("Shot on film")])
    }

    /// Clearing every title is allowed only when asked for in so many words;
    /// appending nothing is never an edit.
    @Test func anEmptyTitleClearsOnlyWhenAskedTo() {
        var draft = EditDraft(kind: .title)
        #expect(draft.edits == nil)
        #expect(draft.problem == "Enter the text, or choose to clear it.")
        draft.clearsText = true
        #expect(draft.edits == [.setTitle("")])
        #expect(draft.batchTitle == "Clear titles")
        draft.textMode = .append
        #expect(draft.edits == nil)
    }

    /// An untouched map is not a place: 0,0 is the sea off West Africa.
    @Test func noPlaceChosenIsNotALocation() {
        var draft = EditDraft(kind: .location)
        #expect(draft.edits == nil)
        draft.latitude = .nan
        draft.longitude = 2
        #expect(draft.edits == nil)
    }

    @Test func batchTitlesUseWhatWasValidated() {
        var draft = EditDraft(kind: .tags)
        draft.tagMode = .rename
        draft.renameFrom = " nyc "
        draft.renameTo = " New York"
        #expect(draft.batchTitle == "Rename tag nyc to New York")
    }

    @Test func visibilityCanCarryCommentAndTagPermissions() {
        var draft = EditDraft(kind: .visibility)
        draft.isPublic = false
        draft.isFamily = true
        #expect(draft.edits == [.setVisibility(.init(isPublic: false, isFriend: false, isFamily: true))])
        draft.changesPermissions = true
        draft.comment = .contacts
        draft.addMeta = .nobody
        #expect(draft.edits == [.setVisibility(.init(isPublic: false, isFriend: false, isFamily: true)),
                                .setPermissions(.init(comment: .contacts, addMeta: .nobody))])
    }

    /// Public with friends ticked is not a thing Flickr stores: public wins.
    @Test func publicClearsFriendsAndFamily() {
        var draft = EditDraft(kind: .visibility)
        draft.isFriend = true
        #expect(draft.edits == [.setVisibility(.init(isPublic: true, isFriend: false, isFamily: false))])
    }

    @Test func aTimeZoneShiftIsSignedHoursAndMinutes() {
        var draft = EditDraft(kind: .dateTaken)
        draft.shiftHours = 3
        draft.shiftMinutes = 30
        draft.shiftsEarlier = true
        #expect(draft.edits == [.shiftTaken(seconds: -12_600)])
        #expect(draft.batchTitle == "Shift date taken 3 h 30 min earlier")
        draft.shiftHours = 0
        draft.shiftMinutes = 0
        #expect(draft.edits == nil)
    }

    @Test func aDateTakenCanBeSetOutright() {
        var draft = EditDraft(kind: .dateTaken)
        draft.dateMode = .set
        draft.takenText = "2024-06-01 21:14:05"
        #expect(draft.edits == [.setTaken("2024-06-01 21:14:05")])
        draft.takenText = "1 June 2024"
        #expect(draft.edits == nil)
        #expect(draft.problem == "Write the date as 2024-06-01 21:14:05.")
    }

    @Test func aLocationMustBeOnTheGlobe() {
        var draft = EditDraft(kind: .location)
        draft.latitude = 37.94
        draft.longitude = 23.64
        #expect(draft.edits == [.setLocation(.init(latitude: 37.94, longitude: 23.64, accuracy: 16))])
        draft.latitude = 91
        #expect(draft.edits == nil)
        draft.locationMode = .remove
        #expect(draft.edits == [.removeLocation])
        draft.locationMode = .privacy
        draft.geoIsPublic = false
        draft.geoIsFriend = true
        #expect(draft.edits == [.setGeoPermissions(.init(isPublic: false, isContact: false, isFriend: true,
                                                         isFamily: false))])
    }

    @Test func safetyContentTypeAndHiddenAreChosenOneAtATime() {
        var draft = EditDraft(kind: .safety)
        draft.safety = .moderate
        #expect(draft.edits == [.setSafety(.moderate)])
        draft.safetyField = .contentType
        draft.contentType = .screenshot
        #expect(draft.edits == [.setContentType(.screenshot)])
        draft.safetyField = .hidden
        draft.hidden = true
        #expect(draft.edits == [.setHiddenFromSearch(true)])
        #expect(draft.batchTitle == "Hide from public search")
    }

    @Test func licence() {
        var draft = EditDraft(kind: .licence)
        draft.licence = .by4
        #expect(draft.edits == [.setLicense(.by4)])
        #expect(draft.batchTitle == "Set licence to CC BY 4.0")
    }
}

@Suite struct ActionDraftTests {
    @Test func rotationIsAnActionNotAnEdit() {
        var draft = EditDraft(kind: .rotate)
        #expect(draft.action == .rotate(degrees: 90))
        #expect(draft.edits == nil)
        #expect(draft.problem == nil)
        draft.degrees = 270
        #expect(draft.action == .rotate(degrees: 270))
        #expect(draft.batchTitle == "Rotate 90° anticlockwise")
    }

    @Test func aPersonNeedsAName() {
        var draft = EditDraft(kind: .people)
        #expect(draft.action == nil)
        #expect(draft.problem == "Enter a Flickr username or photostream URL.")
        draft.person = " tsevis "
        #expect(draft.personQuery == "tsevis")
        #expect(draft.batchTitle == "Tag tsevis")
        draft.removesPerson = true
        #expect(draft.batchTitle == "Untag tsevis")
    }

    @Test func datePostedShiftsOrSets() {
        var draft = EditDraft(kind: .datePosted)
        #expect(draft.edits == nil)
        draft.postedShiftDays = 2
        #expect(draft.edits == [.shiftPosted(seconds: 172_800)])
        draft.postedMode = .set
        draft.postedDate = Date(timeIntervalSince1970: 1_600_000_000)
        #expect(draft.edits == [.setPosted(Date(timeIntervalSince1970: 1_600_000_000))])
    }
}
