import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import FlickrKit

/// What a photo file already says about itself.
///
/// **Whatever the photographer wrote in Lightroom or Photos arrives on Flickr
/// without being typed again**: the IPTC title, caption and keywords, the EXIF
/// date taken, and GPS.
@Suite struct FileMetadataTests {

    /// A real JPEG, written by ImageIO with the properties given.
    static func jpeg(properties: [CFString: Any], name: String = "photo.jpg") throws -> URL {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("caterina-meta-\(UUID().uuidString)-\(name)")
        let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.8, green: 0.5, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return file
    }

    @Test func iptcTitleCaptionAndKeywordsAreRead() throws {
        let file = try Self.jpeg(properties: [kCGImagePropertyIPTCDictionary: [
            kCGImagePropertyIPTCObjectName: "Harbour at dusk",
            kCGImagePropertyIPTCCaptionAbstract: "Piraeus, looking west.",
            kCGImagePropertyIPTCKeywords: ["piraeus", "new york", "dusk"],
        ]])
        defer { try? FileManager.default.removeItem(at: file) }

        let metadata = FileMetadata.read(file)

        #expect(metadata.title == "Harbour at dusk")
        #expect(metadata.description == "Piraeus, looking west.")
        #expect(metadata.keywords == ["piraeus", "new york", "dusk"])
    }

    @Test func theExifDateTakenIsKeptInFlickrsForm() throws {
        let file = try Self.jpeg(properties: [kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifDateTimeOriginal: "2024:06:01 21:14:05",
        ]])
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(FileMetadata.read(file).taken == "2024-06-01 21:14:05")
    }

    /// South and west are carried by separate reference fields, not signs.
    @Test func gpsHonoursItsHemisphere() throws {
        let file = try Self.jpeg(properties: [kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 33.8688, kCGImagePropertyGPSLatitudeRef: "S",
            kCGImagePropertyGPSLongitude: 151.2093, kCGImagePropertyGPSLongitudeRef: "E",
        ]])
        defer { try? FileManager.default.removeItem(at: file) }
        let location = try #require(FileMetadata.read(file).location)
        #expect(abs(location.latitude + 33.8688) < 0.0001)
        #expect(abs(location.longitude - 151.2093) < 0.0001)
        #expect(location.accuracy == 16)
    }

    /// A file with nothing in it is titled by its name, as Flickr itself does.
    @Test func withNoTitleTheFilenameStandsIn() throws {
        let file = try Self.jpeg(properties: [:], name: "IMG_0042.jpg")
        defer { try? FileManager.default.removeItem(at: file) }
        let metadata = FileMetadata.read(file)
        #expect(metadata.title == nil)
        #expect(metadata.suggestedTitle.hasSuffix("IMG_0042"))
        #expect(metadata.keywords.isEmpty)
        #expect(metadata.location == nil)
    }

    @Test func somethingThatIsNotAnImageReadsAsNothing() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("caterina-notes-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let metadata = FileMetadata.read(file)
        #expect(metadata.title == nil && metadata.taken == nil && metadata.location == nil)
    }

    @Test func whatAFileSaysBecomesWhatItUploadsWith() {
        let metadata = FileMetadata(file: URL(fileURLWithPath: "/x/IMG_1.jpg"), title: "Harbour",
                                    description: "West", keywords: ["sea"], taken: nil, location: nil)
        let upload = metadata.uploadMetadata(adding: UploadMetadata(tags: ["athens", "sea"], hiddenFromSearch: true))
        #expect(upload.title == "Harbour")
        #expect(upload.description == "West")
        #expect(upload.tags == ["sea", "athens"])
        #expect(upload.hiddenFromSearch)
    }
}
