import SwiftUI

import CaterinaLibrary
import FlickrKit

/// The sidebar's albums: open one, drag to reorder, rename or delete.
struct AlbumSidebarSection: View {
    let organize: OrganizeModel
    @State private var editing: Album?
    @State private var deleting: Album?

    var body: some View {
        Section {
            ForEach(organize.albums) { album in
                Label(album.title.isEmpty ? "Untitled album" : album.title, systemImage: "rectangle.stack")
                    .badge(album.photoCount)
                    .tag(OrganizeScope.album(id: album.id, title: album.title))
                    .contextMenu {
                        Button("Add Tray to This Album") { Task { await organize.addTray(toAlbum: album.id) } }
                            .disabled(organize.tray.isEmpty || organize.isRunning)
                        Button("Rename…") { editing = album }
                        Divider()
                        Button("Delete Album…", role: .destructive) { deleting = album }
                    }
            }
            .onMove { source, destination in
                Task { await organize.moveAlbums(from: source, to: destination) }
            }
        } header: {
            HStack {
                Text("Albums")
                Spacer()
                Button { Task { await organize.loadAlbums() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Read your albums from Flickr again")
            }
        }
        .sheet(item: $editing) { album in
            AlbumDetailsSheet(title: album.title, description: album.description, heading: "Rename Album") { title, description in
                Task { await organize.editAlbum(album.id, title: title, description: description) }
            }
        }
        .confirmationDialog("Delete “\(deleting?.title ?? "")”?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { album in
            Button("Delete Album", role: .destructive) { Task { await organize.deleteAlbum(album.id) } }
        } message: { album in
            Text("The \(album.photoCount.formatted()) photos stay in your photostream. "
                 + "Undo makes the album again with the same photos, but its views and link are new.")
        }
    }
}

/// Title and description for a new or renamed album.
struct AlbumDetailsSheet: View {
    @State var title: String
    @State var description: String
    let heading: String
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading).font(.headline)
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            TextField("Description", text: $description, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(title.trimmed, description)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

/// What can be done to the open album's selection.
struct AlbumActions: View {
    let organize: OrganizeModel

    var body: some View {
        HStack(spacing: 8) {
            Button("Set as Cover") { Task { await organize.setCoverToSelection() } }
                .disabled(organize.selection.count != 1 || organize.isRunning)
            Button("Remove from Album") { Task { await organize.removeSelectionFromAlbum() } }
                .disabled(organize.selection.isEmpty || organize.isRunning)
            Menu("Sort") {
                ForEach(AlbumOrdering.Sort.allCases) { sort in
                    Button(sort.title) { Task { await organize.sortAlbum(by: sort) } }
                }
            }
            .fixedSize()
            .disabled(organize.isRunning)
        }
        .controlSize(.small)
        .help("Drag photos to reorder them in the album")
    }
}

/// The tray's album choices: an existing album, or a new one.
struct TrayAlbumSection: View {
    let organize: OrganizeModel
    @State private var albumID = ""
    @State private var isNaming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Albums").font(.subheadline.weight(.semibold))
            HStack {
                Picker("Album", selection: $albumID) {
                    Text("Choose an album").tag("")
                    ForEach(organize.albums) { Text($0.title).tag($0.id) }
                }
                .labelsHidden()
                Button("Add") { Task { await organize.addTray(toAlbum: albumID) } }
                    .disabled(albumID.isEmpty || organize.isRunning)
            }
            Button("New Album from Tray…") { isNaming = true }
                .disabled(organize.isRunning)
        }
        .sheet(isPresented: $isNaming) {
            AlbumDetailsSheet(title: "", description: "", heading: "New Album") { title, description in
                Task { await organize.createAlbum(title: title, description: description) }
            }
        }
        .task { if organize.albums.isEmpty { await organize.loadAlbums() } }
    }
}
