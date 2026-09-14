import AppKit
import SwiftUI
import Testing

import CaterinaLibrary
import FlickrKit
@testable import CaterinaUI

/// Organize's panels drawn offscreen, with copies left to look at. No window.
@MainActor
@Suite struct OrganizeRenderTests {

    static let output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("caterina-organize", isDirectory: true)

    private func render<V: View>(_ view: V, _ name: String, size: CGSize) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)))
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: Self.output.appendingPathComponent("\(name).png"))
        return bitmap
    }

    private func organize() throws -> OrganizeModel {
        let store = try LibraryStore.inMemory()
        try store.save((1...12).map { LibraryPhoto(id: "\($0)", title: "Photo \($0)", tags: $0 % 2 == 0 ? ["sea"] : []) },
                       generation: 1)
        let model = OrganizeModel(store: store, flickr: FakeOrganizeFlickr(store: store))
        model.selectAll()
        model.addSelectionToTray()
        return model
    }

    @Test func theTrayShowsItsCostBeforeItRuns() throws {
        let organize = try organize()
        _ = try render(TrayPanel(organize: organize, draft: .constant(EditDraft(kind: .tags)), onApplied: {}), "tray", size: CGSize(width: 380, height: 640))
        var draft = EditDraft(kind: .tags)
        draft.tagText = "New York, blue hour"
        _ = try render(VStack(alignment: .leading) { EditForm(draft: .constant(draft)); ApplyBar(organize: organize, draft: draft, onApplied: {}) }
            .padding(14), "tags-form", size: CGSize(width: 380, height: 260))
        var safety = EditDraft(kind: .safety)
        safety.safetyField = .contentType
        _ = try render(VStack(alignment: .leading) { EditForm(draft: .constant(safety)); ApplyBar(organize: organize, draft: safety, onApplied: {}) }
            .padding(14), "safety-form", size: CGSize(width: 380, height: 220))
    }

    @Test func activityListsABatchWithItsRefusals() async throws {
        let organize = try organize()
        await organize.apply(.setTitle("A"), title: "Set title to “A”")
        let row = try #require(organize.activity.first)
        let refused = BatchActivity(batch: row.batch, summary: .init(applied: 10, failed: 2, pending: 0),
                                    failures: [.init(photoID: "3", title: "Photo 3", message: "Photo not found")],
                                    canResume: false, canUndo: true)
        _ = try render(VStack { ActivityRow(organize: organize, row: row); ActivityRow(organize: organize, row: refused) }
            .padding(14), "activity", size: CGSize(width: 380, height: 200))
    }
}
