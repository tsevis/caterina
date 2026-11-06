import SwiftUI

import CaterinaLibrary
import FlickrKit

/// What will happen in each chosen group, and the button that does it. How
/// photos are dealt out is there for those who want it, folded away.
struct SharePlanPanel: View {
    @Bindable var share: GroupShareModel
    let onAdded: () -> Void
    let onClose: () -> Void
    @State private var isShowingOptions = false
    @State private var isConfirmingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            preview
            Spacer(minLength: 0)
            DisclosureGroup("More Options", isExpanded: $isShowingOptions) { options }
            Divider()
            buttons
        }
        .padding(14)
        .onChange(of: share.chosen) { _, _ in share.schedulePreview() }
        .onChange(of: share.strategy) { _, _ in share.schedulePreview() }
        .onChange(of: share.groupsPerPhoto) { _, _ in share.schedulePreview() }
        .onChange(of: share.capPerGroup) { _, _ in share.schedulePreview() }
        .onChange(of: share.skipsPhotosAlreadyInPools) { _, _ in share.schedulePreview() }
        .confirmationDialog("Remove these photos from \(share.chosen.count) groups?",
                            isPresented: $isConfirmingRemoval) {
            Button("Remove", role: .destructive) { run { await share.removeFromChosen() } }
        } message: {
            Text("Photos not in a group cost a call each and are reported as not there.")
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            StrategyPicker(selection: $share.strategy)
            if share.strategy == .bestFit {
                Stepper("Up to \(share.groupsPerPhoto) groups per photo", value: $share.groupsPerPhoto, in: 1...20)
            }
            HStack {
                Toggle("At most", isOn: Binding(get: { share.capPerGroup != nil },
                                                set: { share.capPerGroup = $0 ? 5 : nil }))
                Stepper("\(share.capPerGroup ?? 5) photos per group",
                        value: Binding(get: { share.capPerGroup ?? 5 }, set: { share.capPerGroup = $0 }), in: 1...100)
                    .disabled(share.capPerGroup == nil)
            }
            Toggle("Skip photos already in a group (\(share.subjects.count.formatted()) calls to check)",
                   isOn: $share.skipsPhotosAlreadyInPools)
            Button("Remove These Photos from Chosen Groups…") { isConfirmingRemoval = true }
                .disabled(share.chosen.isEmpty || share.organize.isBusy)
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private var preview: some View {
        if share.chosen.isEmpty {
            ContentUnavailableView("Tick the groups you want", systemImage: "person.3",
                                   description: Text("You will see here what goes into each one before anything is sent."))
        } else if let plan = share.plan {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(share.chosen, id: \.self) { groupID in
                        PlanGroupRow(name: share.name(of: groupID), tally: plan.tally[groupID],
                                     reasons: plan.skipped.filter { $0.groupID == groupID }.map(\.reason))
                    }
                    let homeless = plan.skipped.count { $0.groupID.isEmpty }
                    if homeless > 0 {
                        Label("\(homeless.formatted()) photos had no chosen group with room",
                              systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                    }
                }
            }
        } else if share.problem != nil {
            Button("Try Again") { share.schedulePreview() }.disabled(share.isWorking)
        } else {
            ProgressView("Checking these groups…").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// No confirmation to add: the button states exactly what it does and
    /// Activity can undo it. ⌘↩, not Return, because Return is what ends a
    /// search, and that must not post photos.
    private var buttons: some View {
        HStack {
            Text(share.summary).font(.callout).monospacedDigit().foregroundStyle(Theme.inkSecondary)
            Spacer()
            Button("Close", action: onClose).keyboardShortcut(.cancelAction)
            Button(share.actionTitle) {
                onAdded()
                Task { await share.share() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .help("You can undo this in Activity (⌘↩)")
            .disabled((share.plan?.assignments.isEmpty ?? true) || share.organize.isBusy)
        }
    }

    private func run(_ action: @escaping () async -> Void) {
        onAdded()
        Task { await action() }
    }
}

/// Every photo everywhere, spread out, or best fit.
private struct StrategyPicker: View {
    @Binding var selection: GroupShareModel.Strategy

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(GroupShareModel.Strategy.allCases) { strategy in
                VStack(alignment: .leading) {
                    Text(strategy.title)
                    Text(strategy.explanation).font(.caption).foregroundStyle(Theme.inkSecondary)
                }
                .tag(strategy)
            }
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
    }
}

/// One group in the preview: sending, and why the rest are not.
struct PlanGroupRow: View {
    let name: String
    let tally: GroupSharePlan.Tally?
    let reasons: [GroupSharePlan.SkipReason]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name).lineLimit(1)
                Spacer()
                Text("\(tally?.sending ?? 0) will be added").monospacedDigit()
            }
            ForEach(grouped, id: \.reason) { item in
                Text("\(item.count) skipped: \(item.reason.explanation)")
                    .font(.caption).foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private var grouped: [(reason: GroupSharePlan.SkipReason, count: Int)] {
        let counts = Dictionary(reasons.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.keys.sorted { $0.rawValue < $1.rawValue }.map { ($0, counts[$0] ?? 0) }
    }
}
