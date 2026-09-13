import SwiftUI

import CaterinaLibrary
import FlickrKit

/// One photo: its numbers first, then the charts, then everything else.
struct PhotoRecordView: View {
    let record: PhotoRecord
    let thumbnailURL: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                figures
                viewsSection
                favesSection
                RecordPlaces(contexts: record.contexts)
                if !record.info.tags.isEmpty { tags }
                RecordCamera(exif: record.exif)
                RecordComments(comments: record.comments)
                RecordFavers(faves: record.faves, total: record.faveTotal)
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            RowThumbnail(address: thumbnailURL, size: 96)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.info.title.isEmpty ? "Untitled" : record.info.title)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                Text(subtitle).foregroundStyle(Theme.inkSecondary)
                if let url = record.info.pageURL {
                    Link("Open on Flickr", destination: url).font(.callout)
                }
            }
        }
    }

    private var subtitle: String {
        [record.info.taken.map { "Taken \($0.prefix(10))" },
         record.info.place,
         record.info.license?.label]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var figures: some View {
        HStack(spacing: 0) {
            Figure(value: record.info.views, label: "views")
            Figure(value: record.faveTotal, label: "faves")
            Figure(value: record.info.commentCount, label: "comments")
            Figure(value: record.contexts.albums.count, label: "albums")
            Figure(value: record.contexts.groups.count, label: "groups")
        }
    }

    @ViewBuilder
    private var viewsSection: some View {
        RecordSection("Views per day") {
            if record.history.isEmpty {
                Text("No daily numbers saved yet. Caterina saves each whole day Flickr Pro stats hold, and keeps them after Flickr lets them go.")
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                ViewsPerDayChart(points: record.history.map { ($0.day, $0.views) })
                    .frame(height: 160)
                Text("Since \(record.history.first?.day.start.formatted(date: .abbreviated, time: .omitted) ?? "")")
                    .font(.caption).foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    @ViewBuilder
    private var favesSection: some View {
        if !record.faves.isEmpty {
            RecordSection("Faves over time") {
                FavesOverTimeChart(counts: PhotoRecord.cumulativeFaves(record.faves))
                    .frame(height: 140)
                if record.faveTotal > record.faves.count {
                    Text("The latest \(record.faves.count.formatted()) of \(record.faveTotal.formatted()) faves.")
                        .font(.caption).foregroundStyle(Theme.inkSecondary)
                }
            }
        }
    }

    private var tags: some View {
        RecordSection("Tags") {
            Text(record.info.tags.joined(separator: " · ")).textSelection(.enabled)
        }
    }
}

struct Figure: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value.formatted()).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct RecordSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
        }
    }
}
