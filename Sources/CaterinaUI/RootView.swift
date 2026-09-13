import AppKit
import SwiftUI

import FlickrKit

/// The window: four tabs over one library.
///
/// What belongs to the window rather than to a tab lives here — the key sheet,
/// the launch sequence, and the Dock badge, which has to keep counting while
/// a download runs behind another tab.
public struct RootView: View {
    @Bindable var model: AppModel
    let about: AboutWindowController

    public init(model: AppModel, about: AboutWindowController) {
        self.model = model
        self.about = about
    }

    public var body: some View {
        content
            .background(WindowConfigurator(autosaveName: "CaterinaMain",
                                           minimum: NSSize(width: 820, height: 560)))
            .toolbar {
                ToolbarItem(placement: .principal) { tabPicker }
            }
            .sheet(isPresented: $model.isShowingOnboarding) {
                CredentialsForm(model: model, isOnboarding: true) {
                    model.isShowingOnboarding = false
                }
            }
            .task {
                // The splash first; whatever should happen after launch happens
                // when it closes, so the order is program order rather than a race
                // between two `.task` modifiers.
                // Last session's previews and drag promises, which nothing could
                // delete at the time.
                TemporaryFiles.sweep()

                about.showOnLaunchIfWanted {
                    if !model.hasAPIKey { model.isShowingOnboarding = true }
                }
            }
            .onChange(of: model.download.completed) { _, _ in updateDockProgress() }
            .onChange(of: model.download.isRunning) { _, _ in updateDockProgress() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.tab {
        case .download: DownloadTab(model: model)
        case .upload, .organize, .browse: PlannedTabView(tab: model.tab)
        }
    }

    private var tabPicker: some View {
        Picker("Tab", selection: $model.tab) {
            ForEach(AppTab.allCases) { tab in
                Text(tab.title)
                    .help("\(tab.purpose) (⌘\(String(tab.shortcut)))")
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    /// A badge rather than a drawn progress bar: the Dock tile is 128 points
    /// wide and "12/40" is legible at that size where a bar is not.
    private func updateDockProgress() {
        let tile = NSApp.dockTile
        if model.download.isRunning {
            tile.badgeLabel = "\(model.download.completed)/\(model.download.total)"
        } else {
            tile.badgeLabel = nil
        }
        tile.display()
    }
}
