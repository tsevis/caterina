import SwiftUI

import FlickrKit

/// Takes a tag off every photo in the library that has it, after saying how
/// many and how long.
struct RemoveTagEverywhereButton: View {
    let organize: OrganizeModel
    let tag: String
    @State private var removing: String?

    var body: some View {
        Button("Remove Tag Everywhere…") { removing = tag }
            .buttonStyle(.borderless)
            .disabled(organize.isRunning)
            .removeTagEverywhereDialog(organize: organize, tag: $removing)
    }
}

extension View {
    /// The question before removing a tag everywhere, with the cost.
    func removeTagEverywhereDialog(organize: OrganizeModel, tag: Binding<String?>) -> some View {
        let estimate = tag.wrappedValue.map { organize.estimateRemovingEverywhere($0) }
        return confirmationDialog("Remove “\(tag.wrappedValue ?? "")” from \(estimate.map { OrganizeModel.count($0.photos) } ?? "")?",
                                  isPresented: Binding(get: { tag.wrappedValue != nil },
                                                       set: { if !$0 { tag.wrappedValue = nil } }),
                                  presenting: tag.wrappedValue) { name in
            Button("Remove from \(estimate.map { OrganizeModel.count($0.photos) } ?? "photos")", role: .destructive) {
                Task { await organize.removeTagEverywhere(name) }
            }
            .disabled((estimate?.photos ?? 0) == 0)
        } message: { _ in
            Text("\(estimate?.summary ?? ""). Every spelling of the tag goes; other tags stay as they are. "
                 + "The tray is not touched. You can stop it, resume it after quitting, and undo it from Activity.")
        }
    }
}
