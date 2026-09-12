import Foundation
import Observation
import SwiftUI

import FlickrKit

/// Everything the window is showing, and the only thing that changes it.
///
/// **One `SectionState` per source, and a load only ever writes back into the
/// source it belongs to.** The reference application shared a selection map and
/// a page number across four tabs, so loading any tab wiped the others'
/// selection while their ticked thumbnails stayed on screen, and the Download
/// button acted on whichever tab had loaded last. Here every load carries a
/// generation, and a reply whose generation has been superseded is dropped
/// rather than drawn.
@MainActor
@Observable
public final class AppModel {

    // MARK: - State

    public private(set) var workspace = Workspace()
    public private(set) var account: CredentialsVault.StoredAccount?
    public private(set) var download = DownloadState()
    /// The Groups source has two inputs: which group, and what to search for
    /// inside it. Only the first belongs to `SectionState`, which every source
    /// shares.
    public var groupSearchText = ""
    public private(set) var resolvedGroup: ResolvedGroup?
    /// Shown when there is no API key yet — the one thing the user must supply.
    public var isShowingOnboarding = false
    public var isShowingInspector = true
    public var downloadVariant: PhotoVariant = .defaultDownload

    private let vault: CredentialsVault
    private let transport: any HTTPTransport
    private let policy: RetryPolicy
    private let engine: DownloadEngine
    private var client: FlickrClient

    /// One in-flight load per source, so loading Groups cannot cancel Search.
    private var loads: [PhotoSource: Task<Void, Never>] = [:]
    private var generations: [PhotoSource: Int] = [:]
    private var downloadTask: Task<DownloadReport, Never>?

    public init(vault: CredentialsVault = CredentialsVault(),
                transport: any HTTPTransport = URLSessionTransport(),
                engine: DownloadEngine = DownloadEngine(),
                policy: RetryPolicy = .standard) {
        self.vault = vault
        self.transport = transport
        self.policy = policy
        self.engine = engine
        self.client = FlickrClient(credentials: vault.credentials() ?? .empty,
                                   transport: transport, policy: policy)
        self.account = vault.account()
        self.isShowingOnboarding = !vault.hasAPIKey
    }

    public var hasAPIKey: Bool { vault.hasAPIKey }
    public var isSignedIn: Bool { vault.isSignedIn }
    public var activeSource: PhotoSource { workspace.active }
    public var state: SectionState { workspace.activeState }

    // MARK: - Navigating

    public func select(_ source: PhotoSource) {
        workspace = workspace.activating(source)
    }

    public func setInput(_ text: String, for source: PhotoSource) {
        workspace = workspace.updating(source) { $0.with(input: text) }
    }

    public func setFilters(_ filters: SearchFilters, for source: PhotoSource) {
        workspace = workspace.updating(source) { $0.with(filters: filters) }
        // A filter change is a new query, so it reruns from page 1 — but only
        // where there is something to rerun.
        if let query = workspace[source].query {
            start(source, query: query)
        }
    }

    public func setPerPage(_ perPage: Int, for source: PhotoSource) {
        workspace = workspace.updating(source) { $0.with(perPage: perPage) }
        guard workspace[source].query != nil else { return }
        fetch(source, page: workspace[source].page)
    }

    // MARK: - Asking for photos

    /// Start a new query. Always page 1.
    public func start(_ source: PhotoSource, query: PhotoQuery) {
        workspace = workspace.updating(source) { $0.beginning(query: query) }
        fetch(source, page: 1)
    }

    public func nextPage(in source: PhotoSource) {
        guard workspace[source].canGoForward else { return }
        workspace = workspace.updating(source) { $0.nextPage() }
        fetch(source, page: workspace[source].page)
    }

    public func previousPage(in source: PhotoSource) {
        guard workspace[source].canGoBack else { return }
        workspace = workspace.updating(source) { $0.previousPage() }
        fetch(source, page: workspace[source].page)
    }

    /// Resolve what the user typed, then load what it names.
    public func submit(_ source: PhotoSource) {
        let input = workspace[source].input.trimmed
        let client = client

        switch source {
        case .search:
            guard !input.isEmpty else { return }
            start(.search, query: .search(text: input))

        case .you:
            start(.you, query: .myPhotos)

        case .user:
            guard !input.isEmpty else { return }
            resolveThenLoad(.user) {
                .userPhotos(userID: try await client.resolveUser(from: input))
            }

        case .groups:
            guard !input.isEmpty else { return }
            let text = groupSearchText
            resolveThenLoad(.groups) { [weak self] in
                let group = try await client.resolveGroup(from: input)
                await MainActor.run { self?.resolvedGroup = group }
                return GroupResolver.query(groupID: group.nsid, text: text)
            }
        }
    }

    /// Re-run the Groups source against the pool it already resolved, so
    /// searching inside a group does not look the group up again.
    public func searchWithinResolvedGroup() {
        guard let group = resolvedGroup else { return }
        start(.groups, query: GroupResolver.query(groupID: group.nsid,
                                                  text: groupSearchText))
    }

    /// A lookup and the load it leads to share one generation, so typing a
    /// second name while the first is still resolving cannot leave the slower
    /// answer on screen.
    private func resolveThenLoad(
        _ source: PhotoSource,
        _ resolve: @escaping @Sendable () async throws -> PhotoQuery
    ) {
        workspace = workspace.updating(source) { $0.resolving() }
        let generation = begin(source)

        loads[source] = Task { [weak self] in
            do {
                let query = try await resolve()
                guard let self, !Task.isCancelled,
                      self.generations[source] == generation else { return }
                self.workspace = self.workspace.updating(source) { $0.beginning(query: query) }
                await self.run(source, page: 1, generation: generation, query: query)
            } catch {
                guard let self, !Task.isCancelled,
                      self.generations[source] == generation else { return }
                self.fail(source, with: error)
            }
        }
    }

    // MARK: - The fetch itself

    private func fetch(_ source: PhotoSource, page: Int) {
        guard let query = workspace[source].query else { return }
        let generation = begin(source)
        loads[source] = Task { [weak self] in
            await self?.run(source, page: page, generation: generation, query: query)
        }
    }

    private func run(_ source: PhotoSource, page: Int, generation: Int,
                     query: PhotoQuery) async {
        let state = workspace[source]
        let request = PhotoRequest(query: query, filters: state.filters,
                                   page: page, perPage: state.perPage)
        do {
            let result = try await client.photos(request)
            // A reply from a superseded load must never draw into the grid.
            guard !Task.isCancelled, generations[source] == generation else { return }
            workspace = workspace.updating(source) { $0.loaded(result) }
        } catch {
            guard !Task.isCancelled, generations[source] == generation else { return }
            fail(source, with: error)
        }
    }

    private func begin(_ source: PhotoSource) -> Int {
        loads[source]?.cancel()
        let generation = (generations[source] ?? 0) + 1
        generations[source] = generation
        return generation
    }

    private func fail(_ source: PhotoSource, with error: any Error) {
        let flickr = error as? FlickrError
            ?? .transport((error as NSError).localizedDescription)
        workspace = workspace.updating(source) { $0.failed(flickr) }
    }

    // MARK: - Selection

    public func toggle(_ photoID: String, in source: PhotoSource) {
        workspace = workspace.updating(source) { $0.toggling(photoID) }
    }

    public func select(_ ids: Set<String>, in source: PhotoSource) {
        workspace = workspace.updating(source) { $0.selecting(ids) }
    }

    public func selectAll(in source: PhotoSource) {
        workspace = workspace.updating(source) { $0.selectingAll() }
    }

    public func clearSelection(in source: PhotoSource) {
        workspace = workspace.updating(source) { $0.clearingSelection() }
    }

    // MARK: - Quick Look

    /// Quick Look needs a file, and a Flickr photo is a URL — so space fetches
    /// the large variant to a temporary file and previews that, which is the
    /// same thing Finder does with anything it has not downloaded yet.
    public var previewURL: URL?
    private var previewTask: Task<Void, Never>?

    public func preview(_ photo: Photo) {
        previewTask?.cancel()
        guard let address = photo.downloadURL(preferring: .large),
              let url = URL(string: address) else { return }

        previewTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled else { return }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(
                "quicklook-\(photo.id).\(Filenames.fileExtension(for: address))")
            guard (try? data.write(to: file)) != nil, !Task.isCancelled else { return }
            self?.previewURL = file
        }
    }

    // MARK: - Downloading

    /// Download the photos selected **in `source`** — not whichever source
    /// loaded last, which is the defect this signature exists to prevent.
    public func startDownload(from source: PhotoSource, to directory: URL,
                              variant: PhotoVariant) {
        let photos = workspace[source].selectedPhotos
        guard !photos.isEmpty else { return }

        download = DownloadState(isRunning: true, completed: 0, total: photos.count)
        let task = Task { [engine] in
            await engine.download(photos, to: directory, variant: variant) { progress in
                Task { @MainActor [weak self] in
                    self?.download.completed = progress.completed
                    self?.download.total = progress.total
                }
            }
        }
        downloadTask = task

        Task { [weak self] in
            let report = await task.value
            self?.download = DownloadState(isRunning: false, completed: report.saved,
                                           total: report.requested, report: report)
        }
    }

    public func cancelDownload() {
        downloadTask?.cancel()
    }

    /// Cancel and *wait*, so closing the window does not lose the report or
    /// leave a `.part` file behind.
    public func finishDownloadBeforeClosing() async {
        downloadTask?.cancel()
        guard let report = await downloadTask?.value else { return }
        download = DownloadState(isRunning: false, completed: report.saved,
                                 total: report.requested, report: report)
    }

    public func dismissDownloadReport() {
        download = DownloadState()
    }

    // MARK: - Credentials

    public func saveAPIKey(key: String, secret: String) throws {
        try vault.saveAPIKey(key: key, secret: secret)
        refreshClient()
        isShowingOnboarding = false
    }

    public func signedIn(_ account: OAuthFlow.Account) throws {
        try vault.saveAccount(token: account.token, secret: account.tokenSecret,
                              nsid: account.nsid, username: account.username)
        refreshClient()
        self.account = vault.account()
    }

    public func signOut() throws {
        try vault.signOut()
        account = nil
        refreshClient()
        // The You source is about the account that just went away.
        workspace = workspace.updating(.you) { _ in SectionState(source: .you) }
    }

    public func credentials() -> OAuth1.Credentials? { vault.credentials() }

    private func refreshClient() {
        client = FlickrClient(credentials: vault.credentials() ?? .empty,
                              transport: transport, policy: policy)
    }
}

/// How a download is going.
public struct DownloadState: Sendable, Equatable {
    public var isRunning = false
    public var completed = 0
    public var total = 0
    public var report: DownloadReport?

    public var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
}

extension OAuth1.Credentials {
    /// Stands in until the user supplies an API key. Every call made with it
    /// fails, which is correct: there is nothing to call Flickr with yet.
    static let empty = OAuth1.Credentials(consumerKey: "", consumerSecret: "")
}
