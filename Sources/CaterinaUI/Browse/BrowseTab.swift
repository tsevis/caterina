import Charts
import SwiftUI

import CaterinaLibrary
import FlickrKit

/// Rankings on the left, photos in the middle, the chosen photo's record.
struct BrowseTab: View {
    let model: AppModel
    private var browse: BrowseModel { model.browse }

    var body: some View {
        NavigationSplitView {
            BrowseSidebar(browse: browse)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } content: {
            List(browse.rows, selection: Binding(get: { browse.selectedPhotoID },
                                                 set: { id in Task { await browse.select(id) } })) { row in
                BrowseRowView(row: row).tag(row.photoID)
            }
            .overlay { if browse.rows.isEmpty { emptyRows } }
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            detail
        }
        .task { await browse.saveStats() }
    }

    @ViewBuilder
    private var detail: some View {
        switch browse.record {
        case .none:
            ContentUnavailableView("Choose a photo", systemImage: "photo",
                                   description: Text("Its views, faves, comments and where it appears."))
        case .loading:
            ProgressView("Reading from Flickr…")
        case let .failed(message):
            ContentUnavailableView("Could not read this photo", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        case let .loaded(record):
            PhotoRecordView(record: record,
                            thumbnailURL: browse.rows.first { $0.photoID == record.info.id }?.thumbnailURL)
        }
    }

    @ViewBuilder
    private var emptyRows: some View {
        switch browse.ranking {
        case .mostViewed, .recentUploads:
            ContentUnavailableView("No photos yet", systemImage: "externaldrive.badge.icloud",
                                   description: Text("Your library copy fills after the first sync. See Organize."))
        default:
            ContentUnavailableView("No history yet", systemImage: "chart.bar",
                                   description: Text("Rankings come from saved daily stats, which need Flickr Pro."))
        }
    }
}

struct BrowseSidebar: View {
    let browse: BrowseModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: Binding(get: { browse.ranking }, set: { browse.show($0 ?? .mostViewed) })) {
                Section("Your photos") {
                    ForEach(BrowseModel.Ranking.allCases) { ranking in
                        Label(ranking.title, systemImage: ranking.systemImage).tag(ranking)
                    }
                }
            }
            AccountSummary(browse: browse)
                .padding(12)
        }
    }
}

/// Views across the account, day by day, and whether saving is working.
struct AccountSummary: View {
    let browse: BrowseModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Account views").font(.caption.weight(.semibold))
            if browse.accountHistory.isEmpty {
                Text("No days saved yet.").font(.caption).foregroundStyle(Theme.inkSecondary)
            } else {
                ViewsPerDayChart(points: browse.accountHistory.suffix(28).map { ($0.day, $0.totals.total) })
                    .chartXAxis(.hidden)
                    .frame(height: 70)
            }
            Text(status).font(.caption).foregroundStyle(Theme.inkSecondary)
        }
    }

    private var status: String {
        switch browse.statsPhase {
        case .idle: "\(browse.accountHistory.count) days saved"
        case .saving: "Saving daily stats…"
        case let .saved(days): days == 0 ? "\(browse.accountHistory.count) days saved, up to date"
                                         : "Saved \(days) new days · \(browse.accountHistory.count) in all"
        case .unavailable: "Daily stats need Flickr Pro."
        case let .failed(message): message
        }
    }
}

struct BrowseRowView: View {
    let row: BrowseModel.Row

    var body: some View {
        HStack(spacing: 10) {
            RowThumbnail(address: row.thumbnailURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).lineLimit(1)
                Text(row.figure).font(.caption).monospacedDigit().foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A square thumbnail from the shared store, or its well while it loads.
struct RowThumbnail: View {
    let address: String?
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Theme.well)
            .frame(width: size, height: size)
            .overlay { if let image { Image(nsImage: image).resizable().scaledToFill() } }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .task(id: address) {
                image = nil
                guard let address else { return }
                image = await ThumbnailStore.shared.image(for: address)
            }
            .accessibilityHidden(true)
    }
}
