import SwiftUI
import ClaudeGaugeCore

/// The status-bar glyph itself.
///
/// Monochrome by default: SwiftUI templates `MenuBarExtra` labels so they
/// match the system's own icons, which is what Apple's HIG asks for. Users
/// who'd rather have the color cue can opt in (`menuBarColored`), which
/// renders the gauge as a drawn image instead of a template symbol.
struct MenuBarLabel: View {
    let snapshot: UsageSnapshot
    let preferences: Preferences

    private var value: Double { preferences.menuBarMetric.value(from: snapshot) }
    private var percentText: String { "\(Int(value.rounded()))%" }
    private var status: UsageStatus {
        UsageStatus(percent: value, thresholds: preferences.statusThresholds)
    }

    var body: some View {
        if !snapshot.hasData {
            Image(systemName: "gauge.with.dots.needle.0percent")
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch preferences.menuBarStyle {
        case .iconOnly:
            icon
        case .percentOnly:
            percentLabel
        case .iconAndPercent:
            HStack(spacing: 3) {
                icon
                percentLabel
            }
        case .iconAndBar:
            HStack(spacing: 4) {
                icon
                MenuBarMiniBar(percent: value, color: barColor)
            }
        }
    }

    private var icon: some View {
        Image(systemName: symbolName)
            .foregroundStyle(preferences.menuBarColored ? AnyShapeStyle(barColor) : AnyShapeStyle(.primary))
    }

    private var percentLabel: some View {
        Text(percentText)
            .font(.system(.body, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(preferences.menuBarColored ? AnyShapeStyle(barColor) : AnyShapeStyle(.primary))
    }

    private var barColor: Color {
        preferences.accent.color(for: status)
    }

    /// SF Symbols ships gauge glyphs at fixed needle positions, so the icon
    /// steps through them rather than tracking the exact percentage.
    private var symbolName: String {
        switch status {
        case .ok: return "gauge.with.dots.needle.33percent"
        case .warning: return "gauge.with.dots.needle.67percent"
        case .critical: return "gauge.with.dots.needle.100percent"
        }
    }
}

/// A tiny capacity bar sized to sit inside the menu bar's ~22pt height.
private struct MenuBarMiniBar: View {
    let percent: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * min(max(percent, 0), 100) / 100)
            }
        }
        .frame(width: 26, height: 6)
    }
}
