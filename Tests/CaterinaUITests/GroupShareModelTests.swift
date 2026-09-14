import Foundation
import Testing

import CaterinaLibrary
import FlickrKit
@testable import CaterinaUI

/// Your groups and their rules, from a script.
actor FakeGroupDirectory: GroupDirectory {
    let groups: [AccountGroup]
    let profiles: [String: GroupProfile]
    let pools: [String: [String]]
    private(set) var profileReads: [String] = []
    private(set) var poolReads: [String] = []

    init(groups: [AccountGroup], profiles: [GroupProfile], pools: [String: [String]] = [:]) {
        self.groups = groups
        self.profiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        self.pools = pools
    }

    func groups(of userID: String) async throws -> [AccountGroup] { groups }
    func groupProfile(id: String, priority: CallPriority) async throws -> GroupProfile {
        profileReads.append(id)
        guard let profile = profiles[id] else { throw FlickrError.api(code: 1, message: "Group not found", transient: false) }
        return profile
    }
    func poolIDs(photoID: String, priority: CallPriority) async throws -> [String] {
        poolReads.append(photoID)
        return pools[photoID] ?? []
    }
}

@MainActor
@Suite struct GroupShareModelTests {

    static func profile(_ id: String, _ name: String, members: Int = 100, remaining: Int? = nil,
                        videos: Bool = true, moderated: Bool = false, admin: Bool = false) -> GroupProfile {
        GroupProfile(id: id, name: name, members: members, poolCount: members * 10, isAdmin: admin, isModerated: moderated,
                     isEighteenPlus: false,
                     throttle: remaining.map { GroupThrottle(mode: .day, count: $0, remaining: $0) }
                        ?? GroupThrottle(mode: .none, count: nil, remaining: nil),
                     restrictions: GroupRestrictions(photos: true, videos: videos, needsLocation: false))
    }

    private let profiles = [
        profile("s", "Street Photography – Europe", members: 5000, remaining: 1),
        profile("a", "Athens Architecture", members: 300, videos: false),
        profile("m", "Mediterranean Light", members: 1200, moderated: true),
        profile("f", "Film Street", members: 80, admin: true),
    ]

    private func setUp(pools: [String: [String]] = [:]) async throws -> (GroupShareModel, OrganizeModel, FakeGroupDirectory, FakeOrganizeFlickr) {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryPhoto(id: "p1", title: "Tram"), LibraryPhoto(id: "p2", title: "Stoa"),
                        LibraryPhoto(id: "v1", title: "Waves", media: .video)], generation: 1)
        let flickr = FakeOrganizeFlickr(store: store)
        let organize = OrganizeModel(store: store, flickr: flickr, accountID: { "me" })
        organize.selectAll()
        organize.addSelectionToTray()
        let directory = FakeGroupDirectory(groups: profiles.map {
            AccountGroup(id: $0.id, name: $0.name, members: $0.members, photos: $0.poolCount, isAdmin: $0.isAdmin)
        }, profiles: profiles, pools: pools)
        let model = GroupShareModel(organize: organize, directory: directory, now: { Date(timeIntervalSince1970: 1_000_000) })
        await model.load()
        return (model, organize, directory, flickr)
    }

    @Test func searchMatchesTheStartOfEveryWordIgnoringCaseAndAccents() {
        #expect(GroupSearch.matches("Street Photography – Europe", query: "street photo"))
        #expect(GroupSearch.matches("Athens Architecture", query: "ARCH ath"))
        #expect(GroupSearch.matches("Café Society", query: "cafe"))
        #expect(!GroupSearch.matches("Streetwise", query: "wise"))
        #expect(GroupSearch.matches("Anything", query: "  "))
    }

    @Test func groupsAreSearchedFilteredAndSorted() async throws {
        let (model, _, _, _) = try await setUp()
        model.query = "street"
        #expect(model.visibleGroups.map(\.id) == ["f", "s"])
        model.sort = .members
        #expect(model.visibleGroups.map(\.id) == ["s", "f"])
        model.query = ""
        model.filters = [.admin]
        #expect(model.visibleGroups.map(\.id) == ["f"])
    }

    /// Rules are read once, for the groups that need them, and remembered.
    @Test func rulesAreReadForVisibleGroupsAndFilterOnThem() async throws {
        let (model, _, directory, _) = try await setUp()
        #expect(model.readCost == 4)
        await model.readRules()
        #expect(await directory.profileReads.sorted() == ["a", "f", "m", "s"])
        model.filters = [.acceptsVideos, .unmoderated]
        #expect(model.visibleGroups.map(\.id) == ["f", "s"])
        await model.readRules()
        #expect(await directory.profileReads.count == 4)
        #expect(model.readCost == 0)
    }

    @Test func choosingGroupsBuildsAPreviewPerGroup() async throws {
        let (model, _, _, _) = try await setUp()
        model.toggle("s")
        model.toggle("a")
        await model.preview()

        let plan = try #require(model.plan)
        #expect(plan.tally["s"] == GroupSharePlan.Tally(sending: 1, skipped: 2))
        #expect(plan.tally["a"] == GroupSharePlan.Tally(sending: 2, skipped: 1))
        #expect(model.summary == "3 shares to 2 groups · 3 calls")
    }

    @Test func spreadAndBestFitAreChoices() async throws {
        let (model, _, _, _) = try await setUp()
        ["a", "m", "f"].forEach(model.toggle)
        model.strategy = .spread
        await model.preview()
        #expect(model.plan?.assignments.count == 3)
        model.strategy = .bestFit
        model.groupsPerPhoto = 2
        await model.preview()
        #expect(model.plan?.assignments.count == 6)
    }

    @Test func photosAlreadyInAPoolAreCheckedWhenAsked() async throws {
        let (model, _, directory, _) = try await setUp(pools: ["p1": ["m"]])
        model.toggle("m")
        model.skipsPhotosAlreadyInPools = true
        await model.preview()
        #expect(await directory.poolReads.sorted() == ["p1", "p2", "v1"])
        #expect(model.plan?.skipped.map(\.reason) == [.alreadyInPool])
    }

    @Test func sharingRunsTheBatchAndReportsPerGroup() async throws {
        let (model, organize, _, flickr) = try await setUp()
        model.toggle("a")
        await model.preview()
        await model.share()

        #expect(await flickr.sent.map(\.method) == ["flickr.groups.pools.add", "flickr.groups.pools.add"])
        let batch = try #require(organize.activity.first)
        #expect(batch.batch.kind == .groups)
        #expect(try organize.store.groupShareReport(of: batch.batch.id).first?.added == 2)
    }

    @Test func groupSetsAreSavedAndChosenAgain() async throws {
        let (model, _, _, _) = try await setUp()
        model.toggle("s")
        model.toggle("f")
        model.saveSet(named: "Street")
        model.clearChosen()
        #expect(model.chosen.isEmpty)
        model.choose(set: try #require(model.sets.first))
        #expect(model.chosen == ["s", "f"])
    }

    @Test func theTrayCanBeTakenOutOfChosenPools() async throws {
        let (model, _, _, flickr) = try await setUp()
        model.toggle("m")
        await model.removeTrayFromChosen()
        #expect(await flickr.sent.map(\.method) == Array(repeating: "flickr.groups.pools.remove", count: 3))
    }
}

@MainActor
@Suite struct GroupFinderTests {

    private func model() async throws -> GroupShareModel {
        let profiles = [GroupShareModelTests.profile("a", "Alpha", members: 10, remaining: 0),
                        GroupShareModelTests.profile("b", "Beta", members: 30, remaining: 4),
                        GroupShareModelTests.profile("c", "Gamma", members: 20)]
        let store = try LibraryStore.inMemory()
        let organize = OrganizeModel(store: store, flickr: FakeOrganizeFlickr(store: store), accountID: { "me" })
        let directory = FakeGroupDirectory(groups: [
            AccountGroup(id: "a", name: "Alpha", members: 10, photos: 500, isAdmin: false),
            AccountGroup(id: "b", name: "Beta", members: 30, photos: 100, isAdmin: false),
            AccountGroup(id: "c", name: "Gamma", members: 20, photos: 900, isAdmin: false)], profiles: profiles)
        let model = GroupShareModel(organize: organize, directory: directory)
        await model.load()
        await model.readRules()
        return model
    }

    @Test func everySortOrdersAsLabelled() async throws {
        let model = try await model()
        model.sort = .poolSize
        #expect(model.visibleGroups.map(\.id) == ["c", "a", "b"])
        model.sort = .room
        #expect(model.visibleGroups.map(\.id) == ["c", "b", "a"])
        model.sort = .members
        #expect(model.visibleGroups.map(\.id) == ["b", "c", "a"])
    }

    @Test func hasRoomLeavesOutGroupsAtTheirLimit() async throws {
        let model = try await model()
        model.filters = [.hasRoom]
        #expect(model.visibleGroups.map(\.id) == ["b", "c"])
        model.chooseVisible()
        #expect(model.chosen == ["b", "c"])
        model.toggle("b")
        #expect(model.chosen == ["c"])
    }

    @Test func setsAreDeletedAndStaleIDsDropped() async throws {
        let model = try await model()
        model.toggle("a")
        model.saveSet(named: "  One  ")
        #expect(model.sets.map(\.name) == ["One"])
        try model.organize.store.saveGroupSet(named: "Old", groupIDs: ["gone", "c"])
        await model.load()
        model.choose(set: try #require(model.sets.first { $0.name == "Old" }))
        #expect(model.chosen == ["c"])
        model.deleteSet(named: "One")
        #expect(model.sets.map(\.name) == ["Old"])
        #expect(model.name(of: "c") == "Gamma")
    }

    @Test func signedOutSaysSo() async throws {
        let store = try LibraryStore.inMemory()
        let organize = OrganizeModel(store: store, flickr: FakeOrganizeFlickr(store: store), accountID: { nil })
        let model = GroupShareModel(organize: organize, directory: FakeGroupDirectory(groups: [], profiles: []))
        await model.load()
        #expect(model.problem == "Sign in to Flickr to share to your groups.")
    }
}

@MainActor
@Suite struct GroupRulesUnknownTests {
    /// A filter on rules not yet read cannot vouch for a group, so hides it;
    /// a failed read is said, and no preview is made from it.
    @Test func unreadRulesHideFromRuleFiltersAndAFailedReadIsReported() async throws {
        let store = try LibraryStore.inMemory()
        try store.save([LibraryPhoto(id: "p1")], generation: 1)
        let organize = OrganizeModel(store: store, flickr: FakeOrganizeFlickr(store: store), accountID: { "me" })
        organize.selectAll()
        organize.addSelectionToTray()
        let directory = FakeGroupDirectory(groups: [AccountGroup(id: "x", name: "X", members: 1, photos: 1, isAdmin: false)],
                                           profiles: [])
        let model = GroupShareModel(organize: organize, directory: directory)
        await model.load()
        model.filters = [.unmoderated]
        #expect(model.visibleGroups.isEmpty)
        model.filters = []
        model.toggle("x")
        await model.preview()
        #expect(model.plan == nil)
        #expect(model.problem == "Group not found")
    }
}
