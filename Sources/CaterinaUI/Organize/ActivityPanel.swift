import SwiftUI

import CaterinaLibrary
import FlickrKit

/// Recent batches: progress, what Flickr refused and why, Resume and Undo.
struct ActivityPanel: View {
    let organize: OrganizeModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Activity").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            RunBanner(organize: organize)
            Divider()
            if organize.activity.isEmpty {
                ContentUnavailableView("No edits yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Every edit made here is listed, and can be undone."))
            } else {
                List(organize.activity) { row in
                    ActivityRow(organize: organize, row: row)
                }
            }
        }
    }
}

/// What is running now, or why it stopped.
struct RunBanner: View {
    let organize: OrganizeModel

    var body: some View {
        switch organize.run {
        case .idle:
            EmptyView()
        case let .running(_, summary):
            let done = summary.applied + summary.failed
            let total = done + summary.pending
            HStack {
                ProgressView(value: Double(done), total: Double(max(total, 1))) {
                    Text("Changing \(done.formatted()) of \(total.formatted())…").monospacedDigit()
                }
                Button("Stop") { organize.stop() }
                    .help("Stop after the photo being changed. The rest can be resumed.")
            }
            .padding(.horizontal, 14).padding(.bottom, 8)
        case let .needsPermission(_, batchID):
            banner("Flickr needs your approval to continue.", systemImage: "lock") {
                Button("Resume") { Task { await organize.resume(batchID) } }
                    .help("Resume once Caterina may change your photos")
            }
        case let .paused(batchID, message):
            banner("Stopped: \(message)", systemImage: "wifi.exclamationmark") {
                Button("Resume") { Task { await organize.resume(batchID) } }
            }
        }
    }

    private func banner(_ text: String, systemImage: String, @ViewBuilder action: () -> some View) -> some View {
        HStack {
            Label(text, systemImage: systemImage).lineLimit(3)
            Spacer()
            action()
        }
        .font(.callout)
        .padding(10)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
        .padding(.horizontal, 14).padding(.bottom, 8)
    }
}

struct ActivityRow: View {
    let organize: OrganizeModel
    let row: BatchActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.batch.title).lineLimit(2)
                Spacer()
                if row.canResume {
                    Button("Resume") { Task { await organize.resume(row.batch.id) } }.disabled(organize.isRunning)
                }
                if row.canUndo {
                    Button("Undo") { Task { await organize.undo(row.batch.id) } }.disabled(organize.isRunning)
                }
            }
            Text(detail).font(.caption).monospacedDigit().foregroundStyle(Theme.inkSecondary)
            if !row.groupReport.isEmpty {
                DisclosureGroup("Per group") {
                    ForEach(row.groupReport) { line in GroupReportView(line: line) }
                }
                .font(.caption)
            } else if !row.failures.isEmpty {
                DisclosureGroup("\(row.failures.count.formatted()) not changed") {
                    ForEach(row.failures) { failure in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(failure.title.isEmpty ? "Untitled (\(failure.photoID))" : failure.title)
                            Text(failure.message).foregroundStyle(Theme.inkSecondary)
                        }
                        .font(.caption)
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private var detail: String {
        let summary = row.summary
        var parts = ["\(summary.applied.formatted()) changed"]
        if summary.failed > 0 { parts.append("\(summary.failed.formatted()) refused") }
        if summary.pending > 0 { parts.append("\(summary.pending.formatted()) waiting") }
        return row.batch.createdAt.formatted(date: .abbreviated, time: .shortened) + " · " + parts.joined(separator: " · ")
    }
}

/// One group's line in a sharing report.
struct GroupReportView: View {
    let line: BatchActivity.GroupReportLine

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(line.name).lineLimit(1)
            Text(counts).foregroundStyle(Theme.inkSecondary).monospacedDigit()
            ForEach(line.row.refused.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { reason in
                Text("\(line.row.refused[reason] ?? 0) not added: \(reason.explanation)").foregroundStyle(.orange)
            }
        }
        .font(.caption)
    }

    private var counts: String {
        let row = line.row
        return [row.added > 0 ? "\(row.added) done" : nil,
                row.waiting > 0 ? "\(row.waiting) waiting for a moderator" : nil,
                row.already > 0 ? "\(row.already) already so" : nil,
                row.pending > 0 ? "\(row.pending) still to send" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
