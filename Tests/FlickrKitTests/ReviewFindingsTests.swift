import Foundation
import Testing

@testable import FlickrKit

/// Defects found in review, each pinned before it was fixed.
@Suite struct ReviewFindingsTests {

    private func photo(_ variants: PhotoVariant...) -> Photo {
        Photo(id: "1", variants: Dictionary(uniqueKeysWithValues:
            variants.map { ($0, "https://live.staticflickr.com/\($0.rawValue).jpg") }))
    }

    // MARK: - A fallback downgrades; it does not upgrade

    /// Asking for Small 320 and getting the Original is not a fallback, it is a
    /// different download — and on three hundred photos it is gigabytes the
    /// user did not ask for.
    @Test func anAbsentSizeFallsBackDownwardNotUpward() {
        let big = photo(.original, .large, .medium, .small)
        #expect(big.downloadURL(preferring: .small320) == big.url(for: .small))
        #expect(big.downloadURL(preferring: .large1600) == big.url(for: .large))
        #expect(big.downloadURL(preferring: .original) == big.url(for: .original))
    }

    /// Only when nothing smaller exists is a larger file better than no file.
    @Test func aPhotoWithOnlyLargerVariantsStillDownloads() {
        let large = photo(.original, .large2048)
        #expect(large.downloadURL(preferring: .small) == large.url(for: .large2048))
    }

    @Test func theExactSizeIsAlwaysPreferred() {
        let all = photo(.original, .large, .medium, .small320, .square)
        for variant in [PhotoVariant.original, .large, .medium, .small320, .square] {
            #expect(all.downloadURL(preferring: variant) == all.url(for: variant))
        }
    }

    // MARK: - Thumbnails the grid can actually use

    /// The smallest variant is the 75×75 square, and every photo has one — so
    /// "smallest" meant every tile in a 128pt grid was a 75px image scaled up.
    @Test func theGridAsksForSomethingBiggerThanASquareThumbnail() {
        let full = photo(.square, .thumbnail, .small, .small320, .medium, .original)
        #expect(full.gridThumbnailURL() == full.url(for: .small320))
    }

    @Test func aPhotoWithOnlyASquareStillShowsSomething() {
        let poor = photo(.square)
        #expect(poor.gridThumbnailURL() == poor.url(for: .square))
        #expect(Photo(id: "x").gridThumbnailURL() == nil)
    }

    // MARK: - Variant URLs are remote data

    @Test func aVariantURLThatIsNotHTTPSIsNotFetched() throws {
        let page = try FlickrResponse.photoPage(from: Data("""
        {"photos":{"page":1,"pages":1,"perpage":25,"total":1,"photo":[
          {"id":"1","url_o":"file:///etc/passwd","url_l":"http://example.com/l.jpg",
           "url_m":"https://live.staticflickr.com/m.jpg","url_s":"javascript:alert(1)"}
        ]},"stat":"ok"}
        """.utf8))
        let photo = try #require(page.photos.first)
        #expect(photo.url(for: .original) == nil)
        #expect(photo.url(for: .large) == nil)
        #expect(photo.url(for: .small) == nil)
        #expect(photo.url(for: .medium) == "https://live.staticflickr.com/m.jpg")
    }

    // MARK: - Page size keeps the position without inventing a page

    /// 25 a page on page 120, switched to 500 a page: page 120 of 500 is past
    /// the end of the results, and asking Flickr for it returns nothing at all.
    @Test func changingThePageSizeCannotLandPastTheEnd() {
        let state = SectionState(source: .search)
            .loaded(PhotoPage(page: 120, pages: 160, perPage: 25, total: 4000,
                              photos: [Photo(id: "1")]))
        #expect(state.page == 120)

        let bigger = state.with(perPage: 500)
        #expect(bigger.perPage == 500)
        #expect(bigger.page <= bigger.totalPages)
        #expect(bigger.totalPages == 8)
    }

    /// Position, not page number: item 2976 of 4000 is on page 6 at 500 a page.
    @Test func changingThePageSizeKeepsRoughlyTheSamePlaceInTheResults() {
        let state = SectionState(source: .search)
            .loaded(PhotoPage(page: 120, pages: 160, perPage: 25, total: 4000,
                              photos: [Photo(id: "1")]))
        #expect(state.with(perPage: 500).page == 6)
        #expect(state.with(perPage: 25).page == 120)
    }

    @Test func aSourceRemembersHowManyPhotosFlickrSaidThereWere() {
        let state = SectionState(source: .search)
            .loaded(PhotoPage(page: 1, pages: 4, perPage: 25, total: 97,
                              photos: [Photo(id: "1")]))
        #expect(state.total == 97)
    }

    // MARK: - A stale page count must not arm the Next button

    /// The old query had 160 pages. While the new one is still loading, Next
    /// was live — and pressed, it fetched page 2 of a query whose page 1 had
    /// not arrived.
    @Test func startingANewQueryForgetsTheOldPageCount() {
        let state = SectionState(source: .search)
            .loaded(PhotoPage(page: 1, pages: 160, perPage: 25, total: 4000,
                              photos: [Photo(id: "1")]))
        #expect(state.canGoForward)

        let restarted = state.beginning(query: .search(text: "new"))
        #expect(restarted.totalPages == 1)
        #expect(!restarted.canGoForward)
        #expect(restarted.total == 0)

        let resolving = state.resolving()
        #expect(!resolving.canGoForward)
    }

    /// Under an error screen with no photos, "Page 4 of 160" is a claim about
    /// results that are not there.
    @Test func aFailureLeavesNoPagesToWalkForwardInto() {
        let state = SectionState(source: .search)
            .loaded(PhotoPage(page: 4, pages: 160, perPage: 25, total: 4000,
                              photos: [Photo(id: "1")]))
            .failed(.notFound("gone"))
        #expect(!state.canGoForward)
    }

    // MARK: - Labels that agree with what they select

    /// The Large bucket contains `url_l`, whose longest edge is 1024 — so a
    /// label reading "1025px and above" described a photo it had just put in
    /// the other bucket.
    @Test func theSizeLabelsMatchTheVariantsTheyActuallyCover() {
        #expect(SizeBucket.large.label.contains("1024"))
        #expect(SizeBucket.medium.label.contains("1023"))
        #expect(SizeBucket.large.variants.contains(.large))
    }
}

/// Findings from the adversarial security audit, each pinned before it was
/// fixed.
@Suite struct SecurityFindingsTests {

    // MARK: - A reply does not get to name its own host

    @Test func onlyFlickrsOwnHostsAreFetchedFrom() throws {
        let page = try FlickrResponse.photoPage(from: Data("""
        {"photos":{"page":1,"pages":1,"perpage":25,"total":1,"photo":[
          {"id":"1",
           "url_o":"https://evil.example.com/o.jpg",
           "url_l":"https://staticflickr.com.evil.test/l.jpg",
           "url_m":"https://live.staticflickr.com/1/m.jpg",
           "url_s":"https://www.flickr.com/s.jpg"}
        ]},"stat":"ok"}
        """.utf8))
        let photo = try #require(page.photos.first)

        #expect(photo.url(for: .original) == nil)
        // A host that merely *ends with* something Flickr-shaped is not Flickr.
        #expect(photo.url(for: .large) == nil)
        #expect(photo.url(for: .medium) != nil)
        #expect(photo.url(for: .small) != nil)
    }

    // MARK: - Writing where something may be waiting

    /// The finding: Quick Look wrote to a fully predictable path — Flickr photo
    /// ids are public — with a plain `Data.write(to:)`. A hostile local process
    /// could pre-plant a symlink there and have the app overwrite whatever it
    /// pointed at.
    @Test func aWriteRefusesToFollowASymlink() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("safefile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let victim = folder.appendingPathComponent("victim.txt")
        try Data("original".utf8).write(to: victim)
        let planted = folder.appendingPathComponent("predictable.jpg")
        try FileManager.default.createSymbolicLink(at: planted, withDestinationURL: victim)

        #expect(throws: (any Error).self) {
            try SafeFile.write(Data("attacker bytes".utf8), to: planted)
        }
        #expect(try String(contentsOf: victim, encoding: .utf8) == "original")
    }

    @Test func anExclusiveWriteRefusesAFileThatIsAlreadyThere() throws {
        let folder = try SafeFile.uniqueDirectory(
            in: URL(fileURLWithPath: NSTemporaryDirectory()), prefix: "safefile-")
        let file = folder.appendingPathComponent("once.jpg")

        try SafeFile.write(Data("first".utf8), to: file)
        #expect(throws: (any Error).self) {
            try SafeFile.write(Data("second".utf8), to: file)
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "first")
    }

    /// A `.part` file left by a crashed run has to be overwritable, which is
    /// why the download path is the one that truncates.
    @Test func aTruncatingWriteReplacesItsOwnLeftovers() throws {
        let folder = try SafeFile.uniqueDirectory(
            in: URL(fileURLWithPath: NSTemporaryDirectory()), prefix: "safefile-")
        let file = folder.appendingPathComponent("stale.part")
        try SafeFile.write(Data("stale".utf8), to: file)

        let handle = try SafeFile.openTruncating(at: file)
        try handle.write(contentsOf: Data("fresh".utf8))
        try handle.close()
        #expect(try String(contentsOf: file, encoding: .utf8) == "fresh")
    }

    @Test func aUniqueDirectoryIsPrivateAndUnpredictable() throws {
        let parent = URL(fileURLWithPath: NSTemporaryDirectory())
        let first = try SafeFile.uniqueDirectory(in: parent, prefix: "drag-")
        let second = try SafeFile.uniqueDirectory(in: parent, prefix: "drag-")
        #expect(first != second)

        let mode = try FileManager.default.attributesOfItem(atPath: first.path)[.posixPermissions]
        #expect(mode as? Int == 0o700)
    }
}
