import WidgetKit
import SwiftUI
import AppIntents
import ClaudeGaugeCore

/// What a single widget instance shows. Exposed through `AppIntent` so each
/// placed widget is configured independently via right-click → Edit Widget
/// — a user can pin one small widget for Session and another for Weekly,
/// which a single global preference couldn't express.
enum WidgetMetricOption: String, AppEnum {
    case both
    case session
    case weekly

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Metric")

    static let caseDisplayRepresentations: [WidgetMetricOption: DisplayRepresentation] = [
        .both: "Both",
        .session: "Session / Tokens",
        .weekly: "Weekly / Requests"
    ]
}

struct ConfigureWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "ClaudeGauge"
    static let description = IntentDescription("Choose what this widget shows.")

    @Parameter(title: "Show", default: .both)
    var metric: WidgetMetricOption

    @Parameter(title: "Show usage trend", default: true)
    var showTrend: Bool
}

/// Deliberately dumb: the widget never calls the network itself. It only
/// ever reads whatever `UsageModel` last wrote to `SharedStorage`, which
/// keeps it inside WidgetKit's background-execution budget and guarantees
/// it can never show a number the menu bar app didn't already show first.
struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
    let preferences: Preferences
    let configuration: ConfigureWidgetIntent
    /// Daily token totals for the trend line. Parsed here rather than read
    /// from a cache because it's local file I/O the extension can afford
    /// once per timeline refresh, and it keeps the app from having to
    /// serialize a second payload through the App Group.
    let trend: [Int]
}

struct UsageTimelineProvider: AppIntentTimelineProvider {
    private let storage = SharedStorage()

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(
            date: Date(),
            snapshot: .empty,
            preferences: .default,
            configuration: ConfigureWidgetIntent(),
            trend: []
        )
    }

    func snapshot(for configuration: ConfigureWidgetIntent, in context: Context) async -> UsageEntry {
        entry(for: configuration, includeTrend: !context.isPreview)
    }

    func timeline(for configuration: ConfigureWidgetIntent, in context: Context) async -> Timeline<UsageEntry> {
        let refreshInterval = storage.readRefreshInterval() ?? 300
        let nextUpdate = Date().addingTimeInterval(max(refreshInterval, 60))
        return Timeline(entries: [entry(for: configuration, includeTrend: true)], policy: .after(nextUpdate))
    }

    private func entry(for configuration: ConfigureWidgetIntent, includeTrend: Bool) -> UsageEntry {
        let trend: [Int]
        if includeTrend && configuration.showTrend {
            trend = TranscriptLogParser.report(sinceDays: 14)
                .dailyPadded(days: 14)
                .map(\.totalTokens)
        } else {
            trend = []
        }
        return UsageEntry(
            date: Date(),
            snapshot: storage.read() ?? .empty,
            preferences: storage.readPreferences(),
            configuration: configuration,
            trend: trend
        )
    }
}

struct ClaudeGaugeWidget: Widget {
    let kind = "ClaudeGaugeWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ConfigureWidgetIntent.self,
            provider: UsageTimelineProvider()
        ) { entry in
            ClaudeGaugeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("ClaudeGauge")
        .description("Live Claude session and weekly usage.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemMedium) {
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
            source: .claudeCodeOAuth,
            account: AccountInfo(subscriptionType: "max")
        ),
        preferences: .default,
        configuration: ConfigureWidgetIntent(),
        trend: [3, 9, 4, 12, 8, 15, 6, 11, 2, 14, 9, 7, 13, 5]
    )
}
