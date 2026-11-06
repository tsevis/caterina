import Foundation
import Observation

import CaterinaLibrary
import FlickrKit

/// Where your groups and their rules come from. `FlickrClient` in the app.
public protocol GroupDirectory: Sendable {
    func groups(of userID: String) async throws -> [AccountGroup]
    func groupProfile(id: String, priority: CallPriority) async throws -> GroupProfile
    func poolIDs(photoID: String, priority: CallPriority) async throws -> [String]
}

extension FlickrClient: GroupDirectory {}

/// Sending the tray to groups: finding them, choosing how, and the preview.
@MainActor
@Observable
public final class GroupShareModel {

    public enum Filter: String, CaseIterable, Identifiable, Sendable {
        case hasRoom, acceptsVideos, unmoderated, admin
        public var id: String { rawValue }
        public var help: String {
            switch self {
            case .hasRoom: "Groups with room left for you now"
            case .acceptsVideos: "Groups that take videos"
            case .unmoderated: "Groups where photos appear without a moderator"
            case .admin: "Groups you run"
            }
        }
        public var title: String {
            switch self {
            case .hasRoom: "Room"
            case .acceptsVideos: "Videos"
            case .unmoderated: "Unmoderated"
            case .admin: "Yours"
            }
        }
    }

    public enum Sort: String, CaseIterable, Identifiable, Sendable {
        case recent, name, members, poolSize, room
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .recent: "Recently used"
            case .name: "Name"
            case .members: "Members"
            case .poolSize: "Pool size"
            case .room: "Room left"
            }
        }
    }

    public enum Strategy: String, CaseIterable, Identifiable, Sendable {
        case everywhere, spread, bestFit
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .everywhere: "Every photo to every group"
            case .spread: "Spread: one group per photo"
            case .bestFit: "Best fit: a few groups per photo"
            }
        }
        public var explanation: String {
            switch self {
            case .everywhere: "As far as each group's limit and rules allow."
            case .spread: "Photos are dealt out in turn, so no group gets them all."
            case .bestFit: "Each photo goes to the groups with the most room left."
            }
        }
    }

    /// Throttles count down as people post, so rules are read again after this.
    nonisolated static let rulesLifetime: TimeInterval = 3600
    nonisolated static let recentGroupsKept = 12
    /// `groups.getInfo`'s "Group not found": about that group, not the account.
    nonisolated static let groupNotFound = 1

    public private(set) var groups: [AccountGroup] = []
    public private(set) var profiles: [String: GroupProfile] = [:]
    public private(set) var sets: [GroupSet] = []
    public var query = ""
    public var filters: Set<Filter> = []
    public var sort = Sort.recent
    /// In the order chosen: spread deals in this order.
    public private(set) var chosen: [String] = []
    // Only a real change drops the plan: the views start a new preview when a
    // value changes, so setting the same one would leave no plan and none coming.
    public var strategy = Strategy.everywhere { didSet { if strategy != oldValue { plan = nil } } }
    public var groupsPerPhoto = 3 { didSet { if groupsPerPhoto != oldValue { plan = nil } } }
    public var capPerGroup: Int? { didSet { if capPerGroup != oldValue { plan = nil } } }
    public var skipsPhotosAlreadyInPools = false { didSet { if skipsPhotosAlreadyInPools != oldValue { plan = nil } } }
    public private(set) var plan: GroupSharePlan?
    public private(set) var isWorking = false
    /// Rules still being read behind the sheet; nothing waits for them.
    public private(set) var rulesLeftToRead = 0
    public private(set) var problem: String?

    let organize: OrganizeModel
    /// The photos this sheet was opened with. Fixed: what you saw is what goes.
    public let subjects: [ShareSubject]
    private var recentIDs: [String] = []
    private let directory: GroupDirectory
    private let now: @Sendable () -> Date
    private var pools: [String: Set<String>] = [:]
    private var previewTask: Task<Void, Never>?

    public init(organize: OrganizeModel, directory: GroupDirectory, subjects: [ShareSubject]? = nil,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.organize = organize
        self.subjects = subjects ?? organize.trayPhotos.map { ShareSubject($0) }
        self.directory = directory
        self.now = now
    }

    public func load() async {
        guard let owner = organize.accountID() else {
            problem = "Sign in to Flickr to share to your groups."
            return
        }
        await working {
            groups = try await directory.groups(of: owner)
            let fresh = try organize.store.groupProfiles(ids: groups.map(\.id), freshAfter: now().addingTimeInterval(-Self.rulesLifetime))
            profiles = Dictionary(uniqueKeysWithValues: fresh.map { ($0.id, $0) })
            sets = try organize.store.groupSets()
            recentIDs = try organize.store.recentGroupIDs(accountID: owner, limit: Self.recentGroupsKept)
        }
    }

    /// Read every group's rules behind the sheet, in list order, so that nobody
    /// has to ask for them. A reply about one group skips that group: its row
    /// stays unknown, and choosing it reports the reason through the preview.
    /// Anything else would fail for every group, so it stops and says why.
    public func readRulesQuietly() async {
        let missing = groups.sorted(by: order).map(\.id).filter { profiles[$0] == nil }
        rulesLeftToRead = missing.count
        defer { rulesLeftToRead = 0 }
        for id in missing {
            guard !Task.isCancelled else { return }
            defer { rulesLeftToRead -= 1 }
            guard profiles[id] == nil else { continue }
            do {
                let profile = try await directory.groupProfile(id: id, priority: .background)
                try organize.store.saveGroupProfiles([profile], readAt: now())
                profiles[id] = profile
            } catch FlickrError.api(code: Self.groupNotFound, _, _), FlickrError.malformedResponse {
                continue
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled { problem = "Could not check your groups' limits: \(OrganizeModel.message(error))" }
                return
            }
        }
    }

    // MARK: - Finding

    public var visibleGroups: [AccountGroup] {
        groups.filter { GroupSearch.matches($0.name, query: query) && passesFilters($0) }.sorted(by: order)
    }

    /// Calls to read the rules of the visible groups not yet known.
    public var readCost: Int { visibleGroups.count { profiles[$0.id] == nil } }

    private func passesFilters(_ group: AccountGroup) -> Bool {
        filters.allSatisfy { filter in
            if filter == .admin { return group.isAdmin }
            guard let profile = profiles[group.id] else { return false }
            switch filter {
            case .hasRoom: return profile.throttle.available.map { $0 > 0 } ?? true
            case .acceptsVideos: return profile.restrictions.videos
            case .unmoderated: return !profile.isModerated
            case .admin: return group.isAdmin
            }
        }
    }

    private func order(_ lhs: AccountGroup, _ rhs: AccountGroup) -> Bool {
        let byName = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        switch sort {
        case .recent:
            let rank = { (group: AccountGroup) in self.recentIDs.firstIndex(of: group.id) ?? .max }
            return rank(lhs) != rank(rhs) ? rank(lhs) < rank(rhs) : byName
        case .name: return byName
        case .members: return lhs.members != rhs.members ? lhs.members > rhs.members : byName
        case .poolSize: return lhs.photos != rhs.photos ? lhs.photos > rhs.photos : byName
        case .room:
            let room = { (group: AccountGroup) in self.profiles[group.id]?.throttle.available ?? .max }
            return room(lhs) != room(rhs) ? room(lhs) > room(rhs) : byName
        }
    }

    // MARK: - Choosing

    public func toggle(_ groupID: String) {
        chosen = chosen.contains(groupID) ? chosen.filter { $0 != groupID } : chosen + [groupID]
        plan = nil
    }

    public func chooseVisible() {
        setChosen(chosen + visibleGroups.map(\.id).filter { !chosen.contains($0) })
    }

    public func clearChosen() {
        setChosen([])
    }

    public func choose(set: GroupSet) {
        let known = Set(groups.map(\.id))
        setChosen(set.groupIDs.filter(known.contains))
    }

    private func setChosen(_ next: [String]) {
        guard next != chosen else { return }
        chosen = next
        plan = nil
    }

    public func saveSet(named name: String) {
        guard !name.trimmed.isEmpty, !chosen.isEmpty else { return }
        do {
            try organize.store.saveGroupSet(named: name.trimmed, groupIDs: chosen)
            sets = try organize.store.groupSets()
        } catch {
            problem = "Could not save the group set: \(OrganizeModel.message(error))"
        }
    }

    public func deleteSet(named name: String) {
        do {
            try organize.store.deleteGroupSet(named: name)
            sets = try organize.store.groupSets()
        } catch {
            problem = "Could not delete the group set: \(OrganizeModel.message(error))"
        }
    }

    @discardableResult
    func readProfiles(_ ids: [String]) async -> Bool {
        let missing = ids.filter { profiles[$0] == nil }
        guard !missing.isEmpty else { return true }
        return await working {
            var read: [GroupProfile] = []
            for id in missing {
                try Task.checkCancellation()
                read.append(try await directory.groupProfile(id: id, priority: .interactive))
            }
            try organize.store.saveGroupProfiles(read, readAt: now())
            profiles.merge(read.map { ($0.id, $0) }) { $1 }
        }
    }

    func readPools() async -> Bool {
        let missing = subjects.map(\.id).filter { pools[$0] == nil }
        return await working {
            for id in missing {
                try Task.checkCancellation()
                pools[id] = Set(try await directory.poolIDs(photoID: id, priority: .interactive))
            }
        }
    }

    /// Runs `body`, reporting a failure. Returns whether it succeeded, so a
    /// following step does not run on a failed read.
    @discardableResult
    func working(_ body: () async throws -> Void) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            try await body()
            return true
        } catch is CancellationError {
            return false
        } catch {
            problem = OrganizeModel.message(error)
            return false
        }
    }

    func clearProblem() { problem = nil }

    public func isRecent(_ groupID: String) -> Bool { recentIDs.contains(groupID) }

    /// One preview at a time: a newer choice cancels the one before.
    public func schedulePreview() {
        previewTask?.cancel()
        previewTask = Task { await preview() }
    }

    func setPlan(_ plan: GroupSharePlan?) { self.plan = plan }
    var poolsRead: [String: Set<String>] { pools }
}
