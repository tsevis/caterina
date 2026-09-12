import Foundation

/// Flickr's licence identifiers, from `flickr.photos.licenses.getInfo`.
///
/// **Getting these wrong has legal consequences for the user.** Selecting a
/// commercially-reusable licence must never return a NonCommercial one, so the
/// ids are Flickr's own and the mapping is pinned by a test rather than
/// maintained by eye.
public enum License: String, CaseIterable, Sendable, Identifiable, Hashable {
    case allRightsReserved = "0"
    case byNcSa = "1"
    case byNc = "2"
    case byNcNd = "3"
    case by = "4"
    case bySa = "5"
    case byNd = "6"
    case noKnownRestrictions = "7"
    case usGovernmentWork = "8"
    case publicDomainDedication = "9"
    case publicDomainMark = "10"
    // Creative Commons 4.0, added by Flickr after the 2.0 set above.
    case by4 = "11"
    case bySa4 = "12"
    case byNd4 = "13"
    case byNc4 = "14"
    case byNcSa4 = "15"
    case byNcNd4 = "16"

    public var id: String { rawValue }

    /// The numeric id, for ordering a `license=` parameter the way Flickr does.
    public var number: Int { Int(rawValue) ?? 0 }

    public var label: String {
        switch self {
        case .allRightsReserved: return "All Rights Reserved"
        case .byNcSa: return "Attribution-NonCommercial-ShareAlike License"
        case .byNc: return "Attribution-NonCommercial License"
        case .byNcNd: return "Attribution-NonCommercial-NoDerivs License"
        case .by: return "Attribution License"
        case .bySa: return "Attribution-ShareAlike License"
        case .byNd: return "Attribution-NoDerivs License"
        case .noKnownRestrictions: return "No known copyright restrictions"
        case .usGovernmentWork: return "United States Government Work"
        case .publicDomainDedication: return "Public Domain Dedication"
        case .publicDomainMark: return "Public Domain Mark"
        case .by4: return "Attribution 4.0"
        case .bySa4: return "Attribution-ShareAlike 4.0"
        case .byNd4: return "Attribution-NoDerivs 4.0"
        case .byNc4: return "Attribution-NonCommercial 4.0"
        case .byNcSa4: return "Attribution-NonCommercial-ShareAlike 4.0"
        case .byNcNd4: return "Attribution-NonCommercial-NoDerivs 4.0"
        }
    }

    /// Whether the licence permits commercial reuse. Not used to filter — the
    /// filter sends ids — but shown beside a photo so the user is not left to
    /// decode `by-nc-sa` themselves.
    public var allowsCommercialUse: Bool {
        switch self {
        case .allRightsReserved: return false
        case .byNcSa, .byNc, .byNcNd, .byNc4, .byNcSa4, .byNcNd4: return false
        case .by, .bySa, .byNd, .noKnownRestrictions, .usGovernmentWork,
             .publicDomainDedication, .publicDomainMark, .by4, .bySa4, .byNd4:
            return true
        }
    }

    /// Accepts the id however Flickr spells it — `"4"` or `4`.
    public static func named(_ id: String) -> License? {
        License(rawValue: id.trimmingCharacters(in: .whitespaces))
    }
}
