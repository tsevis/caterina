import Foundation

/// A group, once it is actually known to exist.
public struct ResolvedGroup: Sendable, Equatable, Hashable {
    public let nsid: String
    public let name: String

    public init(nsid: String, name: String) {
        self.nsid = nsid
        self.name = name
    }
}

/// Talking to Flickr.
///
/// An actor because the credentials change when the user signs in or out, and
/// every section of the interface holds the same client.
public actor FlickrClient {
    public static let endpoint = "https://api.flickr.com/services/rest/"

    private var credentials: OAuth1.Credentials
    private let transport: HTTPTransport
    private let policy: RetryPolicy
    private let sleep: Sleeper

    public init(credentials: OAuth1.Credentials,
                transport: HTTPTransport = URLSessionTransport(),
                policy: RetryPolicy = .standard,
                sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }) {
        self.credentials = credentials
        self.transport = transport
        self.policy = policy
        self.sleep = sleep
    }

    public func update(credentials: OAuth1.Credentials) {
        self.credentials = credentials
    }

    public var isAuthenticated: Bool { credentials.token != nil }

    // MARK: - Listing photos

    public func photos(_ request: PhotoRequest) async throws -> PhotoPage {
        guard !request.requiresAuthentication || credentials.token != nil else {
            throw FlickrError.invalidInput(
                "Sign in to Flickr to see your own photos.")
        }

        let data = try await send(request.parameters())
        let page = try FlickrResponse.photoPage(from: data)

        // The size filter has no Flickr parameter — it is a property of the
        // variants in the reply, so it is applied here rather than sent.
        let kept = request.filters.apply(to: page.photos)
        return PhotoPage(page: page.page, pages: page.pages, perPage: page.perPage,
                         total: page.total, photos: kept,
                         skippedEntries: page.skippedEntries)
    }

    // MARK: - Resolving a person

    /// The NSID for a full photostream URL, a username, or an NSID.
    public func resolveUser(from input: String) async throws -> String {
        let trimmed = input.trimmed
        guard !trimmed.isEmpty else {
            throw FlickrError.invalidInput("Enter a Flickr username or photostream URL.")
        }
        // An NSID is already the answer; asking Flickr to confirm it is a round
        // trip that can only fail.
        if trimmed.contains("@") { return trimmed }

        let username = Self.username(from: trimmed)
        let data = try await send([
            OAuthParameter(name: "method", value: "flickr.people.findByUsername"),
            OAuthParameter(name: "username", value: username),
            OAuthParameter(name: "format", value: "json"),
            OAuthParameter(name: "nojsoncallback", value: "1"),
        ])
        return try FlickrResponse.userID(from: data)
    }

    /// The last useful path component of a photostream URL, or the input.
    static func username(from input: String) -> String {
        guard input.lowercased().contains("flickr.com") else { return input }
        let normalised = input.contains("//") ? input : "//" + input
        let parts = (URLComponents(string: normalised)?.path ?? "")
            .split(separator: "/").map(String.init)
        if let index = parts.firstIndex(of: "photos"), index + 1 < parts.count {
            return parts[index + 1]
        }
        return parts.last ?? input
    }

    // MARK: - Resolving a group

    /// The three-step resolution a group needs.
    ///
    /// `flickr.urls.lookupGroup` handles a slug or URL, `flickr.groups.getInfo`
    /// confirms an NSID and supplies the display name, and
    /// `flickr.groups.search` is the last resort — fuzzy, so its results are
    /// accepted only on an exact name match.
    public func resolveGroup(from input: String) async throws -> ResolvedGroup {
        let identifier = try GroupResolver.identifier(from: input)

        if GroupResolver.isNSID(identifier) {
            return try await groupInfo(nsid: identifier)
        }

        if let nsid = try await lookUpGroupSlug(identifier) {
            return try await groupInfo(nsid: nsid)
        }

        let candidates = try await searchGroups(named: identifier)
        guard let nsid = GroupResolver.exactMatch(in: candidates, identifier: identifier) else {
            throw FlickrError.notFound(
                "No Flickr group is named “\(identifier)”. Check the spelling, or "
                + "paste the group's URL.")
        }
        return try await groupInfo(nsid: nsid)
    }

    private func lookUpGroupSlug(_ identifier: String) async throws -> String? {
        let data: Data
        do {
            data = try await send([
                OAuthParameter(name: "method", value: "flickr.urls.lookupGroup"),
                OAuthParameter(name: "url", value: GroupResolver.lookupURL(for: identifier)),
                OAuthParameter(name: "format", value: "json"),
                OAuthParameter(name: "nojsoncallback", value: "1"),
            ])
        } catch let error as FlickrError where !error.isTransient {
            // Not a group URL Flickr knows. That is a miss, not a failure —
            // the name search is the next step.
            return nil
        }
        return try? FlickrResponse.groupID(from: data)
    }

    private func searchGroups(named identifier: String) async throws -> [GroupSummary] {
        let data = try await send([
            OAuthParameter(name: "method", value: "flickr.groups.search"),
            OAuthParameter(name: "text", value: identifier),
            OAuthParameter(name: "per_page", value: "50"),
            OAuthParameter(name: "format", value: "json"),
            OAuthParameter(name: "nojsoncallback", value: "1"),
        ])
        return try FlickrResponse.groups(from: data)
    }

    private func groupInfo(nsid: String) async throws -> ResolvedGroup {
        let data = try await send([
            OAuthParameter(name: "method", value: "flickr.groups.getInfo"),
            OAuthParameter(name: "group_id", value: nsid),
            OAuthParameter(name: "format", value: "json"),
            OAuthParameter(name: "nojsoncallback", value: "1"),
        ])
        return try FlickrResponse.groupInfo(from: data)
    }

    // MARK: - Sending, with retries

    /// Send `parameters`, retrying only what retrying can fix.
    ///
    /// A transient Flickr code or a transport error is worth another attempt; a
    /// permanent error and an unreadable reply are not, and retrying them just
    /// makes the user wait five seconds for the same message.
    private func send(_ parameters: [OAuthParameter]) async throws -> Data {
        var lastError: FlickrError = .busy("Flickr did not answer.")

        for attempt in 0..<policy.attempts {
            do {
                let url = try OAuth1.signedURL(
                    method: "GET", url: Self.endpoint,
                    parameters: parameters, credentials: credentials)
                let data = try await transport.data(from: url)
                // Reading the status here is what makes a `stat=fail` blip
                // retryable: it has to be seen before the caller decodes.
                try FlickrResponse.throwIfFailed(data)
                return data
            } catch let error as FlickrError {
                guard error.isTransient else { throw error }
                lastError = error
            } catch let error as OAuth1.SigningError {
                throw FlickrError.invalidInput("Could not build the request: \(error)")
            }

            if attempt < policy.attempts - 1 {
                try await sleep(policy.delay(afterAttempt: attempt))
            }
        }

        throw FlickrError.busy(
            "Flickr is busy right now — \(lastError.message) Try again in a moment.")
    }
}
