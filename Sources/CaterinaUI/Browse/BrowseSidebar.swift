import SwiftUI

import CaterinaLibrary
import FlickrKit

/// Every way into the account.
struct BrowseSidebar: View {
    let browse: BrowseModel

    private var selection: Binding<BrowseScope?> {
        Binding(get: { browse.scope }, set: { scope in
            guard let scope else { return }
            Task { await browse.jump(to: scope) }
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: selection) {
                Section("Your photos") {
                    row(.library(.all, title: "All photos"), "photo.on.rectangle")
                    row(.timeline, "calendar")
                    row(.tags, "tag")
                    row(.places, "map")
                    row(.people, "person.2")
                    row(.library(.videos, title: "Videos"), "video")
                }
                Section("Rankings") {
                    ForEach(Ranking.allCases) { row(.ranking($0), $0.systemImage) }
                }
                Section("Organised") {
                    row(.albums, "rectangle.stack")
                    row(.collections, "square.stack.3d.up")
                    row(.galleries, "photo.artframe")
                    row(.groups, "person.3")
                }
                Section("Who can see") {
                    ForEach(Audience.allCases, id: \.self) { audience in
                        row(.library(.seenBy(audience), title: audience.title), audience.systemImage)
                    }
                }
                Section("Licences") {
                    ForEach(License.allCases) { license in
                        row(.library(.licensed(license), title: license.label), "c.circle")
                    }
                }
                Section("On Flickr") {
                    row(.remote(.yourFaves, title: "Your faves"), "star.circle")
                    row(.remote(.explore, title: "Explore"), "sparkles")
                }
            }
            AccountSummary(browse: browse).padding(12)
        }
    }

    private func row(_ scope: BrowseScope, _ image: String) -> some View {
        Label(scope.title, systemImage: image).tag(scope)
    }
}

extension Audience {
    var systemImage: String {
        switch self {
        case .everyone: "globe"
        case .friendsOrFamily: "person.2.circle"
        case .onlyYou: "lock"
        }
    }
}

/// Views across the account, day by day, and whether saving is working.
struct AccountSummary: View {
    let browse: BrowseModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Account views").font(.caption.weight(.semibold))
            if browse.accountHistory.isEmpty {
                Text("No days saved yet.").font(.caption).foregroundStyle(Theme.inkSecondary)
            } else {
                ViewsPerDayChart(points: browse.accountHistory.suffix(28).map { ($0.day, $0.totals.total) })
                    .chartXAxis(.hidden)
                    .frame(height: 70)
            }
            Text(status).font(.caption).foregroundStyle(Theme.inkSecondary)
        }
    }

    private var status: String {
        switch browse.statsPhase {
        case .idle: "\(browse.accountHistory.count) days saved"
        case .saving: "Saving daily stats…"
        case let .saved(days): days == 0 ? "\(browse.accountHistory.count) days saved, up to date"
                                         : "Saved \(days) new days · \(browse.accountHistory.count) in all"
        case .unavailable: "Daily stats need Flickr Pro."
        case let .failed(message): message
        }
    }
}
