import SwiftUI
import Charts
import ClaudeGaugeCore

/// Window identity, kept in one place so the popover's "History" button and
/// the `WindowGroup` declaration can't drift apart.
enum HistoryWindow {
    static let id = "history"
}

struct HistoryView: View {
    @EnvironmentObject private var model: UsageModel
    @State private var range = HistoryRange.month
    @State private var breakdown = Breakdown.total

    enum HistoryRange: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30
        case quarter = 90

        var id: Int { rawValue }
        var title: String {
            switch self {
            case .week: return "7 days"
            case .month: return "30 days"
            case .quarter: return "90 days"
            }
        }
    }

    enum Breakdown: String, CaseIterable, Identifiable {
        case total = "Total"
        case split = "By type"

        var id: String { rawValue }
    }

    private var days: [DailyTokenUsage] {
        model.history.dailyPadded(days: range.rawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            controls

            if model.history.isEmpty && !model.isLoadingHistory {
                emptyState
            } else {
                summaryRow
                chart
                projectsTable
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 540)
        .task { model.loadHistory() }
    }

    // MARK: - Pieces

    private var controls: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Local usage history")
                    .font(.title2.weight(.semibold))
                Text("Read from Claude Code's own transcripts on this Mac. Nothing is uploaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isLoadingHistory {
                ProgressView().controlSize(.small)
            }
            Picker("", selection: $range) {
                ForEach(HistoryRange.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            StatTile(
                title: "Total tokens",
                value: Self.formatted(days.reduce(0) { $0 + $1.totalTokens })
            )
            StatTile(
                title: "Busiest day",
                value: days.max(by: { $0.totalTokens < $1.totalTokens })
                    .map { Self.formatted($0.totalTokens) } ?? "—"
            )
            StatTile(
                title: "Daily average",
                value: days.isEmpty ? "—" :
                    Self.formatted(days.reduce(0) { $0 + $1.totalTokens } / max(days.count, 1))
            )
            StatTile(title: "Projects", value: "\(model.history.projects.count)")
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tokens per day").font(.headline)
                Spacer()
                Picker("", selection: $breakdown) {
                    ForEach(Breakdown.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            Chart {
                ForEach(days) { day in
                    if breakdown == .total {
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Tokens", day.totalTokens)
                        )
                        .foregroundStyle(model.preferences.accent.swatchColor.gradient)
                    } else {
                        // Cache reads dwarf everything else on a typical
                        // Claude Code day, so they're stacked separately —
                        // a single "total" bar makes real input/output
                        // movement invisible.
                        BarMark(x: .value("Day", day.date, unit: .day),
                                y: .value("Tokens", day.inputTokens))
                            .foregroundStyle(by: .value("Type", "Input"))
                        BarMark(x: .value("Day", day.date, unit: .day),
                                y: .value("Tokens", day.outputTokens))
                            .foregroundStyle(by: .value("Type", "Output"))
                        BarMark(x: .value("Day", day.date, unit: .day),
                                y: .value("Tokens", day.cacheReadTokens))
                            .foregroundStyle(by: .value("Type", "Cache read"))
                        BarMark(x: .value("Day", day.date, unit: .day),
                                y: .value("Tokens", day.cacheCreationTokens))
                            .foregroundStyle(by: .value("Type", "Cache write"))
                    }
                }
            }
            .chartLegend(breakdown == .split ? .visible : .hidden)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let count = value.as(Int.self) {
                            Text(Self.compact(count))
                        }
                    }
                }
            }
            .frame(height: 200)
        }
    }

    private var projectsTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By project").font(.headline)
            if model.history.projects.isEmpty {
                Text("No project activity in the transcripts yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Table(Array(model.history.projects.prefix(50))) {
                    TableColumn("Project", value: \.displayName)
                    TableColumn("Tokens") { Text(Self.formatted($0.totalTokens)) }
                    TableColumn("Sessions") { Text("\($0.sessionCount)") }
                    TableColumn("Last used") { project in
                        Text(project.lastUsed, format: .relative(presentation: .named))
                    }
                }
                .frame(minHeight: 160)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No transcripts found")
                .font(.headline)
            Text("ClaudeGauge reads `~/.claude/projects`. Use Claude Code for a while and history will show up here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Formatting

    static func formatted(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }

    static func compact(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }
}

private struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}
