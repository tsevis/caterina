import Foundation

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
    /// Set only when the photographs saved but their credits did not.
    public let creditsProblem: String?

    public init(outcomes: [DownloadOutcome], requested: Int, wasCancelled: Bool,
                creditsProblem: String? = nil) {
        self.outcomes = outcomes
        self.requested = requested
        self.wasCancelled = wasCancelled
        self.creditsProblem = creditsProblem
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

    static let simultaneousTransfers = 4

    public init(transport: ChunkTransport = URLSessionChunkTransport()) {
        self.transport = transport
    }

    public func download(_ photos: [Photo], to directory: URL, variant: PhotoVariant,
                         writingCredits: Bool = true,
                         onProgress: @Sendable (DownloadProgress) -> Void = { _ in }
    ) async -> DownloadReport {
        // The folder was chosen in a panel and is about to be written to for
        // as long as the batch takes. A symlink here would redirect every file
        // in it, which the per-file `O_NOFOLLOW` cannot see.
        if let refusal = Self.refusal(for: directory) {
            return DownloadReport(
                outcomes: photos.map { DownloadOutcome(photoID: $0.id, failure: refusal) },
                requested: photos.count, wasCancelled: false)
        }

        let finished = await transferAll(photos, to: directory, variant: variant,
                                         onProgress: onProgress)
        // In the order they were asked for, not the order they finished in.
        let ordered = finished.outcomes.sorted { $0.index < $1.index }
        let saved = ordered.compactMap { entry in
            entry.outcome.path.map { ($0.lastPathComponent, photos[entry.index]) }
        }
        return finish(outcomes: ordered.map(\.outcome), saved: saved,
                      requested: photos.count,
                      cancelled: finished.wasCancelled || Task.isCancelled,
                      directory: directory, writingCredits: writingCredits)
    }

    /// Up to `simultaneousTransfers` photos at once; a new one starts only when
    /// one finishes, and none starts after cancellation.
    private func transferAll(_ photos: [Photo], to directory: URL, variant: PhotoVariant,
                             onProgress: @Sendable (DownloadProgress) -> Void
    ) async -> (outcomes: [(index: Int, outcome: DownloadOutcome)], wasCancelled: Bool) {
        await withTaskGroup(of: (Int, DownloadOutcome?).self) { group in
            var outcomes: [(index: Int, outcome: DownloadOutcome)] = []
            var wasCancelled = false
            var next = 0

            func startNext() {
                guard next < photos.count, !Task.isCancelled else { return }
                let index = next
                next += 1
                group.addTask { (index, await self.save(photos[index], to: directory,
                                                        variant: variant)) }
            }

            for _ in 0..<Self.simultaneousTransfers { startNext() }
            for await (index, outcome) in group {
                // `nil`: cancelled mid-transfer, and the partial file is gone.
                guard let outcome else { wasCancelled = true; continue }
                outcomes.append((index, outcome))
                onProgress(DownloadProgress(completed: outcomes.count,
                                            total: photos.count, outcome: outcome))
                startNext()
            }
            return (outcomes, wasCancelled || next < photos.count)
        }
    }

    /// Write the credits for whatever actually landed, and report.
    ///
    /// Called on every way out, cancellation included: eight photographs saved
    /// before a cancel are eight photographs that need crediting just as much
    /// as forty would have.
    private func finish(outcomes: [DownloadOutcome], saved: [(String, Photo)],
                        requested: Int, cancelled: Bool, directory: URL,
                        writingCredits: Bool) -> DownloadReport {
        var problem: String?
        if writingCredits, !saved.isEmpty {
            problem = Credits.write(saved.map { Credit(file: $0.0, photo: $0.1) },
                                    into: directory)
        }
        return DownloadReport(outcomes: outcomes, requested: requested,
                              wasCancelled: cancelled, creditsProblem: problem)
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
            // Re-checked per photo, not once per batch: `O_NOFOLLOW` refuses a
            // symlink as the *last* path component, and says nothing about the
            // containing directory being swapped for one part-way through a
            // download that may run for minutes.
            if let refusal = Self.refusal(for: directory) {
                return DownloadOutcome(photoID: photo.id, failure: refusal)
            }
            handle = try SafeFile.openTruncating(at: partial)
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

    /// Why this folder cannot be downloaded into, or `nil` if it can.
    private static func refusal(for directory: URL) -> String? {
        let values = try? directory.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values?.isSymbolicLink == true {
            return "That folder is a link to somewhere else. Choose the folder itself."
        }
        guard values?.isDirectory == true else {
            return "That is not a folder that can be written to."
        }
        return nil
    }

    private static func removeQuietly(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func describe(_ error: any Error) -> String {
        if let flickr = error as? FlickrError { return flickr.message }
        return error.localizedDescription
    }
}
