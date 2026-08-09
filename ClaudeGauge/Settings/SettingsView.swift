import SwiftUI
import UserNotifications
import ClaudeGaugeCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            NotificationSettingsTab()
                .tabItem { Label("Alerts", systemImage: "bell") }
            ProvidersSettingsTab()
                .tabItem { Label("Providers", systemImage: "square.stack.3d.up") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 480)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var model: UsageModel

    var body: some View {
        Form {
            Section("Credentials") {
                Picker("Use", selection: Binding(
                    get: { model.preferences.credentialSource },
                    set: { source in model.update { $0.credentialSource = source } }
                )) {
                    ForEach(CredentialSource.allCases, id: \.self) { source in
                        Text(source.displayName).tag(source)
                    }
                }
                Text(sourceExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Currently active") {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(model.snapshot.hasData ? Color.green : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(model.snapshot.hasData ? model.snapshot.source.displayName : "Nothing yet")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Anthropic API key") {
                SecureField("sk-ant-...", text: $model.apiKeyDraft)
                HStack {
                    Button("Save") { model.saveAPIKey() }
                        .disabled(model.apiKeyDraft.isEmpty)
                    Button("Clear") { model.clearAPIKey() }
                        .disabled(!model.hasStoredAPIKey)
                }
                Text("Optional. A pay-as-you-go Console key is a separate product from a Pro/Max/Team plan and reports Tokens/Requests limits instead of Session/Weekly. Stored in your Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Refresh") {
                Picker("Check every", selection: Binding(
                    get: { model.preferences.refreshIntervalMinutes },
                    set: { minutes in model.update { $0.refreshIntervalMinutes = minutes } }
                )) {
                    ForEach(Preferences.availableIntervalsMinutes, id: \.self) { minutes in
                        Text(minutes == 60 ? "1 hour" : "\(minutes) min").tag(minutes)
                    }
                }
                Text("Each check makes one minimal (1-token) request to Anthropic to read your live usage headers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch ClaudeGauge at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }
        }
        .formStyle(.grouped)
    }

    private var sourceExplanation: String {
        switch model.preferences.credentialSource {
        case .automatic:
            return "Uses your Claude Code login when one exists, otherwise the API key below."
        case .claudeCodeOnly:
            return "Only your Claude Code CLI login. The API key below is ignored."
        case .apiKeyOnly:
            return "Only the API key below, even if you're signed in to Claude Code."
        }
    }
}

// MARK: - Appearance

private struct AppearanceSettingsTab: View {
    @EnvironmentObject private var model: UsageModel

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Show", selection: Binding(
                    get: { model.preferences.menuBarStyle },
                    set: { style in model.update { $0.menuBarStyle = style } }
                )) {
                    ForEach(MenuBarStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Metric", selection: Binding(
                    get: { model.preferences.menuBarMetric },
                    set: { metric in model.update { $0.menuBarMetric = metric } }
                )) {
                    ForEach(MenuBarMetric.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("Use color in the menu bar", isOn: Binding(
                    get: { model.preferences.menuBarColored },
                    set: { on in model.update { $0.menuBarColored = on } }
                ))
                Text("Off by default so the icon matches macOS's own monochrome menu bar items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Color") {
                Picker("Accent", selection: Binding(
                    get: { model.preferences.accent },
                    set: { accent in model.update { $0.accent = accent } }
                )) {
                    ForEach(AccentChoice.allCases, id: \.self) { choice in
                        HStack {
                            Circle().fill(choice.swatchColor).frame(width: 8, height: 8)
                            Text(choice.displayName)
                        }
                        .tag(choice)
                    }
                }
            }

            Section("Thresholds") {
                ThresholdSlider(
                    title: "Warning at",
                    value: Binding(
                        get: { model.preferences.warningThreshold },
                        set: { value in model.update { $0.warningThreshold = value } }
                    ),
                    tint: .yellow
                )
                ThresholdSlider(
                    title: "Critical at",
                    value: Binding(
                        get: { model.preferences.criticalThreshold },
                        set: { value in model.update { $0.criticalThreshold = value } }
                    ),
                    tint: .red
                )
                Text("Where the gauges change color. Critical is always kept above warning.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Popover") {
                Toggle("Compact layout", isOn: Binding(
                    get: { model.preferences.compactPopover },
                    set: { on in model.update { $0.compactPopover = on } }
                ))
                Toggle("Show account details", isOn: Binding(
                    get: { model.preferences.showAccountSection },
                    set: { on in model.update { $0.showAccountSection = on } }
                ))
                Toggle("Show 14-day sparkline", isOn: Binding(
                    get: { model.preferences.showHistorySparkline },
                    set: { on in model.update { $0.showHistorySparkline = on } }
                ))
            }
        }
        .formStyle(.grouped)
    }
}

private struct ThresholdSlider: View {
    let title: String
    @Binding var value: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: 1...100, step: 1)
                .tint(tint)
        }
    }
}

// MARK: - Notifications

private struct NotificationSettingsTab: View {
    @EnvironmentObject private var model: UsageModel

    private let selectableThresholds = [50, 60, 70, 75, 80, 85, 90, 95]

    var body: some View {
        Form {
            Section {
                Toggle("Notify me about usage", isOn: Binding(
                    get: { model.preferences.notificationsEnabled },
                    set: { on in model.update { $0.notificationsEnabled = on } }
                ))
                if model.preferences.notificationsEnabled,
                   model.notificationAuthorization == .denied {
                    Label(
                        "Notifications are turned off for ClaudeGauge in System Settings → Notifications.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Section("Alert me when usage passes") {
                ForEach(selectableThresholds, id: \.self) { threshold in
                    Toggle("\(threshold)%", isOn: Binding(
                        get: { model.preferences.notificationThresholds.contains(threshold) },
                        set: { on in
                            model.update { prefs in
                                if on {
                                    prefs.notificationThresholds.append(threshold)
                                } else {
                                    prefs.notificationThresholds.removeAll { $0 == threshold }
                                }
                            }
                        }
                    ))
                }
                .disabled(!model.preferences.notificationsEnabled)
            }

            Section {
                Toggle("Also tell me when a limit resets", isOn: Binding(
                    get: { model.preferences.notifyOnReset },
                    set: { on in model.update { $0.notifyOnReset = on } }
                ))
                .disabled(!model.preferences.notificationsEnabled)

                Text("Each threshold fires once when you cross it, and re-arms after the window rolls over — so a long session at 90% won't notify you every few minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Providers

private struct ProvidersSettingsTab: View {
    @EnvironmentObject private var model: UsageModel

    var body: some View {
        Form {
            Section("Claude") {
                LabeledContent("Status") {
                    Text(model.snapshot.hasData ? "Connected" : "Not configured")
                        .foregroundStyle(.secondary)
                }
                Text("Always on — Claude drives the menu bar reading.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Also track") {
                ForEach(UsageModel.availableExtraProviders, id: \.id) { provider in
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(provider.name, isOn: Binding(
                            get: { model.preferences.enabledExtraProviderIDs.contains(provider.id) },
                            set: { on in
                                model.update { prefs in
                                    if on {
                                        prefs.enabledExtraProviderIDs.append(provider.id)
                                    } else {
                                        prefs.enabledExtraProviderIDs.removeAll { $0 == provider.id }
                                    }
                                }
                            }
                        ))
                        Text(provider.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let error = model.extraErrors[provider.id],
                           model.preferences.enabledExtraProviderIDs.contains(provider.id) {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            Section {
                Text("Want Gemini CLI or Copilot here? Those write their quota data in formats we haven't been able to verify first-hand yet — if you use one, an issue with a sample of its local files is the fastest way to get it supported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutTab: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("ClaudeGauge").font(.title2.weight(.semibold))
            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("An unofficial, independent project. Not affiliated with, endorsed by, or a product of Anthropic.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/Bajnok11/ClaudeGauge")!)
                Link("Report an issue", destination: URL(string: "https://github.com/Bajnok11/ClaudeGauge/issues")!)
            }
            .font(.caption)

            Spacer()

            Text("Your usage data never leaves this Mac except for the direct requests ClaudeGauge makes to Anthropic's own API.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
