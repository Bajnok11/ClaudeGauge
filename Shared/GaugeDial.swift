import SwiftUI
import ClaudeGaugeCore

/// The single reusable gauge used everywhere ClaudeGauge shows a
/// percentage: the menu bar popover and every widget size. Built entirely
/// from system components (`Gauge`, SF Rounded numerals, semantic
/// materials) so it inherits Liquid Glass rendering and dark/light
/// adaptation for free.
struct GaugeDial: View {
    let title: String
    let percent: Double
    let resetMinutes: Int?

    private var status: UsageStatus { UsageStatus(percent: percent) }
    private var clampedPercent: Double { min(max(percent, 0), 100) }

    var body: some View {
        VStack(spacing: 4) {
            Gauge(value: clampedPercent, in: 0...100) {
                Text(title)
            } currentValueLabel: {
                Text("\(Int(clampedPercent.rounded()))%")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(status.color)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(resetMinutes.map(ResetTimeFormatter.string(fromMinutes:)) ?? " ")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) usage")
        .accessibilityValue("\(Int(clampedPercent.rounded())) percent")
    }
}

#Preview {
    HStack(spacing: 28) {
        GaugeDial(title: "Session", percent: 42, resetMinutes: 150)
        GaugeDial(title: "Weekly", percent: 88, resetMinutes: 4230)
    }
    .padding(24)
}
