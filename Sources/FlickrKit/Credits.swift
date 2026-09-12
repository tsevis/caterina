import Foundation

/// Who made a photograph, and on what terms.
public struct Credit: Sendable, Equatable {
    public let file: String
    public let photoID: String
    public let title: String
    public let photographer: String
    public let licence: String
    public let terms: String
    public let source: String

    public init(file: String, photo: Photo) {
        self.file = file
        self.photoID = photo.id
        self.title = photo.title
        self.photographer = photo.photographer ?? "Unknown"
        self.licence = photo.license?.label ?? "Not stated by Flickr"
        self.terms = photo.license?.termsURL ?? ""
        self.source = photo.pageURL ?? ""
    }
}

/// The credits file written beside a download.
///
/// **Without this the application's own promise was false.** The splash reads
/// "Photos off Flickr, with their licences attached" and tells the reader that
/// a Creative Commons licence still asks for attribution — while what landed on
/// disk was `title_id.jpg` and nothing else. A folder of five hundred CC-BY
/// photographs held no photographer, no licence and no link, so complying with
/// the terms meant finding every one of them on Flickr again by hand.
///
/// CSV because it opens in anything, and appended rather than replaced because
/// a folder is usually downloaded into more than once.
public enum Credits {
    public static let filename = "Credits.csv"

    public static let header = ["File", "Photographer", "Licence", "Terms",
                                "Title", "Photo ID", "Source"]

    /// One row, with the quoting CSV actually requires.
    public static func row(_ credit: Credit) -> String {
        [credit.file, credit.photographer, credit.licence, credit.terms,
         credit.title, credit.photoID, credit.source]
            .map(escaped)
            .joined(separator: ",")
    }

    /// A field is always quoted: a photograph's title is free text from the
    /// internet and may hold a comma, a quotation mark or a newline.
    static func escaped(_ field: String) -> String {
        "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Append `credits` to the file in `directory`, creating it with a header
    /// if it is not there yet.
    ///
    /// Failing to write credits must never fail a download — the photographs
    /// are what was asked for — so this reports rather than throws.
    @discardableResult
    public static func write(_ credits: [Credit], into directory: URL) -> String? {
        guard !credits.isEmpty else { return nil }

        let url = directory.appendingPathComponent(filename)
        let manager = FileManager.default
        let isNew = !manager.fileExists(atPath: url.path)

        var text = isNew ? header.map(escaped).joined(separator: ",") + "\n" : ""
        text += credits.map(row).joined(separator: "\n") + "\n"

        do {
            if isNew {
                try Data(text.utf8).write(to: url, options: [.atomic])
            } else {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(text.utf8))
            }
            return nil
        } catch {
            return "The photos were saved, but the credits file could not be "
                + "written: \(error.localizedDescription)"
        }
    }
}
