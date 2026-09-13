import SwiftUI

import CaterinaLibrary
import FlickrKit

/// Smart views, who can see, licences, the timeline and tags.
struct OrganizeSidebar: View {
    let organize: OrganizeModel
    @State private var tagFilter = ""

    private var selection: Binding<OrganizeScope?> {
        Binding(get: { organize.scope }, set: { scope in
            guard let scope else { return }
            Task { await organize.open(scope) }
        })
    }

    var body: some View {
        List(selection: selection) {
            Section("Library") {
                ForEach(OrganizeScope.smartViews, id: \.self) { row($0) }
            }
            Section("Who can see") {
                ForEach(Audience.allCases, id: \.self) { row(.audience($0)) }
            }
            Section("Licences") {
                ForEach(License.allCases) { row(.licence($0)) }
            }
            Section("Timeline") {
                ForEach(years, id: \.year) { year in
                    DisclosureGroup {
                        ForEach(year.months) { month in
                            Label(month.title, systemImage: "calendar")
                                .badge(month.count)
                                .tag(OrganizeScope.month(month.month))
                        }
                    } label: {
                        Text(year.year).badge(year.months.reduce(0) { $0 + $1.count })
                    }
                }
            }
            Section("Tags") {
                TextField("Filter tags", text: $tagFilter).textFieldStyle(.roundedBorder)
                ForEach(shownTags) { tag in
                    Label(tag.tag, systemImage: "tag").badge(tag.count).tag(OrganizeScope.tag(tag.tag))
                }
            }
        }
    }

    private func row(_ scope: OrganizeScope) -> some View {
        Label(scope.title, systemImage: scope.systemImage)
            .badge(organize.count(of: scope) ?? 0)
            .tag(scope)
    }

    private var years: [(year: String, months: [MonthCount])] {
        let grouped = Dictionary(grouping: organize.months, by: \.year)
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
