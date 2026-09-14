import SwiftUI

import CaterinaLibrary
import FlickrKit

/// The inspector: the tray and its edit, or recent edits.
struct OrganizePanelView: View {
    let model: AppModel
    let organize: OrganizeModel
    @Binding var panel: OrganizePanel

    @Binding var draft: EditDraft
    let shareToGroups: () -> Void

    var body: some View {
        switch panel {
        case .tray: TrayPanel(organize: organize, draft: $draft, shareToGroups: shareToGroups) { panel = .activity }
        case .activity: ActivityPanel(organize: organize)
        }
    }
}

/// What is in the tray, the edit to make, and what it will cost.
struct TrayPanel: View {
    let organize: OrganizeModel
    /// Held by the tab, so going to Activity and back keeps what was typed.
    @Binding var draft: EditDraft
    var shareToGroups: () -> Void = {}
    let onApplied: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if organize.tray.isEmpty {
                ContentUnavailableView("The tray is empty", systemImage: "tray",
                                       description: Text("Select photos and choose Add to Tray (⌘↩). "
                                                         + "The tray keeps them while you look elsewhere."))
            } else {
                TrayStrip(organize: organize).frame(height: 96)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Edit", selection: kind) {
                            ForEach(EditKind.allCases) { Text($0.title).tag($0) }
                        }
                        EditForm(draft: $draft)
                        Divider()
                        TrayAlbumSection(organize: organize)
                        Divider()
                        Text("Groups").font(.subheadline.weight(.semibold))
                        Button("Share to Groups…", action: shareToGroups)
                        .disabled(organize.isRunning)
                    }
                    .padding(14)
                }
                Divider()
                ApplyBar(organize: organize, draft: draft, onApplied: onApplied)
            }
        }
    }

    /// A new kind starts from a blank form, so nothing typed for tags leaks
    /// into a title.
    private var kind: Binding<EditKind> {
        Binding(get: { draft.kind }, set: { draft = EditDraft(kind: $0) })
    }

    private var header: some View {
        HStack {
            Text("Tray").font(.headline)
            Text(organize.tray.count.formatted()).monospacedDigit().foregroundStyle(Theme.inkSecondary)
            Spacer()
            Button("Clear") { organize.clearTray() }
                .disabled(organize.tray.isEmpty || organize.isRunning)
            DeleteTrayButton(organize: organize)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// The tray's photos in a row; each can be taken out.
struct TrayStrip: View {
    let organize: OrganizeModel

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 6) {
                ForEach(organize.trayPhotos) { photo in
                    RowThumbnail(address: photo.thumbnailURL, size: 72)
                        .overlay(alignment: .topTrailing) {
                            Button { organize.removeFromTray([photo.id]) } label: {
                                Image(systemName: "xmark.circle.fill").symbolRenderingMode(.hierarchical)
                            }
                            .buttonStyle(.borderless)
                            .padding(2)
                            .accessibilityLabel("Remove \(photo.title.isEmpty ? "untitled photo" : photo.title) from the tray")
                        }
                        .help(photo.title.isEmpty ? "Untitled" : photo.title)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }
}

/// The cost, what cannot be undone, and the button.
///
/// **No default-button shortcut.** Return in a tag or latitude field would
/// otherwise send the batch to every photo in the tray.
struct ApplyBar: View {
    let organize: OrganizeModel
    let draft: EditDraft
    let onApplied: () -> Void
    @State private var isConfirming = false

    /// Past this many photos, Apply asks first.
    static let confirmAbove = 20

    var body: some View {
        // Once per drawing: it walks every photo in the tray.
        let estimate = draft.kind.isAction ? draft.action.map { organize.estimate(action: $0) }
                                            : draft.edits.map { organize.estimate($0) }
        VStack(alignment: .leading, spacing: 8) {
            if let problem = draft.problem {
                Label(problem, systemImage: "info.circle").foregroundStyle(Theme.inkSecondary)
            } else if let estimate {
                EstimateLines(estimate: estimate)
            }
            HStack {
                Spacer()
                Button("Apply to Tray") {
                    if let estimate, estimate.photos > Self.confirmAbove { isConfirming = true } else { apply() }
                }
                .disabled(organize.isRunning || (estimate?.photos ?? 0) == 0)
            }
        }
        .font(.callout)
        .padding(14)
        .confirmationDialog("Change \(estimate?.photos.formatted() ?? "") photos on Flickr?",
                            isPresented: $isConfirming) {
            Button("Change \(estimate?.photos.formatted() ?? "") Photos") { apply() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(draft.batchTitle). \(estimate?.summary ?? ""). You can undo it from Activity.")
        }
    }

    private func apply() {
        let (draft, organize) = (self.draft, self.organize)
        let title = draft.batchTitle
        switch (draft.kind, draft.action, draft.edits) {
        case (.people, _, _):
            onApplied()
            Task { await organize.tagPerson(draft.personQuery, removing: draft.removesPerson, title: title) }
        case let (_, action?, _):
            onApplied()
            Task { await organize.perform(action, title: title) }
        case let (_, _, edits?):
            onApplied()
            Task { await organize.apply(edits, title: title) }
        default:
            return
        }
    }
}

struct EstimateLines: View {
    let estimate: EditEstimate

    var body: some View {
        Text(estimate.photos == 0 ? "No photo in the tray would change." : estimate.summary)
            .monospacedDigit()
        if estimate.unchanged > 0 {
            Text("\(estimate.unchanged.formatted()) already as asked, left alone.")
                .foregroundStyle(Theme.inkSecondary)
        }
        if !estimate.unrestorable.isEmpty {
            Label("Undo cannot restore the \(estimate.unrestorable.joined(separator: ", ")): "
                  + "Flickr does not say what it was.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}

/// Deleting is apart from every other edit: its own button, its own
/// question naming the count, and Flickr's own permission.
struct DeleteTrayButton: View {
    let organize: OrganizeModel
    @State private var isConfirming = false

    var body: some View {
        Button(role: .destructive) { isConfirming = true } label: { Image(systemName: "trash") }
            .disabled(organize.tray.isEmpty || organize.isRunning)
            .help("Delete the photos in the tray from Flickr")
            .confirmationDialog("Delete \(OrganizeModel.count(organize.tray.count)) from Flickr?",
                                isPresented: $isConfirming) {
                Button("Delete \(OrganizeModel.count(organize.tray.count))", role: .destructive) {
                    Task { await organize.deleteTray() }
                }
            } message: {
                Text("This cannot be undone, here or on flickr.com. Their views, faves, comments and places "
                     + "in albums and groups go with them. Flickr asks you to allow deleting first.")
            }
    }
}
