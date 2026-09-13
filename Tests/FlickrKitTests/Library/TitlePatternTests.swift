import Foundation
import Testing

@testable import FlickrKit

/// Titles and descriptions written from a pattern, one photo at a time.
@Suite struct TitlePatternTests {

    private let photo = LibraryPhoto(id: "5", title: "IMG_2041", taken: "2024-06-01 21:14:05")
    private let context = PhotoEdit.Context(position: 7, count: 120)

    @Test func eachPlaceholderIsFilledFromThePhotoAndItsPlaceInTheBatch() {
        #expect(TitlePattern.render("{title} · {date} · {year} · {n} of {count}", photo: photo, context: context)
                == "IMG_2041 · 2024-06-01 · 2024 · 7 of 120")
    }

    /// `{nn}` pads to as many digits as the batch needs, so titles sort.
    @Test func paddedNumbersTakeTheWidthOfTheBatch() {
        #expect(TitlePattern.render("Athens {nn}", photo: photo, context: context) == "Athens 007")
        #expect(TitlePattern.render("{nn}", photo: photo, context: .init(position: 3, count: 9)) == "3")
    }

    @Test func aPhotoWithNoDateTakenLeavesItsDateEmpty() {
        #expect(TitlePattern.render("{date}|{year}", photo: LibraryPhoto(id: "1"), context: context) == "|")
    }

    @Test func unknownBracesAreLeftAsTyped() {
        #expect(TitlePattern.render("{place} {n", photo: photo, context: context) == "{place} {n")
    }

    @Test func setAndAppendEditsUseThePattern() {
        #expect(PhotoEdit.setTitle("Harbour {n}").applied(to: photo, context: context).title == "Harbour 7")
        #expect(PhotoEdit.appendToTitle(" · {date}").applied(to: photo, context: context).title
                == "IMG_2041 · 2024-06-01")
        #expect(PhotoEdit.setDescription("{n}/{count}").applied(to: photo, context: context).description == "7/120")
        #expect(PhotoEdit.appendToDescription(" #{n}").applied(to: LibraryPhoto(id: "1", description: "Pier"),
                                                              context: context).description == "Pier #7")
    }

    /// `{title}` is the title before this edit, so appending never doubles it.
    @Test func titleMeansTheTitleBeforeTheEdit() {
        #expect(PhotoEdit.setTitle("{title} (scan)").applied(to: photo, context: context).title == "IMG_2041 (scan)")
    }
}
