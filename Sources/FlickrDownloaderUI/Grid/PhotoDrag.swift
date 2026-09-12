import Foundation
import UniformTypeIdentifiers

import FlickrKit

/// Dragging photos out to the Finder.
///
/// An item provider that *promises* a file rather than one that carries a URL:
/// dropping a remote URL on the Finder makes a `.webloc`, which is not what
/// anybody dragging a photograph wants. `registerFileRepresentation` lets the
/// bytes be fetched when the drop happens, under the name the download would
/// have used, so a dragged photo and a downloaded one land as the same file.
enum PhotoDrag {

    static func provider(for photo: Photo, variant: PhotoVariant) -> NSItemProvider {
        let provider = NSItemProvider()
        guard let address = photo.downloadURL(preferring: variant),
              let url = URL(string: address)
        else { return provider }

        let name = Filenames
            .destination(in: URL(fileURLWithPath: NSTemporaryDirectory()),
                         title: photo.title, photoID: photo.id, url: address)
            .lastPathComponent
        provider.suggestedName = name

        let type = UTType(filenameExtension: Filenames.fileExtension(for: address)) ?? .jpeg
        provider.registerFileRepresentation(
            forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all
        ) { completion in
            let task = Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let file = FileManager.default.temporaryDirectory
                        .appendingPathComponent(name)
                    try data.write(to: file)
                    // `false`: the file is ours, in the temporary directory —
                    // the Finder copies it rather than moving it out from under
                    // a Quick Look that may still be showing it.
                    completion(file, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return Progress(totalUnitCount: 1) { task.cancel() }
        }
        return provider
    }
}

private extension Progress {
    /// A progress object whose cancellation reaches the transfer behind it.
    convenience init(totalUnitCount: Int64, onCancel: @escaping @Sendable () -> Void) {
        self.init(totalUnitCount: totalUnitCount)
        isCancellable = true
        cancellationHandler = onCancel
    }
}
