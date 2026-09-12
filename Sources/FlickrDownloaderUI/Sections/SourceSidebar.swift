import SwiftUI

import FlickrKit

/// The four places photos come from.
struct SourceSidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: Binding(
            get: { model.activeSource },
            set: { model.select($0) }
        )) {
            Section("Photos") {
                ForEach(PhotoSource.allCases) { source in
                    Label(source.title, systemImage: source.systemImage)
                        .badge(badge(for: source))
                        .tag(source)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: Theme.Metrics.sidebarWidth, max: 260)
        .safeAreaInset(edge: .bottom) { account }
    }

    /// How many photos a source is holding, so switching back to one says what
    /// is waiting there.
    private func badge(for source: PhotoSource) -> Text? {
        let count = model.workspace[source].selection.count
        return count > 0 ? Text(count.formatted()) : nil
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if let account = model.account {
                Label(account.username.isEmpty ? "Signed in" : account.username,
                      systemImage: "person.crop.circle.fill")
                    .font(.callout)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
            } else {
                Label("Not signed in", systemImage: "person.crop.circle")
                    .font(.callout)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 8)
    }
}
