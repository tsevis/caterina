import SwiftUI

import CaterinaLibrary
import FlickrKit

/// Smart views, who can see, licences, the timeline and tags.
struct OrganizeSidebar: View {
    let organize: OrganizeModel
    @State private var tagFilter = ""
    @State private var searchText = ""
    @State private var timelineByPosted = false
    @State private var removing: String?

    private var selection: Binding<OrganizeScope?> {
        Binding(get: { organize.scope }, set: { scope in
            guard let scope else { return }
            Task { await organize.open(scope) }
        })
    }

    var body: some View {
        List(selection: selection) {
            TextField("Search titles, descriptions, tags", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    Task { await organize.open(.search(text)) }
                }
            Section("Library") {
                ForEach(OrganizeScope.smartViews, id: \.self) { row($0) }
            }
            SavedViewsSection(organize: organize)
            AlbumSidebarSection(organize: organize)
            Section("Who can see") {
                ForEach(Audience.allCases, id: \.self) { row(.audience($0)) }
            }
            Section("Licences") {
                ForEach(License.allCases) { row(.licence($0)) }
            }
            Section("Timeline") {
                Picker("", selection: $timelineByPosted) {
                    Text("Taken").tag(false)
                    Text("Posted").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                ForEach(years, id: \.year) { year in
                    DisclosureGroup {
                        ForEach(year.months) { month in
                            Label(month.title, systemImage: "calendar")
                                .badge(month.count)
                                .tag(timelineByPosted ? OrganizeScope.postedMonth(month.month) : .month(month.month))
                        }
                    } label: {
                        Text(year.year).badge(year.months.reduce(0) { $0 + $1.count })
                    }
                }
            }
            Section("Collections (read only)") {
                ForEach(organize.collections) { CollectionRow(collection: $0) }
                Link(destination: URL(string: "https://www.flickr.com/photos/organize/?start_tab=collection")!) {
                    Label("Edit collections on flickr.com", systemImage: "arrow.up.right.square")
                }
                .help("Flickr's API can read collections but not change them")
            }
            Section("Tags") {
                TextField("Filter tags", text: $tagFilter).textFieldStyle(.roundedBorder)
                ForEach(shownTags) { tag in
                    Label(tag.tag, systemImage: "tag").badge(tag.count).tag(OrganizeScope.tag(tag.tag))
                        .contextMenu {
                            Button("Remove Tag Everywhere…") { removing = tag.tag }
                                .disabled(organize.isRunning)
                        }
                }
            }
        }
        .removeTagEverywhereDialog(organize: organize, tag: $removing)
        .task {
            await organize.loadAlbums()
            await organize.loadCollections()
        }
    }

    private func row(_ scope: OrganizeScope) -> some View {
        Label(scope.title, systemImage: scope.systemImage)
            .badge(organize.count(of: scope) ?? 0)
            .tag(scope)
    }

    private var years: [(year: String, months: [MonthCount])] {
        let grouped = Dictionary(grouping: timelineByPosted ? organize.postedMonths : organize.months, by: \.year)
        return grouped.keys.sorted(by: >).map { ($0, (grouped[$0] ?? []).sorted { $0.month > $1.month }) }
    }

    /// The first 200 by count: a library with thousands of tags would make a
    /// sidebar nobody can scroll.
    private var shownTags: [TagCount] {
        let needle = PhotoEdit.flickrTag(tagFilter)
        let matching = needle.isEmpty ? organize.tags : organize.tags.filter { $0.tag.contains(needle) }
        return Array(matching.prefix(200))
    }
}

/// A collection, its sub-collections and albums; albums open in Organize.
struct CollectionRow: View {
    let collection: PhotoCollection

    var body: some View {
        DisclosureGroup {
            ForEach(collection.children) { CollectionRow(collection: $0) }
            ForEach(collection.albums) { album in
                Label(album.title, systemImage: "rectangle.stack").tag(OrganizeScope.album(id: album.id, title: album.title))
            }
        } label: {
            Label(collection.title, systemImage: "square.stack.3d.up")
        }
    }
}

/// Views saved by name; the current view can be saved from here.
struct SavedViewsSection: View {
    let organize: OrganizeModel
    @State private var isNaming = false
    @State private var name = ""

    var body: some View {
        Section {
            ForEach(organize.savedViews) { view in
                Label(view.name, systemImage: "sparkles.rectangle.stack")
                    .tag(view.scope)
                    .contextMenu {
                        Button("Delete Saved View", role: .destructive) { organize.deleteView(named: view.name) }
                    }
            }
        } header: {
            HStack {
                Text("Saved views")
                Spacer()
                Button { isNaming = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Save “\(organize.scope.title)” as a view that keeps matching new photos")
            }
        }
        .alert("Save this view", isPresented: $isNaming) {
            TextField("Name", text: $name)
            Button("Save") { organize.saveView(named: name); name = "" }
            Button("Cancel", role: .cancel) {}
        }
    }
}
