import SwiftUI

import FlickrKit

struct RecordPlaces: View {
    let contexts: PhotoContexts

    var body: some View {
        if !contexts.albums.isEmpty || !contexts.groups.isEmpty {
            RecordSection("In albums and groups") {
                ForEach(contexts.albums) { Label($0.title, systemImage: "rectangle.stack") }
                ForEach(contexts.groups) { Label($0.title, systemImage: "person.3") }
            }
        }
    }
}

struct RecordCamera: View {
    let exif: PhotoExif
    private static let shown = ["Model", "Lens Model", "Lens", "Focal Length", "Aperture", "Exposure", "ISO Speed"]

    var body: some View {
        RecordSection("Camera") {
            if exif.isHidden {
                Text("The photographer does not share camera data.").foregroundStyle(Theme.inkSecondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                    if let camera = exif.camera { row("Camera", camera) }
                    ForEach(Self.shown, id: \.self) { label in
                        if let value = exif[label] { row(label, value) }
                    }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(Theme.inkSecondary)
            Text(value).textSelection(.enabled)
        }
    }
}

struct RecordComments: View {
    let comments: [PhotoComment]

    var body: some View {
        if !comments.isEmpty {
            RecordSection("Comments") {
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(comment.authorName) · \(comment.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(Theme.inkSecondary)
                        // Flickr allows limited HTML in comments; shown as text, never rendered.
                        Text(comment.text).textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

struct RecordFavers: View {
    let faves: [Fave]
    let total: Int
    private static let shown = 50

    var body: some View {
        if !faves.isEmpty {
            RecordSection("Faved by") {
                Text(faves.prefix(Self.shown).map(\.username).joined(separator: ", "))
                    .textSelection(.enabled)
                if total > Self.shown {
                    Text("and \((total - Self.shown).formatted()) more").font(.caption).foregroundStyle(Theme.inkSecondary)
                }
            }
        }
    }
}
