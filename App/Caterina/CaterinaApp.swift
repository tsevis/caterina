import SwiftUI

import CaterinaUI

@main
struct CaterinaApp: App {
    /// Owned here rather than by `RootView` because Settings is a second scene
    /// and has to see the same model — a preferences window editing a different
    /// copy of the credentials than the one the app is using would be worse
    /// than having no preferences window at all.
    @State private var model = AppModel(libraryStore: LibraryModel.openDefaultStore())
    /// Shown once at launch, and again from About Caterina. It carries
    /// the statement about whose photographs these are, which has to live
    /// somewhere findable.
    @State private var about = AboutWindowController()
    /// Holds the quit long enough for a running download to be cancelled
    /// cleanly and reported.
    @NSApplicationDelegateAdaptor(TerminationGuard.self) private var delegate

    var body: some Scene {
        // One window: there is one workspace, and a New that opened a second
        // copy of the same four sources would be a menu item that teaches
        // distrust.
        Window("Caterina", id: "main") {
            RootView(model: model, about: about)
                .onAppear {
                    delegate.beforeQuit = { await model.finishDownloadBeforeClosing() }
                }
        }
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
        // One bar across the top rather than a title bar with a toolbar under
        // it: the window is a grid of pictures and the chrome should take as
        // little of it as the HIG allows.
        .windowToolbarStyle(.unified)
        .commands {
            AppTabCommands(model: model)
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("About Caterina") { about.show() }
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}
