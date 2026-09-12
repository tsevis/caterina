import Foundation
import Testing

@testable import FlickrKit

/// Ported from `tests/test_search_filters.py` and `tests/test_sort_settings.py`.
///
/// Both filters here once looked like they worked and did not: licence 0 was
/// stripped out of every query, and the size filter asked whether a thumbnail
/// variant existed rather than how big the photo is.
@Suite struct SearchFiltersTests {

    // MARK: - Licences

    @Test func allRightsReservedAloneIsSentNotDropped() {
        #expect(SearchFilters(licenses: [.allRightsReserved]).licenseParameter == "0")
    }

    @Test func allRightsReservedSurvivesAlongsideOthers() {
        let filters = SearchFilters(licenses: [.allRightsReserved, .by, .publicDomainMark])
        #expect(filters.licenseParameter == "0,4,10")
    }

    @Test func nothingSelectedMeansNoFilterAtAll() {
        #expect(SearchFilters().licenseParameter == nil)
        #expect(SearchFilters(licenses: []).licenseParameter == nil)
    }

    @Test func idsAreOrderedNumericallyNotLexically() {
        let filters = SearchFilters(licenses: [.publicDomainMark, .byNcNd4, .by, .byNcSa])
        #expect(filters.licenseParameter == "1,4,10,16")
    }

    @Test func thereAreSeventeenLicences() {
        #expect(License.allCases.count == 17)
        #expect(Set(License.allCases.map(\.rawValue)).count == 17)
        #expect(Set(License.allCases.map(\.label)).count == 17)
    }

    @Test(arguments: [
        ("All Rights Reserved", "0"), ("Attribution License", "4"),
        ("Public Domain Mark", "10"), ("Attribution-NonCommercial-NoDerivs 4.0", "16"),
    ])
    func individualLicencesMapToFlickrIDs(label: String, id: String) {
        #expect(License.allCases.first { $0.label == label }?.rawValue == id)
    }

    @Test func creativeCommonsFourPointZeroLicencesAreAvailable() {
        let modern = License.allCases.filter { $0.label.hasSuffix("4.0") }
        #expect(modern.count == 6)
        #expect(modern.allSatisfy { $0.number >= 11 })
    }

    @Test func commercialUseIsNotGuessedFromTheLabel() {
        #expect(License.by.allowsCommercialUse)
        #expect(!License.byNc4.allowsCommercialUse)
        #expect(!License.allRightsReserved.allowsCommercialUse)
        #expect(License.publicDomainMark.allowsCommercialUse)
    }

    // MARK: - Size buckets

    private func photo(_ variants: PhotoVariant...) -> Photo {
        Photo(id: "1", variants: Dictionary(uniqueKeysWithValues:
            variants.map { ($0, "https://example.com/\($0.rawValue).jpg") }))
    }

    @Test(arguments: [
        (PhotoVariant.original, SizeBucket.large), (.large2048, .large),
        (.large1600, .large), (.large, .large), (.medium800, .medium),
        (.medium640, .medium), (.medium, .medium), (.small320, .small),
        (.small, .small), (.thumbnail, .small), (.square, .small),
    ])
    func theBucketComesFromTheLargestVariantOffered(variant: PhotoVariant, bucket: SizeBucket) {
        #expect(SizeBucket.of(photo(variant)) == bucket)
    }

    /// The defect: a large photo also publishes a square thumbnail, and asking
    /// "does a small variant exist?" classified every photo as small.
    @Test func aLargePhotoIsNotCountedAsSmall() {
        #expect(SizeBucket.of(photo(.square, .thumbnail, .medium, .original)) == .large)
    }

    @Test func aPhotoWithNoVariantsHasNoBucket() {
        #expect(SizeBucket.of(Photo(id: "1")) == nil)
    }

    @Test func filteringByAnEmptySelectionKeepsEverything() {
        let photos = [photo(.original), photo(.medium), photo(.square), Photo(id: "x")]
        #expect(SearchFilters().apply(to: photos).count == 4)
    }

    @Test func severalBucketsCombine() {
        let photos = [photo(.original), photo(.medium), photo(.square)]
        let filters = SearchFilters(sizes: [.large, .small])
        #expect(filters.apply(to: photos).count == 2)
    }

    @Test func aPhotoWithNoURLsIsExcludedWhenFiltering() {
        let filters = SearchFilters(sizes: [.large])
        #expect(filters.apply(to: [Photo(id: "x"), photo(.original)]).map(\.id) == ["1"])
    }

    @Test func sizeLabelsDescribeTheBuckets() {
        #expect(SizeBucket.small.label == "Small (up to 500px)")
        #expect(SizeBucket.medium.label == "Medium (501 – 1024px)")
        #expect(SizeBucket.large.label == "Large (1025px and above)")
    }

    // MARK: - Sort

    /// Flickr answers `stat=ok` for a sort value it does not recognise, so a
    /// wrong value is invisible in the response. The type is the only place it
    /// can be caught.
    @Test func everySortValueIsOneFlickrAccepts() {
        let accepted: Set<String> = [
            "relevance", "date-posted-asc", "date-posted-desc",
            "date-taken-asc", "date-taken-desc",
            "interestingness-asc", "interestingness-desc",
        ]
        #expect(Set(SortOrder.allCases.map(\.rawValue)) == accepted)
    }

    @Test func thereIsNoSizeOrLicenceSort() {
        for value in SortOrder.allCases.map(\.rawValue) {
            #expect(!value.contains("size"))
            #expect(!value.contains("licen"))
        }
    }

    @Test func sortIsExclusiveBecauseItIsASingleValue() {
        var filters = SearchFilters(sort: .relevance)
        filters = filters.with(sort: .datePostedDescending)
        #expect(filters.sort == .datePostedDescending)
    }

    @Test func sortCannotBeLeftUnset() {
        // There is no `nil` case: an unset sort would silently become
        // relevance, which is a different search than the one the user chose.
        #expect(SearchFilters().sort == .relevance)
    }

    @Test func theOfferedSortsAreASubsetOfTheAcceptedOnes() {
        #expect(SortOrder.offered.count == 3)
        #expect(Set(SortOrder.offered).isSubset(of: Set(SortOrder.allCases)))
        #expect(Set(SortOrder.offered.map(\.label)).count == 3)
    }

    // MARK: - Colours

    @Test func thereAreSevenColoursPlusAny() {
        #expect(FlickrColor.allCases.count == 7)
        #expect(SearchFilters().colorParameter == nil)
    }

    @Test func coloursCombineIntoOneParameterInFlickrsOrder() {
        let filters = SearchFilters(colors: [.blackAndWhite, .red, .green])
        #expect(filters.colorParameter == "0,3,6")
    }
}
