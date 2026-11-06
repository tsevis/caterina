import Foundation
import Testing

@testable import FlickrKit

/// The client's side of an upload: permission, budget, retries, clean-up.
@Suite struct ClientUploadTests {

    private let ok = #"<rsp stat="ok"><ticketid>77-1</ticketid></rsp>"#

    private func client(_ transport: ScriptedTransport, granted: FlickrPermission = .write) -> FlickrClient {
        FlickrClient(credentials: Fixtures.credentials, permission: granted, transport: transport,
                     budget: .unspaced, sleep: SleepRecorder().sleep)
    }

    private func photo() throws -> URL {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("caterina-client-upload-\(UUID().uuidString).jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: file)
        return file
    }

    @Test func anUploadReturnsItsTicketAndLeavesNoBodyBehind() async throws {
        let transport = ScriptedTransport(always: ok)
        let file = try photo()
        defer { try? FileManager.default.removeItem(at: file) }

        let ticket = try await client(transport).upload(file: file, metadata: UploadMetadata(title: "x"))

        #expect(ticket == "77-1")
        let sent = try #require(await transport.uploaded.first)
        #expect(sent.request.url?.host == "up.flickr.com")
        #expect(sent.body.range(of: Data([0xFF, 0xD8, 0xFF])) != nil)
        #expect(!FileManager.default.fileExists(atPath: sent.file.path))
    }

    @Test func uploadingNeedsWritePermission() async throws {
        let transport = ScriptedTransport(always: ok)
        let file = try photo()
        defer { try? FileManager.default.removeItem(at: file) }
        await #expect(throws: FlickrError.permissionNeeded(.write)) {
            _ = try await client(transport, granted: .read).upload(file: file, metadata: UploadMetadata())
        }
        #expect(await transport.callCount == 0)
    }

    /// The photo may have arrived before the connection dropped; sending it
    /// again would put it on Flickr twice.
    @Test func aLostConnectionIsNotRetried() async throws {
        let transport = ScriptedTransport([.failure(.transport("The network connection was lost.")), .body(ok)])
        let file = try photo()
        defer { try? FileManager.default.removeItem(at: file) }
        await #expect(throws: FlickrError.self) {
            _ = try await client(transport).upload(file: file, metadata: UploadMetadata())
        }
        #expect(await transport.callCount == 1)
    }

    @Test func flickrBeingBusyIsRetried() async throws {
        let transport = ScriptedTransport([.body(#"<rsp stat="fail"><err code="105" msg="Service currently unavailable" /></rsp>"#),
                                           .body(ok)])
        let file = try photo()
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try await client(transport).upload(file: file, metadata: UploadMetadata()) == "77-1")
        #expect(await transport.callCount == 2)
    }

    @Test func progressIsPassedOn() async throws {
        let transport = ScriptedTransport(always: ok)
        let file = try photo()
        defer { try? FileManager.default.removeItem(at: file) }
        let seen = Fractions()
        _ = try await client(transport).upload(file: file, metadata: UploadMetadata()) { seen.add($0) }
        #expect(seen.values.last == 1.0)
        #expect(seen.values.count == 2)
    }

    @Test func ticketsAreCheckedTogether() async throws {
        let transport = ScriptedTransport(always: #"{"uploader":{"ticket":[{"id":"1","complete":1,"photoid":"9"},{"id":"2","complete":0}]},"stat":"ok"}"#)
        let statuses = try await client(transport).checkTickets(["1", "2"])
        #expect(statuses == ["1": .done(photoID: "9"), "2": .processing])
        #expect(await transport.lastQueryItems["method"] == "flickr.photos.upload.checkTickets")
        #expect(await transport.lastQueryItems["tickets"] == "1,2")
    }
}

final class Fractions: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Double] = []
    var values: [Double] { lock.withLock { stored } }
    func add(_ value: Double) { lock.withLock { stored.append(value) } }
}

/// A 401 means Flickr refused the token before taking anything: never busy,
/// never a retry, and the photo is safe to send again once it is approved.
@Suite struct RejectedTokenTests {

    private func client(_ transport: ScriptedTransport) -> FlickrClient {
        FlickrClient(credentials: Fixtures.credentials, permission: .write, transport: transport,
                     budget: .unspaced, sleep: SleepRecorder().sleep)
    }

    @Test func anHTTP401ReadsAsARejectedSignInNamingTheProblem() {
        let error = URLSessionTransport.failure(status: 401, body: Data("oauth_problem=token_rejected".utf8))
        #expect(error == .signInRejected("token_rejected"))
        #expect(error.isTransient == false)
    }

    @Test func otherStatusesStayTransient() {
        #expect(URLSessionTransport.failure(status: 502, body: Data()).isTransient)
    }

    @Test func anUploadRefusedWith401AsksForApprovalInsteadOfRetrying() async throws {
        let transport = ScriptedTransport([.failure(.signInRejected("token_rejected"))])
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("caterina-rejected-\(UUID().uuidString).jpg")
        try Data([0xFF]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        await #expect(throws: FlickrError.permissionNeeded(.write)) {
            _ = try await client(transport).upload(file: file, metadata: UploadMetadata())
        }
        #expect(await transport.callCount == 1)
    }

    /// Approving issues a new token, which cannot cure a bad signature: the
    /// sheet would come back after every approval, and the reason would be lost.
    @Test func aBadSignatureOnAnUploadKeepsItsReasonInsteadOfAskingForApproval() async throws {
        let transport = ScriptedTransport([.failure(.signInRejected("signature_invalid"))])
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("caterina-signature-\(UUID().uuidString).jpg")
        try Data([0xFF]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        await #expect(throws: FlickrError.signInRejected("signature_invalid")) {
            _ = try await client(transport).upload(file: file, metadata: UploadMetadata())
        }
    }

    @Test func aBadSignatureOnAWriteKeepsItsReasonToo() async throws {
        let transport = ScriptedTransport([.failure(.signInRejected("signature_invalid"))])
        let write = FlickrWrite(method: "flickr.photos.setTags", arguments: ["photo_id": "1", "tags": "a"],
                                repeatable: true)
        await #expect(throws: FlickrError.signInRejected("signature_invalid")) {
            _ = try await client(transport).perform(write)
        }
    }

    /// Files already sent, token revoked while waiting: this has to reach the
    /// same approval sheet, or the batch sits paused with nothing to press.
    @Test func checkingTicketsWithARejectedTokenAsksForApproval() async throws {
        let transport = ScriptedTransport([.failure(.signInRejected("token_rejected"))])
        await #expect(throws: FlickrError.permissionNeeded(.write)) {
            _ = try await client(transport).checkTickets(["1"])
        }
    }

    /// Only a token problem is cured by signing in again.
    @Test func theMessageNamesTheCureThatFits() {
        #expect(FlickrError.signInRejected("token_rejected").message.contains("Sign in again"))
        #expect(FlickrError.signInRejected("timestamp_refused").message.contains("clock"))
    }

    @Test func aWriteRefusedWith401AsksForApprovalToo() async throws {
        let transport = ScriptedTransport([.failure(.signInRejected("token_rejected"))])
        let write = FlickrWrite(method: "flickr.photos.setTags", arguments: ["photo_id": "1", "tags": "a"],
                                repeatable: true)
        await #expect(throws: FlickrError.permissionNeeded(write.permission)) {
            _ = try await client(transport).perform(write)
        }
        #expect(await transport.callCount == 1)
    }
}
