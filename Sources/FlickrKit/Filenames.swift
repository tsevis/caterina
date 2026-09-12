import CryptoKit
import Foundation

/// Building the name a photo is saved under.
///
/// Two rules drive this, and both come from defects:
///
/// * A filename must be unique per photo. Flickr titles are free text and
///   collide constantly — "Untitled", "IMG_1234" — so deriving a name from the
///   title alone silently overwrote earlier downloads.
/// * A filename must always be writable, and always inside the save directory.
///   Titles and ids are unbounded text from the network; they are reduced to
///   characters that are safe in a path component and truncated to a byte
///   budget rather than handed to the filesystem as they arrive.
public enum Filenames {

    /// Conservative: most filesystems cap a single component at 255 bytes.
    public static let maxBasenameBytes = 200

    /// Real Flickr ids are about eleven digits. Anything longer is replaced by
    /// a digest, so the name stays bounded without losing uniqueness.
    public static let maxIDCharacters = 24

    public static let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "gif"]
    public static let defaultExtension = "jpg"

    public static let partialSuffix = "part"

    private static let allowedPunctuation: Set<Character> = [" ", "-", "_"]
    private static let fallbackStem = "photo"

    /// Reduce free text to characters that are safe in a path component.
    ///
    /// Separators, dots and control characters are dropped, so the result can
    /// never traverse out of the target directory and can never be `.` or `..`.
    public static func sanitize(title: String) -> String {
        let kept = title.filter { $0.isLetter || $0.isNumber || allowedPunctuation.contains($0) }
        return kept.split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// An allow-listed image extension for a remote URL, without the dot.
    public static func fileExtension(for url: String) -> String {
        let path = url.split(separator: "?", maxSplits: 1).first
            .map(String.init)?
            .split(separator: "#", maxSplits: 1).first
            .map(String.init) ?? ""
        let candidate = (path as NSString).pathExtension.lowercased()
        return allowedExtensions.contains(candidate) ? candidate : defaultExtension
    }

    /// The path to save `photoID` at, always inside `directory`.
    ///
    /// The id is appended unconditionally, so two photos sharing a title still
    /// get separate files while re-downloading one photo stays idempotent.
    public static func destination(in directory: URL, title: String,
                                   photoID: String, url: String) -> URL {
        let suffix = "_\(identifier(for: photoID)).\(fileExtension(for: url))"
        let budget = maxBasenameBytes - suffix.utf8.count
        let stem = truncate(sanitize(title: title), toBytes: budget)
        let name = (stem.isEmpty ? fallbackStem : stem) + suffix
        return directory.appendingPathComponent(name, isDirectory: false)
    }

    /// Where a transfer is written while it is still in flight.
    public static func partial(for destination: URL) -> URL {
        destination.appendingPathExtension(partialSuffix)
    }

    /// A short, path-safe, collision-free token for a photo id.
    ///
    /// An id is used verbatim only when sanitising leaves it untouched.
    /// Anything else is hashed, because stripping characters would otherwise
    /// map distinct ids — `12/3` and `123` — onto the same filename.
    private static func identifier(for photoID: String) -> String {
        guard !photoID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return fallbackStem }

        let cleaned = sanitize(title: photoID).replacingOccurrences(of: " ", with: "")
        if cleaned == photoID, cleaned.count <= maxIDCharacters { return cleaned }

        let digest = SHA256.hash(data: Data(photoID.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Truncate to a UTF-8 byte budget without splitting a character.
    ///
    /// Counting characters rather than bytes was the defect: a title of 200
    /// emoji is 800 bytes, and the filesystem refused the write.
    private static func truncate(_ text: String, toBytes budget: Int) -> String {
        guard budget > 0 else { return "" }
        guard text.utf8.count > budget else { return text }

        var result = ""
        var used = 0
        for character in text {
            let width = String(character).utf8.count
            if used + width > budget { break }
            result.append(character)
            used += width
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
