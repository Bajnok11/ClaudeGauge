import SwiftUI
import AppKit
import ClaudeGaugeCore

struct MenuBarView: View {
    @EnvironmentObject private var model: UsageModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(spacing: 28) {
                GaugeDial(
                    title: model.snapshot.primaryLabel,
                    percent: model.snapshot.sessionPercent,
                    resetMinutes: model.snapshot.sessionResetMinutes
                )
                GaugeDial(
                    title: model.snapshot.secondaryLabel,
                    percent: model.snapshot.weeklyPercent,
                    resetMinutes: model.snapshot.weeklyResetMinutes
                )
            }
            .frame(maxWidth: .infinity)

            if let error = model.lastErrorMessage {
                Label {
                    Text(error).lineLimit(2)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 260)
    }

    private var header: some View {
        HStack {
            Text("ClaudeGauge")
                .font(.headline)
            Spacer()
            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    model.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh now")
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lastUpdatedText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Button("Settings…") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var lastUpdatedText: String {
        guard model.snapshot.fetchedAt > .distantPast else { return "Not refreshed yet" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated " + formatter.localizedString(for: model.snapshot.fetchedAt, relativeTo: Date())
    }
}
