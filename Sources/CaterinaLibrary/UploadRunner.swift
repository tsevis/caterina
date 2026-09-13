import Foundation

import FlickrKit

/// What sending photos needs from Flickr. `FlickrClient` in the app.
public protocol PhotoUploader: Sendable {
    func upload(file: URL, metadata: UploadMetadata,
                progress: @escaping @Sendable (Double) -> Void) async throws -> String
    func checkTickets(_ tickets: [String]) async throws -> [String: TicketStatus]
    func createAlbum(title: String, description: String, coverPhotoID: String,
                     priority: CallPriority) async throws -> String
    func addToAlbum(photoID: String, albumID: String, priority: CallPriority) async throws
}

extension FlickrClient: PhotoUploader {}

/// Running an upload batch: send, wait for Flickr to process, file into the
/// album.
///
/// **Every step is recorded before the next**, so a relaunch picks up where
/// it stopped: queued files are sent, issued tickets are checked, and done
/// photos still go into their album. The one thing never resumed on its own is
/// a file that was mid-send, because Flickr may already have it.
///
/// One runner per batch at a time: starting marks anything left "sending" as
/// interrupted.
public struct UploadRunner: Sendable {
    public static let simultaneousUploads = 2
    static let ticketsPerCheck = 50

    private let uploader: PhotoUploader
    private let store: LibraryStore
    private let files: FileAccess
    private let pollInterval: Duration
    private let sleep: Sleeper

    public init(uploader: PhotoUploader, store: LibraryStore, files: FileAccess,
                pollInterval: Duration = .seconds(3),
                sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }) {
        self.uploader = uploader
        self.store = store
        self.files = files
        self.pollInterval = pollInterval
        self.sleep = sleep
    }

    @discardableResult
    public func run(_ batchID: String,
                    progress: @escaping @Sendable (UploadBatch.Summary) -> Void = { _ in }) async throws -> UploadBatch.Summary {
        try store.interruptSending(in: batchID)
        try await sendQueued(batchID, progress: progress)
        try await waitForProcessing(batchID, progress: progress)
        try await fileIntoAlbum(batchID)
        return try store.uploadSummary(of: batchID)
    }

    // MARK: - Sending

    private func sendQueued(_ batchID: String,
                            progress: @escaping @Sendable (UploadBatch.Summary) -> Void) async throws {
        let queued = try store.uploadItems(in: batchID, files: files).filter { $0.state == .queued }
        try await withThrowingTaskGroup(of: Void.self) { group in
            var pending = queued[...]
            for _ in 0..<Self.simultaneousUploads {
                guard let item = pending.popFirst() else { break }
                group.addTask { try await send(item) }
            }
            while try await group.next() != nil {
                progress(try store.uploadSummary(of: batchID))
                if let item = pending.popFirst() { group.addTask { try await send(item) } }
            }
        }
    }

    private func send(_ item: UploadItem) async throws {
        try Task.checkCancellation()
        try store.markUpload(item, .sending)
        do {
            let ticket = try await files.withAccess(to: item.file) {
                try await uploader.upload(file: item.file, metadata: item.metadata) { _ in }
            }
            try store.markUpload(item, .processing(ticket: ticket))
        } catch let error as FlickrError {
            // Refused before anything arrived: permission, or Flickr busy. The
            // file is safe to send again, so it goes back in the queue and the
            // batch pauses.
            if case .permissionNeeded = error { try store.markUpload(item, .queued); throw error }
            if case .api = error, error.isTransient { try store.markUpload(item, .queued); throw error }
            if case .busy = error { try store.markUpload(item, .queued); throw error }
            // A lost connection may have lost only the reply.
            if error.isTransient { try store.markUpload(item, .interrupted); throw error }
            try store.markUpload(item, .failed(error.message))
        } catch {
            try? store.markUpload(item, .interrupted)
            throw error
        }
    }

    // MARK: - Waiting for Flickr

    private func waitForProcessing(_ batchID: String,
                                   progress: @Sendable (UploadBatch.Summary) -> Void) async throws {
        while true {
            let processing = try store.uploadItems(in: batchID, files: files).compactMap { item -> (UploadItem, String)? in
                if case let .processing(ticket) = item.state { return (item, ticket) }
                return nil
            }
            guard !processing.isEmpty else { return }
            for chunk in stride(from: 0, to: processing.count, by: Self.ticketsPerCheck) {
                let slice = processing[chunk..<min(chunk + Self.ticketsPerCheck, processing.count)]
                let statuses = try await uploader.checkTickets(slice.map(\.1))
                for (item, ticket) in slice { try record(statuses[ticket] ?? .invalid, for: item) }
            }
            progress(try store.uploadSummary(of: batchID))
            if try store.uploadSummary(of: batchID).remaining > 0 { try await sleep(pollInterval) }
        }
    }

    private func record(_ status: TicketStatus, for item: UploadItem) throws {
        switch status {
        case .processing: return
        case let .done(photoID): try store.markUpload(item, .done(photoID: photoID))
        case .failed: try store.markUpload(item, .failed("Flickr could not process this file."))
        case .invalid:
            try store.markUpload(item, .failed("Flickr lost track of this upload. Check your photostream before sending it again."))
        }
    }

    // MARK: - Albums

    private func fileIntoAlbum(_ batchID: String) async throws {
        let batch = try store.uploadBatch(batchID)
        guard batch.album != .none else { return }
        var albumID = batch.albumID
        let waiting = try store.uploadItems(in: batchID, files: files).filter { $0.photoID != nil && !$0.inAlbum }
        for item in waiting {
            guard let photoID = item.photoID else { continue }
            if let existing = albumID {
                try await uploader.addToAlbum(photoID: photoID, albumID: existing, priority: .upload)
            } else if case let .new(title) = batch.album {
                let created = try await uploader.createAlbum(title: title, description: "",
                                                             coverPhotoID: photoID, priority: .upload)
                try store.recordAlbum(created, for: batchID)
                albumID = created
            }
            try store.markInAlbum(item)
        }
    }
}
