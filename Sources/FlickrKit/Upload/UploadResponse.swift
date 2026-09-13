import Foundation

/// Where one upload has got to after Flickr took the file.
public enum TicketStatus: Sendable, Equatable {
    case processing
    case done(photoID: String)
    /// Flickr could not convert the file.
    case failed
    /// Flickr has no such ticket.
    case invalid
}

/// Reading what the upload endpoint and `checkTickets` answer.
public enum UploadResponse {

    /// The upload endpoint answers XML whatever `format` says.
    public static func ticket(from data: Data) throws -> String {
        let reply = XMLReply(data)
        if let code = reply.errorCode {
            throw FlickrError.api(code: code, message: reply.errorMessage ?? "Flickr refused the upload.",
                                  transient: FlickrError.transientCodes.contains(code))
        }
        guard reply.status == "ok", let ticket = reply.ticketID, !ticket.isEmpty else {
            throw FlickrError.malformedResponse("Flickr's answer to the upload could not be read.")
        }
        return ticket
    }

    public static func tickets(from data: Data) throws -> [String: TicketStatus] {
        try FlickrResponse.throwIfFailed(data)
        struct Envelope: Decodable { let uploader: Uploader? }
        struct Uploader: Decodable { let ticket: [Ticket]? }
        struct Ticket: Decodable {
            let id: String
            let complete: FlickrResponse.LooseInt?
            let invalid: FlickrResponse.LooseInt?
            let photoid: String?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw FlickrError.malformedResponse("Flickr's upload status could not be read.")
        }
        let pairs = (envelope.uploader?.ticket ?? []).map { ticket -> (String, TicketStatus) in
            if ticket.invalid?.value == 1 { return (ticket.id, .invalid) }
            switch ticket.complete?.value {
            case 1: return (ticket.id, ticket.photoid.map { .done(photoID: $0) } ?? .failed)
            case 2: return (ticket.id, .failed)
            default: return (ticket.id, .processing)
            }
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }
}

/// The few elements an upload reply has.
private final class XMLReply: NSObject, XMLParserDelegate {
    private(set) var status: String?
    private(set) var errorCode: Int?
    private(set) var errorMessage: String?
    private(set) var ticketID: String?
    private var text = ""

    init(_ data: Data) {
        super.init()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch element {
        case "rsp": status = attributes["stat"]
        case "err":
            errorCode = attributes["code"].flatMap(Int.init)
            errorMessage = attributes["msg"]
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        if element == "ticketid" { ticketID = text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
