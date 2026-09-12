import Foundation
import Testing
import UniformTypeIdentifiers

import FlickrKit
@testable import FlickrDownloaderUI

/// What a dragged photo promises the Finder.
///
/// Whether the drop itself works is a question for a running window. What the
/// Finder is *told* — the name and the type — is decided here.
@Suite struct PhotoDragTests {

    private func photo(_ title: String, id: String = "51234567890") -> Photo {
        Photo(id: id, title: title,
              variants: [.original: "https://live.staticflickr.com/1/x_o.jpg"])
    }

    /// Dragging a photo out and downloading it must produce the same file, not
    /// two that differ only in how they were asked for.
    @Test func aDraggedPhotoIsNamedExactlyAsADownloadedOneWouldBe() {
        let photo = photo("Harbour at dusk")
        let address = "https://live.staticflickr.com/1/x_o.jpg"

        let dragged = PhotoDrag.promisedName(for: photo, url: address)
        let downloaded = Filenames.destination(
            in: URL(fileURLWithPath: "/tmp"), title: photo.title,
            photoID: photo.id, url: address).lastPathComponent

        #expect(dragged == downloaded)
        #expect(dragged == "Harbour at dusk_51234567890.jpg")
    }

    /// The same rules that stop a download escaping its folder stop a drag
    /// naming a file with a slash in it.
    @Test func aHostileTitleCannotBecomeAPath() {
        let name = PhotoDrag.promisedName(for: photo("../../etc/passwd"),
                                          url: "https://live.staticflickr.com/a.jpg")
        #expect(!name.contains("/"))
        #expect(!name.contains(".."))
    }

    @Test func theTypePromisedMatchesTheExtensionChosen() {
        for (address, expected) in [("https://live.staticflickr.com/a.jpg", UTType.jpeg),
                                    ("https://live.staticflickr.com/a.png", .png),
                                    ("https://live.staticflickr.com/a.gif", .gif)] {
            #expect(PhotoDrag.promisedType(for: address) == expected)
        }
    }

    /// An extension outside the allow-list becomes a JPEG in the filename, so
    /// the promised type has to agree rather than promising something else.
    @Test func anUnknownExtensionPromisesTheTypeTheFileWillActuallyHave() {
        let address = "https://live.staticflickr.com/a.webp"
        #expect(Filenames.fileExtension(for: address) == "jpg")
        #expect(PhotoDrag.promisedType(for: address) == .jpeg)
    }
}

/// Remembering the download folder across launches.
@Suite struct DownloadFolderTests {

    private func directory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flickrdownloader-folder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The security scope is what the *app* needs; this process is not
    /// sandboxed, so the round trip is exercised with a plain bookmark and the
    /// failure paths — which are the ones that break — with the real options.
    @Test func aRememberedFolderComesBack() throws {
        let folder = try directory()
        let data = DownloadFolder.bookmark(for: folder, options: [])
        #expect(!data.isEmpty)

        let restored = DownloadFolder.restored(from: data, options: [])
        #expect(restored?.standardizedFileURL == folder.standardizedFileURL)
    }

    @Test func nothingRememberedIsNotAFolder() {
        #expect(DownloadFolder.restored(from: Data()) == nil)
    }

    /// A corrupted preference must ask again, not crash.
    @Test func rubbishIsNotAFolder() {
        #expect(DownloadFolder.restored(from: Data("not a bookmark".utf8)) == nil)
        #expect(DownloadFolder.restored(from: Data(repeating: 0xFF, count: 512)) == nil)
    }

    /// The case the sandbox actually produces: the folder was moved or deleted
    /// between launches.
    @Test func aFolderThatIsNoLongerThereIsNotOffered() throws {
        let folder = try directory()
        let data = DownloadFolder.bookmark(for: folder, options: [])
        try FileManager.default.removeItem(at: folder)
        #expect(DownloadFolder.restored(from: data, options: []) == nil)
    }
}

/// Quick Look writes a file, and its name comes from the same rules.
@MainActor
@Suite struct QuickLookNamingTests {

    /// A photo id comes from Flickr. `appendingPathComponent` would happily let
    /// one containing slashes walk out of the temporary directory.
    @Test func aHostilePhotoIDCannotEscapeTheTemporaryDirectory() {
        let temporary = FileManager.default.temporaryDirectory
        for id in ["../../evil", "/etc/passwd", "a/b/c", ".."] {
            let file = Filenames.destination(in: temporary, title: "Quick Look",
                                             photoID: id,
                                             url: "https://live.staticflickr.com/a.jpg")
            #expect(file.deletingLastPathComponent().standardizedFileURL
                == temporary.standardizedFileURL,
                "\(id) escaped to \(file.path)")
        }
    }

    @Test func thePreviewKeepsTheExtensionTheImageActuallyHas() {
        let file = Filenames.destination(in: FileManager.default.temporaryDirectory,
                                         title: "Quick Look", photoID: "1",
                                         url: "https://live.staticflickr.com/a.png")
        #expect(file.pathExtension == "png")
    }
}

/// The `.webloc` guard.
///
/// Dropping a remote URL on the Finder makes a `.webloc` — an internet
/// shortcut — rather than a photograph, and the only thing standing between
/// this app and that outcome is which representations the item provider
/// registers. It promises a *file* and nothing else on purpose. Registering a
/// URL beside it, which is a one-line convenience someone will reach for, is
/// enough to bring the shortcut back, because the Finder prefers the URL.
@Suite struct PhotoDragRepresentationTests {

    private let photo = Photo(id: "51234567890", title: "Harbour at dusk",
                              variants: [.original: "https://live.staticflickr.com/1/x_o.jpg"])

    @Test func theProviderPromisesAFileAndNeverAURL() {
        let provider = PhotoDrag.provider(for: photo, variant: .original)
        let registered = provider.registeredTypeIdentifiers

        #expect(registered.contains(UTType.jpeg.identifier))
        for shortcut in [UTType.url.identifier, UTType.fileURL.identifier, "com.apple.web-internet-location"] {
            #expect(!registered.contains(shortcut), "registered \(shortcut): the Finder would write a .webloc")
        }
    }
}
