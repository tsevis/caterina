import SwiftUI

import CaterinaLibrary
import FlickrKit

/// Send the tray to many groups: find them, choose how, see what will
/// happen in each, then share.
struct GroupShareSheet: View {
    @Bindable var share: GroupShareModel
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Share to Groups").font(.title2.weight(.semibold))
                Text("\(share.organize.tray.count.formatted()) photos in the tray").foregroundStyle(Theme.inkSecondary)
                Spacer()
                if share.isWorking { ProgressView().controlSize(.small) }
                if let problem = share.problem {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).lineLimit(2)
                }
            }
            .padding(16)
            Divider()
            HSplitView {
                GroupFinder(share: share).frame(minWidth: 380)
                SharePlanPanel(share: share, onDone: onDone).frame(minWidth: 380)
            }
        }
        .frame(minWidth: 860, idealWidth: 980, minHeight: 600, idealHeight: 680)
        .task { await share.load() }
    }
}

/// Search, filter, sort and choose groups; saved sets.
struct GroupFinder: View {
    @Bindable var share: GroupShareModel
    @State private var isNamingSet = false
    @State private var setName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Search your \(share.groups.count.formatted()) groups", text: $share.query)
                    .textFieldStyle(.roundedBorder)
                Picker("Sort", selection: $share.sort) {
                    ForEach(GroupShareModel.Sort.allCases) { Text($0.title).tag($0) }
                }
                .fixedSize()
            }
            HStack(spacing: 6) {
                ForEach(GroupShareModel.Filter.allCases) { filter in
                    Toggle(filter.title, isOn: Binding(
                        get: { share.filters.contains(filter) },
                        set: { share.filters = $0 ? share.filters.union([filter]) : share.filters.subtracting([filter]) }))
                        .toggleStyle(.button)
                        .controlSize(.small)
                }
                Spacer()
                setsMenu
            }
            if share.readCost > 0 {
                HStack {
                    Text(share.filters.contains(where: { $0 != .admin })
                         ? "Filters need each group's rules." : "Limits and rules are not read yet.")
                        .foregroundStyle(Theme.inkSecondary)
                    Button("Read Rules (\(share.readCost.formatted()) calls)") { Task { await share.readRules() } }
                        .disabled(share.isWorking)
                }
                .font(.callout)
            }
            List {
                ForEach(share.visibleGroups) { group in
                    GroupRow(group: group, profile: share.profiles[group.id],
                             isChosen: share.chosen.contains(group.id)) { share.toggle(group.id) }
                }
            }
            .listStyle(.inset)
            HStack {
                Button("Choose All Shown") { share.chooseVisible() }.disabled(share.visibleGroups.isEmpty)
                Button("Clear") { share.clearChosen() }.disabled(share.chosen.isEmpty)
                Spacer()
                Text("\(share.chosen.count.formatted()) chosen").monospacedDigit().foregroundStyle(Theme.inkSecondary)
            }
            .font(.callout)
        }
        .padding(14)
        .alert("Save these groups as a set", isPresented: $isNamingSet) {
            TextField("Name", text: $setName)
            Button("Save") { share.saveSet(named: setName); setName = "" }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var setsMenu: some View {
        Menu("Group Sets") {
            ForEach(share.sets) { set in
                Button("\(set.name) (\(set.groupIDs.count))") { share.choose(set: set) }
            }
            if !share.sets.isEmpty { Divider() }
            Button("Save Chosen as a Set…") { isNamingSet = true }.disabled(share.chosen.isEmpty)
            if !share.sets.isEmpty {
                Menu("Delete a Set") {
                    ForEach(share.sets) { set in Button(set.name, role: .destructive) { share.deleteSet(named: set.name) } }
                }
            }
        }
        .fixedSize()
    }
}

/// One group: chosen or not, its size, and what its rules say.
struct GroupRow: View {
    let group: AccountGroup
    let profile: GroupProfile?
    let isChosen: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle("", isOn: Binding(get: { isChosen }, set: { _ in toggle() })).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).lineLimit(1)
                Text("\(group.members.formatted()) members · \(group.photos.formatted()) photos")
                    .font(.caption).foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            badges
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChosen ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 4) {
            if group.isAdmin { badge("You run it", "person.crop.circle.badge.checkmark") }
            if let profile {
                if profile.isModerated { badge("A moderator approves new photos", "hourglass") }
                if !profile.restrictions.videos { badge("No videos", "video.slash") }
                if profile.restrictions.needsLocation { badge("Photos need a location", "location") }
                Text(room(profile.throttle)).font(.caption.monospacedDigit())
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Theme.well, in: Capsule())
            } else {
                Text("Rules not read").font(.caption).foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private func badge(_ help: String, _ image: String) -> some View {
        Image(systemName: image).foregroundStyle(Theme.inkSecondary).help(help).accessibilityLabel(help)
    }

    private func room(_ throttle: GroupThrottle) -> String {
        switch (throttle.mode, throttle.available) {
        case (.disabled, _): "Closed"
        case (_, nil): "No limit"
        case let (.ever, left?): "\(left) left"
        case let (mode, left?): "\(left) left this \(mode.rawValue)"
        }
    }
}
