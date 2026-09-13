import SwiftUI

/// What an unbuilt tab shows: what it will do, plainly marked as not here yet.
struct PlannedTabView: View {
    let tab: AppTab

    var body: some View {
        ContentUnavailableView {
            Label(tab.title, systemImage: tab.systemImage)
        } description: {
            VStack(spacing: 10) {
                Text(tab.purpose)
                    .foregroundStyle(Theme.inkSecondary)
                Text("Not built yet")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.markText)
            }
            .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground)
    }
}
