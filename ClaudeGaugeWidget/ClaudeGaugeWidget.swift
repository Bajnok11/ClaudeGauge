import WidgetKit
import SwiftUI
import ClaudeGaugeCore

/// Deliberately dumb: the widget never calls the network itself. It only
/// ever reads whatever `UsageModel` last wrote to `SharedStorage`, which
/// keeps it inside WidgetKit's background-execution budget and guarantees
/// it can never show a number the menu bar app didn't already show first.
struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct UsageTimelineProvider: TimelineProvider {
    private let storage = SharedStorage()

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(), snapshot: storage.read() ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = UsageEntry(date: Date(), snapshot: storage.read() ?? .empty)
        let refreshInterval = storage.readRefreshInterval() ?? 300
        let nextUpdate = Date().addingTimeInterval(max(refreshInterval, 60))
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct ClaudeGaugeWidget: Widget {
    let kind = "ClaudeGaugeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageTimelineProvider()) { entry in
            ClaudeGaugeWidgetView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("ClaudeGauge")
        .description("Live Claude session and weekly usage.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    ClaudeGaugeWidget()
} timeline: {
    UsageEntry(
        date: .now,
        snapshot: UsageSnapshot(
            sessionPercent: 42,
            weeklyPercent: 18,
            sessionResetMinutes: 150,
            weeklyResetMinutes: 4000,
            fetchedAt: .now,
            source: .claudeCodeOAuth
        )
    )
}
