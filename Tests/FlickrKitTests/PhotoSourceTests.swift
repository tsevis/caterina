import Foundation
import Testing

@testable import FlickrKit

/// **Selection and pagination belong to one source.**
///
/// The reference application kept one map of selected photos and one page
/// number for four tabs. Loading any tab wiped the others' selection while
/// their ticked thumbnails stayed on screen, and the Download button
/// downloaded another tab's photos, or nothing at all.
@Suite struct SectionStateTests {

    private func photos(_ ids: [String]) -> [Photo] {
        ids.map { Photo(id: $0, title: "Photo \($0)",
                        variants: [.medium: "https://example.com/\($0).jpg"]) }
    }

    private func page(_ ids: [String], page: Int = 1, pages: Int = 5) -> PhotoPage {
        PhotoPage(page: page, pages: pages, perPage: 25, total: pages * 25,
                  photos: photos(ids))
    }

    // MARK: - One source's state is its own

    @Test func loadingOneSectionLeavesTheOthersUntouched() {
        var workspace = Workspace()
        workspace = workspace.updating(.search) {
            $0.beginning(query: .search(text: "boats")).loaded(page(["1", "2"]))
        }
        workspace = workspace.updating(.search) { $0.selecting(["1", "2"]) }

        workspace = workspace.updating(.groups) {
            $0.beginning(query: .groupPool(groupID: "9@N1")).loaded(page(["8", "9"], page: 3))
        }

        #expect(workspace[.search].selection == ["1", "2"])
        #expect(workspace[.search].page == 1)
        #expect(workspace[.groups].page == 3)
        #expect(workspace[.groups].selection.isEmpty)
    }

    /// The defect, stated directly: the button must download what the source
    /// the user is looking at has selected.
    @Test func theDownloadSetComesFromTheSectionItWasSelectedIn() {
        var workspace = Workspace()
        workspace = workspace.updating(.search) {
            $0.beginning(query: .search(text: "boats")).loaded(page(["1", "2", "3"]))
                .selecting(["2", "3"])
        }
        workspace = workspace.updating(.user) {
            $0.beginning(query: .userPhotos(userID: "7@N7")).loaded(page(["90", "91"]))
                .selecting(["90"])
        }

        #expect(workspace[.search].selectedPhotos.map(\.id) == ["2", "3"])
        #expect(workspace[.user].selectedPhotos.map(\.id) == ["90"])
    }

    @Test func everySectionStartsIdleAndEmpty() {
        let workspace = Workspace()
        for source in PhotoSource.allCases {
            #expect(workspace[source].status == .idle)
            #expect(workspace[source].photos.isEmpty)
            #expect(workspace[source].selection.isEmpty)
            #expect(workspace[source].page == 1)
        }
    }

    @Test func thereIsNoGlobalCurrentPage() {
        var workspace = Workspace()
        for (index, source) in PhotoSource.allCases.enumerated() {
            workspace = workspace.updating(source) {
                $0.loaded(page(["a"], page: index + 1, pages: 9))
            }
        }
        #expect(Set(PhotoSource.allCases.map { workspace[$0].page }).count == PhotoSource.allCases.count)
    }

    // MARK: - A new query resets to page 1

    @Test func aNewSearchTermGoesBackToPageOne() {
        let state = SectionState(source: .search)
            .beginning(query: .search(text: "boats"))
            .loaded(page(["1"], page: 1))
            .paging(to: 4)
            .loaded(page(["2"], page: 4))
        #expect(state.page == 4)

        let restarted = state.beginning(query: .search(text: "harbours"))
        #expect(restarted.page == 1)
    }

    @Test func repeatingTheSameSearchAlsoStartsAtPageOne() {
        // Pressing Return again is a new search, not a refresh of page 4.
        let state = SectionState(source: .search)
            .beginning(query: .search(text: "boats"))
            .loaded(page(["1"], page: 4))
            .beginning(query: .search(text: "boats"))
        #expect(state.page == 1)
    }

    @Test func adifferentUserOrGroupGoesBackToPageOne() {
        let user = SectionState(source: .user)
            .beginning(query: .userPhotos(userID: "1@N1")).loaded(page(["a"], page: 6))
            .beginning(query: .userPhotos(userID: "2@N2"))
        #expect(user.page == 1)

        let group = SectionState(source: .groups)
            .beginning(query: .groupPool(groupID: "1@N1")).loaded(page(["a"], page: 6))
            .beginning(query: .groupPool(groupID: "2@N2"))
        #expect(group.page == 1)
    }

    @Test func changingTheFiltersIsANewQueryToo() {
        let state = SectionState(source: .search)
            .beginning(query: .search(text: "boats")).loaded(page(["a"], page: 3))
            .with(filters: SearchFilters(licenses: [.by]))
        #expect(state.page == 1)
    }

    @Test func onlyPagingPreservesThePosition() {
        let state = SectionState(source: .search)
            .beginning(query: .search(text: "boats")).loaded(page(["a"], page: 2, pages: 9))
        #expect(state.nextPage().page == 3)
        #expect(state.previousPage().page == 1)
    }

    /// The *position*, not the page number: page 3 at 25 a page starts at item
    /// 51, which at 100 a page is on page 1.
    @Test func perPageKeepsThePositionRatherThanTheNumber() {
        let state = SectionState(source: .search)
            .beginning(query: .search(text: "boats")).loaded(page(["a"], page: 3, pages: 9))
        #expect(state.page == 3)

        let denser = state.with(perPage: 100)
        #expect(denser.perPage == 100)
        #expect(denser.page == 1)
        #expect(denser.page <= denser.totalPages)
    }

    @Test func pagingCannotWalkOffEitherEnd() {
        let state = SectionState(source: .search)
            .beginning(query: .search(text: "x")).loaded(page(["a"], page: 1, pages: 3))
        #expect(state.previousPage().page == 1)

        let last = state.paging(to: 3).loaded(page(["a"], page: 3, pages: 3))
        #expect(last.nextPage().page == 3)
    }

    // MARK: - Selection follows the photos that are actually there

    @Test func selectionIsDroppedWhenTheQueryChanges() {
        let state = SectionState(source: .search)
            .beginning(query: .search(text: "boats")).loaded(page(["1", "2"]))
            .selecting(["1", "2"])
            .beginning(query: .search(text: "harbours"))
        #expect(state.selection.isEmpty)
    }

    /// A selected id that is no longer on screen cannot be downloaded, and
    /// leaving it in the set is how the count came to disagree with the grid.
    @Test func selectionIsIntersectedWithWhatTheNewPageActuallyHolds() {
        let state = SectionState(source: .search)
            .beginning(query: .search(text: "x")).loaded(page(["1", "2", "3"]))
            .selecting(["1", "3"])
            .paging(to: 2).loaded(page(["3", "4"], page: 2))
        #expect(state.selection == ["3"])
    }

    @Test func selectingAllSelectsWhatIsOnScreen() {
        let state = SectionState(source: .search)
            .loaded(page(["1", "2", "3"])).selectingAll()
        #expect(state.selection.count == 3)
        #expect(state.clearingSelection().selection.isEmpty)
    }

    @Test func togglingIsReversible() {
        let loaded = SectionState(source: .search).loaded(page(["1", "2"]))
        #expect(loaded.toggling("1").selection == ["1"])
        #expect(loaded.toggling("1").toggling("1").selection.isEmpty)
    }

    @Test func aSelectedPhotoThatIsNotLoadedIsNotDownloadable() {
        let state = SectionState(source: .search).loaded(page(["1"])).selecting(["1", "999"])
        #expect(state.selectedPhotos.map(\.id) == ["1"])
    }

    @Test func selectedPhotosComeBackInTheOrderTheyAreShown() {
        let state = SectionState(source: .search)
            .loaded(page(["5", "4", "3", "2"])).selecting(["2", "5"])
        #expect(state.selectedPhotos.map(\.id) == ["5", "2"])
    }

    // MARK: - States the interface has to draw

    @Test func aPageWithNoPhotosIsEmptyNotReady() {
        #expect(SectionState(source: .search).loaded(page([])).status == .empty)
        #expect(SectionState(source: .search).loaded(page(["1"])).status == .ready)
    }

    /// "Flickr is busy" is a different message from "that group does not
    /// exist", and showing the second when it means the first is what the
    /// reference application got complaints for.
    @Test func aTransientFailureReadsDifferentlyFromARealError() {
        let busy = SectionState(source: .search).failed(.busy("Flickr is busy."))
        let real = SectionState(source: .search).failed(.notFound("No such group."))
        #expect(busy.status.isTransient)
        #expect(!real.status.isTransient)
        #expect(busy.status != real.status)
    }

    @Test func beginningAQuerySaysItIsLoading() {
        #expect(SectionState(source: .search)
            .beginning(query: .search(text: "x")).status == .loading)
    }

    @Test func aFailureDoesNotSilentlyKeepTheOldPhotosSelectable() {
        let state = SectionState(source: .search)
            .loaded(page(["1", "2"])).selecting(["1"])
            .failed(.notFound("gone"))
        #expect(state.selection.isEmpty)
    }

    // MARK: - The 4000-result cap

    /// Flickr reports a page count for the whole result set but serves at most
    /// about 4000 results; paging past that repeats earlier photos.
    @Test func reachablePagesAreClampedToWhatFlickrWillActuallyServe() {
        #expect(Pagination.reachablePages(reported: 1000, perPage: 25) == 160)
        #expect(Pagination.reachablePages(reported: 40, perPage: 100) == 40)
        #expect(Pagination.reachablePages(reported: 1, perPage: 25) == 1)
        #expect(Pagination.reachablePages(reported: 0, perPage: 25) == 1)
    }

    @Test func theClampIsExplainedRatherThanSilent() {
        #expect(Pagination.isClamped(reported: 1000, perPage: 25))
        #expect(!Pagination.isClamped(reported: 10, perPage: 25))
        #expect(!Pagination.explanation.isEmpty)
    }

    @Test func aSectionOnlyOffersPagesItCanReach() {
        let state = SectionState(source: .search)
            .loaded(PhotoPage(page: 1, pages: 4000, perPage: 25, total: 100_000,
                              photos: photos(["1"])))
        #expect(state.totalPages == 160)
        #expect(state.isPageCountClamped)
    }
}
