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
