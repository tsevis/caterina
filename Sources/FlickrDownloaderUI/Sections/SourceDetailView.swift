import SwiftUI

import FlickrKit

/// One source, from its query bar to its pagination bar.
public struct SourceDetailView: View {
    @Bindable var model: AppModel
    let source: PhotoSource

    @FocusState private var isQueryFocused: Bool

    public var body: some View {
        VStack(spacing: 0) {
            queryBar
            Divider()

            Group {
                if case .ready = state.status {
                    PhotoGridView(photos: state.photos,
                                  selection: state.selection.ids,
                                  onClick: { model.click($0, modifiers: $1, in: source) },
                                  onSweep: { model.sweep($0, in: source) },
                                  onMove: { model.moveSelection(by: $0, in: source) },
                                  onPreview: { model.preview($0) },
                                  dragVariant: model.downloadVariant)
                } else {
                    SourceStateView(source: source, status: state.status,
                                    isSignedIn: model.isSignedIn) {
                        model.submit(source)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            PaginationBar(state: state,
                          onPrevious: { model.previousPage(in: source) },
                          onNext: { model.nextPage(in: source) },
                          onPerPage: { model.setPerPage($0, for: source) })
        }
        .navigationTitle(source.title)
        .onAppear { isQueryFocused = source != .you }
    }

    private var state: SectionState { model.workspace[source] }

    // MARK: - What each source asks for

    @ViewBuilder
    private var queryBar: some View {
        HStack(spacing: 8) {
            switch source {
            case .you:
                youBar
            case .search:
                field("Search Flickr", prompt: "harbour at dusk")
                submitButton("Search")
            case .user:
                field("Photostream", prompt: "flickr.com/photos/someone or a username")
                submitButton("Load")
            case .groups:
                field("Group", prompt: "flickr.com/groups/name or the exact group name")
                groupSearchField
                submitButton("Load")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var youBar: some View {
        HStack(spacing: 10) {
            if let account = model.account {
                Label(account.username.isEmpty ? "Signed in" : account.username,
                      systemImage: "person.crop.circle.fill")
                    .foregroundStyle(Theme.inkSecondary)
                Button("Reload") { model.submit(.you) }
            } else {
                Text("Sign in to Flickr to see your own photos.")
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
        }
    }

    private func field(_ label: String, prompt: String) -> some View {
        TextField(label, text: Binding(
            get: { state.input },
            set: { model.setInput($0, for: source) }
        ), prompt: Text(prompt))
            .textFieldStyle(.roundedBorder)
            .focused($isQueryFocused)
            .onSubmit { model.submit(source) }
            .accessibilityLabel(label)
    }

    /// Searching *inside* a pool is a different API method from listing it, and
    /// only the first supports the filters — so it gets its own field rather
    /// than overloading the group field.
    private var groupSearchField: some View {
        TextField("In this group", text: $model.groupSearchText,
                  prompt: Text("optional: search inside the pool"))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 240)
            .onSubmit {
                if model.resolvedGroup != nil {
                    model.searchWithinResolvedGroup()
                } else {
                    model.submit(.groups)
                }
            }
    }

    /// No keyboard shortcut: the field's own `onSubmit` handles Return, and a
    /// `.return` shortcut here ran the search a second time on every press.
    private func submitButton(_ title: String) -> some View {
        Button(title) { model.submit(source) }
            .disabled(state.input.trimmed.isEmpty && source != .you)
    }
}
