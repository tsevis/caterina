import SwiftUI

import CaterinaLibrary
import FlickrKit

/// Add photos to groups: tick the groups, see what will happen in each, press
/// the button. Your usual groups come first and rules load by themselves.
struct GroupShareSheet: View {
    @Bindable var share: GroupShareModel
    let onClose: () -> Void
    let onAdded: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Add to Groups").font(.title2.weight(.semibold))
                Text(OrganizeModel.count(share.subjects.count)).foregroundStyle(Theme.inkSecondary)
                SubjectStrip(subjects: share.subjects).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
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
                SharePlanPanel(share: share, onAdded: onAdded, onClose: onClose).frame(minWidth: 380)
            }
        }
        .frame(minWidth: 860, idealWidth: 980, minHeight: 600, idealHeight: 680)
        .task {
            await share.load()
            await share.readRulesQuietly()
        }
    }
}

/// The photos going, so nobody adds the wrong ones. Just-uploaded photos have
/// no thumbnail yet, and the count beside this says how many.
private struct SubjectStrip: View {
    private static let shown = 8
    let subjects: [ShareSubject]

    var body: some View {
        let pictured = subjects.filter { $0.thumbnailURL != nil }
        HStack(spacing: 4) {
            ForEach(pictured.prefix(Self.shown)) { subject in
                RowThumbnail(address: subject.thumbnailURL, size: 36).help(subject.title)
            }
            if pictured.count > Self.shown {
                Text("+\((pictured.count - Self.shown).formatted())")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}

/// Search, filter, sort and choose groups; saved sets.
struct GroupFinder: View {
    @Bindable var share: GroupShareModel
    @State private var isNamingSet = false
    @State private var setName = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Search your \(share.groups.count.formatted()) groups", text: $share.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
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
                        .fixedSize()
                        .help(filter.help)
                }
                Spacer()
                setsMenu
            }
            rulesStatus
            List {
                ForEach(share.visibleGroups) { group in
                    GroupRow(group: group, profile: share.profiles[group.id],
                             isChosen: share.chosen.contains(group.id), isRecent: share.isRecent(group.id),
                             isCheckingRules: share.rulesLeftToRead > 0) { share.toggle(group.id) }
                }
            }
            .listStyle(.inset)
            .overlay {
                if share.visibleGroups.isEmpty && !share.isWorking {
                    ContentUnavailableView("No groups to show", systemImage: "magnifyingglass",
                                           description: Text("Try another word, or turn off a filter."))
                }
            }
            HStack {
                Button("Choose All Shown") { share.chooseVisible() }.disabled(share.visibleGroups.isEmpty)
                Button("Clear") { share.clearChosen() }.disabled(share.chosen.isEmpty)
                Spacer()
                Text("\(share.chosen.count.formatted()) chosen").monospacedDigit().foregroundStyle(Theme.inkSecondary)
            }
            .font(.callout)
        }
        .padding(14)
        .onAppear { isSearchFocused = true }
        .alert("Save these groups as a set", isPresented: $isNamingSet) {
            TextField("Name", text: $setName)
            Button("Save") { share.saveSet(named: setName); setName = "" }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Quiet while it works; a button only if it stopped short.
    @ViewBuilder
    private var rulesStatus: some View {
        if share.rulesLeftToRead > 0 {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Checking each group's limits… \(share.rulesLeftToRead.formatted()) left")
                    .foregroundStyle(Theme.inkSecondary)
            }
            .font(.callout)
        } else if share.readCost > 0 && !share.isWorking {
            HStack {
                Text("Limits unknown for \(share.readCost.formatted()) \(share.readCost == 1 ? "group" : "groups").")
                    .foregroundStyle(Theme.inkSecondary)
                Button("Try Again") {
                    share.clearProblem()
                    Task { await share.readRulesQuietly() }
                }
            }
            .font(.callout)
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
    var isRecent = false
    var isCheckingRules = false
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
            if isRecent { badge("You added photos here recently", "clock") }
            if group.isAdmin { badge("You run it", "person.crop.circle.badge.checkmark") }
            if let profile {
                if profile.isModerated { badge("A moderator approves new photos", "hourglass") }
                if !profile.restrictions.videos { badge("No videos", "video.slash") }
                if profile.restrictions.needsLocation { badge("Photos need a location", "location") }
                Text(room(profile.throttle)).font(.caption.monospacedDigit())
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Theme.well, in: Capsule())
            } else {
                Text(isCheckingRules ? "Checking…" : "Limits unknown").font(.caption).foregroundStyle(Theme.inkSecondary)
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
        case let (.day, left?): "\(left) left today"
        case let (.week, left?): "\(left) left this week"
        case let (.month, left?): "\(left) left this month"
        case let (_, left?): "\(left) left"
        }
    }
}
