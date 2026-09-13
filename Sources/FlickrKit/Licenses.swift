import Foundation

/// What a licence lets someone do.
///
/// **A boolean was not honest enough.** "No known copyright restrictions" is a
/// Flickr Commons institution saying it has *not found* a rights holder — it is
/// a statement of ignorance, not a grant — and it was being reported as
/// commercially reusable. A photograph can also be freely reusable and still
/// forbid derivatives, which a single flag cannot say either.
public enum Reuse: Sendable, Equatable, Hashable {
    /// Reusable, including commercially, under the licence's terms.
    case permitted
    /// Reusable, but not commercially.
    case nonCommercialOnly
    /// The photographer reserved their rights.
    case reserved
    /// Nobody has asserted rights, and nobody has cleared them either.
    case unclear
}

/// Flickr's licence identifiers.
///
/// **Getting these wrong has legal consequences for the user**, so they are not
/// maintained by eye: `LiveAPITests` calls `flickr.photos.licenses.getInfo` and
/// fails if this table and Flickr's disagree on a single id or name.
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
    case by4 = "11"
    case bySa4 = "12"
    case byNd4 = "13"
    case byNc4 = "14"
    case byNcSa4 = "15"
    case byNcNd4 = "16"

    public var id: String { rawValue }
    public var number: Int { Int(rawValue) ?? 0 }

    /// Flickr's own name for the licence, as `licenses.getInfo` returns it.
    public var label: String {
        switch self {
        case .allRightsReserved: return "All Rights Reserved"
        case .byNcSa: return "CC BY-NC-SA 2.0"
        case .byNc: return "CC BY-NC 2.0"
        case .byNcNd: return "CC BY-NC-ND 2.0"
        case .by: return "CC BY 2.0"
        case .bySa: return "CC BY-SA 2.0"
        case .byNd: return "CC BY-ND 2.0"
        case .noKnownRestrictions: return "No known copyright restrictions"
        case .usGovernmentWork: return "United States Government Work"
        case .publicDomainDedication: return "Public Domain Dedication (CC0)"
        case .publicDomainMark: return "Public Domain Mark"
        case .by4: return "CC BY 4.0"
        case .bySa4: return "CC BY-SA 4.0"
        case .byNd4: return "CC BY-ND 4.0"
        case .byNc4: return "CC BY-NC 4.0"
        case .byNcSa4: return "CC BY-NC-SA 4.0"
        case .byNcNd4: return "CC BY-NC-ND 4.0"
        }
    }

    /// What goes on a thumbnail.
    ///
    /// **Every licence gets one, and no two mean the same thing.** Collapsing
    /// sixteen licences into "CC" and "CC-NC" told someone holding a
    /// No-Derivatives photograph the same thing it told someone holding a CC0
    /// one, and showed nothing at all for All Rights Reserved — which is not
    /// the same as a photo whose licence Flickr did not state.
    public var badge: String {
        switch self {
        case .allRightsReserved: return "©"
        case .by, .by4: return "BY"
        case .bySa, .bySa4: return "BY-SA"
        case .byNd, .byNd4: return "BY-ND"
        case .byNc, .byNc4: return "BY-NC"
        case .byNcSa, .byNcSa4: return "BY-NC-SA"
        case .byNcNd, .byNcNd4: return "BY-NC-ND"
        case .noKnownRestrictions: return "Commons"
        case .usGovernmentWork: return "US Gov"
        case .publicDomainDedication: return "CC0"
        case .publicDomainMark: return "PD"
        }
    }

    public var reuse: Reuse {
        switch self {
        case .allRightsReserved:
            return .reserved
        case .byNcSa, .byNc, .byNcNd, .byNc4, .byNcSa4, .byNcNd4:
            return .nonCommercialOnly
        case .noKnownRestrictions:
            // Flickr Commons: the institution has found no rights holder. That
            // is not permission, and saying otherwise is how somebody ends up
            // using a photograph commercially that they had no right to.
            return .unclear
        case .by, .bySa, .byNd, .usGovernmentWork, .publicDomainDedication,
             .publicDomainMark, .by4, .bySa4, .byNd4:
            return .permitted
        }
    }

    /// Whether the licence asks for credit. Public domain marks do not require
    /// it; every CC licence does.
    public var requiresAttribution: Bool {
        switch self {
        case .publicDomainDedication, .publicDomainMark, .usGovernmentWork,
             .allRightsReserved, .noKnownRestrictions:
            return false
        default:
            return true
        }
    }

    /// Whether the licence permits changing the work.
    public var allowsDerivatives: Bool {
        switch self {
        case .byNd, .byNd4, .byNcNd, .byNcNd4: return false
        case .allRightsReserved: return false
        default: return true
        }
    }

    /// Where the terms actually are, so a credit can point at them.
    public var termsURL: String? {
        switch self {
        case .allRightsReserved: return nil
        case .byNcSa: return "https://creativecommons.org/licenses/by-nc-sa/2.0/"
        case .byNc: return "https://creativecommons.org/licenses/by-nc/2.0/"
        case .byNcNd: return "https://creativecommons.org/licenses/by-nc-nd/2.0/"
        case .by: return "https://creativecommons.org/licenses/by/2.0/"
        case .bySa: return "https://creativecommons.org/licenses/by-sa/2.0/"
        case .byNd: return "https://creativecommons.org/licenses/by-nd/2.0/"
        case .noKnownRestrictions: return "https://www.flickr.com/commons/usage/"
        case .usGovernmentWork: return "https://www.usa.gov/government-works"
        case .publicDomainDedication: return "https://creativecommons.org/publicdomain/zero/1.0/"
        case .publicDomainMark: return "https://creativecommons.org/publicdomain/mark/1.0/"
        case .by4: return "https://creativecommons.org/licenses/by/4.0/"
        case .bySa4: return "https://creativecommons.org/licenses/by-sa/4.0/"
        case .byNd4: return "https://creativecommons.org/licenses/by-nd/4.0/"
        case .byNc4: return "https://creativecommons.org/licenses/by-nc/4.0/"
        case .byNcSa4: return "https://creativecommons.org/licenses/by-nc-sa/4.0/"
        case .byNcNd4: return "https://creativecommons.org/licenses/by-nc-nd/4.0/"
        }
    }

    /// Accepts the id however Flickr spells it — `"4"` or `4`.
    public static func named(_ id: String) -> License? {
        License(rawValue: id.trimmingCharacters(in: .whitespaces))
    }
}

/// Stored as its Flickr id.
extension License: Codable {}
