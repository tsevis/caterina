import AppKit
import Foundation

import FlickrKit

/// Thumbnails, fetched concurrently and remembered.
///
/// The reference application fetched thumbnails one at a time on the GUI
/// thread, so a page of 25 took about twelve seconds during which the window
/// was unusable. Here each tile awaits its own image inside its own `.task`,
/// and the fetch is *structured* — awaited directly rather than handed to an
/// unstructured `Task` — so scrolling a tile away cancels the transfer rather
/// than merely discarding its result. Five hundred abandoned requests still in
/// flight is the bug that wording used to hide.
public actor ThumbnailStore {
    public static let shared = ThumbnailStore()

    /// Bounded, so a long session over a large photostream does not grow
    /// without limit. Counted in images rather than bytes because every
    /// thumbnail here is roughly the same size.
    private static let capacity = 600

    private var cache: [String: NSImage] = [:]
    private var order: [String] = []
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
        guard let url = URL(string: address),
              let (data, _) = try? await session.data(from: url),
              let image = NSImage(data: data)
        else { return nil }

        remember(image, for: address)
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
