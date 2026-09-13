import SwiftUI

import FlickrKit

/// The states a grid spends most of its life in.
///
/// Designed rather than left blank: an empty rectangle and a failed request
/// look identical, and "Flickr is busy" is a different sentence from "that
/// group does not exist" — showing the second when it means the first is what
/// the reference application got complaints for.
struct SourceStateView: View {
    let source: PhotoSource
    let status: SectionStatus
    var isSignedIn: Bool = false
    let retry: () -> Void

    var body: some View {
        switch status {
        case .ready:
            // The grid itself is drawn instead; this view is what stands in for
            // it the rest of the time.
            EmptyView()

        case .idle:
            ContentUnavailableView {
                Label(idleTitle, systemImage: source.systemImage)
            } description: {
                Text(idleDescription)
            } actions: {
                // Telling someone to sign in without giving them a way to is
                // an instruction to go and find Settings.
                if source.requiresAuthentication, !isSignedIn {
                    SettingsLink { Text("Sign In to Flickr…") }
                        .buttonStyle(.borderedProminent)
                }
            }

        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text("Asking Flickr…").foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .empty:
            ContentUnavailableView {
                Label("No photos", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("Nothing here matched. Try a different term, or loosen the filters.")
            }

        case let .failed(error):
            ContentUnavailableView {
                Label(error.isTransient ? "Flickr is busy" : "That did not work",
                      systemImage: error.isTransient
                          ? "clock.arrow.trianglehead.counterclockwise.rotate.90"
                          : "exclamationmark.triangle")
            } description: {
                Text(error.message)
            } actions: {
                Button(error.isTransient ? "Try Again" : "Retry", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var idleTitle: String {
        switch source {
        case .you: return "Your photos"
        case .search: return "Search Flickr"
        case .user: return "Someone's photostream"
        case .groups: return "A group's pool"
        }
    }

    private var idleDescription: String {
        switch source {
        case .you: return "Sign in to Flickr to see the photos on your own account."
        case .search: return "Type what you are looking for and press Return."
        case .user: return "Paste a photostream URL, or type a Flickr username."
        case .groups: return "Paste a group URL, or type the group's exact name."
        }
    }
}

/// The bar along the bottom: where in the results the user is, and how to move.
struct PaginationBar: View {
    let state: SectionState
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onPerPage: (Int) -> Void

    private static let pageSizes = [25, 50, 100, 250, 500]

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrevious) { Label("Previous page", systemImage: "chevron.left") }
                .labelStyle(.iconOnly)
                .help("Previous page (⌘←)")
                .disabled(!state.canGoBack)
                .keyboardShortcut(.leftArrow, modifiers: .command)

            Text("Page \(state.page) of \(state.totalPages)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityLabel(state.total > 0
                    ? "Page \(state.page) of \(state.totalPages), \(state.total) photos found"
                    : "Page \(state.page) of \(state.totalPages)")

            Button(action: onNext) { Label("Next page", systemImage: "chevron.right") }
                .labelStyle(.iconOnly)
                .help("Next page (⌘→)")
                .disabled(!state.canGoForward)
                .keyboardShortcut(.rightArrow, modifiers: .command)

            if state.isPageCountClamped {
                // Flickr reports a page count for the whole result set and
                // serves about four thousand of them; paging past that repeats
                // photos. Saying so beats letting it look like a bug.
                Image(systemName: "info.circle")
                    .foregroundStyle(Theme.markText)
                    .help(Pagination.explanation)
                    .accessibilityLabel(Pagination.explanation)
            }

            Spacer()

            if let notice = state.skippedNotice {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .help("Flickr sent entries this version could not read. "
                          + "They are left out rather than shown as blanks.")
            }

            // A menu of choices rather than a `Picker` over a `Binding`: the
            // binding's setter has to be `@Sendable`, and this one closes over
            // a main-actor model, so the picker form is a concurrency warning
            // dressed up as a control.
            Menu("\(state.perPage) per page") {
                ForEach(Self.pageSizes, id: \.self) { size in
                    Button("\(size) per page") { onPerPage(size) }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Photos per page")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

extension SectionState {
    /// Entries Flickr sent that could not be read, said out loud rather than
    /// quietly dropped.
    var skippedNotice: String? {
        guard skippedEntries > 0 else { return nil }
        return skippedEntries == 1
            ? "1 entry skipped"
            : "\(skippedEntries) entries skipped"
    }
}
