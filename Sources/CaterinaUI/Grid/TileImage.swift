import FlickrKit

/// Which of Flickr's sizes a tile asks for.
///
/// Flickr's address names its size, and every photo has these: `_z` is 640
/// pixels on the long side and `_n` is 320, which still covers a small tile on
/// a Retina screen. Asking for less is what lets a whole library scroll without
/// holding every large image in memory.
enum TileImage {
    /// Points. Above this, 320 pixels would look soft.
    static let smallTile = 120.0

    static func address(of photo: LibraryPhoto, tileSize: Double) -> String? {
        let medium = photo.mediumURL ?? photo.thumbnailURL
        guard tileSize <= smallTile, let address = photo.mediumURL, address.hasSuffix("_z.jpg") else { return medium }
        return String(address.dropLast("_z.jpg".count)) + "_n.jpg"
    }
}
