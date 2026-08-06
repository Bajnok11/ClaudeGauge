import SwiftUI
import ClaudeGaugeCore

struct ClaudeGaugeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: UsageSnapshot

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 20) {
                GaugeDial(
                    title: snapshot.primaryLabel,
                    percent: snapshot.sessionPercent,
                    resetMinutes: snapshot.sessionResetMinutes
                )
                GaugeDial(
                    title: snapshot.secondaryLabel,
                    percent: snapshot.weeklyPercent,
                    resetMinutes: snapshot.weeklyResetMinutes
                )
            }
        default:
            GaugeDial(
                title: snapshot.primaryLabel,
                percent: snapshot.sessionPercent,
                resetMinutes: snapshot.sessionResetMinutes
            )
        }
    }
}
