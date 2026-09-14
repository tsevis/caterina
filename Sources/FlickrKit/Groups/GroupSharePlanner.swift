import Foundation

/// A tray photo, with what group rules look at.
public struct SharePhoto: Sendable, Equatable, Hashable {
    public let id: String
    public let isVideo: Bool
    public let hasLocation: Bool

    public init(id: String, isVideo: Bool, hasLocation: Bool) {
        self.id = id
        self.isVideo = isVideo
        self.hasLocation = hasLocation
    }
}

/// Which photo goes to which group, and why the rest do not.
public struct GroupSharePlan: Sendable, Equatable {
    public struct Assignment: Sendable, Equatable, Hashable {
        public let photoID: String
        public let groupID: String
    }

    public struct Skip: Sendable, Equatable, Hashable {
        public let photoID: String
        /// Empty when no group had room for the photo.
        public let groupID: String
        public let reason: SkipReason
    }

    public enum SkipReason: String, Sendable, Equatable, Hashable {
        case videosNotAllowed, photosNotAllowed, needsLocation, alreadyInPool
        case overGroupLimit, overCap, poolDisabled, noGroupWithRoom

        public var explanation: String {
            switch self {
            case .videosNotAllowed: "No videos in this group"
            case .photosNotAllowed: "No photos in this group, only videos"
            case .needsLocation: "This group wants photos with a location"
            case .alreadyInPool: "Already in the group"
            case .overGroupLimit: "Over the group's limit for now"
            case .overCap: "Over the most you chose per group"
            case .poolDisabled: "The group's pool is closed"
            case .noGroupWithRoom: "No chosen group had room"
            }
        }
    }

    public struct Tally: Sendable, Equatable {
        public let sending: Int
        public let skipped: Int
    }

    public let assignments: [Assignment]
    public let skipped: [Skip]

    /// Per group id.
    public var tally: [String: Tally] {
        let groups = Set(assignments.map(\.groupID) + skipped.map(\.groupID).filter { !$0.isEmpty })
        return Dictionary(uniqueKeysWithValues: groups.map { id in
            (id, Tally(sending: assignments.count { $0.groupID == id }, skipped: skipped.count { $0.groupID == id }))
        })
    }

    /// One `pools.add` per assignment.
    public var calls: Int { assignments.count }
}

public enum GroupShareStrategy: Sendable, Equatable, Hashable {
    /// Every photo to every chosen group, as far as each group allows.
    case everywhere
    /// Each photo to one group, dealt in turn.
    case spread
    /// Each photo to up to this many groups, those with the most room first.
    case bestFit(groupsPerPhoto: Int)
}

public enum GroupSharePlanner {

    public struct Options: Sendable, Equatable {
        public let strategy: GroupShareStrategy
        /// At most this many photos to any one group.
        public let capPerGroup: Int?

        public init(strategy: GroupShareStrategy, capPerGroup: Int? = nil) {
            self.strategy = strategy
            self.capPerGroup = capPerGroup
        }
    }

    /// Reading each group's rules, and each photo's pools when asked.
    public static func readCalls(photos: Int, groups: Int, checkingPools: Bool) -> Int {
        groups + (checkingPools ? photos : 0)
    }

    /// `pools`: the groups each photo is already in, when read.
    public static func plan(photos: [SharePhoto], groups: [GroupProfile], pools: [String: Set<String>] = [:],
                            options: Options) -> GroupSharePlan {
        var ledger = Ledger(groups: groups, cap: options.capPerGroup)
        var assignments: [GroupSharePlan.Assignment] = []
        var skipped: [GroupSharePlan.Skip] = []
        let fits = { (photo: SharePhoto, group: GroupProfile) -> GroupSharePlan.SkipReason? in
            rule(photo, group, pools[photo.id] ?? [])
        }
        switch options.strategy {
        case .everywhere:
            for group in groups {
                for photo in photos {
                    if let reason = fits(photo, group) ?? ledger.refusal(group.id) {
                        skipped.append(.init(photoID: photo.id, groupID: group.id, reason: reason))
                    } else {
                        ledger.take(group.id)
                        assignments.append(.init(photoID: photo.id, groupID: group.id))
                    }
                }
            }
        case .spread:
            (assignments, skipped) = spread(photos, groups, &ledger, fits)
        case let .bestFit(perPhoto):
            (assignments, skipped) = bestFit(photos, groups, max(1, perPhoto), &ledger, fits)
        }
        return GroupSharePlan(assignments: assignments, skipped: skipped)
    }

    private typealias Fits = (SharePhoto, GroupProfile) -> GroupSharePlan.SkipReason?

    private static func spread(_ photos: [SharePhoto], _ groups: [GroupProfile], _ ledger: inout Ledger,
                               _ fits: Fits) -> ([GroupSharePlan.Assignment], [GroupSharePlan.Skip]) {
        var assignments: [GroupSharePlan.Assignment] = []
        var skipped: [GroupSharePlan.Skip] = []
        var next = 0
        for photo in photos {
            let turn = groups.indices.map { groups[(next + $0) % groups.count] }
            guard let index = turn.firstIndex(where: { fits(photo, $0) == nil && ledger.refusal($0.id) == nil }) else {
                skipped.append(.init(photoID: photo.id, groupID: "", reason: .noGroupWithRoom))
                continue
            }
            let group = turn[index]
            ledger.take(group.id)
            assignments.append(.init(photoID: photo.id, groupID: group.id))
            next = (next + index + 1) % groups.count
        }
        return (assignments, skipped)
    }

    private static func bestFit(_ photos: [SharePhoto], _ groups: [GroupProfile], _ perPhoto: Int,
                                _ ledger: inout Ledger, _ fits: Fits) -> ([GroupSharePlan.Assignment], [GroupSharePlan.Skip]) {
        var assignments: [GroupSharePlan.Assignment] = []
        var skipped: [GroupSharePlan.Skip] = []
        for photo in photos {
            let open = groups.filter { fits(photo, $0) == nil && ledger.refusal($0.id) == nil }
            let current = ledger
            let room = { (group: GroupProfile) in current.room(group.id) }
            // Most room first; the order chosen breaks ties.
            let chosen = open.enumerated()
                .sorted { room($0.element) != room($1.element) ? room($0.element) > room($1.element) : $0.offset < $1.offset }
                .prefix(perPhoto).map(\.element)
            guard !chosen.isEmpty else {
                skipped.append(.init(photoID: photo.id, groupID: "", reason: .noGroupWithRoom))
                continue
            }
            for group in chosen {
                ledger.take(group.id)
                assignments.append(.init(photoID: photo.id, groupID: group.id))
            }
        }
        return (assignments, skipped)
    }

    private static func rule(_ photo: SharePhoto, _ group: GroupProfile,
                             _ pools: Set<String>) -> GroupSharePlan.SkipReason? {
        if group.throttle.mode == .disabled { return .poolDisabled }
        if photo.isVideo && !group.restrictions.videos { return .videosNotAllowed }
        if !photo.isVideo && !group.restrictions.photos { return .photosNotAllowed }
        if group.restrictions.needsLocation && !photo.hasLocation { return .needsLocation }
        if pools.contains(group.id) { return .alreadyInPool }
        return nil
    }

    /// What each group can still take in this plan.
    private struct Ledger {
        private var used: [String: Int] = [:]
        private let limits: [String: Int?]
        private let cap: Int?

        init(groups: [GroupProfile], cap: Int?) {
            limits = Dictionary(groups.map { ($0.id, $0.throttle.available) }, uniquingKeysWith: { first, _ in first })
            self.cap = cap
        }

        func refusal(_ id: String) -> GroupSharePlan.SkipReason? {
            let count = used[id] ?? 0
            // Whichever binds first is the reason given.
            if let limit = limits[id] ?? nil, count >= limit, limit <= (cap ?? .max) { return .overGroupLimit }
            if let cap, count >= cap { return .overCap }
            return nil
        }

        /// Room left; no limit counts as the most.
        func room(_ id: String) -> Int {
            let limit = min(limits[id].flatMap { $0 } ?? .max, cap ?? .max)
            return limit == .max ? .max : limit - (used[id] ?? 0)
        }

        mutating func take(_ id: String) { used[id, default: 0] += 1 }
    }
}
