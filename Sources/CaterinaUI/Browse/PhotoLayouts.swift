import MapKit
import SwiftUI

import CaterinaLibrary
import FlickrKit

/// A binding to the chosen photo that loads its record when it changes.
@MainActor
func photoSelection(_ browse: BrowseModel) -> Binding<String?> {
    Binding(get: { browse.selectedPhotoID }, set: { id in Task { await browse.select(id) } })
}

/// Rows: title, figure, thumbnail. The densest way to scan a ranking.
struct PhotoListLayout: View {
    let browse: BrowseModel

    var body: some View {
        List(selection: photoSelection(browse)) {
            ForEach(browse.items) { item in
                HStack(spacing: 10) {
                    RowThumbnail(address: item.photo.thumbnailURL, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.photo.title.isEmpty ? "Untitled" : item.photo.title).lineLimit(1)
                        Text(item.figure).font(.caption).monospacedDigit().foregroundStyle(Theme.inkSecondary)
                    }
                }
                .padding(.vertical, 2)
                .tag(item.photo.id)
            }
            LoadMoreRow(browse: browse)
        }
    }
}

/// Tiles, as large as the window allows. The way to see the photographs.
struct PhotoGridLayout: View {
    let browse: BrowseModel
    @AppStorage("BrowseTileSize") private var tileSize = 180.0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                PhotoTiles(items: browse.items, browse: browse, tileSize: tileSize)
                    .padding(12)
                LoadMoreRow(browse: browse).padding(.bottom, 12)
            }
            TileSizeBar(tileSize: $tileSize)
        }
    }
}

/// Months as headed sections, newest first, tiles inside.
struct PhotoTimelineLayout: View {
    let browse: BrowseModel
    @AppStorage("BrowseTileSize") private var tileSize = 180.0

    private var months: [(month: String, items: [BrowseItem])] {
        let grouped = Dictionary(grouping: browse.items) { $0.photo.taken.map { String($0.prefix(7)) } ?? "" }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18, pinnedViews: .sectionHeaders) {
                    ForEach(months, id: \.month) { month in
                        Section {
                            PhotoTiles(items: month.items, browse: browse, tileSize: tileSize)
                        } header: {
                            Text(month.month.isEmpty ? "Date unknown" : MonthCount(month: month.month, count: 0).title)
                                .font(.headline)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.bar)
                        }
                    }
                }
                .padding(12)
                LoadMoreRow(browse: browse).padding(.bottom, 12)
            }
            TileSizeBar(tileSize: $tileSize)
        }
    }
}

/// Located photos as pins; choosing one shows its record.
struct PhotoMapLayout: View {
    let browse: BrowseModel
    /// SwiftUI's map does not cluster; beyond this many pins it stops
    /// being readable or quick.
    static let pinLimit = 2_000

    private var located: [BrowseItem] {
        Array(browse.items.filter { $0.photo.location != nil }.prefix(Self.pinLimit))
    }

    var body: some View {
        Map(selection: photoSelection(browse)) {
            ForEach(located) { item in
                if let location = item.photo.location {
                    Annotation(item.photo.title, coordinate: CLLocationCoordinate2D(latitude: location.latitude,
                                                                                    longitude: location.longitude)) {
                        RowThumbnail(address: item.photo.thumbnailURL, size: browse.selectedPhotoID == item.photo.id ? 56 : 32)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white, lineWidth: 2))
                            .shadow(radius: 2)
                    }
                    .tag(item.photo.id)
                }
            }
        }
        .mapControls { MapZoomStepper(); MapCompass(); MapScaleView() }
        .overlay(alignment: .bottomLeading) {
            if browse.items.filter({ $0.photo.location != nil }).count > Self.pinLimit {
                Text("Showing the first \(Self.pinLimit.formatted()) located photos")
                    .font(.caption).padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5)).padding(10)
            }
        }
    }
}

/// The shared tile grid.
struct PhotoTiles: View {
    let items: [BrowseItem]
    let browse: BrowseModel
    let tileSize: Double

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: tileSize), spacing: 8)], spacing: 8) {
            ForEach(items) { item in
                BrowseTile(item: item, isSelected: browse.selectedPhotoID == item.photo.id)
                    .onTapGesture { Task { await browse.select(item.photo.id) } }
            }
        }
    }
}

struct BrowseTile: View {
    let item: BrowseItem
    let isSelected: Bool
    @State private var image: NSImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(Theme.well)
            .overlay { if let image { Image(nsImage: image).resizable().scaledToFill() } }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius)
                    .strokeBorder(isSelected ? Theme.mark : Theme.hairline, lineWidth: isSelected ? 3 : 1)
            }
            .overlay(alignment: .bottomLeading) {
                Text(item.figure)
                    .font(.caption2.weight(.medium)).monospacedDigit()
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .padding(5)
                    .opacity(item.figure.isEmpty ? 0 : 1)
            }
            .contentShape(Rectangle())
            .help(item.photo.title.isEmpty ? "Untitled" : item.photo.title)
            .accessibilityElement()
            .accessibilityLabel(item.photo.title.isEmpty ? "Untitled" : item.photo.title)
            .accessibilityValue(item.figure)
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            .task(id: item.photo.id) {
                guard let address = item.photo.mediumURL ?? item.photo.thumbnailURL else { return }
                image = await ThumbnailStore.shared.image(for: address)
            }
    }
}

struct TileSizeBar: View {
    @Binding var tileSize: Double

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            Image(systemName: "photo").imageScale(.small).foregroundStyle(Theme.inkSecondary)
            Slider(value: $tileSize, in: 90...420).frame(width: 140).controlSize(.small)
                .accessibilityLabel("Tile size")
            Image(systemName: "photo").imageScale(.large).foregroundStyle(Theme.inkSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .top) { Theme.hairline.frame(height: 1) }
    }
}

struct LoadMoreRow: View {
    let browse: BrowseModel

    var body: some View {
        if browse.canLoadMore {
            HStack {
                Spacer()
                Button(browse.isLoading ? "Loading…" : "Load More") { Task { await browse.loadMore() } }
                    .disabled(browse.isLoading)
                Spacer()
            }
        }
    }
}

/// A square thumbnail from the shared store, or its well while it loads.
struct RowThumbnail: View {
    let address: String?
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Theme.well)
            .frame(width: size, height: size)
            .overlay { if let image { Image(nsImage: image).resizable().scaledToFill() } }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .task(id: address) {
                image = nil
                guard let address else { return }
                image = await ThumbnailStore.shared.image(for: address)
            }
            .accessibilityHidden(true)
    }
}
