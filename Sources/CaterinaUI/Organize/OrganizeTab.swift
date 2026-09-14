import SwiftUI

import CaterinaLibrary
import FlickrKit

/// Smart views on the left, photos in the middle, and on the right either
/// the tray with its edit, or the Activity panel.
struct OrganizeTab: View {
    let model: AppModel
    @State private var panel = OrganizePanel.tray
    @State private var isShowingPanel = true
    @State private var draft = EditDraft(kind: .tags)
    /// Captured when the sheet opens, so approval resumes that batch and no
    /// other.
    @State private var permissionRequest: PermissionRequest?

    var body: some View {
        if let organize = model.organize {
            NavigationSplitView {
                OrganizeSidebar(organize: organize)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
            } detail: {
                VStack(spacing: 0) {
                    OrganizeContent(organize: organize)
                    LibraryStatusBar(model: model)
                }
                .inspector(isPresented: $isShowingPanel) {
                    OrganizePanelView(model: model, organize: organize, panel: $panel, draft: $draft)
                        .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
                }
            }
            .toolbar { toolbar(organize) }
            .onChange(of: organize.run) { _, run in
                if case let .needsPermission(permission, batchID) = run {
                    permissionRequest = PermissionRequest(permission: permission, batchID: batchID)
                }
            }
            .sheet(item: $permissionRequest) { request in
                PermissionRequestSheet(model: model, permission: request.permission) {
                    permissionRequest = nil
                    await organize.resume(request.batchID)
                } onCancel: { permissionRequest = nil }
            }
        } else {
            ContentUnavailableView("The library copy could not be opened", systemImage: "externaldrive.badge.exclamationmark",
                                   description: Text("Organize works from the copy of your library on this Mac."))
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ organize: OrganizeModel) -> some ToolbarContent {
        ToolbarItemGroup {
            Button {
                organize.addSelectionToTray()
                panel = .tray
                isShowingPanel = true
            } label: {
                Label("Add to Tray", systemImage: "tray.and.arrow.down")
            }
            .disabled(organize.selection.isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Put the selected photos in the tray (⌘↩)")

            Picker("Panel", selection: $panel) {
                ForEach(OrganizePanel.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("The tray and its edit, or recent edits")

            Button { isShowingPanel.toggle() } label: { Label("Panel", systemImage: "sidebar.right") }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .help("Show or hide the tray (⌥⌘I)")
        }
    }
}

struct PermissionRequest: Identifiable {
    var id: String { batchID }
    let permission: FlickrPermission
    let batchID: String
}

enum OrganizePanel: String, CaseIterable, Identifiable {
    case tray, activity
    var id: String { rawValue }
    var title: String { self == .tray ? "Tray" : "Activity" }
    var systemImage: String { self == .tray ? "tray" : "clock.arrow.circlepath" }
}

/// The header over the photos, and the grid.
struct OrganizeContent: View {
    let organize: OrganizeModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(organize.scope.title).font(.title3.weight(.semibold)).lineLimit(1)
                Text(organize.photos.count.formatted() + (organize.canLoadMore ? "+" : ""))
                    .monospacedDigit().foregroundStyle(Theme.inkSecondary)
                if !organize.selection.isEmpty {
                    Text("· \(organize.selection.count.formatted()) selected").foregroundStyle(Theme.inkSecondary)
                }
                Button(organize.selection.isEmpty ? "Select All" : "Select None") {
                    organize.selection.isEmpty ? organize.selectAll() : organize.clearSelection()
                }
                .buttonStyle(.borderless)
                .disabled(organize.photos.isEmpty)
                Spacer()
                if organize.scope == .notInAlbum { NotInAlbumStatus(organize: organize) }
                if let problem = organize.problem {
                    Label(problem, systemImage: "exclamationmark.triangle").font(.callout)
                        .foregroundStyle(Theme.inkSecondary).lineLimit(2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
            if organize.photos.isEmpty {
                ContentUnavailableView("No photos here", systemImage: organize.scope.systemImage,
                                       description: Text(emptyReason))
            } else {
                OrganizeGrid(organize: organize)
            }
        }
    }

    private var emptyReason: String {
        if organize.scope == .notInAlbum, organize.notInAlbumReadAt == nil {
            return organize.isReadingNotInAlbum ? "Reading from Flickr…" : "Not read from Flickr yet."
        }
        return "Nothing in the library copy matches this view."
    }
}

/// When "not in an album" was read, and reading it again.
struct NotInAlbumStatus: View {
    let organize: OrganizeModel

    var body: some View {
        HStack(spacing: 6) {
            if organize.isReadingNotInAlbum {
                ProgressView().controlSize(.small)
                Text("Reading from Flickr…")
            } else if let readAt = organize.notInAlbumReadAt {
                Text("Read \(readAt.formatted(.relative(presentation: .named)))")
            }
            Button("Read Again") { Task { await organize.refreshNotInAlbum() } }
                .disabled(organize.isReadingNotInAlbum)
                .help("Ask Flickr again which photos are in no album")
        }
        .font(.callout)
        .foregroundStyle(Theme.inkSecondary)
    }
}
