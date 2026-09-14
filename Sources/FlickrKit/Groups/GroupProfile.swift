import Foundation

/// How many photos a group takes from each member, and how often.
public struct GroupThrottle: Sendable, Equatable, Hashable, Codable {
    public enum Mode: String, Sendable, Codable {
        case none, day, week, month, ever, disabled
        /// A mode this build does not know: its count is taken as the limit.
        case unknown
    }

    public let mode: Mode
    public let count: Int?
    /// What is left in the current period, as Flickr counts it for you.
    public let remaining: Int?

    public init(mode: Mode, count: Int?, remaining: Int?) {
        self.mode = mode
        self.count = count
        self.remaining = remaining
    }

    /// Photos the group will take now; nil for no limit.
    public var available: Int? {
        switch mode {
        case .none: nil
        case .disabled: 0
        case .unknown: remaining ?? count ?? 0
        default: remaining ?? count
        }
    }
}

/// What a group's pool accepts. Safety level and content type are also
/// restricted by some groups, but a photo's own values are not known here,
/// so Flickr decides those when the photo is sent.
public struct GroupRestrictions: Sendable, Equatable, Hashable, Codable {
    public let photos: Bool
    public let videos: Bool
    public let needsLocation: Bool

    public init(photos: Bool, videos: Bool, needsLocation: Bool) {
        self.photos = photos
        self.videos = videos
        self.needsLocation = needsLocation
    }

    public static let none = GroupRestrictions(photos: true, videos: true, needsLocation: false)
}

/// A group, with what matters before sending photos to its pool.
public struct GroupProfile: Sendable, Equatable, Hashable, Identifiable, Codable {
    public let id: String
    public let name: String
    public let members: Int
    public let poolCount: Int
    public let isAdmin: Bool
    /// New photos wait for a moderator.
    public let isModerated: Bool
    public let isEighteenPlus: Bool
    public let throttle: GroupThrottle
    public let restrictions: GroupRestrictions

    public init(id: String, name: String, members: Int, poolCount: Int, isAdmin: Bool, isModerated: Bool,
                isEighteenPlus: Bool, throttle: GroupThrottle, restrictions: GroupRestrictions) {
        self.id = id
        self.name = name
        self.members = members
        self.poolCount = poolCount
        self.isAdmin = isAdmin
        self.isModerated = isModerated
        self.isEighteenPlus = isEighteenPlus
        self.throttle = throttle
        self.restrictions = restrictions
    }
}

/// The writes that put photos in pools and take them out.
public enum GroupWrites {
    /// Not retried inside one call: a retry's "already in pool" would hide
    /// that this call put it there. A lost reply stops the batch; the runner's
    /// sending marker settles it on resume.
    public static func add(photoID: String, groupID: String) -> FlickrWrite {
        FlickrWrite(method: "flickr.groups.pools.add", arguments: ["photo_id": photoID, "group_id": groupID],
                    repeatable: false)
    }

    /// Not retried inside one call, for the same reason as `add`.
    public static func remove(photoID: String, groupID: String) -> FlickrWrite {
        FlickrWrite(method: "flickr.groups.pools.remove", arguments: ["photo_id": photoID, "group_id": groupID],
                    repeatable: false)
    }
}

/// What happened to one photo sent to one pool.
public enum GroupShareOutcome: Sendable, Equatable, Hashable, Codable {
    case added
    case alreadyInPool
    /// A moderated pool: in the queue, not the pool.
    case pendingModeration
    case alreadyPending
    case refused(Refusal)
    /// Not sent: the group or the photo was closed by an earlier refusal.
    case skipped(Refusal)
    /// Taken out of the pool (or its queue).
    case removed
    case notInPool

    public enum Refusal: String, Sendable, Equatable, Hashable, Codable {
        case photoNotFound, groupNotFound, photoInTooManyPools, groupLimitReached, contentNotAllowed
        case poolFull, poolDisabled, other

        public enum Scope: Sendable, Equatable { case group, photo }

        /// Whether this ends sending to the whole group, or of this photo.
        public var closes: Scope? {
            switch self {
            case .groupLimitReached, .poolFull, .poolDisabled, .groupNotFound: .group
            case .photoInTooManyPools, .photoNotFound: .photo
            case .contentNotAllowed, .other: nil
            }
        }

        public var explanation: String {
            switch self {
            case .photoNotFound: "Flickr could not find the photo."
            case .groupNotFound: "Flickr could not find the group."
            case .photoInTooManyPools: "The photo is in as many groups as Flickr allows."
            case .groupLimitReached: "You have reached this group's limit for now."
            case .contentNotAllowed: "The group does not accept this kind of photo."
            case .poolFull: "The group's pool is full."
            case .poolDisabled: "The group's pool is closed."
            case .other: "Flickr refused it."
            }
        }
    }

    public init(addingFailedWith error: FlickrError) {
        guard case let .api(code, _, _) = error else {
            self = .refused(.other)
            return
        }
        switch code {
        case 1: self = .refused(.photoNotFound)
        case 2: self = .refused(.groupNotFound)
        case 3: self = .alreadyInPool
        case 4: self = .refused(.photoInTooManyPools)
        case 5: self = .refused(.groupLimitReached)
        case 6: self = .pendingModeration
        case 7: self = .alreadyPending
        case 8: self = .refused(.contentNotAllowed)
        case 10: self = .refused(.poolFull)
        case 11: self = .refused(.poolDisabled)
        default: self = .refused(.other)
        }
    }

    /// Removing from a pool: "not in pool" is already what was wanted.
    public init(removingFailedWith error: FlickrError) {
        if case .api(2, _, _) = error { self = .notInPool } else { self = .refused(.other) }
    }

    /// In the pool or its queue because of this batch: what undo takes out.
    public var placedByThisBatch: Bool { self == .added || self == .pendingModeration }

    /// Out of the pool because of this batch: what undo puts back.
    public var removedByThisBatch: Bool { self == .removed }

    /// Did what was asked, or found it already so.
    public var isSuccess: Bool {
        switch self {
        case .refused, .skipped: false
        default: true
        }
    }
}
