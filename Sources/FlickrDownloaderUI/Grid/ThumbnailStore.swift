import AppKit
import Foundation

import FlickrKit

/// Thumbnails, fetched concurrently and remembered.
///
/// The reference application fetched thumbnails one at a time on the GUI
/// thread, so a page of 25 took about twelve seconds during which the window
/// was unusable. Here each tile awaits its own image and SwiftUI cancels that
/// work when the tile goes away, which is the structured-concurrency equivalent
/// of the generation token that paper over the same problem.
public actor ThumbnailStore {
    public static let shared = ThumbnailStore()

    /// Bounded, so a long session over a large photostream does not grow
    /// without limit. Counted in images rather than bytes because every
    /// thumbnail here is roughly the same size.
    private static let capacity = 600

    private var cache: [String: NSImage] = [:]
    private var order: [String] = []
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 15
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            self.session = URLSession(configuration: configuration)
        }
    }

    public func image(for address: String) async -> NSImage? {
        if let cached = cache[address] { return cached }
        // Two tiles asking for the same URL share one fetch; a page of
        // duplicates should not be a page of requests.
        if let existing = inFlight[address] { return await existing.value }

        let task = Task<NSImage?, Never> { [session] in
            guard let url = URL(string: address) else { return nil }
            guard let (data, _) = try? await session.data(from: url) else { return nil }
            return NSImage(data: data)
        }
        inFlight[address] = task

        let image = await task.value
        inFlight[address] = nil
        if let image { remember(image, for: address) }
        return image
    }

    private func remember(_ image: NSImage, for address: String) {
        if cache[address] == nil { order.append(address) }
        cache[address] = image
        while order.count > Self.capacity {
            cache.removeValue(forKey: order.removeFirst())
        }
    }

    public func clear() {
        cache.removeAll()
        order.removeAll()
    }
}
