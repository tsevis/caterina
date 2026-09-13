import SwiftUI

import CaterinaLibrary
import FlickrKit

/// The inspector: the tray and its edit, or recent edits.
struct OrganizePanelView: View {
    let model: AppModel
    let organize: OrganizeModel
    @Binding var panel: OrganizePanel

    var body: some View {
        switch panel {
        case .tray: TrayPanel(organize: organize) { panel = .activity }
        case .activity: ActivityPanel(model: model, organize: organize)
        }
    }
}

/// What is in the tray, the edit to make, and what it will cost.
struct TrayPanel: View {
    let organize: OrganizeModel
    let onApplied: () -> Void
    @State private var draft = EditDraft(kind: .tags)

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
struct ApplyBar: View {
    let organize: OrganizeModel
    let draft: EditDraft
    let onApplied: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let problem = draft.problem {
                Label(problem, systemImage: "info.circle").foregroundStyle(Theme.inkSecondary)
            } else if let edits = draft.edits {
                let estimate = organize.estimate(edits)
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
            HStack {
                Spacer()
                Button("Apply to Tray") {
                    guard let edits = draft.edits else { return }
                    let title = draft.batchTitle
                    onApplied()
                    Task { await organize.apply(edits, title: title) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canApply)
            }
        }
        .font(.callout)
        .padding(14)
    }

    private var canApply: Bool {
        guard let edits = draft.edits, !organize.isRunning else { return false }
        return organize.estimate(edits).photos > 0
    }
}
