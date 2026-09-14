import SwiftUI

import CaterinaLibrary
import FlickrKit

/// How to share, the preview per group, and the buttons.
struct SharePlanPanel: View {
    @Bindable var share: GroupShareModel
    let onDone: () -> Void
    @State private var confirming: Confirmation?

    private enum Confirmation: Identifiable {
        case share, remove
        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to share").font(.headline)
            Picker("", selection: $share.strategy) {
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
            options
            Divider()
            preview
            Spacer(minLength: 0)
            buttons
        }
        .padding(14)
        .onChange(of: share.chosen) { _, _ in Task { await share.preview() } }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            presenting: confirming) { action in
            switch action {
            case .share: Button("Share") { run { await share.share() } }
            case .remove: Button("Remove", role: .destructive) { run { await share.removeTrayFromChosen() } }
            }
        } message: { action in
            Text(action == .share ? "Each group's report appears in Activity. You can undo it there."
                                  : "Photos not in a group cost a call each and are reported as not there.")
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            Toggle("Skip photos already in a group (\(share.organize.tray.count.formatted()) calls to check)",
                   isOn: $share.skipsPhotosAlreadyInPools)
        }
        .onChange(of: share.strategy) { _, _ in Task { await share.preview() } }
        .onChange(of: share.groupsPerPhoto) { _, _ in Task { await share.preview() } }
        .onChange(of: share.capPerGroup) { _, _ in Task { await share.preview() } }
        .onChange(of: share.skipsPhotosAlreadyInPools) { _, _ in Task { await share.preview() } }
    }

    @ViewBuilder
    private var preview: some View {
        if share.chosen.isEmpty {
            ContentUnavailableView("Choose groups", systemImage: "person.3",
                                   description: Text("Search on the left, tick groups, or pick a saved set."))
        } else if let plan = share.plan {
            Text(share.summary).font(.headline).monospacedDigit()
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
        } else {
            Button("Preview") { Task { await share.preview() } }.disabled(share.isWorking)
        }
    }

    private var buttons: some View {
        HStack {
            Button("Remove Tray from Chosen Groups…") { confirming = .remove }
                .disabled(share.chosen.isEmpty || share.organize.isRunning)
            Spacer()
            Button("Close", action: onDone).keyboardShortcut(.cancelAction)
            Button("Share…") { confirming = .share }
                .disabled((share.plan?.assignments.isEmpty ?? true) || share.organize.isRunning)
        }
    }

    private var confirmTitle: String {
        switch confirming {
        case .share: "Share: \(share.summary)?"
        case .remove: "Remove the tray from \(share.chosen.count) groups?"
        case nil: ""
        }
    }

    private func run(_ action: @escaping () async -> Void) {
        onDone()
        Task { await action() }
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
                Text("\(tally?.sending ?? 0) to send").monospacedDigit()
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
