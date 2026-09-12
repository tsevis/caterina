import AppKit
import Foundation
import ImageIO

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

    private var images: [String: NSImage] = [:]
    private var order: [String] = []
    private let session: URLSession

    /// What the on-disk cache is allowed to grow to.
    ///
    /// **`URLSessionConfiguration.default` has no meaningful bound**, and this
    /// cache holds other people's photographs: a browsing session left 6.6MB of
    /// them in the container, growing with every page and surviving every
    /// relaunch. Caching thumbnails is worth doing — it is what makes paging
    /// back feel instant — but it has to be a stated size rather than whatever
    /// the system feels like keeping.
    public static let diskCapacity = 128 * 1024 * 1024
    public static let memoryCapacity = 32 * 1024 * 1024

    private let cache: URLCache

    public init(session: URLSession? = nil) {
        let cache = URLCache(memoryCapacity: Self.memoryCapacity,
                             diskCapacity: Self.diskCapacity, directory: nil)
        self.cache = cache

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 15
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            configuration.urlCache = cache
            self.session = URLSession(configuration: configuration)
        }
    }

    public func image(for address: String) async -> NSImage? {
        if let cached = images[address] { return cached }
        guard let url = URL(string: address),
              let (data, _) = try? await session.data(from: url),
              let image = Self.thumbnail(from: data)
        else { return nil }

        remember(image, for: address)
        return image
    }

    /// The largest a thumbnail is ever drawn, and therefore the largest it is
    /// ever decoded.
    public static let maximumPixels = 1024

    /// Decode to a bounded size rather than to whatever the file claims.
    ///
    /// **`NSImage(data:)` will allocate whatever the image says it needs.** A
    /// small file can declare enormous dimensions — a decompression bomb — and
    /// these files come from any Flickr user, reachable through a search or a
    /// group pool. The cache bounds how many thumbnails are kept and how many
    /// bytes are held on disk; neither bounds the decoded bitmap. `ImageIO`
    /// decodes straight to the size actually wanted, so a hostile image costs
    /// no more memory than an honest one.
    static func thumbnail(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage,
                       size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func remember(_ image: NSImage, for address: String) {
        if images[address] == nil { order.append(address) }
        images[address] = image
        while order.count > Self.capacity {
            images.removeValue(forKey: order.removeFirst())
        }
    }

    /// Forget every thumbnail, on disk as well as in memory.
    ///
    /// What someone browsed is their business, and "sign out" should not leave
    /// a picture of it behind.
    public func clear() {
        images.removeAll()
        order.removeAll()
        cache.removeAllCachedResponses()
    }

    /// How much of the bound is currently in use, for anyone who wants to know.
    public var diskUsage: Int { cache.currentDiskUsage }
}
