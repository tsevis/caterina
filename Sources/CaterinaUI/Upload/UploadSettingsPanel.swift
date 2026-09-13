import SwiftUI

import FlickrKit

/// Who can see the photos, which album they go in, and the button that sends.
struct UploadSettingsPanel: View {
    @Bindable var uploads: UploadModel

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
                Picker("Put in", selection: $uploads.albumSelection) {
                    Text("No album").tag(UploadModel.AlbumSelection.none)
                    Text("New album…").tag(UploadModel.AlbumSelection.new)
                    if !uploads.albums.isEmpty { Divider() }
                    ForEach(uploads.albums) { album in
                        Text("\(album.title) (\(album.photoCount))").tag(UploadModel.AlbumSelection.existing(album.id))
                    }
                }
                if uploads.albumSelection == .new {
                    TextField("Album title", text: $uploads.newAlbumTitle)
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

}
