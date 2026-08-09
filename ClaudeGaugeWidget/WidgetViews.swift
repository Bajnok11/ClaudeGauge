import SwiftUI
import WidgetKit
import ClaudeGaugeCore

/// Thin adapter: unwraps WidgetKit's timeline entry and hands the plain
/// values to `WidgetContentView` (in `Shared/`), which is also compiled
/// into the app target so README screenshots render the identical layout.
struct ClaudeGaugeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        WidgetContentView(
            snapshot: entry.snapshot,
            preferences: entry.preferences,
            metric: entry.configuration.metric.selection,
            showTrend: entry.configuration.showTrend,
            trend: entry.trend,
            family: family
        )
    }
}

extension WidgetMetricOption {
    var selection: WidgetMetricSelection {
        switch self {
        case .both: return .both
        case .session: return .session
        case .weekly: return .weekly
        }
    }
}
