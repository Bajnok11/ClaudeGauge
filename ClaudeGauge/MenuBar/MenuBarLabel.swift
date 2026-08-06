import SwiftUI
import ClaudeGaugeCore

/// The status-bar glyph itself. Deliberately monochrome (SwiftUI templates
/// `MenuBarExtra` labels automatically) to match the system menu bar's own
/// icons per Apple HIG — color lives in the popover and widget, not here.
struct MenuBarLabel: View {
    let snapshot: UsageSnapshot

    var body: some View {
        if snapshot.source == .none {
            Image(systemName: "gauge.with.dots.needle.0percent")
        } else {
            let percent = Int(max(snapshot.sessionPercent, snapshot.weeklyPercent).rounded())
            Label {
                Text("\(percent)%")
                    .font(.system(.body, design: .rounded))
                    .monospacedDigit()
            } icon: {
                Image(systemName: symbolName)
            }
        }
    }

    private var symbolName: String {
        switch snapshot.status {
        case .ok: return "gauge.with.dots.needle.33percent"
        case .warning: return "gauge.with.dots.needle.67percent"
        case .critical: return "gauge.with.dots.needle.100percent"
        }
    }
}
