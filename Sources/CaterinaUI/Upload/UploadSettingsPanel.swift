import SwiftUI

import FlickrKit

/// Who can see the photos, which album they go in, and the button that sends.
struct UploadSettingsPanel: View {
    @Bindable var uploads: UploadModel
    @State private var newAlbumTitle = ""
    @State private var albumMode: AlbumMode = .none

    private enum AlbumMode: Hashable { case none, new, existing(String) }

    var body: some View {
        Form {
            Section("Who can see them") {
                Picker("Preset", selection: $uploads.preset) {
                    ForEach(uploads.presets.load()) { preset in Text(preset.name).tag(preset) }
                }
                Text(visibilitySummary)
                    .font(.callout)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Section("Album") {
                Picker("Put in", selection: $albumMode) {
                    Text("No album").tag(AlbumMode.none)
                    Text("New album…").tag(AlbumMode.new)
                    if !uploads.albums.isEmpty { Divider() }
                    ForEach(uploads.albums) { album in
                        Text("\(album.title) (\(album.photoCount))").tag(AlbumMode.existing(album.id))
                    }
                }
                if albumMode == .new {
                    TextField("Album title", text: $newAlbumTitle)
                }
            }
            Section {
                Button(sendTitle) { Task { await uploads.send() } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(uploads.drafts.isEmpty || uploads.activeBatchID != nil)
                    .frame(maxWidth: .infinity)
            } footer: {
                Text("Photos are sent two at a time. Quitting pauses the upload; it carries on next time.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: albumMode) { _, _ in applyAlbum() }
        .onChange(of: newAlbumTitle) { _, _ in applyAlbum() }
    }

    private var sendTitle: String {
        let count = uploads.drafts.count
        return count == 1 ? "Upload 1 Photo" : "Upload \(count) Photos"
    }

    private var visibilitySummary: String {
        let visibility = uploads.preset.metadata.visibility
        if visibility.isPublic { return "Anyone can see them." }
        switch (visibility.isFriend, visibility.isFamily) {
        case (true, true): return "Only your friends and family can see them."
        case (true, false): return "Only your friends can see them."
        case (false, true): return "Only your family can see them."
        case (false, false): return "Only you can see them."
        }
    }

    private func applyAlbum() {
        switch albumMode {
        case .none: uploads.album = .none
        case .new: uploads.album = .new(title: newAlbumTitle)
        case let .existing(id):
            uploads.album = uploads.albums.first { $0.id == id }.map { .existing($0) } ?? .none
        }
    }
}
