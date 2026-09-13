import SwiftUI

/// How much of your library is here, how fresh it is, and a way to refresh it.
struct LibraryStatusBar: View {
    let model: AppModel

    private var library: LibraryModel { model.library }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.icloud")
                .foregroundStyle(Theme.markText)
                .accessibilityHidden(true)
            status
            Spacer()
            Button("Sync Now") {
                Task { await model.syncLibrary() }
            }
            .disabled(library.isSyncing || library.phase == .unavailable)
            .help("Fetch what changed on Flickr since the last sync")
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Theme.hairline.frame(height: 1) }
    }

    @ViewBuilder
    private var status: some View {
        switch library.phase {
        case .idle:
            Text(library.statusLine)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
        case let .syncing(fetched, total):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(total > 0 ? "Syncing library… \(fetched.formatted()) of \(total.formatted())"
                               : "Syncing library…")
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Theme.inkSecondary)
        case .unavailable:
            Label("The library copy could not be opened on this Mac.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}
