import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

import CaterinaLibrary
import FlickrKit
@testable import CaterinaUI

/// Sends every file straight through; can be told to need permission first.
actor FakeUploader: PhotoUploader, AlbumLister {
    var needsPermission: Bool
    private(set) var sent: [(file: String, metadata: UploadMetadata)] = []
    private(set) var createdAlbum: String?

    init(needsPermission: Bool = false) { self.needsPermission = needsPermission }

    func grant() { needsPermission = false }

    func upload(file: URL, metadata: UploadMetadata,
                progress: @escaping @Sendable (Double) -> Void) async throws -> String {
        if needsPermission { throw FlickrError.permissionNeeded(.write) }
        sent.append((file.lastPathComponent, metadata))
        return "t-\(file.lastPathComponent)"
    }
    func checkTickets(_ tickets: [String]) async throws -> [String: TicketStatus] {
        Dictionary(uniqueKeysWithValues: tickets.map { ($0, .done(photoID: "p-\($0)")) })
    }
    func createAlbum(title: String, description: String, coverPhotoID: String,
                     priority: CallPriority) async throws -> String {
        createdAlbum = title
        return "a-1"
    }
    func addToAlbum(photoID: String, albumID: String, priority: CallPriority) async throws {}
    func albums(page: Int) async throws -> AlbumPage {
        AlbumPage(page: 1, pages: 1, albums: [Album(id: "72157001", title: "Athens", description: "",
                                                    photoCount: 3, coverPhotoID: "1", views: 0)])
    }
}

@MainActor
@Suite struct UploadModelTests {

    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("caterina-drops-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Inner"), withIntermediateDirectories: true)
        for name in ["b.jpg", "a.jpg", "Inner/c.jpg"] {
            try Self.writeJPEG(to: folder.appendingPathComponent(name), title: name == "a.jpg" ? "Harbour" : nil)
        }
        try Data("not a photo".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        return folder
    }

    static func writeJPEG(to file: URL, title: String?) throws {
        let context = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = title.map { [kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCObjectName: $0]] } ?? [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func model(_ uploader: FakeUploader, store: LibraryStore? = nil) throws -> UploadModel {
        UploadModel(store: try store ?? LibraryStore.inMemory(), uploader: uploader, albums: uploader,
                    files: PlainFileAccess(), presets: UploadPresetStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
                    pollInterval: .zero)
    }

    @Test func aDroppedFolderAddsItsPhotosInNameOrderAndNothingElse() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try model(FakeUploader())

        await model.add([folder])

        #expect(model.drafts.map(\.file.lastPathComponent) == ["a.jpg", "b.jpg", "c.jpg"])
        #expect(model.drafts.first?.title == "Harbour")
        #expect(model.drafts[1].title == "b")
    }

    @Test func theSameFileTwiceIsAddedOnce() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try model(FakeUploader())
        await model.add([folder.appendingPathComponent("a.jpg")])
        await model.add([folder.appendingPathComponent("a.jpg")])
        #expect(model.drafts.count == 1)
    }

    @Test func editingADraftChangesOnlyThatDraft() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try model(FakeUploader())
        await model.add([folder])
        let first = try #require(model.drafts.first)

        model.update(first.id, title: "Piraeus", tags: "sea, \"new york\" dusk")

        #expect(model.drafts.first?.title == "Piraeus")
        #expect(model.drafts.first?.tags == ["sea", "new york", "dusk"])
        #expect(model.drafts[1].title == "b")
    }

    @Test func aQuotedTagKeepsItsCommasAndSpaces() {
        #expect(UploadModel.parseTags(#"athens, "rock, paper" sea"#) == ["athens", "rock, paper", "sea"])
    }

    @Test func sendingUsesThePresetAndEmptiesTheList() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let uploader = FakeUploader()
        let model = try model(uploader)
        await model.add([folder])
        model.preset = UploadPreset.builtIn.first { $0.name == "Private" }!
        model.album = .new(title: "Athens 2026")

        await model.send()

        #expect(model.drafts.isEmpty)
        #expect(model.phase == .finished(UploadBatch.Summary(done: 3, failed: 0, remaining: 0, interrupted: 0)))
        let sent = await uploader.sent
        #expect(sent.count == 3)
        #expect(sent.allSatisfy { !$0.metadata.visibility.isPublic })
        #expect(await uploader.createdAlbum == "Athens 2026")
    }

    /// The batch waits, whole, for the person to approve; then goes on.
    @Test func needingPermissionAsksAndThenCarriesOn() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let uploader = FakeUploader(needsPermission: true)
        let model = try model(uploader)
        await model.add([folder])

        await model.send()
        #expect(model.phase == .needsPermission(.write))

        await uploader.grant()
        await model.resume()
        #expect(model.phase == .finished(UploadBatch.Summary(done: 3, failed: 0, remaining: 0, interrupted: 0)))
    }

    @Test func nothingToSendIsNotABatch() async throws {
        let uploader = FakeUploader()
        let model = try model(uploader)
        await model.send()
        #expect(model.phase == .editing)
        #expect(await uploader.sent.isEmpty)
    }

    @Test func yourAlbumsAreOfferedToAddTo() async throws {
        let model = try model(FakeUploader())
        await model.loadAlbums()
        #expect(model.albums.map(\.title) == ["Athens"])
    }

    // MARK: - Presets

    @Test func presetsYouMakeAreKept() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let custom = UploadPreset(name: "Portfolio", metadata: UploadMetadata(tags: ["tsevis"], hiddenFromSearch: false))
        UploadPresetStore(defaults: defaults).save([custom])
        #expect(UploadPresetStore(defaults: defaults).load().map(\.name) == UploadPreset.builtIn.map(\.name) + ["Portfolio"])
    }

    @Test func theBuiltInPresetsCoverWhoCanSee() {
        let names = UploadPreset.builtIn.map(\.name)
        #expect(names == ["Public", "Friends & family", "Private"])
        #expect(UploadPreset.builtIn[1].metadata.visibility == .init(isPublic: false, isFriend: true, isFamily: true))
    }
}
