import SwiftUI

import CaterinaLibrary
import FlickrKit

/// The batch going out, file by file.
struct UploadProgressList: View {
    let uploads: UploadModel

    var body: some View {
        List(uploads.items, id: \.position) { item in
            HStack(spacing: 10) {
                icon(item.state)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.metadata.title.isEmpty ? item.file.lastPathComponent : item.metadata.title)
                        .lineLimit(1)
                    Text(detail(item))
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(2)
                }
                Spacer()
                if item.state == .interrupted || item.message != nil {
                    Button("Send Again") { Task { await uploads.resend(item) } }
                        .help("Only if the photo is not already in your photostream")
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func icon(_ state: UploadItem.State) -> some View {
        switch state {
        case .queued: Image(systemName: "clock").foregroundStyle(Theme.inkSecondary)
        case .sending, .processing: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .interrupted: Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
        }
    }

    private func detail(_ item: UploadItem) -> String {
        switch item.state {
        case .queued: "Waiting"
        case .sending: "Sending…"
        case .processing: "Flickr is processing it…"
        case .done: item.inAlbum ? "On Flickr, in the album" : "On Flickr"
        case let .failed(message): message
        case .interrupted: "Stopped while sending. Check your photostream before sending it again."
        }
    }
}

/// Where the batch has got to, and what to do next.
struct UploadStatusBar: View {
    let model: AppModel
    @State private var askingPermission: FlickrPermission?

    private var uploads: UploadModel { model.uploads }

    var body: some View {
        HStack(spacing: 10) {
            status
            Spacer()
            actions
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Theme.hairline.frame(height: 1) }
        .onChange(of: uploads.phase) { _, phase in
            if case let .needsPermission(permission) = phase { askingPermission = permission }
        }
        .sheet(item: $askingPermission) { permission in
            PermissionRequestSheet(model: model, permission: permission) {
                askingPermission = nil
                await uploads.resume()
            } onCancel: { askingPermission = nil }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch uploads.phase {
        case .editing, .unavailable:
            Text(uploads.drafts.isEmpty ? "" : "\(uploads.drafts.count) ready to upload")
                .foregroundStyle(Theme.inkSecondary)
        case let .sending(summary):
            ProgressView().controlSize(.small)
            Text("Uploading… \(summary.done) done, \(summary.remaining) to go")
                .monospacedDigit()
        case .needsPermission:
            Label("Waiting for your approval on Flickr", systemImage: "lock")
        case let .paused(message):
            Label(message, systemImage: "pause.circle")
        case let .finished(summary):
            Text(finishedText(summary)).monospacedDigit()
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch uploads.phase {
        case .paused, .needsPermission:
            Button("Resume") { Task { await uploads.resume() } }
        case .finished:
            Button("Upload More") { uploads.startOver() }
        default:
            EmptyView()
        }
    }

    private func finishedText(_ summary: UploadBatch.Summary) -> String {
        var parts = ["\(summary.done) uploaded"]
        if summary.failed > 0 { parts.append("\(summary.failed) refused") }
        if summary.interrupted > 0 { parts.append("\(summary.interrupted) to check") }
        return parts.joined(separator: " · ")
    }
}

extension FlickrPermission: Identifiable {
    public var id: String { rawValue }
}
