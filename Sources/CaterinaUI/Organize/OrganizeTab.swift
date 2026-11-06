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
    @State private var groupShare: GroupShareModel?
    @State private var searchText = ""

    var body: some View {
        if let organize = model.organize {
            NavigationSplitView {
                OrganizeSidebar(organize: organize)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
            } detail: {
                OrganizeContent(organize: organize)
                .inspector(isPresented: $isShowingPanel) {
                    OrganizePanelView(model: model, organize: organize, panel: $panel, draft: $draft) {
                        groupShare = GroupShareModel(organize: organize, directory: model.groupDirectory)
                    }
                        .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
                }
            }
            .toolbar { toolbar(organize) }
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search your photos")
            .task(id: searchText) {
                // A pause in typing, not every keystroke.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await organize.search(searchText)
            }
            .onChange(of: organize.scope) { _, scope in
                if case .search = scope {} else if !searchText.isEmpty { searchText = "" }
            }
            .onChange(of: organize.run) { _, run in
                if case let .needsPermission(permission, batchID) = run {
                    permissionRequest = PermissionRequest(permission: permission, batchID: batchID)
                }
            }
            .modifier(UndoRequestDialog(organize: organize))
            .sheet(item: $groupShare) { share in
                GroupShareSheet(share: share, onClose: { groupShare = nil }, onAdded: {
                    groupShare = nil
                    showActivity()
                })
            }
            .onChange(of: organize.pendingGroupSubjects) { _, subjects in
                guard let subjects else { return }
                organize.pendingGroupSubjects = nil
                guard !subjects.isEmpty else { return }
                groupShare = GroupShareModel(organize: organize, directory: model.groupDirectory, subjects: subjects)
            }
            .onChange(of: organize.prefersActivityPanel, initial: true) { _, prefers in
                guard prefers else { return }
                organize.prefersActivityPanel = false
                showActivity()
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

    private func showActivity() {
        panel = .activity
        isShowingPanel = true
    }

    @ToolbarContentBuilder
    private func toolbar(_ organize: OrganizeModel) -> some ToolbarContent {
        ToolbarItemGroup {
            Button {
                organize.pendingGroupSubjects = organize.groupSubjectsForToolbar
            } label: {
                Label("Add to Groups", systemImage: "person.3").labelStyle(.titleAndIcon)
            }
            .disabled((organize.selection.isEmpty && organize.tray.isEmpty) || organize.isBusy)
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .help("Add the selected photos, or the tray, to your groups (⇧⌘G)")

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
                Text(organize.photos.count.formatted())
                    .monospacedDigit().foregroundStyle(Theme.inkSecondary)
                Button(organize.selection.isEmpty ? "Select All" : "Select None") {
                    organize.selection.isEmpty ? organize.selectAll() : organize.clearSelection()
                }
                .buttonStyle(.borderless)
                .disabled(organize.photos.isEmpty)
                Button("Add All \(organize.viewCount.formatted()) to Tray") {
                    Task { await organize.addEntireViewToTray() }
                }
                .buttonStyle(.borderless)
                .disabled(organize.viewCount == 0)
                .help("Every photo in this view")
                if case let .tag(tag) = organize.scope { RemoveTagEverywhereButton(organize: organize, tag: tag) }
                Spacer()
                if organize.canSort { OrganizeSortMenu(organize: organize) }
                if organize.scope.albumID != nil { AlbumActions(organize: organize) }
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
                OrganizeChoiceBar(organize: organize)
                Divider()
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

extension GroupShareModel: Identifiable {
    public nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
