import SwiftUI

import CaterinaLibrary
import FlickrKit

/// Someone else's photo into one of your galleries, recorded in Organize's
/// Activity where it can be undone.
struct AddToGalleryBar: View {
    let photoID: String
    let directory: AccountDirectory
    let organize: OrganizeModel
    @State private var galleryID = ""
    @State private var comment = ""

    var body: some View {
        HStack(spacing: 8) {
            Picker("Gallery", selection: $galleryID) {
                Text("Add to a gallery…").tag("")
                ForEach(directory.galleries) { Text($0.title).tag($0.id) }
            }
            .labelsHidden()
            TextField("Comment (optional)", text: $comment).textFieldStyle(.roundedBorder)
            Button("Add") {
                let title = directory.galleries.first { $0.id == galleryID }?.title ?? "gallery"
                let (photo, gallery, note) = (photoID, galleryID, comment)
                Task { await organize.addToGallery(photoID: photo, galleryID: gallery, galleryTitle: title, comment: note) }
                comment = ""
            }
            .disabled(galleryID.isEmpty || organize.isRunning)
            .help("Galleries hold other people's photos. Undo from Organize's Activity.")
        }
        .controlSize(.small)
        .overlay(alignment: .top) {
            if let problem = organize.problem {
                Text(problem).font(.caption).foregroundStyle(.orange).offset(y: -18)
            }
        }
        .padding(10)
        .background(.bar)
        .task { await directory.load(.galleries) }
    }
}
