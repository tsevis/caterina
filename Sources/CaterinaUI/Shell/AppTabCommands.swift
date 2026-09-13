import SwiftUI

/// ⌘1 to ⌘4, in the View menu, so the tabs are reachable from the keyboard and
/// discoverable from the menu bar.
public struct AppTabCommands: Commands {
    let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some Commands {
        CommandGroup(before: .toolbar) {
            ForEach(AppTab.allCases) { tab in
                Button(tab.title) { model.tab = tab }
                    .keyboardShortcut(KeyEquivalent(tab.shortcut), modifiers: .command)
            }
            Divider()
        }
    }
}
