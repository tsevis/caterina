import Foundation
import Testing

@testable import FlickrKit

/// Ported from `tests/test_filenames.py`. Every case here was a real defect:
/// titles that collided and overwrote each other, titles long enough that the
/// filesystem refused the write, and titles or ids that walked out of the save
/// directory entirely.
@Suite struct FilenamesTests {

    private let directory = URL(fileURLWithPath: "/tmp/fd-tests", isDirectory: true)

    private func destination(_ title: String, _ id: String,
                             _ url: String = "https://example.com/a.jpg") -> URL {
        Filenames.destination(in: directory, title: title, photoID: id, url: url)
    }

    // MARK: - Uniqueness

    @Test func duplicateTitlesProduceDistinctFilenames() {
        #expect(destination("Untitled", "1") != destination("Untitled", "2"))
    }

    @Test func theSamePhotoAlwaysLandsOnTheSamePath() {
        #expect(destination("Sunset", "42") == destination("Sunset", "42"))
    }

    @Test func thePhotoIDIsAlwaysInTheFilename() {
        #expect(destination("Sunset", "51234567890").lastPathComponent.contains("51234567890"))
    }

    @Test func anEmptyTitleFallsBackRatherThanProducingABareExtension() {
        for title in ["", "   ", "///", "..."] {
            let name = destination(title, "9").lastPathComponent
            #expect(name.hasPrefix("photo"))
            #expect(name.contains("9"))
        }
    }

    // MARK: - Length

    @Test(arguments: [50, 200, 500, 5000])
    func longTitlesStayWritable(length: Int) {
        let name = destination(String(repeating: "a", count: length), "1").lastPathComponent
        #expect(name.utf8.count <= Filenames.maxBasenameBytes)
    }

    @Test func longTitlesAreStillUnique() {
        let title = String(repeating: "b", count: 1000)
        #expect(destination(title, "1") != destination(title, "2"))
    }

    /// A budget counted in characters truncated mid-sequence and produced a
    /// name the filesystem rejected; it is counted in UTF-8 bytes.
    @Test func multibyteTitlesRespectTheByteLimit() {
        for title in [String(repeating: "δ", count: 300),
                      String(repeating: "🙂", count: 300),
                      String(repeating: "日", count: 300)] {
            let name = destination(title, "1").lastPathComponent
            #expect(name.utf8.count <= Filenames.maxBasenameBytes)
            // Truncation must not leave a replacement character behind.
            #expect(!name.contains("\u{FFFD}"))
        }
    }

    @Test func aLongIDDoesNotBlowTheBudget() {
        let name = destination("Title", String(repeating: "7", count: 400)).lastPathComponent
        #expect(name.utf8.count <= Filenames.maxBasenameBytes)
    }

    @Test func aLongIDAndALongTitleTogetherStillFit() {
        let name = destination(String(repeating: "t", count: 900),
                               String(repeating: "9", count: 900)).lastPathComponent
        #expect(name.utf8.count <= Filenames.maxBasenameBytes)
    }

    // MARK: - Traversal

    @Test(arguments: ["../../etc/passwd", "/etc/passwd", "..", ".", "a/b/c",
                      "..\\..\\windows", "x\u{0000}y"])
    func titlesCannotEscapeTheSaveDirectory(title: String) {
        let path = destination(title, "1")
        #expect(path.deletingLastPathComponent().standardizedFileURL
            == directory.standardizedFileURL)
        #expect(!path.lastPathComponent.contains("/"))
    }

    @Test(arguments: ["../../etc/passwd", "/tmp/evil", "..", "a/b", "x\u{0000}y"])
    func hostileIDsCannotEscapeTheSaveDirectoryEither(id: String) {
        let path = destination("Title", id)
        #expect(path.deletingLastPathComponent().standardizedFileURL
            == directory.standardizedFileURL)
    }

    /// Stripping characters would map `12/3` and `123` onto one name, so an id
    /// that sanitising changes is hashed rather than cleaned.
    @Test func idsDifferingOnlyByStrippedCharactersDoNotCollide() {
        #expect(destination("T", "12/3") != destination("T", "123"))
        #expect(destination("T", "1.2") != destination("T", "12"))
    }

    @Test func pathologicalIDsStayUniqueAmongThemselves() {
        let ids = ["../a", "..\\a", "a/../b", "a", "a ", " a", "a/b", "a.b"]
        let names = Set(ids.map { destination("T", $0).lastPathComponent })
        #expect(names.count == ids.count)
    }

    /// The common case must stay readable — a hash for every photo would make
    /// the download folder unusable.
    @Test func ordinaryFlickrIDsStayHumanReadable() {
        #expect(destination("Harbour", "51234567890").lastPathComponent
            == "Harbour_51234567890.jpg")
    }

    /// Reserved on Windows and merely odd on macOS; the appended id means none
    /// of them is ever bare.
    @Test(arguments: ["CON", "PRN", "AUX", "NUL", "COM1", "LPT1"])
    func windowsReservedNamesAreNeverBare(reserved: String) {
        let name = destination(reserved, "5").deletingPathExtension().lastPathComponent
        #expect(name != reserved)
    }

    // MARK: - Extensions

    @Test(arguments: [
        ("https://example.com/a.jpg", "jpg"),
        ("https://example.com/a.JPEG", "jpeg"),
        ("https://example.com/a.png", "png"),
        ("https://example.com/a.gif", "gif"),
        ("https://example.com/a.webp", "jpg"),
        ("https://example.com/a.php?x=.png", "jpg"),
        ("https://example.com/a", "jpg"),
        ("https://example.com/a.jpg?size=big#frag", "jpg"),
        ("", "jpg"),
    ])
    func extensionsAreAllowListed(url: String, expected: String) {
        #expect(Filenames.fileExtension(for: url) == expected)
    }

    // MARK: - Sanitising

    @Test func sanitisingStripsSeparatorsAndCollapsesWhitespace() {
        #expect(Filenames.sanitize(title: "a/b\\c:d") == "abcd")
        #expect(Filenames.sanitize(title: "  spaced   out  ") == "spaced out")
        #expect(Filenames.sanitize(title: "keep-these_ones 1") == "keep-these_ones 1")
        #expect(Filenames.sanitize(title: "dots.are.dropped") == "dotsaredropped")
    }

    @Test func sanitisingKeepsLettersFromAnyScript() {
        #expect(Filenames.sanitize(title: "Ελλάδα 2024") == "Ελλάδα 2024")
    }

    @Test func aPartialPathSitsBesideItsDestination() {
        let final = destination("Harbour", "1")
        #expect(Filenames.partial(for: final).lastPathComponent
            == final.lastPathComponent + ".part")
    }
}
