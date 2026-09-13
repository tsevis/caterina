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
/// every source of the interface holds the same client.
public actor FlickrClient {
    public static let endpoint = "https://api.flickr.com/services/rest/"

    private var credentials: OAuth1.Credentials
    private var permission: FlickrPermission
    private let transport: HTTPTransport
    private let policy: RetryPolicy
    private let sleep: Sleeper
    private let budget: CallBudget

    public init(credentials: OAuth1.Credentials,
                permission: FlickrPermission = .read,
                transport: HTTPTransport = URLSessionTransport(),
                policy: RetryPolicy = .standard,
                budget: CallBudget = .standard,
                sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }) {
        self.credentials = credentials
        self.permission = permission
        self.transport = transport
        self.policy = policy
        self.sleep = sleep
        self.budget = budget
    }

    public func update(credentials: OAuth1.Credentials, permission: FlickrPermission = .read) {
        self.credentials = credentials
        self.permission = permission
    }

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

        // A name with spaces is usually a slug with the spaces taken out.
        // Measured against the live API: `groups.search` for "black and white"
        // answers with "Black and White Unlimited" first and never returns the
        // group actually called "Black and White" — but `/groups/blackandwhite/`
        // resolves straight to it. This is still an exact route: a slug names
        // one URL. The name it resolves to is checked all the same, so it
        // cannot become fuzzy matching under another name.
        let despaced = identifier.components(separatedBy: .whitespaces).joined()
        if despaced != identifier, !despaced.isEmpty,
           let nsid = try await lookUpGroupSlug(despaced) {
            let group = try await groupInfo(nsid: nsid)
            if GroupResolver.namesMatch(group.name, identifier) { return group }
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

    /// Flickr's own licence table.
    ///
    /// Not used to draw anything — `License` is an enum for a reason — but to
    /// check that enum against the source of truth. Getting a licence wrong has
    /// legal consequences for whoever trusts the badge.
    public func licenses() async throws -> [String: String] {
        let data = try await send([
            OAuthParameter(name: "method", value: "flickr.photos.licenses.getInfo"),
            OAuthParameter(name: "format", value: "json"),
            OAuthParameter(name: "nojsoncallback", value: "1"),
        ])
        return try FlickrResponse.licenses(from: data)
    }

    // MARK: - Your library

    /// A page of your own photos. Background work: a sync is spaced out so it
    /// never crowds what the person is looking at.
    public func library(_ query: LibraryQuery,
                        priority: CallPriority = .background) async throws -> LibraryPage {
        guard credentials.token != nil else { throw FlickrError.permissionNeeded(.read) }
        let credentials = self.credentials
        let data = try await withRetries(priority: priority, retryingLostConnections: true) { transport in
            let url = try OAuth1.signedURL(method: "GET", url: Self.endpoint,
                                           parameters: query.parameters, credentials: credentials)
            return try await transport.data(from: url)
        }
        return try LibraryResponse.page(from: data)
    }

    // MARK: - Writing

    /// Change something on Flickr. Needs a signed-in account.
    ///
    /// `priority` is `.edit` unless the person is waiting on this one call:
    /// a batch is spaced out so that it never crowds what they are looking at.
    public func perform(_ write: FlickrWrite, priority: CallPriority = .edit) async throws -> Data {
        guard credentials.token != nil else {
            throw FlickrError.invalidInput("Sign in to Flickr to change your photos.")
        }
        guard write.permission <= permission else {
            throw FlickrError.permissionNeeded(write.permission)
        }
        let credentials = self.credentials
        do {
            return try await withRetries(priority: priority,
                                         retryingLostConnections: write.repeatable) { transport in
                let request = try OAuth1.signedPOSTRequest(
                    url: Self.endpoint, parameters: write.parameters, credentials: credentials)
                return try await transport.send(request)
            }
        } catch FlickrError.api(code: Self.insufficientPermissions, _, _) {
            // Revoked on flickr.com since this token was issued.
            throw FlickrError.permissionNeeded(write.permission)
        }
    }

    /// Flickr's "Insufficient permissions" code.
    static let insufficientPermissions = 99

    // MARK: - Sending, with retries

    private func send(_ parameters: [OAuthParameter]) async throws -> Data {
        let credentials = self.credentials
        return try await withRetries(priority: .interactive,
                                     retryingLostConnections: true) { transport in
            let url = try OAuth1.signedURL(
                method: "GET", url: Self.endpoint,
                parameters: parameters, credentials: credentials)
            return try await transport.data(from: url)
        }
    }

    /// Run `call`, retrying only what retrying can fix.
    ///
    /// A transient Flickr code is worth another attempt: `stat=fail` means
    /// Flickr read the request and did nothing. A lost connection is retried
    /// only when doing the call twice is harmless. A permanent error and an
    /// unreadable reply are never retried — that just makes the user wait five
    /// seconds for the same message. Every attempt is signed afresh, so no two
    /// share a nonce.
    private func withRetries(
        priority: CallPriority,
        retryingLostConnections: Bool,
        _ call: @Sendable (HTTPTransport) async throws -> Data
    ) async throws -> Data {
        var lastError: FlickrError = .busy("Flickr did not answer.")

        for attempt in 0..<policy.attempts {
            // Every attempt is a call Flickr counts, retries included.
            try await budget.acquire(priority)
            do {
                let data = try await call(transport)
                // Reading the status here is what makes a `stat=fail` blip
                // retryable: it has to be seen before the caller decodes.
                try FlickrResponse.throwIfFailed(data)
                return data
            } catch let error as FlickrError {
                guard error.isTransient else { throw error }
                if case .api = error {} else if !retryingLostConnections { throw error }
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
