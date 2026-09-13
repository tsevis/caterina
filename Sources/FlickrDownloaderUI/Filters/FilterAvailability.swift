/// The inspector's sections.
enum FilterSection: CaseIterable {
    case clear, sort, size, colour, licence
}

/// Which sections a source can use.
///
/// **Decided per section, never on the `Form`.** A parent's `.disabled(true)`
/// cannot be undone by a child's `.disabled(false)`, so gating the whole form
/// and exempting Size greyed Size out with everything else.
enum FilterAvailability {
    static func isEnabled(_ section: FilterSection, supportsFilters: Bool) -> Bool {
        switch section {
        // Size is applied to the results here rather than sent to Flickr, so
        // it works on a photostream and a pool exactly as on a search; and
        // clearing has to reach a size filter set there.
        case .clear, .size: return true
        case .sort, .colour, .licence: return supportsFilters
        }
    }
}
