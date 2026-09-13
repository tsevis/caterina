import AppKit
import QuickLook
import SwiftUI

import FlickrKit

/// The Download tab: sources on the left, the grid, filters on the right.
struct DownloadTab: View {
    @Bindable var model: AppModel

    @State private var isShowingDownloadSheet = false

    var body: some View {
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
        .sheet(isPresented: $isShowingDownloadSheet) {
            DownloadSheet(model: model, source: model.activeSource,
                          isPresented: $isShowingDownloadSheet)
        }
        .quickLookPreview($model.previewURL)
    }

    private var state: SectionState { model.state }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            // Beside the buttons it describes. In `.navigation` it shared a
            // slot with the window title and never appeared.
            Text(selectionSummary)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityLabel(selectionSummary.isEmpty
                    ? "Nothing selected" : selectionSummary)

            Button {
                model.selectAll(in: model.activeSource)
            } label: {
                Label("Select All", systemImage: "checkmark.circle")
            }
            // ⇧⌘A, not ⌘A: a plain ⌘A here outranks the focused query field,
            // where it means "select the text I just typed".
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(state.photos.isEmpty)
            .help("Select every photo on this page (⇧⌘A)")

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
}
