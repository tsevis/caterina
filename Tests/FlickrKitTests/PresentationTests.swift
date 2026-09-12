import Foundation
import Testing

@testable import FlickrKit

/// Every value the interface puts in front of a person has to have a name, and
/// no two may share one — a duplicate label in a picker is a control the user
/// cannot use.
@Suite struct PresentationTests {

    @Test func everyLicenceHasItsOwnLabel() {
        #expect(License.allCases.allSatisfy { !$0.label.isEmpty })
        #expect(Set(License.allCases.map(\.label)).count == License.allCases.count)
    }

    @Test func everySortHasItsOwnLabel() {
        #expect(SortOrder.allCases.allSatisfy { !$0.label.isEmpty })
        #expect(Set(SortOrder.allCases.map(\.label)).count == SortOrder.allCases.count)
    }

    @Test func everyColourHasItsOwnLabelAndCode() {
        #expect(FlickrColor.allCases.allSatisfy { !$0.label.isEmpty })
        #expect(Set(FlickrColor.allCases.map(\.label)).count == 7)
        #expect(FlickrColor.allCases.map(\.number) == [0, 1, 2, 3, 4, 5, 6])
    }

    @Test func everySizeBucketHasItsOwnLabelAndVariants() {
        #expect(Set(SizeBucket.allCases.map(\.label)).count == 3)
        let claimed = SizeBucket.allCases.flatMap(\.variants)
        // The buckets partition the variants: none missing, none counted twice.
        #expect(Set(claimed).count == claimed.count)
        #expect(Set(claimed) == Set(PhotoVariant.allCases))
    }

    @Test func everySectionHasATitleAndASymbol() {
        #expect(Set(PhotoSource.allCases.map(\.title)).count == 4)
        #expect(Set(PhotoSource.allCases.map(\.systemImage)).count == 4)
        #expect(PhotoSource.allCases.filter(\.requiresAuthentication) == [.you])
    }

    @Test func everyErrorSaysSomething() {
        let errors: [FlickrError] = [
            .api(code: 1, message: "no", transient: false),
            .malformedResponse("bad"), .transport("offline"),
            .invalidInput("empty"), .notFound("gone"), .busy("later"),
        ]
        #expect(errors.allSatisfy { !$0.message.isEmpty })
        #expect(errors.filter(\.isTransient).count == 2)   // transport and busy
    }

    @Test func aVariantsDescriptionNamesItsPixels() {
        #expect(PhotoVariant.allCases.allSatisfy { !$0.pixelDescription.isEmpty })
        #expect(PhotoVariant.defaultDownload == .large)
        #expect(PhotoVariant.descendingBySize.count == 11)
        #expect(Set(PhotoVariant.descendingBySize) == Set(PhotoVariant.allCases))
    }

    @Test func aThumbnailIsTheSmallestVariantOnOffer() {
        let photo = Photo(id: "1", variants: [.original: "o", .square: "sq", .medium: "m"])
        #expect(photo.thumbnailURL() == "sq")
        #expect(Photo(id: "2").thumbnailURL() == nil)
    }

    @Test func aFilterSetKnowsWhetherItIsDoingAnything() {
        #expect(!SearchFilters().isFiltering)
        #expect(SearchFilters(licenses: [.by]).isFiltering)
        #expect(SearchFilters(sizes: [.large]).isFiltering)
        #expect(SearchFilters(colors: [.red]).isFiltering)
        #expect(SearchFilters(sort: .dateTakenAscending).isFiltering)
    }

    @Test func replacingOneFilterLeavesTheOthersAlone() {
        let start = SearchFilters(licenses: [.by], sizes: [.large],
                                  sort: .relevance, colors: [.red])
        #expect(start.with(licenses: [.byNc]).sizes == [.large])
        #expect(start.with(sizes: [.small]).licenses == [.by])
        #expect(start.with(colors: [.blue]).sort == .relevance)
        #expect(start.with(sort: .dateTakenDescending).colors == [.red])
    }

    @Test func aSectionKnowsWhichWayItCanPage() {
        let middle = SectionState(source: .search, page: 2, totalPages: 5)
        #expect(middle.canGoBack)
        #expect(middle.canGoForward)

        let only = SectionState(source: .search, page: 1, totalPages: 1)
        #expect(!only.canGoBack)
        #expect(!only.canGoForward)
    }

    @Test func whatTheUserTypedSurvivesSwitchingSections() {
        var workspace = Workspace()
        workspace = workspace.updating(.user) { $0.with(input: "someone") }
        workspace = workspace.activating(.groups).activating(.user)
        #expect(workspace[.user].input == "someone")
        #expect(workspace.activeState.source == .user)
        #expect(workspace.active == .user)
    }

    @Test func aPhotoRequestCanBeMovedToAnotherPageWithoutRebuildingIt() {
        let request = PhotoRequest(query: .search(text: "x"), page: 1, perPage: 50)
        #expect(request.onPage(4).page == 4)
        #expect(request.onPage(4).perPage == 50)
        #expect(request.onPage(0).page == 1)
    }

    @Test func aQueryKnowsWhatMakesItADifferentQuery() {
        #expect(PhotoQuery.search(text: "a").identity != PhotoQuery.search(text: "b").identity)
        #expect(PhotoQuery.search(text: " a ").identity == PhotoQuery.search(text: "a").identity)
        #expect(PhotoQuery.groupPool(groupID: "1@N1").identity
            != PhotoQuery.groupSearch(groupID: "1@N1", text: "x").identity)
        #expect(PhotoQuery.myPhotos.identity != PhotoQuery.userPhotos(userID: "me").identity)
    }
}
