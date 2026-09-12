import AppKit
import SwiftUI

import FlickrKit

/// Choosing a size and a folder, then watching it happen.
struct DownloadSheet: View {
    @Bindable var model: AppModel
    let source: PhotoSource
    @Binding var isPresented: Bool

    /// **A bookmark, not a path.** Under the sandbox, the panel's grant does
    /// not survive a relaunch: a remembered path would be pre-filled, look
    /// right, and fail to write. A security-scoped bookmark is the grant.
    @AppStorage("LastDownloadFolderBookmark") private var lastFolder = Data()
    @State private var destination: URL?
    @State private var problem: String?

    private var photos: [Photo] { model.workspace[source].selectedPhotos }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(photos.count == 1 ? "Download 1 photo"
                                   : "Download \(photos.count) photos")
                .font(.headline)

            Picker("Size", selection: $model.downloadVariant) {
                ForEach(PhotoVariant.allCases) { variant in
                    Text("\(variant.name) — \(variant.pixelDescription)").tag(variant)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Text("Save to")
                Text(destination?.path ?? "Choose a folder…")
                    .accessibilityLabel(destination.map { "Saving to \($0.lastPathComponent)" }
                        ?? "No folder chosen")
                    .foregroundStyle(destination == nil ? Theme.inkSecondary : Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose…", action: chooseFolder)
            }

            // Flickr never upscales, so asking for Original and getting Medium
            // is normal — saying so beforehand beats a folder of surprises.
            Label("A photo that has no file at the chosen size is saved at the "
                  + "largest size Flickr published for it.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)

            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Download") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(destination == nil || photos.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { destination = restoredFolder() }
    }

    private func restoredFolder() -> URL? { DownloadFolder.restored(from: lastFolder) }

    private func remember(_ url: URL) { lastFolder = DownloadFolder.bookmark(for: url) }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = destination
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destination = url
        remember(url)
    }

    private func start() {
        guard let destination else { return }
        guard FileManager.default.isWritableFile(atPath: destination.path) else {
            problem = "That folder cannot be written to. Choose another."
            return
        }
        model.startDownload(from: source, to: destination, variant: model.downloadVariant)
        isPresented = false
    }
}

/// Progress while it runs, and the count when it stops.
struct DownloadBar: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.download.isRunning {
            HStack(spacing: 12) {
                ProgressView(value: model.download.fraction)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 260)
                    .accessibilityLabel("Downloading")
                    .accessibilityValue(
                        "\(model.download.completed) of \(model.download.total)")
                Text("\(model.download.completed) of \(model.download.total)")
                    .monospacedDigit()
                    .font(.callout)
                    .foregroundStyle(Theme.inkSecondary)
                Button("Cancel") { model.cancelDownload() }
                    .keyboardShortcut(".", modifiers: .command)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
        } else if let report = model.download.report {
            HStack(spacing: 12) {
                Label(report.summary,
                      systemImage: report.failures.isEmpty
                          ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.callout)
                if !report.failures.isEmpty {
                    Text(report.failures.count == 1 ? "1 failed"
                                                    : "\(report.failures.count) failed")
                        .font(.callout)
                        .foregroundStyle(Theme.inkSecondary)
                        .help(report.failures.compactMap(\.failure).prefix(5)
                            .joined(separator: "\n"))
                }
                Spacer()
                Button("Dismiss") { model.dismissDownloadReport() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}
