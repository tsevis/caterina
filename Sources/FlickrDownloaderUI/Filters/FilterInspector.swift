import SwiftUI

import FlickrKit

/// The filters, in an inspector rather than a modal.
///
/// A modal dialog made filtering a thing you finished and dismissed; an
/// inspector makes it a thing you adjust while looking at the results, which is
/// what filtering actually is.
struct FilterInspector: View {
    @Bindable var model: AppModel
    let source: PhotoSource

    var body: some View {
        Form {
            if !supportsFilters {
                Section {
                    Label(inactiveExplanation, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            if filters.isFiltering {
                Section {
                    Button("Clear All Filters") { update(SearchFilters()) }
                        .buttonStyle(.link)
                }
            }

            Section("Sort") {
                // Exclusive, and only values Flickr accepts. Flickr answers
                // `stat=ok` for a sort it does not recognise, so a wrong value
                // would be invisible in the reply — the type is the only place
                // it can be caught.
                Picker("Sort", selection: binding(\.sort) { $0.with(sort: $1) }) {
                    ForEach(SortOrder.offered) { order in
                        Text(order.label).tag(order)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            // **Not disabled with the rest.** Size is applied to the results
            // here rather than sent to Flickr, so it works on a photostream and
            // a pool exactly as it does on a search.
            Section("Size") {
                Toggle("Any size", isOn: Binding(
                    get: { filters.sizes.isEmpty },
                    set: { if $0 { update(filters.with(sizes: [])) } }
                ))
                ForEach(SizeBucket.allCases) { bucket in
                    Toggle(bucket.label, isOn: member(bucket, in: \.sizes) {
                        $0.with(sizes: $1)
                    })
                }
            }
            .disabled(false)

            Section("Colour") {
                Toggle("Any colour", isOn: Binding(
                    get: { filters.colors.isEmpty },
                    set: { if $0 { update(filters.with(colors: [])) } }
                ))
                ForEach(FlickrColor.allCases) { colour in
                    Toggle(colour.label, isOn: member(colour, in: \.colors) {
                        $0.with(colors: $1)
                    })
                }
            }

            Section("Licence") {
                HStack {
                    Button("All") { update(filters.with(licenses: Set(License.allCases))) }
                    Button("None") { update(filters.with(licenses: [])) }
                    Spacer()
                }
                .buttonStyle(.link)
                .font(.callout)

                ForEach(License.allCases) { licence in
                    Toggle(licence.label, isOn: member(licence, in: \.licenses) {
                        $0.with(licenses: $1)
                    })
                    .lineLimit(2)
                }
            }
        }
        // Checkboxes, not switches. A switch says "this setting is on"; these
        // are a set of things being picked out of a list, and macOS spells that
        // with a checkbox.
        .toggleStyle(.checkbox)
        .formStyle(.grouped)
        .disabled(!supportsFilters)
        .inspectorColumnWidth(min: 240, ideal: Theme.Metrics.inspectorWidth, max: 340)
    }

    // MARK: - Reading and writing one filter at a time

    private var filters: SearchFilters { model.workspace[source].filters }

    private var supportsFilters: Bool {
        model.workspace[source].query?.supportsFilters ?? (source == .search)
    }

    /// Why the panel is greyed out, in the words of the method that is running.
    private var inactiveExplanation: String {
        switch source {
        case .groups:
            return "Listing a group's pool uses an API method that takes no "
                + "filters. Type something in the group's search field to search "
                + "inside the pool, where they do apply."
        case .you, .user:
            return "A photostream comes back in Flickr's own order. Licence, "
                + "colour and sort are search filters, and this is not a search."
        case .search:
            // Unreachable: a search's query is a search, and those take
            // filters. Kept so the switch stays exhaustive over the enum
            // rather than over today's call sites.
            return ""
        }
    }

    private func update(_ next: SearchFilters) {
        model.setFilters(next, for: source)
    }

    private func binding<Value>(_ path: KeyPath<SearchFilters, Value>,
                                _ apply: @escaping (SearchFilters, Value) -> SearchFilters
    ) -> Binding<Value> {
        Binding(get: { filters[keyPath: path] },
                set: { update(apply(filters, $0)) })
    }

    private func member<Element: Hashable>(
        _ element: Element,
        in path: KeyPath<SearchFilters, Set<Element>>,
        _ apply: @escaping (SearchFilters, Set<Element>) -> SearchFilters
    ) -> Binding<Bool> {
        Binding(
            get: { filters[keyPath: path].contains(element) },
            set: { isOn in
                var next = filters[keyPath: path]
                if isOn { next.insert(element) } else { next.remove(element) }
                update(apply(filters, next))
            })
    }
}
