import Foundation
import Testing

import CaterinaLibrary
import FlickrKit
@testable import CaterinaUI

/// Getting photos into groups with as little in the way as possible.
@MainActor
@Suite struct AddToGroupsTests {

    private let profiles = [
        GroupShareModelTests.profile("a", "Athens Architecture"),
        GroupShareModelTests.profile("m", "Mediterranean Light"),
        GroupShareModelTests.profile("s", "Street Photography"),
    ]

    private func organize() async throws -> (OrganizeModel, FakeOrganizeFlickr) {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryPhoto(id: "p1", title: "Tram"), LibraryPhoto(id: "p2", title: "Stoa"),
                        LibraryPhoto(id: "p3", title: "Agora")], generation: 1)
        let flickr = FakeOrganizeFlickr(store: store)
        let organize = OrganizeModel(store: store, flickr: flickr, accountID: { "me" })
        organize.selectAll()
        return (organize, flickr)
    }

    private func directory(known: [GroupProfile]? = nil) -> FakeGroupDirectory {
        FakeGroupDirectory(groups: profiles.map {
            AccountGroup(id: $0.id, name: $0.name, members: $0.members, photos: $0.poolCount, isAdmin: $0.isAdmin)
        }, profiles: known ?? profiles)
    }

    // MARK: - Choosing photos

    /// Choosing photos needs no modifier key: a click ticks, another unticks.
    @Test func aPlainClickTicksAPhotoAndAnotherUnticksIt() async throws {
        let (organize, _) = try await organize()
        organize.clearSelection()
        organize.tap("p1", modifiers: [])
        organize.tap("p2", modifiers: [])
        #expect(organize.selection.ids == ["p1", "p2"])
        organize.tap("p1", modifiers: [])
        #expect(organize.selection.ids == ["p2"])
    }

    // MARK: - Reaching it

    @Test func aRightClickOutsideTheSelectionMeansThatOnePhoto() async throws {
        let (organize, _) = try await organize()
        organize.click("p1", modifiers: [])
        organize.askToAddToGroups(clicked: "p2")
        #expect(organize.pendingGroupSubjects?.map(\.id) == ["p2"])
    }

    @Test func aRightClickInsideTheSelectionMeansAllOfItInGridOrder() async throws {
        let (organize, _) = try await organize()
        organize.askToAddToGroups(clicked: "p3")
        #expect(organize.pendingGroupSubjects?.map(\.id) == organize.photos.map(\.id))
    }

    @Test func withNothingSelectedTheToolbarMeansTheTray() async throws {
        let (organize, _) = try await organize()
        organize.addSelectionToTray()
        organize.click("p1", modifiers: [.command])
        let selected = Set(organize.selection.ids)
        #expect(Set(organize.groupSubjectsForToolbar.map(\.id)) == selected)

        for id in selected { organize.click(id, modifiers: [.command]) }
        #expect(organize.selection.isEmpty)
        #expect(organize.groupSubjectsForToolbar.map(\.id) == organize.tray)
    }

    /// What the sheet opened with is what goes, whatever the tray holds.
    @Test func onlyThePhotosTheSheetWasOpenedWithAreSent() async throws {
        let (organize, flickr) = try await organize()
        organize.addSelectionToTray()
        let only = try #require(organize.trayPhotos.first { $0.id == "p2" })
        let model = GroupShareModel(organize: organize, directory: directory(), subjects: [ShareSubject(only)])
        await model.load()
        model.toggle("a")
        await model.preview()
        await model.share()

        let sent = await flickr.sent.map { $0.arguments["photo_id"] }
        #expect(sent == ["p2"])
    }

    // MARK: - Finding the group

    @Test func theGroupsLastAddedToComeFirstWithoutAsking() async throws {
        let (organize, _) = try await organize()
        organize.addSelectionToTray()
        let first = GroupShareModel(organize: organize, directory: directory())
        await first.load()
        first.toggle("s")
        await first.preview()
        await first.share()

        let next = GroupShareModel(organize: organize, directory: directory())
        await next.load()
        #expect(next.visibleGroups.map(\.id) == ["s", "a", "m"])
    }

    // MARK: - No chores

    @Test func rulesAreReadWithoutAskingAndAtTheLowestPriority() async throws {
        let (organize, _) = try await organize()
        organize.addSelectionToTray()
        let directory = directory()
        let model = GroupShareModel(organize: organize, directory: directory)
        await model.load()
        await model.readRulesQuietly()

        #expect(model.readCost == 0)
        #expect(await Set(directory.profileReads) == ["a", "m", "s"])
        #expect(await directory.profilePriorities == [.background])
    }

    /// One private or deleted group must not leave every other row unread, nor
    /// put an error in front of someone who did not ask for anything.
    @Test func aGroupThatCannotBeReadDoesNotStopTheOthersOrComplain() async throws {
        let (organize, _) = try await organize()
        organize.addSelectionToTray()
        let unreadable = directory(known: profiles.filter { $0.id != "a" })
        let model = GroupShareModel(organize: organize, directory: unreadable)
        await model.load()
        await model.readRulesQuietly()

        #expect(Set(model.profiles.keys) == ["m", "s"])
        #expect(model.problem == nil)
    }

    /// A refused key or token fails for every group, so reading on only spends
    /// calls on the same answer.
    @Test func anAccountWideRefusalStopsReadingAndSaysSo() async throws {
        let (organize, _) = try await organize()
        organize.addSelectionToTray()
        let directory = directory()
        await directory.failing(["*": .api(code: 98, message: "Invalid auth token", transient: false)])
        let model = GroupShareModel(organize: organize, directory: directory)
        await model.load()
        await model.readRulesQuietly()

        #expect(await directory.profileReads.count == 1)
        #expect(model.problem?.contains("Invalid auth token") == true)
    }

    @Test func oneUnreadableReplyDoesNotBlockTheGroupsAfterIt() async throws {
        let (organize, _) = try await organize()
        organize.addSelectionToTray()
        let directory = directory()
        await directory.failing(["a": .malformedResponse("garbled")])
        let model = GroupShareModel(organize: organize, directory: directory)
        await model.load()
        await model.readRulesQuietly()

        #expect(Set(model.profiles.keys) == ["m", "s"])
    }

    @Test func losingTheConnectionStopsReadingAndSaysSo() async throws {
        let (organize, _) = try await organize()
        organize.addSelectionToTray()
        let directory = directory()
        await directory.failing(["*": .transport("offline")])
        let model = GroupShareModel(organize: organize, directory: directory)
        await model.load()
        await model.readRulesQuietly()

        #expect(await directory.profileReads.count == 1)
        #expect(model.problem?.contains("offline") == true)
    }

    // MARK: - The preview

    /// The panel shows a spinner while there is no plan and only a change of
    /// choice starts a new one, so a no-op must not throw the plan away.
    @Test func choosingWhatIsAlreadyChosenKeepsThePreview() async throws {
        let (organize, _) = try await organize()
        organize.addSelectionToTray()
        let model = GroupShareModel(organize: organize, directory: directory())
        await model.load()
        model.chooseVisible()
        await model.preview()
        let set = GroupSet(name: "all", groupIDs: model.chosen)

        model.chooseVisible()
        #expect(model.plan != nil)
        model.choose(set: set)
        #expect(model.plan != nil)
        model.strategy = model.strategy
        #expect(model.plan != nil)
        model.capPerGroup = model.capPerGroup
        #expect(model.plan != nil)
    }

    // MARK: - The button

    @Test func theButtonSaysExactlyWhatItWillDo() async throws {
        let (organize, _) = try await organize()
        organize.addSelectionToTray()
        let model = GroupShareModel(organize: organize, directory: directory())
        await model.load()
        #expect(model.actionTitle == "Add to Groups")
        model.toggle("a")
        model.toggle("m")
        await model.preview()
        #expect(model.actionTitle == "Add 3 Photos to 2 Groups")
    }

    @Test func oneOfEachIsSingular() async throws {
        let (organize, _) = try await organize()
        organize.addSelectionToTray()
        let one = try #require(organize.trayPhotos.first)
        let model = GroupShareModel(organize: organize, directory: directory(), subjects: [ShareSubject(one)])
        await model.load()
        model.toggle("a")
        await model.preview()
        #expect(model.actionTitle == "Add 1 Photo to 1 Group")
    }

    // MARK: - Straight after uploading

    /// What Flickr did with a file's own location is not known here, so a
    /// location rule is left for Flickr to judge rather than skipped on a guess.
    @Test func anUploadedFileIsReadyToAddWithoutGuessingItsLocation() {
        let photo = ShareSubject(uploaded: URL(fileURLWithPath: "/tmp/tram.jpg"), photoID: "9", title: "")
        #expect(photo.id == "9")
        #expect(photo.title == "tram.jpg")
        #expect(photo.photo.isVideo == false)
        #expect(photo.photo.hasLocation)
    }

    @Test func anUploadedMovieIsAVideo() {
        let film = ShareSubject(uploaded: URL(fileURLWithPath: "/tmp/waves.mov"), photoID: "9", title: "Waves")
        #expect(film.photo.isVideo)
        #expect(film.title == "Waves")
    }
}
