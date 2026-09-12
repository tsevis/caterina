import Foundation

/// The four places photos come from.
public enum PhotoSource: String, CaseIterable, Sendable, Identifiable, Hashable {
    case you, search, user, groups

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .you: return "You"
        case .search: return "Search"
        case .user: return "User"
        case .groups: return "Groups"
        }
    }

    public var systemImage: String {
        switch self {
        case .you: return "person.crop.circle"
        case .search: return "magnifyingglass"
        case .user: return "person.2"
        case .groups: return "rectangle.3.group"
        }
    }

    public var requiresAuthentication: Bool { self == .you }
}

/// What the grid should be drawing.
public enum SectionStatus: Sendable, Equatable {
    /// Nothing asked for yet — the designed empty state.
    case idle
    case loading
    case ready
    /// The query worked and matched nothing.
    case empty
    /// Something went wrong. `isTransient` decides which of two very different
    /// messages the user sees.
    case failed(FlickrError)

    public var isTransient: Bool {
        if case let .failed(error) = self { return error.isTransient }
        return false
    }

    public var error: FlickrError? {
        if case let .failed(error) = self { return error }
        return nil
    }
}

/// One source's world: what it asked for, what came back, what is selected,
/// and where in the results it is.
///
/// **A value type, and one per source.** The reference application shared a
/// single selection map and a single page number across four tabs, so loading
/// any tab wiped the others' selection while their ticked thumbnails stayed on
/// screen, and the Download button acted on whichever tab had loaded last.
public struct SectionState: Sendable, Equatable {
    public let source: PhotoSource
    /// What the user typed — kept so the field survives switching sources.
    public let input: String
    public let query: PhotoQuery?
    public let filters: SearchFilters
    public let photos: [Photo]
    /// What is selected, and where a ⇧-click would measure from. Always a
    /// subset of `photos`.
    public let selection: GridSelection
    public let page: Int
    public let totalPages: Int
    public let perPage: Int
    /// How many photos Flickr said the whole result set holds.
    public let total: Int
    public let status: SectionStatus
    /// True when Flickr reported more pages than it will actually serve.
    public let isPageCountClamped: Bool
    /// Entries in the last reply that could not be read. Surfaced rather than
    /// hidden: a page that quietly shrank is worse than one that says why.
    public let skippedEntries: Int

    public init(source: PhotoSource, input: String = "", query: PhotoQuery? = nil,
                filters: SearchFilters = SearchFilters(), photos: [Photo] = [],
                selection: GridSelection = GridSelection(), page: Int = 1,
                totalPages: Int = 1,
                perPage: Int = PhotoRequest.defaultPerPage, total: Int = 0,
                status: SectionStatus = .idle, isPageCountClamped: Bool = false,
                skippedEntries: Int = 0) {
        self.source = source
        self.input = input
        self.query = query
        self.filters = filters
        self.photos = photos
        self.selection = selection
        self.page = max(1, page)
        self.totalPages = max(1, totalPages)
        self.perPage = max(1, perPage)
        self.total = max(0, total)
        self.status = status
        self.isPageCountClamped = isPageCountClamped
        self.skippedEntries = max(0, skippedEntries)
    }

    // MARK: - Asking for something

    /// Start a new query. **Always page 1.**
    ///
    /// A new search term, a different user, a different group — or the same one
    /// asked for again — begins at the beginning. Only paging preserves a
    /// position, which is the whole of the rule.
    /// A new query. **Always page 1, and always one page until Flickr says
    /// otherwise** — leaving the old query's page count in place armed the Next
    /// button while the new query's first page was still loading, and pressing
    /// it fetched page 2 of results that had not arrived.
    public func beginning(query: PhotoQuery) -> SectionState {
        copy(query: query, photos: [], selection: GridSelection(), page: 1, totalPages: 1,
             total: 0, status: .loading, isPageCountClamped: false, skippedEntries: 0)
    }

    /// Looking something up — a username, a group — before there is a query
    /// to run. The source is busy but has nothing to page through yet.
    public func resolving() -> SectionState {
        copy(query: .some(nil), photos: [], selection: GridSelection(), page: 1, totalPages: 1,
             total: 0, status: .loading, isPageCountClamped: false, skippedEntries: 0)
    }

    /// Move to an explicit page, keeping everything else.
    public func paging(to page: Int) -> SectionState {
        copy(page: min(max(1, page), totalPages), status: .loading)
    }

    public func nextPage() -> SectionState { paging(to: page + 1) }
    public func previousPage() -> SectionState { paging(to: page - 1) }

    /// Changing the filters changes the query, so it starts again at page 1.
    public func with(filters: SearchFilters) -> SectionState {
        copy(filters: filters, selection: GridSelection(), page: 1)
    }

    /// Changing the page size keeps the *position*, which is not the same as
    /// keeping the page number.
    ///
    /// Page 120 of 160 at 25 a page is item 2,976. At 500 a page that is page 6
    /// of 8 — and page 120 does not exist, so keeping the number asked Flickr
    /// for a page past the end and drew "Nothing here matched" over a result
    /// set of four thousand photos.
    public func with(perPage newPerPage: Int) -> SectionState {
        let newPerPage = max(1, newPerPage)
        let offset = (page - 1) * self.perPage
        let reported = total > 0 ? (total + newPerPage - 1) / newPerPage : totalPages
        let reachable = Pagination.reachablePages(reported: reported, perPage: newPerPage)
        return copy(page: min(offset / newPerPage + 1, reachable),
                    totalPages: reachable, perPage: newPerPage)
    }

    public func with(input: String) -> SectionState {
        copy(input: input)
    }

    // MARK: - What came back

    public func loaded(_ result: PhotoPage) -> SectionState {
        let reachable = Pagination.reachablePages(reported: result.pages,
                                                  perPage: result.perPage)
        return copy(photos: result.photos,
                    // A selected photo that is no longer on screen cannot be
                    // downloaded; keeping it is how the count came to disagree
                    // with the grid.
                    selection: selection.keeping(to: result.photos.map(\.id)),
                    page: min(max(1, result.page), reachable),
                    totalPages: reachable,
                    perPage: result.perPage,
                    total: result.total,
                    status: result.photos.isEmpty ? .empty : .ready,
                    isPageCountClamped: Pagination.isClamped(reported: result.pages,
                                                             perPage: result.perPage),
                    skippedEntries: result.skippedEntries)
    }

    /// A failure leaves the page it was on — so a retry goes back to where the
    /// user was — but no pages ahead of it: "Page 4 of 160" under an error
    /// screen with no photos is a claim about results that are not there.
    public func failed(_ error: FlickrError) -> SectionState {
        copy(photos: [], selection: GridSelection(), totalPages: page,
             status: .failed(error))
    }

    // MARK: - Selection

    /// A click, with whatever modifiers were held. The rules live in
    /// `GridSelection`, where they can be checked without a mouse.
    public func clicking(_ photoID: String, modifiers: ClickModifiers) -> SectionState {
        copy(selection: selection.clicking(photoID, modifiers: modifiers, in: order))
    }

    /// What a marquee covered.
    public func sweeping(_ ids: Set<String>) -> SectionState {
        copy(selection: selection.sweeping(ids, in: order))
    }

    /// An arrow key, by one photo or by a row.
    public func movingSelection(by offset: Int) -> SectionState {
        copy(selection: selection.moving(by: offset, in: order))
    }

    public func toggling(_ photoID: String) -> SectionState {
        clicking(photoID, modifiers: .command)
    }

    public func selecting(_ ids: Set<String>) -> SectionState {
        copy(selection: selection.sweeping(ids, in: order))
    }

    public func selectingAll() -> SectionState {
        copy(selection: selection.selectingAll(in: order))
    }

    public func clearingSelection() -> SectionState {
        copy(selection: selection.clearing())
    }

    /// The photo ids in the order the grid shows them.
    private var order: [String] { photos.map(\.id) }

    /// The selected photos, in the order the grid shows them — so a download's
    /// progress runs top to bottom rather than in hash order.
    public var selectedPhotos: [Photo] {
        photos.filter { selection.ids.contains($0.id) }
    }

    public var canGoBack: Bool { page > 1 }
    public var canGoForward: Bool { page < totalPages }

    // MARK: - Copying

    private func copy(input: String? = nil, query: PhotoQuery?? = nil,
                      filters: SearchFilters? = nil, photos: [Photo]? = nil,
                      selection: GridSelection? = nil, page: Int? = nil,
                      totalPages: Int? = nil, perPage: Int? = nil,
                      total: Int? = nil, status: SectionStatus? = nil,
                      isPageCountClamped: Bool? = nil,
                      skippedEntries: Int? = nil) -> SectionState {
        SectionState(
            source: source,
            input: input ?? self.input,
            query: query ?? self.query,
            filters: filters ?? self.filters,
            photos: photos ?? self.photos,
            selection: selection ?? self.selection,
            page: page ?? self.page,
            totalPages: totalPages ?? self.totalPages,
            perPage: perPage ?? self.perPage,
            total: total ?? self.total,
            status: status ?? self.status,
            isPageCountClamped: isPageCountClamped ?? self.isPageCountClamped,
            skippedEntries: skippedEntries ?? self.skippedEntries)
    }
}

/// All four sources, and which one the user is looking at.
///
/// The only way to change a source is through `updating`, which returns a new
/// workspace — so one source's load cannot reach into another's state.
public struct Workspace: Sendable, Equatable {
    public let active: PhotoSource
    private let states: [PhotoSource: SectionState]

    public init(active: PhotoSource = .search) {
        self.active = active
        self.states = Dictionary(uniqueKeysWithValues:
            PhotoSource.allCases.map { ($0, SectionState(source: $0)) })
    }

    private init(active: PhotoSource, states: [PhotoSource: SectionState]) {
        self.active = active
        self.states = states
    }

    public subscript(source: PhotoSource) -> SectionState {
        states[source] ?? SectionState(source: source)
    }

    public var activeState: SectionState { self[active] }

    public func updating(_ source: PhotoSource,
                         _ transform: (SectionState) -> SectionState) -> Workspace {
        var next = states
        next[source] = transform(self[source])
        return Workspace(active: active, states: next)
    }

    public func activating(_ source: PhotoSource) -> Workspace {
        Workspace(active: source, states: states)
    }
}
