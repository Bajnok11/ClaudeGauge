import SwiftUI
import ClaudeGaugeCore

struct SettingsView: View {
    @EnvironmentObject private var model: UsageModel

    var body: some View {
        Form {
            Section("Anthropic API Key") {
                SecureField("sk-ant-...", text: $model.apiKey)
                Text(credentialSourceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("A pay-as-you-go Console API key shows Tokens/Requests limits instead of Session/Weekly — it's a separate product from a Claude Pro/Max/Team plan, which is what \"Session\"/\"Weekly\" actually mean.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button("Save") {
                    model.saveAPIKey()
                }
                .disabled(model.apiKey.isEmpty)
            }

            Section("Refresh") {
                Picker("Refresh every", selection: Binding(
                    get: { model.refreshIntervalMinutes },
                    set: { model.updateRefreshInterval($0) }
                )) {
                    ForEach(UsageModel.availableIntervalsMinutes, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                Text("Each refresh makes one minimal (1-token) request to Anthropic to read your live usage headers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch ClaudeGauge at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }

            Section {
                Text("ClaudeGauge reads your existing Claude Code CLI login automatically when available. Your usage data never leaves this Mac except to Anthropic's own API.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 380)
    }

    private var credentialSourceDescription: String {
        switch model.snapshot.source {
        case .claudeCodeOAuth:
            return "Currently using your Claude Code CLI login — the key above is only a fallback if that ever stops working."
        case .manualAPIKey:
            return "Currently using this API key."
        case .none:
            return "No credentials found yet. Paste an API key above, or run `claude` in Terminal to log in."
        }
    }
}
