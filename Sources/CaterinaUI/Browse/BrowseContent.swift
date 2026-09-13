import SwiftUI

import CaterinaLibrary
import FlickrKit

/// The middle of Browse: a header, then an index or photos in the chosen layout.
struct BrowseContent: View {
    let browse: BrowseModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if browse.canGoBack {
                Button { Task { await browse.goBack() } } label: { Image(systemName: "chevron.backward") }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Back (⌘[)")
            }
            Text(browse.scope.title).font(.title3.weight(.semibold)).lineLimit(1)
            if !browse.scope.isIndex {
                Text(browse.items.count.formatted() + (browse.canLoadMore ? "+" : ""))
                    .monospacedDigit().foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            if browse.isLoading { ProgressView().controlSize(.small) }
            if let problem = browse.problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch browse.scope {
        case .tags: TagsIndex(browse: browse)
        case .timeline: TimelineIndex(browse: browse)
        case .people: PeopleIndex(browse: browse)
        case .albums: AlbumsIndex(browse: browse)
        case .collections: CollectionsIndex(browse: browse)
        case .galleries: GalleriesIndex(browse: browse)
        case .groups: GroupsIndex(browse: browse)
        default: photos
        }
    }

    @ViewBuilder
    private var photos: some View {
        if browse.items.isEmpty && !browse.isLoading {
            ContentUnavailableView(emptyTitle, systemImage: "photo.on.rectangle.angled", description: Text(emptyDetail))
        } else {
            switch browse.layout {
            case .list: PhotoListLayout(browse: browse)
            case .grid: PhotoGridLayout(browse: browse)
            case .timeline: PhotoTimelineLayout(browse: browse)
            case .map: PhotoMapLayout(browse: browse)
            }
        }
    }

    private var emptyTitle: String {
        if case .ranking(.rising) = browse.scope { return "Not enough history yet" }
        return "Nothing here"
    }

    private var emptyDetail: String {
        switch browse.scope {
        case .ranking(.rising): "Rising compares this week with last week, so it needs 14 saved days."
        case .ranking(.topThisWeek), .ranking(.mostFavedThisMonth): "Rankings come from saved daily stats, which need Flickr Pro."
        case .favedBy: "The fans index has not read these faves yet."
        case .places: "None of your photos in the library copy has a location."
        default: "No photos match. The library copy fills after the first sync."
        }
    }
}
