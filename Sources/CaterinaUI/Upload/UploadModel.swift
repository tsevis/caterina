import Foundation
import Observation
import UniformTypeIdentifiers

import CaterinaLibrary
import FlickrKit

/// The Upload tab: files you added, what they go with, and the batch sending.
@MainActor
@Observable
public final class UploadModel {

    public struct Draft: Identifiable, Equatable, Sendable {
        public var id: URL { file }
        public let file: URL
        public let fileMetadata: FileMetadata
        public let title: String
        public let description: String
        public let tags: [String]
    }

    public enum AlbumChoice: Equatable, Sendable {
        case none
        case new(title: String)
        case existing(Album)
    }

    public enum Phase: Equatable, Sendable {
        case editing
        case sending(UploadBatch.Summary)
        case needsPermission(FlickrPermission)
        case paused(String)
        case finished(UploadBatch.Summary)
        case unavailable
    }

    public private(set) var drafts: [Draft] = []
    public private(set) var albums: [Album] = []
    public private(set) var phase: Phase = .editing
    public private(set) var activeBatchID: String?
    public private(set) var items: [UploadItem] = []
    public var preset: UploadPreset
    public var album: AlbumChoice = .none

    public let presets: UploadPresetStore
    private let store: LibraryStore?
    private let runner: UploadRunner?
    private let albumLister: AlbumLister
    private let files: FileAccess

    public init(store: LibraryStore?, uploader: PhotoUploader, albums: AlbumLister, files: FileAccess,
                presets: UploadPresetStore = UploadPresetStore(), pollInterval: Duration = .seconds(3)) {
        self.store = store
        self.albumLister = albums
        self.files = files
        self.presets = presets
        self.preset = UploadPreset.builtIn[0]
        self.runner = store.map { UploadRunner(uploader: uploader, store: $0, files: files, pollInterval: pollInterval) }
        if store == nil { phase = .unavailable }
    }

    // MARK: - Files

    /// Add files and folders. Folders are searched for photos and videos;
    /// anything else, and anything already added, is skipped.
    public func add(_ urls: [URL]) async {
        let known = Set(drafts.map(\.file.standardizedFileURL))
        let found = await Task.detached { Self.drafts(for: urls, skipping: known) }.value
        drafts += found
    }

    public func remove(_ ids: Set<URL>) {
        drafts = drafts.filter { !ids.contains($0.id) }
    }

    /// `tags` is typed as the person types it: commas or spaces between,
    /// quotes around a tag of several words.
    public func update(_ id: URL, title: String? = nil, description: String? = nil, tags: String? = nil) {
        drafts = drafts.map { draft in
            guard draft.id == id else { return draft }
            return Draft(file: draft.file, fileMetadata: draft.fileMetadata,
                         title: title ?? draft.title, description: description ?? draft.description,
                         tags: tags.map(Self.parseTags) ?? draft.tags)
        }
    }

    public func loadAlbums() async {
        guard let first = try? await albumLister.albums(page: 1) else { return }
        albums = first.albums
    }

    // MARK: - Sending

    public func send() async {
        guard let store, !drafts.isEmpty else { return }
        let base = preset.metadata
        let entries = drafts.map { draft in
            (file: draft.file,
             metadata: UploadMetadata(title: draft.title, description: draft.description,
                                      tags: Self.merged(draft.tags, base.tags), visibility: base.visibility,
                                      safety: base.safety, contentType: base.contentType,
                                      hiddenFromSearch: base.hiddenFromSearch))
        }
        do {
            let batch = try store.createUploadBatch(items: entries, album: batchAlbum, files: files)
            activeBatchID = batch.id
            drafts = []
            await resume()
        } catch {
            phase = .paused("Could not queue the upload: \(error.localizedDescription)")
        }
    }

    /// Run the active batch from wherever it stopped.
    public func resume() async {
        guard let runner, let store, let batchID = activeBatchID else { return }
        phase = .sending((try? store.uploadSummary(of: batchID)) ?? .init(done: 0, failed: 0, remaining: 0, interrupted: 0))
        do {
            let summary = try await runner.run(batchID) { [weak self] summary in
                Task { @MainActor in self?.showProgress(summary) }
            }
            refreshItems()
            phase = .finished(summary)
        } catch let FlickrError.permissionNeeded(permission) {
            refreshItems()
            phase = .needsPermission(permission)
        } catch {
            refreshItems()
            phase = .paused((error as? FlickrError)?.message ?? error.localizedDescription)
        }
    }

    /// At launch: take up the newest batch with work left and carry on.
    public func restoreUnfinished() async {
        guard activeBatchID == nil, let store,
              let batchID = try? store.unfinishedUploadBatchIDs().first else { return }
        activeBatchID = batchID
        await resume()
    }

    /// Send again a file the person has checked is not on Flickr.
    public func resend(_ item: UploadItem) async {
        try? store?.resend(item)
        await resume()
    }

    public func startOver() {
        guard case .finished = phase else { return }
        activeBatchID = nil
        items = []
        phase = .editing
    }

    // MARK: - Private

    private var batchAlbum: UploadBatch.AlbumChoice {
        switch album {
        case .none: .none
        case let .new(title): title.trimmingCharacters(in: .whitespaces).isEmpty ? .none : .new(title: title)
        case let .existing(album): .existing(id: album.id)
        }
    }

    private func showProgress(_ summary: UploadBatch.Summary) {
        guard case .sending = phase else { return }
        phase = .sending(summary)
        refreshItems()
    }

    private func refreshItems() {
        guard let store, let activeBatchID else { return }
        items = (try? store.uploadItems(in: activeBatchID, files: files)) ?? items
    }

    nonisolated static func drafts(for urls: [URL], skipping known: Set<URL>) -> [Draft] {
        var seen = known
        return expand(urls).compactMap { file in
            guard seen.insert(file.standardizedFileURL).inserted else { return nil }
            let metadata = FileMetadata.read(file)
            return Draft(file: file, fileMetadata: metadata, title: metadata.suggestedTitle,
                         description: metadata.description ?? "", tags: metadata.keywords)
        }
    }

    /// Files as given, and the photos and videos inside folders, by name.
    nonisolated static func expand(_ urls: [URL]) -> [URL] {
        urls.flatMap { url -> [URL] in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                return isMedia(url) ? [url] : []
            }
            let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants])
            return (walker?.allObjects as? [URL] ?? []).filter(isMedia)
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
    }

    private nonisolated static func isMedia(_ file: URL) -> Bool {
        guard let type = UTType(filenameExtension: file.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .movie)
    }

    nonisolated static func parseTags(_ typed: String) -> [String] {
        var tags: [String] = []
        var current = ""
        var quoted = false
        for character in typed {
            switch character {
            case "\"": quoted.toggle()
            case "," where !quoted, " " where !quoted:
                if !current.isEmpty { tags.append(current) }
                current = ""
            default: current.append(character)
            }
        }
        if !current.isEmpty { tags.append(current) }
        return tags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func merged(_ first: [String], _ second: [String]) -> [String] {
        (first + second).reduce(into: [String]()) { list, tag in
            if !list.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { list.append(tag) }
        }
    }
}
