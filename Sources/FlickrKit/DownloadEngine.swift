import Foundation

/// Streaming bytes from a URL, in chunks.
///
/// A protocol so cancellation and partial-file behaviour can be tested without
/// a network — a stalled transfer in a test is a stream that suspends, not a
/// real socket left open.
public protocol ChunkTransport: Sendable {
    func chunks(from url: URL) async throws -> AsyncThrowingStream<Data, any Error>
}

/// The real one. **Every transfer carries a timeout**; one without a timeout
/// hung the reference application forever, with a progress bar and no way out.
public struct URLSessionChunkTransport: ChunkTransport {
    public static let requestTimeout: TimeInterval = 30
    public static let resourceTimeout: TimeInterval = 600
    public static let chunkSize = 64 * 1024

    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.resourceTimeout
        self.session = URLSession(configuration: configuration)
    }

    public func chunks(from url: URL) async throws -> AsyncThrowingStream<Data, any Error> {
        let (bytes, response) = try await session.bytes(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FlickrError.transport("The photo server answered HTTP \(http.statusCode).")
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var buffer = Data()
                buffer.reserveCapacity(Self.chunkSize)
                do {
                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= Self.chunkSize {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty { continuation.yield(buffer) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Results

public struct DownloadOutcome: Sendable, Equatable, Identifiable {
    public let photoID: String
    public let path: URL?
    /// Nil when the photo was saved.
    public let failure: String?

    public var id: String { photoID }
    public var isSaved: Bool { failure == nil && path != nil }

    public init(photoID: String, path: URL? = nil, failure: String? = nil) {
        self.photoID = photoID
        self.path = path
        self.failure = failure
    }
}

public struct DownloadProgress: Sendable, Equatable {
    public let completed: Int
    public let total: Int
    public let outcome: DownloadOutcome

    public var fraction: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }
}

/// What to tell the user when it is over.
///
/// `requested` is what was asked for and `outcomes` is what was attempted, so a
/// cancelled batch can report "Saved 4 of 20" rather than claiming twenty were
/// tried.
public struct DownloadReport: Sendable, Equatable {
    public let outcomes: [DownloadOutcome]
    public let requested: Int
    public let wasCancelled: Bool

    public init(outcomes: [DownloadOutcome], requested: Int, wasCancelled: Bool) {
        self.outcomes = outcomes
        self.requested = requested
        self.wasCancelled = wasCancelled
    }

    public var saved: Int { outcomes.filter(\.isSaved).count }
    public var failures: [DownloadOutcome] { outcomes.filter { !$0.isSaved } }

    public var summary: String { "Saved \(saved) of \(requested)" }
}

// MARK: - The engine

/// Downloading a batch of photos.
///
/// An actor, so a download in flight has one owner and closing the window can
/// cancel it and *await* the result rather than abandoning it. Cancellation is
/// deterministic: the transfer in flight is deleted, everything already renamed
/// into place stays, and the report is returned rather than thrown away.
public actor DownloadEngine {
    private let transport: ChunkTransport

    public init(transport: ChunkTransport = URLSessionChunkTransport()) {
        self.transport = transport
    }

    public func download(_ photos: [Photo], to directory: URL, variant: PhotoVariant,
                         onProgress: @Sendable (DownloadProgress) -> Void = { _ in }
    ) async -> DownloadReport {
        var outcomes: [DownloadOutcome] = []

        for photo in photos {
            if Task.isCancelled {
                return DownloadReport(outcomes: outcomes, requested: photos.count,
                                      wasCancelled: true)
            }

            guard let outcome = await save(photo, to: directory, variant: variant) else {
                // Cancelled mid-transfer: the partial file is already gone.
                return DownloadReport(outcomes: outcomes, requested: photos.count,
                                      wasCancelled: true)
            }

            outcomes.append(outcome)
            onProgress(DownloadProgress(completed: outcomes.count,
                                        total: photos.count, outcome: outcome))
        }

        return DownloadReport(outcomes: outcomes, requested: photos.count,
                              wasCancelled: Task.isCancelled)
    }

    /// One photo. `nil` means the user cancelled while it was in flight.
    private func save(_ photo: Photo, to directory: URL,
                      variant: PhotoVariant) async -> DownloadOutcome? {
        guard let address = photo.downloadURL(preferring: variant),
              let url = URL(string: address)
        else {
            return DownloadOutcome(photoID: photo.id,
                                   failure: "Flickr published no downloadable file for this photo.")
        }

        let destination = Filenames.destination(in: directory, title: photo.title,
                                                photoID: photo.id, url: address)
        let partial = Filenames.partial(for: destination)

        var handle: FileHandle
        do {
            handle = try Self.openRefusingSymlinks(at: partial)
        } catch {
            return DownloadOutcome(photoID: photo.id, failure: Self.describe(error))
        }

        do {
            for try await chunk in try await transport.chunks(from: url) {
                if Task.isCancelled {
                    try? handle.close()
                    Self.removeQuietly(partial)
                    return nil
                }
                try handle.write(contentsOf: chunk)
            }
            // **A cancelled stream ends, it does not throw.** `AsyncThrowingStream`
            // finishes its iterator when the consuming task is cancelled, so
            // the loop above exits normally with a half-written file — and the
            // rename below would publish it as a complete photo. Cancellation
            // has to be re-checked here, not only inside the loop.
            if Task.isCancelled {
                try? handle.close()
                Self.removeQuietly(partial)
                return nil
            }
            try handle.close()
        } catch {
            try? handle.close()
            Self.removeQuietly(partial)
            if Task.isCancelled || error is CancellationError { return nil }
            return DownloadOutcome(photoID: photo.id, failure: Self.describe(error))
        }

        // Renamed only once the transfer completed, so a failure never leaves a
        // truncated image behind for the user to discover later.
        guard rename(partial.path, destination.path) == 0 else {
            let reason = String(cString: strerror(errno))
            Self.removeQuietly(partial)
            return DownloadOutcome(photoID: photo.id, failure: "Could not save the file: \(reason)")
        }
        return DownloadOutcome(photoID: photo.id, path: destination)
    }

    /// Open for writing, refusing to follow a symlink at that name.
    ///
    /// The save directory may be shared and the temp name is predictable, so a
    /// pre-planted symlink must not redirect the write to another file.
    private static func openRefusingSymlinks(at url: URL) throws -> FileHandle {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else {
            throw FlickrError.transport(
                "Could not write to \(url.lastPathComponent): \(String(cString: strerror(errno)))")
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private static func removeQuietly(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func describe(_ error: any Error) -> String {
        if let flickr = error as? FlickrError { return flickr.message }
        return error.localizedDescription
    }
}
