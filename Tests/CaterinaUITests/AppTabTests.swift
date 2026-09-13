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

    /// Organize was the last to be built.
    @Test func everyTabIsBuilt() {
        #expect(AppTab.allCases.filter { !$0.isBuilt }.isEmpty)
    }

    @Test func theWindowOpensOnDownload() {
        let model = AppModel(vault: CredentialsVault(store: MemoryStore(seeded: true)),
                             transport: FakeTransport(body: "{}"))
        #expect(model.tab == .download)
        model.tab = .browse
        #expect(model.tab == .browse)
    }
}
