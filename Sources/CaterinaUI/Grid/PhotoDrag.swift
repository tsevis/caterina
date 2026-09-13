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

    /// The name a dragged photo lands under.
    ///
    /// Deliberately the same rules a download uses: dragging a photo out and
    /// downloading it should produce the same file, not two files that differ
    /// only in how they were asked for.
    static func promisedName(for photo: Photo, url address: String) -> String {
        Filenames.destination(in: URL(fileURLWithPath: NSTemporaryDirectory()),
                              title: photo.title, photoID: photo.id, url: address)
            .lastPathComponent
    }

    /// The type the Finder is promised, derived from the same allow-list that
    /// decides the extension — so the two cannot disagree.
    static func promisedType(for address: String) -> UTType {
        UTType(filenameExtension: Filenames.fileExtension(for: address)) ?? .jpeg
    }

    static func provider(for photo: Photo, variant: PhotoVariant) -> NSItemProvider {
        let provider = NSItemProvider()
        guard let address = photo.downloadURL(preferring: variant),
              let url = URL(string: address)
        else { return provider }

        let name = promisedName(for: photo, url: address)
        provider.suggestedName = name

        let type = promisedType(for: address)
        provider.registerFileRepresentation(
            forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all
        ) { completion in
            let task = Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    // A directory of its own, per drag: the name comes from a
                    // remote title and is therefore predictable, and two drags
                    // of two photos with the same title would otherwise write
                    // the same path. The same audited helper the download and
                    // preview paths use.
                    let folder = try SafeFile.uniqueDirectory(
                        in: FileManager.default.temporaryDirectory, prefix: "drag-")
                    let file = folder.appendingPathComponent(name)
                    try SafeFile.write(data, to: file)
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
