import AppKit
import SwiftUI
import UniformTypeIdentifiers

import CaterinaLibrary
import FlickrKit

/// Drop photos, check what they go with, send.
struct UploadTab: View {
    let model: AppModel
    @State private var isShowingSettings = true
    @State private var isTargeted = false

    private var uploads: UploadModel { model.uploads }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .dropDestination(for: URL.self) { urls, _ in
                    Task { await uploads.add(urls) }
                    return !urls.isEmpty
                } isTargeted: { isTargeted = $0 }
                .overlay { if isTargeted { dropHighlight } }
            UploadStatusBar(model: model)
        }
        .inspector(isPresented: $isShowingSettings) {
            UploadSettingsPanel(uploads: uploads)
                .inspectorColumnWidth(min: 240, ideal: Theme.Metrics.inspectorWidth, max: 340)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { chooseFiles() } label: { Label("Add Photos…", systemImage: "plus") }
                    .keyboardShortcut("o", modifiers: .command)
                    .help("Choose photos or folders to upload (⌘O)")
                Button { isShowingSettings.toggle() } label: {
                    Label("Upload Settings", systemImage: "slider.horizontal.3")
                }
                .help("Show or hide who can see the photos and which album they go in")
            }
        }
        .task { await uploads.loadAlbums() }
    }

    @ViewBuilder
    private var content: some View {
        if uploads.phase == .unavailable {
            ContentUnavailableView("Uploads are unavailable", systemImage: "exclamationmark.triangle",
                                   description: Text("The upload queue could not be opened on this Mac."))
        } else if uploads.activeBatchID != nil {
            UploadProgressList(uploads: uploads)
        } else if uploads.drafts.isEmpty {
            ContentUnavailableView {
                Label("Drop photos here", systemImage: "arrow.up.circle")
            } description: {
                Text("Photos and folders. Titles, captions and keywords already in the files come along.")
            } actions: {
                Button("Add Photos…") { chooseFiles() }
            }
        } else {
            UploadDraftTable(uploads: uploads)
        }
    }

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius)
            .strokeBorder(Theme.mark, lineWidth: 3)
            .padding(6)
            .allowsHitTesting(false)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.image, .movie]
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { await uploads.add(urls) }
    }
}

/// The files waiting to go, with their title and tags editable in place.
struct UploadDraftTable: View {
    let uploads: UploadModel
    @State private var selection = Set<URL>()

    var body: some View {
        Table(uploads.drafts, selection: $selection) {
            TableColumn("File") { draft in
                Text(draft.file.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(draft.file.path)
            }
            .width(min: 120, ideal: 180)
            TableColumn("Title") { draft in
                TextField("Title", text: Binding(get: { draft.title },
                                                 set: { uploads.update(draft.id, title: $0) }))
                    .labelsHidden()
            }
            TableColumn("Tags") { draft in
                TagsField(tags: draft.tags) { uploads.update(draft.id, tags: $0) }
            }
            TableColumn("Place") { draft in
                Image(systemName: draft.fileMetadata.location == nil ? "" : "location.fill")
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityLabel(draft.fileMetadata.location == nil ? "No location" : "Has a location")
            }
            .width(44)
        }
        .onDeleteCommand { uploads.remove(selection) }
    }
}

/// The typed text stays the field's own while it is being edited — parsing
/// half a quoted tag back into it would drop the quote from under the cursor —
/// but every change reaches the draft at once, so ⌘↩ straight after typing
/// sends what was typed.
struct TagsField: View {
    let tags: [String]
    let commit: (String) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Tags", text: $text)
            .labelsHidden()
            .focused($isFocused)
            .onAppear { text = UploadMetadata.tagList(tags) }
            .onChange(of: text) { _, typed in if isFocused { commit(typed) } }
            .onChange(of: tags) { _, new in if !isFocused { text = UploadMetadata.tagList(new) } }
    }
}
