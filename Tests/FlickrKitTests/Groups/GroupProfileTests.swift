import Foundation
import Testing

@testable import FlickrKit

/// A group's rules for its pool, as `groups.getInfo` gives them.
@Suite struct GroupProfileTests {

    private func client(_ transport: ScriptedTransport) -> FlickrClient {
        FlickrClient(credentials: Fixtures.credentials, permission: .write, transport: transport,
                     budget: .unspaced, sleep: SleepRecorder().sleep)
    }

    @Test func throttleRestrictionsAndModerationAreRead() async throws {
        let transport = ScriptedTransport(always: """
        {"group":{"id":"34427465497@N01","ispoolmoderated":1,"eighteenplus":0,"name":{"_content":"GNE &amp; Friends"},
          "members":{"_content":"69"},"pool_count":{"_content":"1200"},
          "throttle":{"count":"10","mode":"month","remaining":3},
          "restrictions":{"photos_ok":1,"videos_ok":0,"images_ok":1,"screens_ok":1,"art_ok":1,"safe_ok":1,
                          "moderate_ok":0,"restricted_ok":0,"has_geo":1}},"stat":"ok"}
        """)

        let group = try await client(transport).groupProfile(id: "34427465497@N01", priority: .edit)

        #expect(group.name == "GNE & Friends")
        #expect(group.members == 69)
        #expect(group.poolCount == 1200)
        #expect(group.isModerated)
        #expect(group.throttle == GroupThrottle(mode: .month, count: 10, remaining: 3))
        #expect(group.restrictions.videos == false)
        #expect(group.restrictions.needsLocation)
        #expect(await transport.lastQueryItems["method"] == "flickr.groups.getInfo")
    }

    @Test func anUnthrottledGroupHasNoLimit() async throws {
        let transport = ScriptedTransport(always: #"{"group":{"id":"g","name":{"_content":"Open"},"throttle":{"mode":"none"}},"stat":"ok"}"#)
        let group = try await client(transport).groupProfile(id: "g", priority: .edit)
        #expect(group.throttle.available == nil)
        #expect(group.restrictions.photos && group.restrictions.videos)
        #expect(!group.restrictions.needsLocation)
    }

    @Test func aDisabledPoolTakesNothing() {
        #expect(GroupThrottle(mode: .disabled, count: nil, remaining: nil).available == 0)
        #expect(GroupThrottle(mode: .day, count: 5, remaining: 2).available == 2)
        #expect(GroupThrottle(mode: .day, count: 5, remaining: nil).available == 5)
    }

    @Test func thePoolsAPhotoIsInAreRead() async throws {
        let transport = ScriptedTransport(always: """
        {"set":[{"id":"72157","title":"Athens"}],"pool":[{"id":"1@N01","title":"FlickrCentral"},{"id":"2@N01","title":"Greece"}],"stat":"ok"}
        """)
        #expect(try await client(transport).poolIDs(photoID: "9", priority: .edit) == ["1@N01", "2@N01"])
        #expect(await transport.lastQueryItems["method"] == "flickr.photos.getAllContexts")
    }

    /// Every pool reply that is not a plain yes, in the words the report uses.
    @Test(arguments: [
        (3, GroupShareOutcome.alreadyInPool), (6, .pendingModeration), (7, .alreadyPending),
        (4, .refused(.photoInTooManyPools)), (5, .refused(.groupLimitReached)), (8, .refused(.contentNotAllowed)),
        (10, .refused(.poolFull)), (11, .refused(.poolDisabled)), (2, .refused(.groupNotFound)),
    ])
    func poolRepliesMapToOutcomes(code: Int, outcome: GroupShareOutcome) {
        #expect(GroupShareOutcome(addingFailedWith: .api(code: code, message: "x", transient: false)) == outcome)
    }

    /// Whether a refusal says anything about the rest of the batch.
    @Test func someRefusalsCloseAGroupOrAPhoto() {
        #expect(GroupShareOutcome.Refusal.groupLimitReached.closes == .group)
        #expect(GroupShareOutcome.Refusal.poolFull.closes == .group)
        #expect(GroupShareOutcome.Refusal.poolDisabled.closes == .group)
        #expect(GroupShareOutcome.Refusal.photoInTooManyPools.closes == .photo)
        #expect(GroupShareOutcome.Refusal.contentNotAllowed.closes == nil)
    }

    @Test func poolWritesAreRepeatable() {
        let add = GroupWrites.add(photoID: "1", groupID: "g")
        #expect(add.method == "flickr.groups.pools.add")
        #expect(add.arguments == ["photo_id": "1", "group_id": "g"])
        #expect(add.repeatable)
        #expect(GroupWrites.remove(photoID: "1", groupID: "g").method == "flickr.groups.pools.remove")
    }
}
