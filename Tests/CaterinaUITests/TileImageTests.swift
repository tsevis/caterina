import Testing

import FlickrKit
@testable import CaterinaUI

/// Which of Flickr's sizes a tile asks for.
@Suite struct TileImageTests {
    private func photo(medium: String?) -> LibraryPhoto {
        LibraryPhoto(id: "1", thumbnailURL: "https://x/1_q.jpg", mediumURL: medium)
    }

    /// Catches: tiny tiles downloading and holding images they cannot show.
    @Test func aSmallTileAsksFlickrForASmallerImage() {
        #expect(TileImage.address(of: photo(medium: "https://x/1_z.jpg"), tileSize: 90) == "https://x/1_n.jpg")
    }

    /// Catches: large tiles going soft.
    @Test func aLargeTileKeepsTheMediumImage() {
        #expect(TileImage.address(of: photo(medium: "https://x/1_z.jpg"), tileSize: 200) == "https://x/1_z.jpg")
    }

    /// Catches: a broken address when Flickr's name is not the expected one.
    @Test func anAddressOfAnotherShapeIsLeftAlone() {
        #expect(TileImage.address(of: photo(medium: "https://x/1_o.png"), tileSize: 90) == "https://x/1_o.png")
        #expect(TileImage.address(of: photo(medium: nil), tileSize: 90) == "https://x/1_q.jpg")
    }
}
