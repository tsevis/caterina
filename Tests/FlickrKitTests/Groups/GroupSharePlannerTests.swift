import Foundation
import Testing

@testable import FlickrKit

/// Which photo goes to which group, decided before anything is sent.
@Suite struct GroupSharePlannerTests {

    private let photos = [SharePhoto(id: "p1", isVideo: false, hasLocation: true),
                          SharePhoto(id: "p2", isVideo: false, hasLocation: false),
                          SharePhoto(id: "p3", isVideo: true, hasLocation: true)]

    private func group(_ id: String, remaining: Int? = nil, videos: Bool = true, geo: Bool = false,
                       mode: GroupThrottle.Mode = .none) -> GroupProfile {
        GroupProfile(id: id, name: id, members: 10, poolCount: 10, isAdmin: false, isModerated: false,
                     isEighteenPlus: false,
                     throttle: GroupThrottle(mode: remaining == nil ? mode : .day, count: remaining, remaining: remaining),
                     restrictions: GroupRestrictions(photos: true, videos: videos, needsLocation: geo))
    }

    private func pairs(_ plan: GroupSharePlan) -> [String] { plan.assignments.map { "\($0.photoID)>\($0.groupID)" } }

    @Test func everyPhotoToEveryGroupObeysEachGroupsRules() {
        let plan = GroupSharePlanner.plan(photos: photos,
                                          groups: [group("open"), group("noVideo", videos: false), group("geo", geo: true)],
                                          options: .init(strategy: .everywhere))
        #expect(pairs(plan) == ["p1>open", "p2>open", "p3>open", "p1>noVideo", "p2>noVideo", "p1>geo", "p3>geo"])
        #expect(plan.skipped.map(\.reason) == [.videosNotAllowed, .needsLocation])
    }

    @Test func aGroupsRemainingQuotaAndTheCapLimitWhatItGets() {
        let plan = GroupSharePlanner.plan(photos: photos, groups: [group("two", remaining: 2), group("capped")],
                                          options: .init(strategy: .everywhere, capPerGroup: 1))
        #expect(pairs(plan) == ["p1>two", "p1>capped"])
        #expect(plan.tally["two"] == GroupSharePlan.Tally(sending: 1, skipped: 2))
        #expect(plan.skipped.filter { $0.groupID == "two" }.map(\.reason) == [.overCap, .overCap])

        let quota = GroupSharePlanner.plan(photos: photos, groups: [group("two", remaining: 2)],
                                           options: .init(strategy: .everywhere))
        #expect(quota.skipped.map(\.reason) == [.overGroupLimit])
    }

    @Test func aDisabledPoolGetsNothing() {
        let plan = GroupSharePlanner.plan(photos: photos, groups: [group("off", mode: .disabled)],
                                          options: .init(strategy: .everywhere))
        #expect(plan.assignments.isEmpty)
        #expect(Set(plan.skipped.map(\.reason)) == [.poolDisabled])
    }

    @Test func photosAlreadyInAPoolAreLeftOut() {
        let plan = GroupSharePlanner.plan(photos: photos, groups: [group("open")],
                                          pools: ["p2": ["open"]], options: .init(strategy: .everywhere))
        #expect(pairs(plan) == ["p1>open", "p3>open"])
        #expect(plan.skipped.map(\.reason) == [.alreadyInPool])
    }

    /// Spread: each photo to one group, dealt in turn, so no group is flooded.
    @Test func spreadDealsEachPhotoToOneGroupInTurn() {
        let many = (1...5).map { SharePhoto(id: "p\($0)", isVideo: false, hasLocation: false) }
        let plan = GroupSharePlanner.plan(photos: many, groups: [group("a"), group("b", remaining: 1), group("c")],
                                          options: .init(strategy: .spread))
        #expect(pairs(plan) == ["p1>a", "p2>b", "p3>c", "p4>a", "p5>c"])
    }

    /// Best fit: each photo to up to K groups, those with the most room first.
    @Test func bestFitSendsEachPhotoToTheGroupsWithMostRoom() {
        let two = [SharePhoto(id: "p1", isVideo: false, hasLocation: false),
                   SharePhoto(id: "p2", isVideo: false, hasLocation: false)]
        let plan = GroupSharePlanner.plan(photos: two,
                                          groups: [group("small", remaining: 1), group("big", remaining: 5), group("open")],
                                          options: .init(strategy: .bestFit(groupsPerPhoto: 2)))
        // "open" has no limit, so the most room; then "big".
        #expect(pairs(plan) == ["p1>open", "p1>big", "p2>open", "p2>big"])
    }

    @Test func thePlanCostsOneCallPerPairAndOnePerPoolRead() {
        let plan = GroupSharePlanner.plan(photos: photos, groups: [group("open")], options: .init(strategy: .everywhere))
        #expect(plan.calls == 3)
        #expect(GroupSharePlanner.readCalls(photos: 3, groups: 4, checkingPools: true) == 7)
        #expect(GroupSharePlanner.readCalls(photos: 3, groups: 4, checkingPools: false) == 4)
    }
}
