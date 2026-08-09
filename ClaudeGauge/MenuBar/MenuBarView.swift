import SwiftUI
import AppKit
import ClaudeGaugeCore

struct MenuBarView: View {
    @EnvironmentObject private var model: UsageModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    private var prefs: Preferences { model.preferences }

    var body: some View {
        VStack(alignment: .leading, spacing: prefs.compactPopover ? 10 : 14) {
            header

            gauges

            if prefs.showAccountSection, !model.snapshot.account.isEmpty {
                accountSection
            }

            if !model.preferences.enabledExtraProviderIDs.isEmpty {
                extraProviders
            }

            if prefs.showHistorySparkline, !prefs.compactPopover {
                historySection
            }

            if let error = model.lastErrorMessage {
                errorBanner(error)
            }

            Divider()

            footer
        }
        .padding(14)
        .frame(width: prefs.compactPopover ? 240 : 288)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .foregroundStyle(.secondary)
            Text("ClaudeGauge")
                .font(.headline)
            Spacer()
            if model.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    model.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh now")
            }
        }
    }

    private var gauges: some View {
        HStack(spacing: prefs.compactPopover ? 18 : 28) {
            GaugeDial(
                title: model.snapshot.primaryLabel,
                percent: model.snapshot.sessionPercent,
                resetMinutes: model.snapshot.sessionResetMinutes,
                thresholds: model.statusThresholds,
                accent: prefs.accent,
                compact: prefs.compactPopover
            )
            GaugeDial(
                title: model.snapshot.secondaryLabel,
                percent: model.snapshot.weeklyPercent,
                resetMinutes: model.snapshot.weeklyResetMinutes,
                thresholds: model.statusThresholds,
                accent: prefs.accent,
                compact: prefs.compactPopover
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)
                if let plan = model.snapshot.account.displayPlan {
                    Text(plan)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                Text(model.credentialSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if let tier = model.snapshot.account.rateLimitTier {
                Text(tier)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if model.snapshot.account.isExpired {
                Label("Login expired — run `claude` to sign in again", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var extraProviders: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            ForEach(UsageModel.availableExtraProviders.filter {
                model.preferences.enabledExtraProviderIDs.contains($0.id)
            }, id: \.id) { provider in
                if let snapshot = model.extraSnapshots[provider.id] {
                    ExtraProviderRow(
                        name: provider.name,
                        snapshot: snapshot,
                        thresholds: model.statusThresholds,
                        accent: prefs.accent
                    )
                } else if let error = model.extraErrors[provider.id] {
                    HStack(spacing: 6) {
                        Text(provider.name).font(.caption).fontWeight(.medium)
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack {
                Text("Last 14 days")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Self.compactTokens(model.history.totalTokens))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Sparkline(
                values: model.history.dailyPadded(days: 14).map(\.totalTokens),
                tint: prefs.accent.swatchColor
            )
            .frame(height: 34)
        }
    }

    private func errorBanner(_ error: String) -> some View {
        Label {
            Text(error).lineLimit(3)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.caption)
        .foregroundStyle(.orange)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lastUpdatedText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("History") {
                    openWindow(id: HistoryWindow.id)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.plain)

                Button("Settings…") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var lastUpdatedText: String {
        guard model.snapshot.hasData else { return "Not refreshed yet" }
        let age = Date().timeIntervalSince(model.snapshot.fetchedAt)
        // RelativeDateTimeFormatter renders a just-taken reading as
        // "in 0 seconds" — future tense for something that already
        // happened. Handle the fresh case explicitly.
        guard age >= 60 else { return "Updated just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated " + formatter.localizedString(for: model.snapshot.fetchedAt, relativeTo: Date())
    }

    /// 1_234_567 → "1.2M". Used where a full digit group would crowd the
    /// popover's narrow layout.
    static func compactTokens(_ count: Int) -> String {
        switch count {
        case 1_000_000...:
            return String(format: "%.1fM tokens", Double(count) / 1_000_000)
        case 1_000...:
            return String(format: "%.0fK tokens", Double(count) / 1_000)
        default:
            return "\(count) tokens"
        }
    }
}

/// One compact row for a non-Claude provider — a name plus two inline bars,
/// rather than another pair of full dials, so adding providers doesn't grow
/// the popover without bound.
private struct ExtraProviderRow: View {
    let name: String
    let snapshot: UsageSnapshot
    let thresholds: UsageStatus.Thresholds
    let accent: AccentChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(.caption).fontWeight(.medium)
                Spacer()
                Text(staleness)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            bar(label: snapshot.primaryLabel, percent: snapshot.sessionPercent)
            if snapshot.weeklyPercent > 0 {
                bar(label: snapshot.secondaryLabel, percent: snapshot.weeklyPercent)
            }
        }
    }

    private func bar(label: String, percent: Double) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(accent.color(for: UsageStatus(percent: percent, thresholds: thresholds)))
                        .frame(width: geo.size.width * min(max(percent, 0), 100) / 100)
                }
            }
            .frame(height: 5)
            Text("\(Int(percent.rounded()))%")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    /// Codex data comes from files the CLI wrote, so it can be days old —
    /// saying so is more useful than implying it's live.
    private var staleness: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: snapshot.fetchedAt, relativeTo: Date())
    }
}
