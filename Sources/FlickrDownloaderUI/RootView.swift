import AppKit
import QuickLook
import SwiftUI

import FlickrKit

/// The window.
public struct RootView: View {
    @Bindable var model: AppModel
    let about: AboutWindowController

    @State private var isShowingDownloadSheet = false

    public init(model: AppModel, about: AboutWindowController) {
        self.model = model
        self.about = about
    }

    public var body: some View {
        NavigationSplitView {
            SourceSidebar(model: model)
        } detail: {
            VStack(spacing: 0) {
                SourceDetailView(model: model, source: model.activeSource)
                DownloadBar(model: model)
            }
            .frame(minWidth: 560, minHeight: 420)
        }
        .inspector(isPresented: $model.isShowingInspector) {
            FilterInspector(model: model, source: model.activeSource)
        }
        .toolbar { toolbar }
        .sheet(isPresented: $model.isShowingOnboarding) {
            CredentialsForm(model: model, isOnboarding: true) {
                model.isShowingOnboarding = false
            }
        }
        .sheet(isPresented: $isShowingDownloadSheet) {
            DownloadSheet(model: model, source: model.activeSource,
                          isPresented: $isShowingDownloadSheet)
        }
        .quickLookPreview($model.previewURL)
        .task {
            // The splash first; whatever should happen after launch happens
            // when it closes, so the order is program order rather than a race
            // between two `.task` modifiers.
            about.showOnLaunchIfWanted {
                if !model.hasAPIKey { model.isShowingOnboarding = true }
            }
        }
        .onChange(of: model.download.completed) { _, _ in updateDockProgress() }
        .onChange(of: model.download.isRunning) { _, _ in updateDockProgress() }
    }

    private var state: SectionState { model.state }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Text(selectionSummary)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityLabel(selectionSummary)
        }

        ToolbarItemGroup {
            Button {
                model.selectAll(in: model.activeSource)
            } label: {
                Label("Select All", systemImage: "checkmark.circle")
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(state.photos.isEmpty)
            .help("Select every photo on this page")

            Button {
                model.clearSelection(in: model.activeSource)
            } label: {
                Label("Deselect", systemImage: "circle.slash")
            }
            .disabled(state.selection.isEmpty)
            .help("Clear the selection")

            Button {
                isShowingDownloadSheet = true
            } label: {
                Label("Download…", systemImage: "arrow.down.circle")
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(state.selection.isEmpty || model.download.isRunning)
            .help("Download the selected photos")

            Button {
                model.isShowingInspector.toggle()
            } label: {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help("Show or hide the filters")
        }
    }

    private var selectionSummary: String {
        let selected = state.selection.count
        guard selected > 0 else {
            return state.photos.isEmpty ? "" : "\(state.photos.count) photos"
        }
        return "\(selected) of \(state.photos.count) selected"
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
