import SwiftUI
import ClaudeGaugeCore

/// The one place the traffic-light palette is defined, so the menu bar
/// popover and the widget can never visually disagree with each other.
extension UsageStatus {
    var color: Color {
        switch self {
        case .ok: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}

extension AccentChoice {
    /// The fixed color for this choice, or nil for `.status` — which means
    /// "follow the traffic light", so the caller has to resolve it against
    /// an actual usage value rather than a constant.
    var fixedColor: Color? {
        switch self {
        case .status: return nil
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .orange: return .orange
        case .green: return .green
        case .graphite: return .secondary
        }
    }

    /// Resolves to the color a gauge should actually be tinted.
    func color(for status: UsageStatus) -> Color {
        fixedColor ?? status.color
    }

    /// A representative swatch for settings UI, where there's no live
    /// reading to resolve `.status` against.
    var swatchColor: Color {
        fixedColor ?? .green
    }
}
