import Foundation

/// A Flickr member, as confirmed by Flickr.
public struct FlickrPerson: Sendable, Equatable, Hashable {
    public let nsid: String
    public let username: String

    public init(nsid: String, username: String) {
        self.nsid = nsid
        self.username = username
    }
}

extension FlickrClient {

    /// Exactly the member meant: an address is resolved by Flickr
    /// (`urls.lookupUser`), an NSID confirmed (`people.getInfo`), anything
    /// else looked up as a username. The name comes back to be shown before
    /// anything is written.
    public func lookUpPerson(_ input: String) async throws -> FlickrPerson {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw FlickrError.invalidInput("Enter a Flickr username or photostream address.") }
        struct Name: Decodable { let _content: String? }
        if Self.isNSID(text) {
            struct Envelope: Decodable { let person: Person }
            struct Person: Decodable { let nsid: String; let username: Name? }
            let person = try InsightsResponse.decode(Envelope.self, try checked(await call("flickr.people.getInfo", ["user_id": text])),
                                                     "the member").person
            return FlickrPerson(nsid: person.nsid, username: person.username?._content ?? person.nsid)
        }
        struct Envelope: Decodable { let user: User }
        struct User: Decodable { let id: String; let username: Name? }
        let isAddress = text.lowercased().contains("flickr.com")
        let data = isAddress ? try await call("flickr.urls.lookupUser", ["url": text])
                             : try await call("flickr.people.findByUsername", ["username": text])
        let user = try InsightsResponse.decode(Envelope.self, try checked(data), "the member").user
        return FlickrPerson(nsid: user.id, username: user.username?._content ?? user.id)
    }

    static func isNSID(_ text: String) -> Bool {
        text.wholeMatch(of: /[0-9]+@N[0-9]+/) != nil
    }

    private func checked(_ data: Data) throws -> Data {
        try FlickrResponse.throwIfFailed(data)
        return data
    }
}
