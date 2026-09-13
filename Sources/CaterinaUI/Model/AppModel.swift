import Foundation
import Observation
import SwiftUI

import CaterinaLibrary
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
    /// Which of the four tabs the window is showing.
    public var tab: AppTab = .download
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
    /// The credentials, in memory. The Keychain is touched on launch, on save
    /// and on sign-out — never on a redraw.
    private var stored: StoredCredentials?
    private let transport: any HTTPTransport
    private let policy: RetryPolicy
    /// How long to let the user keep ticking before asking Flickr again.
    ///
    /// Without it, every checkbox in the inspector was its own search: ticking
    /// eight licences fired eight requests and blanked the grid eight times.
    private let settleTime: Duration
    private let engine: DownloadEngine
    private let client: FlickrClient
    /// The local copy of your library, shared by Organize and Browse.
    public let library: LibraryModel
    public let uploads: UploadModel
    public let browse: BrowseModel
    /// Read by Browse off the main actor, so kept in a box it can hold.
    private let accountID: AccountIDBox

    /// One in-flight load per source, so loading Groups cannot cancel Search.
    private var loads: [PhotoSource: Task<Void, Never>] = [:]
    private var generations: [PhotoSource: Int] = [:]
    private var downloadTask: Task<DownloadReport, Never>?
    private var downloadObserver: Task<Void, Never>?
    /// Bumped per download, so a straggling progress callback from a cancelled
    /// batch cannot write "40 of 100" over the five-photo one that replaced it.
    private var downloadGeneration = 0
    private var filterReload: Task<Void, Never>?

    public init(vault: CredentialsVault = CredentialsVault(),
                transport: any HTTPTransport = URLSessionTransport(),
                engine: DownloadEngine = DownloadEngine(),
                policy: RetryPolicy = .standard,
                settleTime: Duration = .milliseconds(500),
                libraryStore: LibraryStore? = nil) {
        self.vault = vault
        self.transport = transport
        self.policy = policy
        self.settleTime = settleTime
        self.engine = engine
        // **Read once.** These used to be read from view bodies, so SwiftUI
        // re-evaluating a view asked the Keychain again — and the Keychain
        // asks the user. Everything is held in memory from here and written
        // back only when it changes.
        let stored = vault.load()
        self.stored = stored
        self.client = FlickrClient(credentials: stored?.oauth ?? .empty,
                                   permission: stored?.grantedPermission ?? .read,
                                   transport: transport, policy: policy)
        self.library = LibraryModel(store: libraryStore, source: client)
        self.uploads = UploadModel(store: libraryStore, uploader: client, albums: client,
                                   files: SecurityScopedFileAccess())
        let accountBox = AccountIDBox(stored?.account?.nsid)
        self.accountID = accountBox
        self.browse = BrowseModel(store: libraryStore, records: client, stats: client, directory: client, faves: client,
                                  accountID: { accountBox.value })
        self.account = stored?.account
        self.isShowingOnboarding = !(stored?.hasAPIKey ?? false)
    }

    /// Bring the library copy up to date. Quiet when there is nothing to do:
    /// signed out at launch is not an error worth showing.
    public func syncLibrary() async {
        await library.sync(signedIn: isSignedIn)
    }

    public var hasAPIKey: Bool { stored?.hasAPIKey ?? false }
    public var isSignedIn: Bool { stored?.isSignedIn ?? false }
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
        guard workspace[source].query != nil else { return }

        filterReload?.cancel()
        filterReload = Task { [weak self, settleTime] in
            try? await Task.sleep(for: settleTime)
            guard !Task.isCancelled, let self,
                  let query = self.workspace[source].query else { return }
            // A filter change is a new query, so it reruns from page 1.
            self.start(source, query: query)
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

        // Said here rather than left to come back as an OAuth failure the user
        // cannot act on.
        guard !source.requiresAuthentication || isSignedIn else {
            fail(source, with: FlickrError.invalidInput(
                "Sign in to Flickr to see your own photos."))
            return
        }

        switch source {
        case .search:
            guard !input.isEmpty else { return }
            start(.search, query: .search(text: input))

        case .you:
            start(.you, query: .myPhotos)

        case .user:
            guard !input.isEmpty else { return }
            resolveThenLoad(.user) {
                (.userPhotos(userID: try await client.resolveUser(from: input)), nil)
            }

        case .groups:
            guard !input.isEmpty else { return }
            let text = groupSearchText
            resolveThenLoad(.groups, thenRemember: { [weak self] group in
                self?.resolvedGroup = group
            }) {
                let group = try await client.resolveGroup(from: input)
                return (GroupResolver.query(groupID: group.nsid, text: text), group)
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
        thenRemember remember: (@MainActor (ResolvedGroup) -> Void)? = nil,
        _ resolve: @escaping @Sendable () async throws -> (PhotoQuery, ResolvedGroup?)
    ) {
        workspace = workspace.updating(source) { $0.resolving() }
        let generation = begin(source)

        loads[source] = Task { [weak self] in
            do {
                let (query, resolved) = try await resolve()
                guard let self, !Task.isCancelled,
                      self.generations[source] == generation else { return }
                // Written only after the generation check: two lookups in
                // flight could otherwise leave the slower one's group behind
                // the faster one's results.
                if let resolved { remember?(resolved) }
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

    public func click(_ photoID: String, modifiers: ClickModifiers,
                      in source: PhotoSource) {
        workspace = workspace.updating(source) { $0.clicking(photoID, modifiers: modifiers) }
    }

    public func sweep(_ ids: Set<String>, in source: PhotoSource) {
        workspace = workspace.updating(source) { $0.sweeping(ids) }
    }

    public func moveSelection(by offset: Int, in source: PhotoSource) {
        workspace = workspace.updating(source) { $0.movingSelection(by: offset) }
    }

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
            // **A fresh directory, and a write that refuses a symlink.**
            // The old path was entirely predictable — Flickr photo ids are
            // public — and written with a plain `Data.write(to:)`, so a hostile
            // process running as the same user could pre-plant a symlink at
            // that name and have this overwrite whatever it pointed at.
            guard let folder = try? SafeFile.uniqueDirectory(
                    in: FileManager.default.temporaryDirectory, prefix: "Quick Look_")
            else { return }
            let file = Filenames.destination(in: folder, title: "Quick Look",
                                             photoID: photo.id, url: address)
            guard (try? SafeFile.write(data, to: file)) != nil,
                  !Task.isCancelled else { return }
            self?.previewURL = file
        }
    }

    // MARK: - Downloading

    /// Download the photos selected **in `source`** — not whichever source
    /// loaded last, which is the defect this signature exists to prevent.
    public func startDownload(from source: PhotoSource, to directory: URL,
                              variant: PhotoVariant) {
        let photos = workspace[source].selectedPhotos
        // One at a time: a second batch started over a running one would share
        // its progress state and its report.
        guard !photos.isEmpty, !download.isRunning else { return }

        downloadGeneration += 1
        let generation = downloadGeneration
        download = DownloadState(isRunning: true, completed: 0, total: photos.count)

        // The panel granted access to this folder; under the sandbox a folder
        // restored from a bookmark needs it held open for the whole batch.
        let scoped = directory.startAccessingSecurityScopedResource()

        let task = Task { [engine] in
            await engine.download(photos, to: directory, variant: variant) { progress in
                Task { @MainActor [weak self] in
                    self?.record(progress, generation: generation)
                }
            }
        }
        downloadTask = task

        downloadObserver = Task { [weak self] in
            let report = await task.value
            if scoped { directory.stopAccessingSecurityScopedResource() }
            guard let self, self.downloadGeneration == generation else { return }
            self.download = DownloadState(isRunning: false, completed: report.saved,
                                          total: report.requested, report: report)
        }
    }

    private func record(_ progress: DownloadProgress, generation: Int) {
        guard downloadGeneration == generation else { return }
        download.completed = progress.completed
        download.total = progress.total
    }

    public func cancelDownload() {
        downloadTask?.cancel()
    }

    /// Cancel and *wait*, so closing the window does not lose the report or
    /// leave a `.part` file behind.
    public func finishDownloadBeforeClosing() async {
        guard let downloadTask else { return }
        downloadTask.cancel()
        let report = await downloadTask.value
        // The observer would do this too, but quitting does not wait for it.
        download = DownloadState(isRunning: false, completed: report.saved,
                                 total: report.requested, report: report)
    }

    public func dismissDownloadReport() {
        download = DownloadState()
    }

    // MARK: - Credentials

    /// Saving does **not** dismiss the onboarding sheet: signing in saves the
    /// key first, and tearing the sheet down mid-flow took its spinner and its
    /// error message with it, so a failed sign-in was silent. The view dismisses
    /// itself when it is actually finished.
    public func saveAPIKey(key: String, secret: String) throws {
        var next = stored ?? StoredCredentials(apiKey: "", apiSecret: "")
        next.apiKey = key.trimmed
        next.apiSecret = secret.trimmed
        try vault.save(next)
        stored = next
        refreshClient()
    }

    /// Store the new token and wait until the client holds it: a write retried
    /// straight after approving more permission must not go out with the old
    /// one.
    public func signedIn(_ account: OAuthFlow.Account) async throws {
        guard let stored else {
            throw FlickrError.invalidInput("Enter an API key before signing in.")
        }
        let next = stored.signedIn(account)
        try vault.save(next)
        self.stored = next
        // Approving more for the same account keeps what Browse has; a
        // different account starts it afresh.
        if accountID.value != next.nsid.flatMap({ $0.isEmpty ? nil : $0 }) { browse.reset() }
        accountID.set(next.nsid)
        await client.update(credentials: next.oauth, permission: next.grantedPermission ?? .read)
        self.account = next.account
    }

    public func signOut() throws {
        if let stored {
            let next = stored.signedOut()
            try vault.save(next)
            self.stored = next
        }
        account = nil
        accountID.set(nil)
        browse.reset()
        refreshClient()
        // **Cancel first.** Pressing Reload on You and then signing out left a
        // request in flight whose reply repopulated the grid with the account's
        // photos *after* the account was gone. `begin` cancels the task and
        // bumps the generation, so the reply has nowhere to land.
        _ = begin(.you)
        workspace = workspace.updating(.you) { _ in SectionState(source: .you) }
    }

    public func credentials() -> OAuth1.Credentials? { stored?.oauth }

    /// What the current sign-in allows; signing in again asks for no less.
    public var grantedPermission: FlickrPermission { stored?.grantedPermission ?? .read }

    /// Hand the existing actor its new credentials rather than building a
    /// second one: a request already in flight keeps the client it started
    /// with, and there is one place the credentials live.
    private func refreshClient() {
        let credentials = stored?.oauth ?? .empty
        let permission = stored?.grantedPermission ?? .read
        Task { [client] in await client.update(credentials: credentials, permission: permission) }
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

/// The signed-in NSID, readable from any thread.
final class AccountIDBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    init(_ value: String?) { stored = Self.meaningful(value) }

    var value: String? { lock.withLock { stored } }
    func set(_ value: String?) { lock.withLock { stored = Self.meaningful(value) } }

    /// An empty NSID is none: sent as `user_id=""` it asks Flickr for nobody.
    private static func meaningful(_ value: String?) -> String? {
        value.flatMap { $0.isEmpty ? nil : $0 }
    }
}
