import Charts
import SwiftUI

import CaterinaLibrary
import FlickrKit

/// Views per day, one bar a day. One series, so no legend: the title names it.
struct ViewsPerDayChart: View {
    let points: [(day: StatsDay, views: Int)]
    @State private var hovered: Date?

    var body: some View {
        Chart {
            ForEach(points, id: \.day) { point in
                BarMark(x: .value("Day", point.day.start, unit: .day), y: .value("Views", point.views))
                    .foregroundStyle(Theme.mark)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2))
            }
            if let hovered, let point = nearest(to: hovered) {
                RuleMark(x: .value("Day", point.day.start, unit: .day))
                    .foregroundStyle(Theme.hairline)
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        ChartReadout(title: point.day.start.formatted(.dateTime.month(.abbreviated).day()),
                                     value: "\(point.views.formatted()) views")
                    }
            }
        }
        .chartXSelection(value: $hovered)
        .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Theme.hairline); AxisValueLabel() } }
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
        .accessibilityLabel("Views per day")
        .accessibilityValue(points.map { "\($0.day.text): \($0.views)" }.joined(separator: ", "))
    }

    private func nearest(to date: Date) -> (day: StatsDay, views: Int)? {
        points.min { abs($0.day.start.timeIntervalSince(date)) < abs($1.day.start.timeIntervalSince(date)) }
    }
}

/// Faves as a running total. A line: it is change over time, not daily amounts.
struct FavesOverTimeChart: View {
    let counts: [PhotoRecord.FaveCount]
    @State private var hovered: Date?

    var body: some View {
        Chart {
            ForEach(counts) { point in
                LineMark(x: .value("Date", point.date), y: .value("Faves", point.count))
                    // The count rises on the day of each fave.
                    .interpolationMethod(.stepStart)
                    .foregroundStyle(Theme.mark)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if let last = counts.last {
                PointMark(x: .value("Date", last.date), y: .value("Faves", last.count))
                    .foregroundStyle(Theme.mark)
                    .symbolSize(40)
            }
            if let hovered, let point = counts.last(where: { $0.date <= hovered }) ?? counts.first {
                RuleMark(x: .value("Date", hovered))
                    .foregroundStyle(Theme.hairline)
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        ChartReadout(title: point.date.formatted(date: .abbreviated, time: .omitted),
                                     value: "\(point.count.formatted()) faves")
                    }
            }
        }
        .chartXSelection(value: $hovered)
        .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Theme.hairline); AxisValueLabel() } }
        .chartXAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Theme.hairline); AxisValueLabel() } }
        .accessibilityLabel("Faves over time")
        .accessibilityValue(counts.last.map { "\($0.count) faves by \($0.date.formatted(date: .abbreviated, time: .omitted))" } ?? "")
    }
}

/// The small tooltip every chart here shares: text in text colours, never the
/// series colour.
struct ChartReadout: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(Theme.inkSecondary)
            Text(value).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
    }
}
