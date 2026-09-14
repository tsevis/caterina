import Foundation

extension FlickrClient {

    /// A group's pool rules: throttle, restrictions, moderation.
    public func groupProfile(id: String, priority: CallPriority) async throws -> GroupProfile {
        try GroupResponse.profile(from: await call("flickr.groups.getInfo", ["group_id": id], priority: priority))
    }

    /// The groups whose pools hold the photo.
    public func poolIDs(photoID: String, priority: CallPriority) async throws -> [String] {
        struct Envelope: Decodable { let pool: [FlickrResponse.Lenient<Pool>]? }
        struct Pool: Decodable { let id: String }
        let data = try await call("flickr.photos.getAllContexts", ["photo_id": photoID], priority: priority)
        try FlickrResponse.throwIfFailed(data)
        return (try InsightsResponse.decode(Envelope.self, data, "the photo's groups").pool ?? [])
            .compactMap(\.value).map(\.id)
    }
}

enum GroupResponse {
    typealias LooseInt = FlickrResponse.LooseInt

    static func profile(from data: Data) throws -> GroupProfile {
        struct Envelope: Decodable { let group: Group }
        struct Text: Decodable { let _content: String? }
        struct Group: Decodable {
            let id: String
            let name: Text?
            let members: Text?
            let pool_count: Text?
            let ispoolmoderated: LooseInt?
            let eighteenplus: LooseInt?
            let is_admin: LooseInt?
            let throttle: Throttle?
            let restrictions: Restrictions?
        }
        struct Throttle: Decodable { let mode: String?; let count: LooseInt?; let remaining: LooseInt? }
        struct Restrictions: Decodable { let photos_ok: LooseInt?; let videos_ok: LooseInt?; let has_geo: LooseInt? }

        try FlickrResponse.throwIfFailed(data)
        let group = try InsightsResponse.decode(Envelope.self, data, "the group's details").group
        let flag = { (value: LooseInt?, otherwise: Bool) in value?.value.map { $0 != 0 } ?? otherwise }
        let throttle = GroupThrottle(mode: GroupThrottle.Mode(rawValue: group.throttle?.mode ?? "none") ?? .unknown,
                                     count: group.throttle?.count?.value, remaining: group.throttle?.remaining?.value)
        return GroupProfile(
            id: group.id, name: GroupResolver.unescapingHTML(group.name?._content ?? group.id),
            members: Int(group.members?._content ?? "") ?? 0, poolCount: Int(group.pool_count?._content ?? "") ?? 0,
            isAdmin: flag(group.is_admin, false), isModerated: flag(group.ispoolmoderated, false),
            isEighteenPlus: flag(group.eighteenplus, false), throttle: throttle,
            restrictions: GroupRestrictions(photos: flag(group.restrictions?.photos_ok, true),
                                            videos: flag(group.restrictions?.videos_ok, true),
                                            needsLocation: flag(group.restrictions?.has_geo, false)))
    }
}
