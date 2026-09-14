import SwiftUI

import CaterinaLibrary
import FlickrKit

/// Every way into the account on the left; photos, laid out as chosen; the
/// chosen photo's record beside them.
struct BrowseTab: View {
    let model: AppModel
    @State private var isShowingRecord = true

    private var browse: BrowseModel { model.browse }

    var body: some View {
        NavigationSplitView {
            BrowseSidebar(browse: browse)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            BrowseContent(browse: browse)
                .inspector(isPresented: $isShowingRecord) {
                    RecordPanel(browse: browse, organize: model.organize)
                        .inspectorColumnWidth(min: 320, ideal: 400, max: 560)
                }
        }
        .toolbar {
            ToolbarItemGroup {
                if !browse.scope.isIndex {
                    Picker("Layout", selection: Binding(get: { browse.layout }, set: { browse.layout = $0 })) {
                        ForEach(browse.availableLayouts) { layout in
                            Label(layout.title, systemImage: layout.systemImage).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("List, grid, timeline or map")
                }
                Button { isShowingRecord.toggle() } label: { Label("Photo Record", systemImage: "sidebar.right") }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .help("Show or hide the chosen photo's record (⌥⌘I)")
            }
        }
        .task { await browse.saveStats() }
    }
}

/// The chosen photo's record, or what to do to get one.
struct RecordPanel: View {
    let browse: BrowseModel
    var organize: OrganizeModel?

    var body: some View {
        switch browse.record {
        case .none:
            ContentUnavailableView("Choose a photo", systemImage: "photo",
                                   description: Text("Its views, faves, comments and where it appears."))
        case .loading:
            ProgressView("Reading from Flickr…").frame(maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView("Could not read this photo", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        case let .loaded(record):
            PhotoRecordView(record: record, thumbnailURL: browse.thumbnailURL(for: record.info.id))
                .safeAreaInset(edge: .bottom) {
                    if let organize, record.info.owner.nsid != browse.accountID() {
                        AddToGalleryBar(photoID: record.info.id, directory: browse.directory, organize: organize)
                    }
                }
        }
    }
}
