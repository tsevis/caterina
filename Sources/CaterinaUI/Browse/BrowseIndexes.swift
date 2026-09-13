import SwiftUI

import CaterinaLibrary
import FlickrKit

/// Every tag, sized by how often it is used; typing narrows it.
struct TagsIndex: View {
    let browse: BrowseModel
    @State private var filter = ""

    private var shown: [TagCount] {
        filter.isEmpty ? browse.tags : browse.tags.filter { $0.tag.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter \(browse.tags.count.formatted()) tags", text: $filter)
                .textFieldStyle(.roundedBorder).padding(12)
            ScrollView {
                FlowLayout(spacing: 6) {
                    ForEach(shown.prefix(1_500)) { tag in
                        Button { Task { await browse.open(.library(.tagged(tag.tag), title: tag.tag)) } } label: {
                            HStack(spacing: 4) {
                                Text(tag.tag)
                                Text(tag.count.formatted()).foregroundStyle(Theme.inkSecondary).monospacedDigit()
                            }
                            .font(.system(size: size(for: tag.count)))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.well, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("\(tag.count) photos tagged \(tag.tag)")
                    }
                }
                .padding(12)
            }
        }
    }

    /// Logarithmic, so one tag on every photo does not shrink the rest to dust.
    private func size(for count: Int) -> CGFloat {
        let most = Double(browse.tags.first?.count ?? 1)
        let share = log(Double(count) + 1) / log(most + 1)
        return 11 + 9 * share
    }
}

/// Years, each with its months as bars sized by how many photos were taken.
struct TimelineIndex: View {
    let browse: BrowseModel

    private var years: [(year: String, months: [MonthCount])] {
        let grouped = Dictionary(grouping: browse.months, by: \.year)
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        let busiest = browse.months.map(\.count).max() ?? 1
        List {
            ForEach(years, id: \.year) { year in
                Section {
                    ForEach(year.months) { month in
                        Button { Task { await browse.open(.library(.takenIn(month.month), title: month.title)) } } label: {
                            HStack(spacing: 10) {
                                Text(month.title).frame(width: 130, alignment: .leading)
                                GeometryReader { geometry in
                                    RoundedRectangle(cornerRadius: 2).fill(Theme.mark)
                                        .frame(width: max(2, geometry.size.width * Double(month.count) / Double(busiest)))
                                }
                                .frame(height: 10)
                                Text(month.count.formatted()).monospacedDigit().foregroundStyle(Theme.inkSecondary)
                                    .frame(width: 56, alignment: .trailing)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Button { Task { await browse.open(.library(.takenIn(year.year), title: year.year)) } } label: {
                        Text("\(year.year) · \(year.months.reduce(0) { $0 + $1.count }.formatted()) photos")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Your fans, recent faves, and the people you follow.
struct PeopleIndex: View {
    let browse: BrowseModel

    var body: some View {
        List {
            Section("Your top fans") {
                if browse.fans.isEmpty {
                    Text("The fans index reads faves in the background, most viewed photos first. It fills over the next hours.")
                        .foregroundStyle(Theme.inkSecondary)
                }
                ForEach(browse.fans) { fan in
                    Button { Task { await browse.open(.favedBy(nsid: fan.nsid, name: fan.username)) } } label: {
                        HStack {
                            Text(fan.username)
                            Spacer()
                            Text("\(fan.faveCount.formatted()) of your photos").monospacedDigit().foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Section("Recent faves") {
                ForEach(browse.recentFaves.prefix(30)) { fave in
                    HStack {
                        Text(fave.username)
                        Spacer()
                        Text(fave.date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(Theme.inkSecondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { Task { await browse.select(fave.photoID) } }
                }
            }
            Section("People you follow · \(browse.directory.contacts.count.formatted())") {
                ForEach(browse.directory.contacts) { contact in
                    Button { Task { await browse.open(.photostream(of: contact)) } } label: {
                        HStack {
                            Text(contact.displayName)
                            if contact.isFriend { Text("friend").font(.caption).foregroundStyle(Theme.markText) }
                            if contact.isFamily { Text("family").font(.caption).foregroundStyle(Theme.markText) }
                            Spacer()
                            Text(contact.username).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct AlbumsIndex: View {
    let browse: BrowseModel

    var body: some View {
        List(browse.directory.albums) { album in
            Button { open(album) } label: {
                HStack {
                    Label(album.title, systemImage: "rectangle.stack")
                    Spacer()
                    Text("\(album.photoCount.formatted()) · \(BrowseModel.count(album.views, "view"))")
                        .monospacedDigit().foregroundStyle(Theme.inkSecondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func open(_ album: Album) {
        guard let account = browse.accountID() else { return }
        Task { await browse.open(.album(album, accountID: account)) }
    }
}

struct CollectionsIndex: View {
    let browse: BrowseModel

    var body: some View {
        if browse.directory.collections.isEmpty && !browse.isLoading {
            ContentUnavailableView("No collections", systemImage: "square.stack.3d.up",
                                   description: Text("Collections are made on flickr.com; Flickr's API can read them but not change them."))
        } else {
            List(browse.directory.collections.map(CollectionNode.init), children: \.children) { node in
                switch node.kind {
                case .collection:
                    Label(node.title, systemImage: "square.stack.3d.up")
                case .album:
                    Button { open(id: String(node.id.dropFirst("album-".count)), title: node.title) } label: { Label(node.title, systemImage: "rectangle.stack") }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func open(id: String, title: String) {
        guard let account = browse.accountID() else { return }
        Task { await browse.open(.remote(.album(id: id, ownerID: account), title: title)) }
    }
}

/// One row of the collections tree: a collection holding collections and
/// albums, or an album. One tree, so one disclosure triangle per level.
struct CollectionNode: Identifiable, Hashable {
    enum Kind: Hashable { case collection, album }

    let id: String
    let title: String
    let kind: Kind
    let children: [CollectionNode]?

    init(_ collection: PhotoCollection) {
        id = collection.id
        title = collection.title
        kind = .collection
        let nested = collection.children.map(CollectionNode.init)
            + collection.albums.map { CollectionNode(album: $0) }
        children = nested.isEmpty ? nil : nested
    }

    private init(album: PhotoCollection.AlbumRef) {
        id = "album-\(album.id)"
        title = album.title
        kind = .album
        children = nil
    }
}

struct GalleriesIndex: View {
    let browse: BrowseModel

    var body: some View {
        List(browse.directory.galleries) { gallery in
            Button { Task { await browse.open(.gallery(gallery)) } } label: {
                HStack {
                    Label(gallery.title, systemImage: "photo.artframe")
                    Spacer()
                    Text(gallery.itemCount.formatted()).monospacedDigit().foregroundStyle(Theme.inkSecondary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct GroupsIndex: View {
    let browse: BrowseModel

    var body: some View {
        List(browse.directory.groups) { group in
            Button { open(group) } label: {
                HStack {
                    Label(group.name, systemImage: group.isAdmin ? "person.3.fill" : "person.3")
                    Spacer()
                    Text("\(BrowseModel.count(group.members, "member")) · \(group.photos.formatted()) in pool")
                        .monospacedDigit().foregroundStyle(Theme.inkSecondary)
                }
            }
            .buttonStyle(.plain)
            .help("Your photos in \(group.name)")
        }
    }

    private func open(_ group: AccountGroup) {
        guard let account = browse.accountID() else { return }
        Task { await browse.open(.pool(of: group, accountID: account)) }
    }
}

/// Wraps children onto lines, left to right.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, origin) in arrange(proposal: proposal, subviews: subviews).origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let width = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + line), origins)
    }
}
