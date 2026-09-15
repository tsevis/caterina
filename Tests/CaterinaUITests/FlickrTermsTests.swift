import Foundation
import Testing

@testable import CaterinaUI

/// Flickr's API terms ask for one sentence, word for word, and for a plain
/// statement of what is collected. Checked everywhere the app describes itself.
@Suite struct FlickrTermsTests {

    static let required = "This product uses the Flickr API but is not endorsed or certified by SmugMug, Inc."

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func theNoticeIsFlickrsWordsExactly() {
        #expect(FlickrTerms.notice == Self.required)
    }

    @Test func aboutShowsTheNoticeAndWhatIsCollected() {
        #expect(AboutView.about.contains(FlickrTerms.notice))
        #expect(AboutView.legal.contains(FlickrTerms.privacy))
    }

    /// GRDB stores the library copy: the credits must not say nothing is linked.
    @Test func theCreditsNameTheLibraryThatIsLinked() {
        #expect(AboutView.legal.contains("GRDB"))
        #expect(!AboutView.legal.contains("No third-party libraries"))
        #expect(AboutView.legal.contains("Copyright (C) 2015-2025 Gwendal Roué"))
        #expect(AboutView.legal.contains("THE SOFTWARE IS PROVIDED \"AS IS\""))
    }

    @Test(arguments: ["App/Caterina/Info.plist", "README.md"])
    func theFilesThatDescribeTheAppCarryTheNotice(_ path: String) throws {
        let text = try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
        #expect(text.contains(Self.required))
    }
}
