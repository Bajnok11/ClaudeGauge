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
    var thresholds: UsageStatus.Thresholds = .default
    var accent: AccentChoice = .status
    var compact = false

    private var status: UsageStatus { UsageStatus(percent: percent, thresholds: thresholds) }
    private var clampedPercent: Double { min(max(percent, 0), 100) }
    private var tint: Color { accent.color(for: status) }

    var body: some View {
        VStack(spacing: compact ? 2 : 4) {
            Gauge(value: clampedPercent, in: 0...100) {
                Text(title)
            } currentValueLabel: {
                Text("\(Int(clampedPercent.rounded()))%")
                    .font(.system(compact ? .body : .title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(tint)
            .scaleEffect(compact ? 0.78 : 1)
            .frame(height: compact ? 46 : 58)

            Text(title)
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)

            if !compact {
                Text(resetMinutes.map(ResetTimeFormatter.string(fromMinutes:)) ?? " ")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) usage")
        .accessibilityValue("\(Int(clampedPercent.rounded())) percent")
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 28) {
            GaugeDial(title: "Session", percent: 42, resetMinutes: 150)
            GaugeDial(title: "Weekly", percent: 88, resetMinutes: 4230)
        }
        HStack(spacing: 28) {
            GaugeDial(title: "Session", percent: 42, resetMinutes: 150, accent: .purple, compact: true)
            GaugeDial(title: "Weekly", percent: 88, resetMinutes: 4230, accent: .purple, compact: true)
        }
    }
    .padding(24)
}
