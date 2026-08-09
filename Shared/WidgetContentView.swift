import SwiftUI
import WidgetKit
import ClaudeGaugeCore

/// Which reading a widget instance shows. Mirrors the widget's AppIntent
/// option, but lives here as a plain enum so this view can be compiled into
/// the app target too — the app renders these same layouts for the README
/// screenshots, and duplicating the layout code would let the two drift.
enum WidgetMetricSelection: String, Sendable {
    case both
    case session
    case weekly
}

/// The actual widget rendering, free of WidgetKit's timeline/intent types.
/// `ClaudeGaugeWidgetView` in the extension is a thin adapter over this.
struct WidgetContentView: View {
    let snapshot: UsageSnapshot
    let preferences: Preferences
    let metric: WidgetMetricSelection
    let showTrend: Bool
    let trend: [Int]
    let family: WidgetFamily

    private var thresholds: UsageStatus.Thresholds { preferences.statusThresholds }
    private var hasTrend: Bool { showTrend && trend.count > 1 }

    var body: some View {
        if !snapshot.hasData {
            unconfigured
        } else {
            switch family {
            case .systemLarge: large
            case .systemMedium: medium
            default: small
            }
        }
    }

    // MARK: - Sizes

    private var small: some View {
        VStack(spacing: 6) {
            switch metric {
            case .weekly:
                dial(title: snapshot.secondaryLabel,
                     percent: snapshot.weeklyPercent,
                     reset: snapshot.weeklyResetMinutes)
            case .session, .both:
                // "Both" can't fit two readable dials in a small widget, so
                // it shows the primary one rather than shrinking both into
                // illegibility.
                dial(title: snapshot.primaryLabel,
                     percent: snapshot.sessionPercent,
                     reset: snapshot.sessionResetMinutes)
            }

            if hasTrend {
                Sparkline(values: trend, tint: preferences.accent.swatchColor)
                    .frame(height: 20)
            }
        }
    }

    private var medium: some View {
        VStack(spacing: 8) {
            HStack(spacing: 22) {
                switch metric {
                case .both:
                    dial(title: snapshot.primaryLabel,
                         percent: snapshot.sessionPercent,
                         reset: snapshot.sessionResetMinutes)
                    dial(title: snapshot.secondaryLabel,
                         percent: snapshot.weeklyPercent,
                         reset: snapshot.weeklyResetMinutes)
                case .session:
                    dial(title: snapshot.primaryLabel,
                         percent: snapshot.sessionPercent,
                         reset: snapshot.sessionResetMinutes)
                case .weekly:
                    dial(title: snapshot.secondaryLabel,
                         percent: snapshot.weeklyPercent,
                         reset: snapshot.weeklyResetMinutes)
                }
            }

            if hasTrend {
                Sparkline(values: trend, tint: preferences.accent.swatchColor)
                    .frame(height: 26)
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ClaudeGauge").font(.headline)
                Spacer()
                if let plan = snapshot.account.displayPlan {
                    Text(plan)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }

            HStack(spacing: 22) {
                dial(title: snapshot.primaryLabel,
                     percent: snapshot.sessionPercent,
                     reset: snapshot.sessionResetMinutes)
                dial(title: snapshot.secondaryLabel,
                     percent: snapshot.weeklyPercent,
                     reset: snapshot.weeklyResetMinutes)
            }
            .frame(maxWidth: .infinity)

            if hasTrend {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last 14 days")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    // Takes the remaining height rather than a fixed one:
                    // a large widget is square, and a short fixed-height
                    // chart leaves a dead band across the bottom half.
                    Sparkline(values: trend, tint: preferences.accent.swatchColor)
                        .frame(maxHeight: .infinity)
                }
            } else {
                Spacer(minLength: 0)
            }

            Text(freshnessText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Same "just now" handling as the popover: `.relative` formats a
    /// seconds-old reading as "0 sec", which reads oddly next to "Updated".
    private var freshnessText: String {
        let age = Date().timeIntervalSince(snapshot.fetchedAt)
        guard age >= 60 else { return "Updated just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated " + formatter.localizedString(for: snapshot.fetchedAt, relativeTo: Date())
    }

    private var unconfigured: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.0percent")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text("Open ClaudeGauge to connect")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(8)
    }

    private func dial(title: String, percent: Double, reset: Int?) -> some View {
        GaugeDial(
            title: title,
            percent: percent,
            resetMinutes: reset,
            thresholds: thresholds,
            accent: preferences.accent,
            compact: family == .systemSmall
        )
    }
}
