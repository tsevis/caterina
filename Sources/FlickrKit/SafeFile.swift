import Foundation

/// Writing untrusted bytes to a path, safely, in one place.
///
/// **There were three implementations of this and they were not equally good.**
/// The download path opened with `O_NOFOLLOW` precisely because its temporary
/// name is predictable; the drag path put each file under a fresh UUID
/// directory; and the Quick Look path — whose name is *entirely* predictable,
/// since Flickr photo ids are public — used a plain `Data.write(to:)` with
/// neither protection. A hostile process running as the same user could
/// pre-plant a symlink at that name and have the app overwrite whatever the
/// link pointed at, with bytes from a photograph the attacker chose.
///
/// One audited helper, used by all three.
public enum SafeFile {

    /// Open for writing, refusing to follow a symlink at that name, replacing
    /// whatever is there.
    ///
    /// For a name the application expects to reuse — a `.part` file left by a
    /// previous run has to be overwritable.
    public static func openTruncating(at url: URL) throws -> FileHandle {
        try open(at: url, flags: O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW)
    }

    /// Open for writing, refusing both to follow a symlink *and* to touch a
    /// file that already exists.
    ///
    /// For a name that should be new every time. If anything is already there,
    /// something put it there.
    public static func createExclusively(at url: URL) throws -> FileHandle {
        try open(at: url, flags: O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW)
    }

    public static func write(_ data: Data, to url: URL) throws {
        let handle = try createExclusively(at: url)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
    }

    /// A directory nothing can have got to first.
    ///
    /// The name carries a UUID, so there is no path for an attacker to predict
    /// and pre-plant, and `withIntermediateDirectories: false` means creation
    /// fails rather than succeeds if one somehow exists.
    public static func uniqueDirectory(in parent: URL, prefix: String) throws -> URL {
        let url = parent.appendingPathComponent("\(prefix)\(UUID().uuidString)",
                                                isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return url
    }

    private static func open(at url: URL, flags: Int32) throws -> FileHandle {
        // 0600: a downloaded photograph is the user's business, not the
        // machine's.
        let descriptor = Darwin.open(url.path, flags, 0o600)
        guard descriptor >= 0 else {
            throw FlickrError.transport(
                "Could not write \(url.lastPathComponent): "
                + String(cString: strerror(errno)))
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
}
