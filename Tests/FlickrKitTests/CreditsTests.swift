import Foundation
import Testing

@testable import FlickrKit

/// The credits written beside a download.
///
/// **The promise this keeps.** The splash reads "Photos off Flickr, with their
/// licences attached" and tells the reader that a Creative Commons licence
/// still asks for attribution — while what used to land on disk was
/// `title_id.jpg` and nothing else, so complying meant finding every photograph
/// on Flickr again by hand.
@Suite struct CreditsTests {

    private func photo(_ id: String = "51234567890") -> Photo {
        Photo(id: id, title: "Harbour at dusk", owner: "12345@N00",
              ownerName: "A Photographer", license: .by,
              variants: [.medium: "https://live.staticflickr.com/m.jpg"])
    }

    private func directory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("credits-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func contents(of directory: URL) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(Credits.filename),
                   encoding: .utf8)
    }

    // MARK: - What a credit has to carry

    @Test func aCreditNamesThePhotographerTheLicenceAndWhereItCameFrom() throws {
        let folder = try directory()
        Credits.write([Credit(file: "Harbour at dusk_51234567890.jpg", photo: photo())],
                      into: folder)

        let text = try contents(of: folder)
        #expect(text.contains("A Photographer"))
        #expect(text.contains("CC BY 2.0"))
        #expect(text.contains("https://creativecommons.org/licenses/by/2.0/"))
        #expect(text.contains("https://www.flickr.com/photos/12345@N00/51234567890"))
        #expect(text.contains("Harbour at dusk_51234567890.jpg"))
    }

    @Test func theFileStartsWithAHeaderSoItOpensAnywhere() throws {
        let folder = try directory()
        Credits.write([Credit(file: "a.jpg", photo: photo())], into: folder)

        let lines = try contents(of: folder).split(separator: "\n")
        #expect(lines.first?.contains("Photographer") == true)
        #expect(lines.first?.contains("Licence") == true)
        #expect(lines.count == 2)
    }

    /// A folder is usually downloaded into more than once.
    @Test func aSecondDownloadAppendsRatherThanReplacing() throws {
        let folder = try directory()
        Credits.write([Credit(file: "a.jpg", photo: photo("1"))], into: folder)
        Credits.write([Credit(file: "b.jpg", photo: photo("2"))], into: folder)

        let lines = try contents(of: folder).split(separator: "\n")
        #expect(lines.count == 3)  // header plus two rows
        #expect(try contents(of: folder).contains("a.jpg"))
        #expect(try contents(of: folder).contains("b.jpg"))
    }

    // MARK: - The title is free text from the internet

    @Test func aTitleWithCommasAndQuotesDoesNotBreakTheFile() throws {
        let folder = try directory()
        let awkward = Photo(id: "9", title: #"Ben, "the dog", at home"#,
                            owner: "1@N1", ownerName: "Someone", license: .bySa)
        Credits.write([Credit(file: "x.jpg", photo: awkward)], into: folder)

        let text = try contents(of: folder)
        #expect(text.contains(#""Ben, ""the dog"", at home""#))
        // Header plus exactly one row: the commas did not become new columns
        // and the quotes did not end the field.
        #expect(text.split(separator: "\n").count == 2)
    }

    @Test func aTitleWithANewlineStaysOnItsOwnRow() {
        let field = Credits.escaped("two\nlines")
        #expect(field.hasPrefix("\""))
        #expect(field.hasSuffix("\""))
    }

    // MARK: - What is not known

    /// A photo whose licence Flickr did not state must say so, not imply one.
    @Test func anUnstatedLicenceIsWrittenAsUnstated() throws {
        let folder = try directory()
        let bare = Photo(id: "7", title: "No licence", owner: "2@N2")
        Credits.write([Credit(file: "n.jpg", photo: bare)], into: folder)

        let text = try contents(of: folder)
        #expect(text.contains("Not stated by Flickr"))
        #expect(!text.contains("CC BY"))
    }

    @Test func aPhotographerWithNoNameFallsBackToTheirIdentifier() {
        let credit = Credit(file: "a.jpg",
                            photo: Photo(id: "1", owner: "99@N99", license: .by))
        #expect(credit.photographer == "99@N99")
    }

    @Test func aPhotoWithNoOwnerAtAllIsStillCredited() {
        let credit = Credit(file: "a.jpg", photo: Photo(id: "1", license: .by))
        #expect(credit.photographer == "Unknown")
        #expect(credit.source.isEmpty)
    }

    @Test func nothingSavedWritesNoFile() throws {
        let folder = try directory()
        Credits.write([], into: folder)
        #expect(!FileManager.default.fileExists(
            atPath: folder.appendingPathComponent(Credits.filename).path))
    }

    /// Credits failing must never fail the download: the photographs are what
    /// was asked for.
    @Test func aFolderThatCannotBeWrittenToIsReportedNotThrown() {
        let problem = Credits.write([Credit(file: "a.jpg", photo: photo())],
                                    into: URL(fileURLWithPath: "/nowhere/at/all"))
        #expect(problem?.isEmpty == false)
    }

    // MARK: - The photo page

    @Test func aPhotoKnowsTheAddressOfItsOwnPage() {
        #expect(photo().pageURL == "https://www.flickr.com/photos/12345@N00/51234567890")
        #expect(Photo(id: "1").pageURL == nil)
    }
}
