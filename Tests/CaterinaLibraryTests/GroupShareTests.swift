import Foundation
import Testing

import FlickrKit
@testable import CaterinaLibrary

/// Group pools on Flickr, in memory, with limits and moderation.
actor FakePools: GroupPoolWriter {
    var pools: [String: [String]]
    var pending: [String: [String]] = [:]
    let limits: [String: Int]
    let moderated: Set<String>
    let refusing: [String: Int]
    private(set) var sent: [String] = []
    var offlineAfter: Int?

    init(pools: [String: [String]] = [:], limits: [String: Int] = [:], moderated: Set<String> = [],
         refusing: [String: Int] = [:]) {
        self.pools = pools
        self.limits = limits
        self.moderated = moderated
        self.refusing = refusing
    }

    func goOffline(after calls: Int) { offlineAfter = calls }

    func perform(_ write: FlickrWrite, priority: CallPriority) async throws -> Data {
        if let offlineAfter, sent.count >= offlineAfter { throw FlickrError.transport("offline") }
        let (photo, group) = (write.arguments["photo_id"] ?? "", write.arguments["group_id"] ?? "")
        sent.append("\(write.method == "flickr.groups.pools.add" ? "+" : "-")\(photo)>\(group)")
        let fail = { (code: Int) in FlickrError.api(code: code, message: "code \(code)", transient: false) }
        if write.method == "flickr.groups.pools.remove" {
            if pools[group]?.contains(photo) == true { pools[group]?.removeAll { $0 == photo } }
            else if pending[group]?.contains(photo) == true { pending[group]?.removeAll { $0 == photo } }
            else { throw fail(2) }
            return Data()
        }
        if let code = refusing["\(photo)>\(group)"] { throw fail(code) }
        if pools[group, default: []].contains(photo) { throw fail(3) }
        if let limit = limits[group], pools[group, default: []].count + pending[group, default: []].count >= limit { throw fail(5) }
        if moderated.contains(group) {
            pending[group, default: []].append(photo)
            throw fail(6)
        }
        pools[group, default: []].append(photo)
        return Data()
    }
}

@Suite struct GroupShareTests {

    private func pairs(_ list: [String]) -> [GroupPair] {
        list.map { let p = $0.split(separator: ">"); return GroupPair(photoID: String(p[0]), groupID: String(p[1])) }
    }

    @Test func eachPairIsSentAndItsOutcomeKept() async throws {
        let store = try LibraryStore.inMemory()
        let flickr = FakePools(pools: ["g1": ["p2"]], moderated: ["mod"],
                               refusing: ["p1>strict": 8])
        let batch = try store.createGroupBatch(title: "Share", adding: pairs(["p1>g1", "p2>g1", "p1>mod", "p1>strict"]),
                                               accountID: "me")

        try await GroupShareRunner(flickr: flickr, store: store).run(batch.id)

        let outcomes = try store.groupEntries(in: batch.id).map(\.outcome)
        #expect(outcomes == [.added, .alreadyInPool, .pendingModeration, .refused(.contentNotAllowed)])
        #expect(try store.summary(of: batch.id) == EditBatch.Summary(applied: 3, failed: 1, pending: 0))
    }

    /// A group that says "limit reached" gets nothing more from this batch;
    /// the rest is marked skipped without a call each.
    @Test func aGroupAtItsLimitIsClosedForTheRestOfTheBatch() async throws {
        let store = try LibraryStore.inMemory()
        let flickr = FakePools(limits: ["tight": 1])
        let batch = try store.createGroupBatch(title: "Share", adding: pairs(["p1>tight", "p2>tight", "p3>tight", "p2>open"]),
                                               accountID: "me")
        try await GroupShareRunner(flickr: flickr, store: store).run(batch.id)

        #expect(await flickr.sent == ["+p1>tight", "+p2>tight", "+p2>open"])
        #expect(try store.groupEntries(in: batch.id).map(\.outcome)
                == [.added, .refused(.groupLimitReached), .skipped(.groupLimitReached), .added])
    }

    @Test func aPhotoInTooManyPoolsIsNotOfferedToTheRest() async throws {
        let store = try LibraryStore.inMemory()
        let flickr = FakePools(refusing: ["p1>a": 4])
        let batch = try store.createGroupBatch(title: "Share", adding: pairs(["p1>a", "p1>b", "p2>b"]), accountID: "me")
        try await GroupShareRunner(flickr: flickr, store: store).run(batch.id)
        #expect(try store.groupEntries(in: batch.id).map(\.outcome)
                == [.refused(.photoInTooManyPools), .skipped(.photoInTooManyPools), .added])
    }

    @Test func offlineStopsTheBatchAndItResumes() async throws {
        let store = try LibraryStore.inMemory()
        let flickr = FakePools()
        await flickr.goOffline(after: 1)
        let batch = try store.createGroupBatch(title: "Share", adding: pairs(["p1>a", "p2>a"]), accountID: "me")
        await #expect(throws: FlickrError.self) { try await GroupShareRunner(flickr: flickr, store: store).run(batch.id) }
        #expect(try store.summary(of: batch.id).pending == 1)
    }

    /// Undo takes out only what this batch put in, queue included; a photo
    /// that was already in the pool stays.
    @Test func undoRemovesOnlyWhatThisBatchPlaced() async throws {
        let store = try LibraryStore.inMemory()
        let flickr = FakePools(pools: ["g1": ["p2"]], moderated: ["mod"])
        let batch = try store.createGroupBatch(title: "Share", adding: pairs(["p1>g1", "p2>g1", "p1>mod"]), accountID: "me")
        try await GroupShareRunner(flickr: flickr, store: store).run(batch.id)

        let undo = try store.undoBatch(for: batch.id)
        try await GroupShareRunner(flickr: flickr, store: store).run(undo.id)

        #expect(await flickr.pools["g1"] == ["p2"])
        #expect(await flickr.pending["mod"] == [])
        #expect(try store.groupEntries(in: undo.id).map(\.outcome) == [.removed, .removed])
    }

    @Test func removingFromPoolsIsUndoneByAddingBack() async throws {
        let store = try LibraryStore.inMemory()
        let flickr = FakePools(pools: ["g1": ["p1", "p2"]])
        let batch = try store.createGroupBatch(title: "Remove", removing: pairs(["p1>g1", "p9>g1"]), accountID: "me")
        try await GroupShareRunner(flickr: flickr, store: store).run(batch.id)
        #expect(try store.groupEntries(in: batch.id).map(\.outcome) == [.removed, .notInPool])

        try await GroupShareRunner(flickr: flickr, store: store).run(try store.undoBatch(for: batch.id).id)
        #expect(await flickr.pools["g1"] == ["p2", "p1"])
    }

    @Test func theReportCountsEachGroupsOutcomes() async throws {
        let store = try LibraryStore.inMemory()
        let flickr = FakePools(limits: ["tight": 1], moderated: ["mod"])
        let batch = try store.createGroupBatch(title: "Share", adding: pairs(["p1>tight", "p2>tight", "p1>mod"]),
                                               accountID: "me")
        try await GroupShareRunner(flickr: flickr, store: store).run(batch.id)

        let report = try store.groupShareReport(of: batch.id)
        #expect(report.first { $0.groupID == "tight" }
                == GroupShareReport.Row(groupID: "tight", added: 1, waiting: 0, already: 0,
                                        refused: [.groupLimitReached: 1], pending: 0))
        #expect(report.first { $0.groupID == "mod" }?.waiting == 1)
    }

    @Test func groupSetsAreSavedByName() throws {
        let store = try LibraryStore.inMemory()
        try store.saveGroupSet(named: "Street", groupIDs: ["a", "b"])
        try store.saveGroupSet(named: "Street", groupIDs: ["b", "c"])
        try store.saveGroupSet(named: "Architecture", groupIDs: ["d"])
        #expect(try store.groupSets() == [GroupSet(name: "Architecture", groupIDs: ["d"]),
                                          GroupSet(name: "Street", groupIDs: ["b", "c"])])
        try store.deleteGroupSet(named: "Street")
        #expect(try store.groupSets().map(\.name) == ["Architecture"])
    }

    @Test func groupRulesAreKeptForADay() throws {
        let store = try LibraryStore.inMemory()
        let profile = GroupProfile(id: "g", name: "G", members: 1, poolCount: 1, isAdmin: false, isModerated: false,
                                   isEighteenPlus: false, throttle: .init(mode: .day, count: 5, remaining: 2),
                                   restrictions: .none)
        let now = Date(timeIntervalSince1970: 1_000_000)
        try store.saveGroupProfiles([profile], readAt: now)
        #expect(try store.groupProfiles(ids: ["g"], freshAfter: now.addingTimeInterval(-3600)) == [profile])
        #expect(try store.groupProfiles(ids: ["g"], freshAfter: now.addingTimeInterval(1)).isEmpty)
    }
}

/// Found in review.
@Suite struct GroupShareSafetyTests {

    /// Flickr took the photo but the reply was lost; on resume it says
    /// "already in pool". That was this batch, so undo takes it out.
    @Test func aPairSentBeforeAnInterruptionCountsAsPlacedByTheBatch() async throws {
        let store = try LibraryStore.inMemory()
        let flickr = FakePools(pools: ["g": ["p1"]])
        let batch = try store.createGroupBatch(title: "Share", adding: [GroupPair(photoID: "p1", groupID: "g")],
                                               accountID: "me")
        try store.markSending(try #require(try store.groupEntries(in: batch.id).first))

        try await GroupShareRunner(flickr: flickr, store: store).run(batch.id)

        #expect(try store.groupEntries(in: batch.id).first?.outcome == .added)
    }

    /// Pool writes are not retried by the client: a retry's "already in
    /// pool" would hide that this batch put the photo there.
    @Test func poolWritesAreNotRetriedInsideOneCall() {
        #expect(!GroupWrites.add(photoID: "1", groupID: "g").repeatable)
        #expect(!GroupWrites.remove(photoID: "1", groupID: "g").repeatable)
    }

    /// A daily limit may have reset by the time a batch is resumed; only
    /// refusals that do not pass carry over.
    @Test func aLimitReachedYesterdayDoesNotCloseTheGroupToday() async throws {
        let store = try LibraryStore.inMemory()
        let tight = FakePools(limits: ["g": 1])
        await tight.goOffline(after: 2)
        let batch = try store.createGroupBatch(title: "Share", adding: [
            GroupPair(photoID: "p1", groupID: "g"), GroupPair(photoID: "p2", groupID: "g"),
            GroupPair(photoID: "p3", groupID: "h")], accountID: "me")
        await #expect(throws: FlickrError.self) { try await GroupShareRunner(flickr: tight, store: store).run(batch.id) }

        let entries = try store.groupEntries(in: batch.id)
        #expect(entries.map(\.outcome) == [.added, .refused(.groupLimitReached), nil])
        #expect(!GroupShareRunner.carriesOver(.groupLimitReached))
        #expect(GroupShareRunner.carriesOver(.poolDisabled))
    }

    @Test func usedRulesAreForgottenAfterSharing() throws {
        let store = try LibraryStore.inMemory()
        let profile = GroupProfile(id: "g", name: "G", members: 1, poolCount: 1, isAdmin: false, isModerated: false,
                                   isEighteenPlus: false, throttle: .init(mode: .day, count: 5, remaining: 2),
                                   restrictions: .none)
        try store.saveGroupProfiles([profile], readAt: Date())
        try store.forgetGroupProfiles(["g"])
        #expect(try store.groupProfiles(ids: ["g"], freshAfter: Date(timeIntervalSince1970: 0)).isEmpty)
    }
}
