import Foundation

/// Text with placeholders, filled in for each photo in a batch.
///
/// `{title}` the title before the edit · `{date}` date taken, `yyyy-MM-dd` ·
/// `{year}` · `{n}` the photo's place in the batch, from 1 · `{nn}` the same,
/// padded to the batch's width · `{count}` photos in the batch. Anything else
/// in braces is left as typed.
public enum TitlePattern {

    public static let placeholders = ["{title}", "{date}", "{year}", "{n}", "{nn}", "{count}"]

    public static func render(_ pattern: String, photo: LibraryPhoto, context: PhotoEdit.Context) -> String {
        guard pattern.contains("{") else { return pattern }
        let date = photo.taken.map { String($0.prefix(10)) } ?? ""
        let width = String(context.count).count
        let number = String(context.position)
        let values = [
            "{title}": photo.title,
            "{date}": date,
            "{year}": String(date.prefix(4)),
            "{nn}": String(repeating: "0", count: max(0, width - number.count)) + number,
            "{n}": number,
            "{count}": String(context.count),
        ]
        return fill(pattern, with: values)
    }

    /// One pass, left to right, so a value that happens to contain a
    /// placeholder (a title with "{n}" in it) is never filled in again.
    private static func fill(_ pattern: String, with values: [String: String]) -> String {
        var output = ""
        var rest = pattern[...]
        while let open = rest.firstIndex(of: "{") {
            output += rest[..<open]
            let tail = rest[open...]
            if let key = values.keys.first(where: { tail.hasPrefix($0) }), let value = values[key] {
                output += value
                rest = tail.dropFirst(key.count)
            } else {
                output += "{"
                rest = tail.dropFirst()
            }
        }
        return output + rest
    }
}
