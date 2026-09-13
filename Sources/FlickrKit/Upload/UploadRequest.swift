import Foundation
import UniformTypeIdentifiers

/// A signed upload, with its body already written to a file.
///
/// **The body lives on disk, not in memory.** A 200MB photo read into a `Data`
/// is 200MB of memory per upload in flight; written once to a temporary file
/// it can be streamed by `URLSession` and deleted afterwards.
public struct UploadRequest: Sendable {
    public static let endpoint = "https://up.flickr.com/services/upload/"
    /// Where bodies are written, so anything left by a crash can be swept.
    public static let bodyFolderName = "caterina-upload-bodies"
    private static let copyChunk = 1 << 20

    public let request: URLRequest
    /// The multipart body. The caller deletes it when the upload is over.
    public let body: URL

    public static func make(file: URL, metadata: UploadMetadata, credentials: OAuth1.Credentials,
                            nonce: String = OAuth1.nonce(),
                            timestamp: Int = Int(Date().timeIntervalSince1970)) throws -> UploadRequest {
        guard FileManager.default.isReadableFile(atPath: file.path) else {
            throw FlickrError.invalidInput("Could not read \(file.lastPathComponent).")
        }
        let signed = try OAuth1.signedParameters(method: "POST", url: endpoint,
                                                 parameters: metadata.parameters,
                                                 credentials: credentials, nonce: nonce, timestamp: timestamp)
        let boundary = "caterina-\(UUID().uuidString)"
        let body = try writeBody(fields: signed, file: file, boundary: boundary)

        guard let url = URL(string: endpoint) else { throw OAuth1.SigningError.unusableURL(endpoint) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        return UploadRequest(request: request, body: body)
    }

    private static func writeBody(fields: [OAuthParameter], file: URL, boundary: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(bodyFolderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let body = folder.appendingPathComponent("\(UUID().uuidString).multipart")
        guard FileManager.default.createFile(atPath: body.path, contents: nil) else {
            throw FlickrError.invalidInput("Could not prepare the upload of \(file.lastPathComponent).")
        }
        do {
            let output = try FileHandle(forWritingTo: body)
            defer { try? output.close() }
            for field in fields {
                try output.write(contentsOf: Data("""
                    --\(boundary)\r\nContent-Disposition: form-data; name="\(field.name)"\r\n\r\n\(field.value)\r\n
                    """.utf8))
            }
            try output.write(contentsOf: Data("""
                --\(boundary)\r\nContent-Disposition: form-data; name="photo"; filename="\(headerSafe(file.lastPathComponent))"\r\n\
                Content-Type: \(mimeType(of: file))\r\n\r\n
                """.utf8))
            try copy(file, to: output)
            try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            return body
        } catch {
            try? FileManager.default.removeItem(at: body)
            throw FlickrError.invalidInput("Could not prepare the upload of \(file.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private static func copy(_ file: URL, to output: FileHandle) throws {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: copyChunk), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
    }

    /// A quote, backslash or line break would end the header early.
    static func headerSafe(_ name: String) -> String {
        String(name.map { "\"\\\r\n".contains($0) ? "_" : $0 })
    }

    private static func mimeType(of file: URL) -> String {
        UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}
