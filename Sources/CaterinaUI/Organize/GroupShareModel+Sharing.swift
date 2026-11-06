import Foundation

import CaterinaLibrary
import FlickrKit

extension GroupShareModel {

    /// Work out what goes where, reading what the plan needs first.
    public func preview() async {
        guard !chosen.isEmpty, !subjects.isEmpty else {
            setPlan(nil)
            return
        }
        clearProblem()
        let wanted = chosen
        guard await readProfiles(wanted), !Task.isCancelled else { return }
        if skipsPhotosAlreadyInPools { guard await readPools(), !Task.isCancelled else { return } }
        // The choice changed while reading: the newer preview will answer.
        guard wanted == chosen else { return }
        let groups = chosen.compactMap { profiles[$0] }
        guard groups.count == chosen.count else { return }
        let photos = subjects.map(\.photo)
        let options = GroupSharePlanner.Options(strategy: plannerStrategy, capPerGroup: capPerGroup)
        setPlan(GroupSharePlanner.plan(photos: photos, groups: groups,
                                       pools: skipsPhotosAlreadyInPools ? poolsRead : [:], options: options))
    }

    /// "12 additions to 4 groups · 12 calls".
    public var summary: String {
        guard let plan else { return "" }
        let groups = Set(plan.assignments.map(\.groupID)).count
        return "\(plan.assignments.count.formatted()) \(plan.assignments.count == 1 ? "addition" : "additions") to "
            + "\(groups.formatted()) \(groups == 1 ? "group" : "groups") · \(plan.calls.formatted()) calls"
    }

    /// The button: exactly what pressing it does.
    public var actionTitle: String {
        guard let plan, !plan.assignments.isEmpty else { return "Add to Groups" }
        let photos = Set(plan.assignments.map(\.photoID)).count
        let groups = Set(plan.assignments.map(\.groupID)).count
        return "Add \(photos.formatted()) \(photos == 1 ? "Photo" : "Photos") to "
            + "\(groups.formatted()) \(groups == 1 ? "Group" : "Groups")"
    }

    public func share() async {
        guard let plan, !plan.assignments.isEmpty else { return }
        let pairs = plan.assignments.map { GroupPair(photoID: $0.photoID, groupID: $0.groupID) }
        let groups = Set(pairs.map(\.groupID)).count
        await organize.runGroupBatch(title: "Add \(OrganizeModel.count(Set(pairs.map(\.photoID)).count)) "
                                        + "to \(groups) \(groups == 1 ? "group" : "groups")") { title, store, owner in
            try store.createGroupBatch(title: title, adding: pairs, accountID: owner)
        }
    }

    /// Every one of these photos out of every chosen pool; photos not there
    /// cost a call and are reported as not in the pool.
    public func removeFromChosen() async {
        let pairs = chosen.flatMap { group in subjects.map { GroupPair(photoID: $0.id, groupID: group) } }
        guard !pairs.isEmpty else { return }
        await organize.runGroupBatch(title: "Remove \(OrganizeModel.count(subjects.count)) from "
                                        + "\(chosen.count) \(chosen.count == 1 ? "group" : "groups")") { title, store, owner in
            try store.createGroupBatch(title: title, removing: pairs, accountID: owner)
        }
    }

    public func name(of groupID: String) -> String {
        profiles[groupID]?.name ?? groups.first { $0.id == groupID }?.name ?? groupID
    }

    private var plannerStrategy: GroupShareStrategy {
        switch strategy {
        case .everywhere: .everywhere
        case .spread: .spread
        case .bestFit: .bestFit(groupsPerPhoto: groupsPerPhoto)
        }
    }
}

extension OrganizeModel {

    /// Record a group batch with `make` and run it, as this account.
    func runGroupBatch(title: String,
                       _ make: (String, LibraryStore, String) throws -> EditBatch) async {
        guard let owner = accountID() else {
            problem = "Sign in to Flickr to share to your groups."
            return
        }
        guard !isBusy else {
            problem = busyMessage
            return
        }
        do {
            let batch = try make(title, store, owner)
            await runBatch(batch.id)
        } catch {
            problem = "Could not record the group batch: \(Self.message(error))"
        }
    }
}
