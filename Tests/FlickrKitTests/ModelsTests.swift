import Foundation
import Testing

@testable import FlickrKit

/// Flickr's JSON is not a contract. Fields that are documented as integers
/// arrive as strings, `photo` is occasionally something other than an array,
/// and an entry can be null. None of that may take the application down: a
/// malformed payload surfaces as a message the user can read.
@Suite struct ModelsTests {

    private func decodePage(_ json: String) throws -> PhotoPage {
        try FlickrResponse.photoPage(from: Data(json.utf8))
    }

    // MARK: - The ordinary case

    @Test func decodesATypicalSearchPayload() throws {
        let page = try decodePage("""
        {"photos":{"page":2,"pages":7,"perpage":25,"total":163,"photo":[
          {"id":"51234567890","owner":"12345@N00","title":"Blue hour",
           "license":"4","url_m":"https://live.staticflickr.com/1/a_m.jpg",
           "url_o":"https://live.staticflickr.com/1/a_o.jpg"}
        ]},"stat":"ok"}
        """)

        #expect(page.page == 2)
        #expect(page.pages == 7)
        #expect(page.perPage == 25)
        #expect(page.total == 163)
        #expect(page.photos.count == 1)

        let photo = try #require(page.photos.first)
        #expect(photo.id == "51234567890")
        #expect(photo.title == "Blue hour")
        #expect(photo.owner == "12345@N00")
        #expect(photo.license == .by)
        #expect(photo.url(for: .original) == "https://live.staticflickr.com/1/a_o.jpg")
        #expect(photo.url(for: .large) == nil)
    }

    // MARK: - Scalars that change type

    @Test func countsArriveAsStringsJustAsOftenAsNumbers() throws {
        let page = try decodePage("""
        {"photos":{"page":"3","pages":"12","perpage":"50","total":"600","photo":[]},"stat":"ok"}
        """)
        #expect(page.page == 3)
        #expect(page.pages == 12)
        #expect(page.perPage == 50)
        #expect(page.total == 600)
    }

    @Test func countsThatAreNotNumbersAtAllFallBackRatherThanThrow() throws {
        let page = try decodePage("""
        {"photos":{"page":null,"pages":"lots","perpage":{},"total":[],"photo":[]},"stat":"ok"}
        """)
        #expect(page.page == 1)
        #expect(page.pages == 1)
        #expect(page.total == 0)
    }

    /// A page count of zero would make the pagination bar read "Page 1 of 0".
    @Test func pageCountsClampToAtLeastOne() throws {
        let page = try decodePage("""
        {"photos":{"page":0,"pages":0,"perpage":25,"total":0,"photo":[]},"stat":"ok"}
        """)
        #expect(page.page == 1)
        #expect(page.pages == 1)
    }

    @Test func aNegativePageCountIsNotBelievedEither() throws {
        let page = try decodePage("""
        {"photos":{"page":-4,"pages":-9,"perpage":-1,"total":-2,"photo":[]},"stat":"ok"}
        """)
        #expect(page.page == 1)
        #expect(page.pages == 1)
        #expect(page.perPage >= 1)
        #expect(page.total == 0)
    }

    // MARK: - Shapes that are simply wrong

    @Test func photosArrivingAsAListIsAMessageNotACrash() {
        #expect(throws: FlickrError.self) {
            _ = try decodePage(#"{"photos":[1,2,3],"stat":"ok"}"#)
        }
    }

    @Test func aMissingPhotosContainerIsAMessageNotACrash() {
        #expect(throws: FlickrError.self) {
            _ = try decodePage(#"{"stat":"ok"}"#)
        }
    }

    @Test func bytesThatAreNotJSONAreAMessageNotACrash() {
        #expect(throws: FlickrError.self) {
            _ = try FlickrResponse.photoPage(from: Data("<html>502 Bad Gateway</html>".utf8))
        }
    }

    @Test func anEmptyBodyIsAMessageNotACrash() {
        #expect(throws: FlickrError.self) {
            _ = try FlickrResponse.photoPage(from: Data())
        }
    }

    // MARK: - Entries that are wrong, in a page that is not

    /// One bad entry must not cost the user the other twenty-four.
    @Test func aNullEntryIsDroppedAndTheRestSurvive() throws {
        let page = try decodePage("""
        {"photos":{"page":1,"pages":1,"perpage":25,"total":3,"photo":[
          {"id":"1","title":"first"}, null, {"id":"3","title":"third"}
        ]},"stat":"ok"}
        """)
        #expect(page.photos.map(\.id) == ["1", "3"])
        #expect(page.skippedEntries == 1)
    }

    @Test func anEntryWithNoUsableIdIsDropped() throws {
        let page = try decodePage("""
        {"photos":{"page":1,"pages":1,"perpage":25,"total":3,"photo":[
          {"title":"no id"}, {"id":"","title":"blank id"}, {"id":"7","title":"fine"}
        ]},"stat":"ok"}
        """)
        #expect(page.photos.map(\.id) == ["7"])
        #expect(page.skippedEntries == 2)
    }

    @Test func aNumericIdIsAcceptedAndBecomesAString() throws {
        let page = try decodePage("""
        {"photos":{"page":1,"pages":1,"perpage":25,"total":1,"photo":[{"id":51234567890}]},"stat":"ok"}
        """)
        #expect(page.photos.map(\.id) == ["51234567890"])
    }

    @Test func aMissingTitleIsEmptyNotAbsent() throws {
        let page = try decodePage("""
        {"photos":{"page":1,"pages":1,"perpage":25,"total":1,"photo":[{"id":"1"}]},"stat":"ok"}
        """)
        #expect(page.photos.first?.title == "")
    }

    /// Flickr has added licences before and will again; an id this build has
    /// never heard of must read as "unknown", not as a decoding failure.
    @Test func anUnrecognisedLicenceIsUnknownNotFatal() throws {
        let page = try decodePage("""
        {"photos":{"page":1,"pages":1,"perpage":25,"total":1,
         "photo":[{"id":"1","license":"99"}]},"stat":"ok"}
        """)
        #expect(page.photos.first?.license == nil)
    }

    @Test func aVariantURLThatIsNotAStringIsIgnored() throws {
        let page = try decodePage("""
        {"photos":{"page":1,"pages":1,"perpage":25,"total":1,
         "photo":[{"id":"1","url_o":42,"url_m":"https://example.com/m.jpg"}]},"stat":"ok"}
        """)
        let photo = try #require(page.photos.first)
        #expect(photo.url(for: .original) == nil)
        #expect(photo.url(for: .medium) == "https://example.com/m.jpg")
    }

    // MARK: - The failure envelope

    @Test func statFailBecomesAnAPIErrorCarryingCodeAndMessage() {
        let json = #"{"stat":"fail","code":1,"message":"Photo not found"}"#
        #expect {
            _ = try FlickrResponse.photoPage(from: Data(json.utf8))
        } throws: { error in
            guard case let FlickrError.api(code, message, transient) = error else { return false }
            return code == 1 && message == "Photo not found" && transient == false
        }
    }

    @Test func theBlipCodesAreMarkedTransient() {
        for code in [105, 106, 111, 112, 201] {
            let json = #"{"stat":"fail","code":\#(code),"message":"busy"}"#
            #expect {
                _ = try FlickrResponse.photoPage(from: Data(json.utf8))
            } throws: { error in
                guard case let FlickrError.api(_, _, transient) = error else { return false }
                return transient
            }
        }
    }

    @Test func aFailureCodeArrivingAsAStringIsStillRead() {
        let json = #"{"stat":"fail","code":"201","message":"busy"}"#
        #expect {
            _ = try FlickrResponse.photoPage(from: Data(json.utf8))
        } throws: { error in
            guard case let FlickrError.api(code, _, transient) = error else { return false }
            return code == 201 && transient
        }
    }

    // MARK: - Variants

    @Test func thereAreElevenDownloadableVariants() {
        #expect(PhotoVariant.allCases.count == 11)
    }

    @Test func everyVariantHasADistinctExtrasFieldAndLabel() {
        #expect(Set(PhotoVariant.allCases.map(\.rawValue)).count == 11)
        #expect(Set(PhotoVariant.allCases.map(\.name)).count == 11)
        #expect(Set(PhotoVariant.allCases.map(\.pixelDescription)).count == 11)
    }

    /// The reference app's `SIZE_OPTIONS`, in its order.
    @Test func variantsAreOfferedLargestLastExactlyAsTheReferenceDid() {
        #expect(PhotoVariant.allCases.map(\.name) == [
            "Square", "Thumbnail", "Small", "Small 320", "Medium", "Medium 640",
            "Medium 800", "Large", "Large 1600", "Large 2048", "Original",
        ])
    }

    @Test func theExtrasListAsksForEveryVariant() {
        for variant in PhotoVariant.allCases {
            #expect(PhotoVariant.extrasParameter.contains(variant.rawValue))
        }
        #expect(PhotoVariant.extrasParameter.contains("license"))
        #expect(PhotoVariant.extrasParameter.contains("owner"))
    }
}
