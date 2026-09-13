import AppKit
import SwiftUI
import Testing

import FlickrKit
@testable import CaterinaUI

/// The four tabs across the top of the window.
@MainActor
@Suite struct AppTabTests {

    @Test func theTabsAreInTheOrderTheToolbarShowsThem() {
        #expect(AppTab.allCases == [.download, .upload, .organize, .browse])
    }

    /// ⌘1 to ⌘4, left to right, as every tabbed Mac window does it.
    @Test func eachTabIsCommandAndItsPosition() {
        #expect(AppTab.allCases.map(\.shortcut) == ["1", "2", "3", "4"])
    }

    @Test func everyTabHasANameAnIconAndSaysWhatItIsFor() {
        for tab in AppTab.allCases {
            #expect(!tab.title.isEmpty)
            #expect(NSImage(systemSymbolName: tab.systemImage, accessibilityDescription: nil) != nil,
                    "\(tab.systemImage) is not an SF Symbol")
            #expect(!tab.purpose.isEmpty)
        }
        #expect(Set(AppTab.allCases.map(\.title)).count == AppTab.allCases.count)
    }

    /// Only Download is built. The others must say so rather than show an
    /// empty grid that looks broken.
    @Test func downloadAndUploadAreBuiltSoFar() {
        #expect(AppTab.allCases.filter(\.isBuilt) == [.download, .upload])
    }

    @Test func theWindowOpensOnDownload() {
        let model = AppModel(vault: CredentialsVault(store: MemoryStore(seeded: true)),
                             transport: FakeTransport(body: "{}"))
        #expect(model.tab == .download)
        model.tab = .browse
        #expect(model.tab == .browse)
    }

    @Test(arguments: AppTab.allCases.filter { !$0.isBuilt })
    func anUnbuiltTabIsDrawnAsWhatIsComing(tab: AppTab) throws {
        let renderer = ImageRenderer(content:
            PlannedTabView(tab: tab)
                .frame(width: 640, height: 420)
                .background(Color(nsColor: .windowBackgroundColor)))
        let image = try #require(renderer.nsImage)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var seen = Set<String>()
        for x in stride(from: 20, to: bitmap.pixelsWide - 20, by: 12) {
            for y in stride(from: 20, to: bitmap.pixelsHigh - 20, by: 12) {
                guard let colour = bitmap.colorAt(x: x, y: y) else { continue }
                seen.insert(String(format: "%.2f", colour.brightnessComponent))
            }
        }
        #expect(seen.count > 2)
    }
}
