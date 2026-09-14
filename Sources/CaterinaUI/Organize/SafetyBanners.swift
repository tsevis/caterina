import SwiftUI

import CaterinaLibrary
import FlickrKit

/// A delete counting down, or the edit that just finished, each with its way back.
struct SafetyBanners: View {
    let organize: OrganizeModel

    var body: some View {
        if let pending = organize.pendingDelete {
            PendingDeleteBanner(organize: organize, pending: pending)
        } else if let last = organize.lastEdit, !organize.isBusy {
            banner {
                Label("“\(last.batch.title)” is done.", systemImage: "checkmark.circle").lineLimit(2)
                Spacer()
                Button("Undo") { Task { await organize.undo(last.id) } }
                    .help("Put back what Flickr had before this edit")
                Button { organize.dismissLastEdit() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Dismiss")
            }
        }
    }
}

/// Counts down to the delete; until then nothing has been sent.
private struct PendingDeleteBanner: View {
    let organize: OrganizeModel
    let pending: PendingDelete

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(pending.deadline.timeIntervalSince(context.date).rounded(.up)))
            banner {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Deleting \(OrganizeModel.count(pending.photoIDs.count)) in \(seconds)s…",
                          systemImage: "trash")
                        .monospacedDigit()
                        .foregroundStyle(.red)
                    HStack {
                        Spacer()
                        Button("Keep Photos") { organize.cancelPendingDelete() }
                            .help("Take back the delete. Nothing has been sent to Flickr.")
                        Button("Delete Now", role: .destructive) { Task { await organize.deletePendingNow() } }
                    }
                }
            }
        }
    }
}

private func banner(@ViewBuilder _ content: () -> some View) -> some View {
    HStack { content() }
        .font(.callout)
        .padding(10)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
        .padding(.horizontal, 14).padding(.bottom, 8)
}

/// Undo covers what Caterina changed; a backup covers everything else.
struct BackupTip: View {
    static let short = "Tip: back up your photostream before big edits."
    static let accountData = URL(string: "https://www.flickr.com/account")

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // One literal: joined with +, the ** would show as text.
            Text("**Back up first:** before a big edit, save your originals from Download (⌘1), and request your titles, tags and albums under Your Flickr Data on flickr.com.")
            if let accountData = Self.accountData {
                Link("Open Flickr account settings", destination: accountData)
            }
        }
    }
}

/// Undo from the Edit menu, for the newest edit that can be taken back.
struct UndoRequestDialog: ViewModifier {
    let organize: OrganizeModel

    func body(content: Content) -> some View {
        content.confirmationDialog("Undo “\(organize.undoRequest?.batch.title ?? "")” on Flickr?",
                                   isPresented: Binding(get: { organize.undoRequest != nil },
                                                        set: { if !$0 { organize.cancelUndoRequest() } })) {
            Button("Undo") { Task { await organize.confirmUndoRequest() } }
            Button("Cancel", role: .cancel) { organize.cancelUndoRequest() }
        } message: {
            Text("Caterina writes back what each photo had before, one photo at a time.")
        }
    }
}
