import SwiftUI

import CaterinaLibrary

/// Always above the grid, so that what to do next is never a guess: how to
/// choose photos, then what can be done with the ones chosen. The same height
/// either way, so the photos do not jump when the first one is ticked.
struct OrganizeChoiceBar: View {
    let organize: OrganizeModel

    var body: some View {
        HStack(spacing: 10) {
            if organize.selection.isEmpty {
                Label("Click the photos you want. Click again to take one out.", systemImage: "hand.tap")
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                Text("\(organize.selection.count.formatted()) chosen")
                    .font(.body.weight(.semibold)).monospacedDigit()
                Button {
                    organize.pendingGroupSubjects = organize.groupSubjectsForToolbar
                } label: {
                    Label("Add to Groups…", systemImage: "person.3")
                }
                .buttonStyle(.borderedProminent)
                .disabled(organize.isBusy)
                Button("Add to Tray") { organize.addSelectionToTray() }
                Button("Clear") { organize.clearSelection() }
            }
            Spacer()
        }
        .frame(minHeight: Self.height)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private static let height: CGFloat = 28
}
