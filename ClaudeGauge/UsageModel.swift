import Foundation
import SwiftUI
import WidgetKit
import ServiceManagement
// `@preconcurrency` because UserNotifications hasn't been audited for
// Sendable: `UNUserNotificationCenter.notificationSettings()` returns a
// non-Sendable `UNNotificationSettings`, which Swift 6 rejects when it
// crosses an isolation boundary. Only `authorizationStatus` (a plain enum)
// is ever read from it here, so nothing non-Sendable actually escapes —
// this downgrades the diagnostic rather than papering over a real race.
//
// Worth knowing: Xcode 26 accepts this code without the attribute while
// the Xcode 16 toolchain on CI does not, so building green locally is not
// evidence it builds on someone else's machine.
@preconcurrency import UserNotifications
import ClaudeGaugeCore

/// The app's single source of truth: owns the poll loop, talks to the
/// providers, and is the only thing that ever writes to `SharedStorage`
/// (the widget only reads). Every UI-facing mutation goes through an
/// explicit method rather than a `didSet` observer, so settings changes
/// never fire side effects during `init`.
@MainActor
final class UsageModel: ObservableObject {
    // MARK: Published state

    @Published private(set) var snapshot: UsageSnapshot
    /// Extra providers the user turned on (Codex today), keyed by provider ID.
    @Published private(set) var extraSnapshots: [String: UsageSnapshot] = [:]
    @Published private(set) var extraErrors: [String: String] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var preferences: Preferences
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var history = TranscriptUsageReport()
    @Published private(set) var isLoadingHistory = false
    @Published private(set) var notificationAuthorization: UNAuthorizationStatus = .notDetermined

    /// Bound directly by the API-key field; only committed to the Keychain
    /// when the user hits Save.
    @Published var apiKeyDraft: String

    // MARK: Collaborators

    private let storage = SharedStorage()
    private let keychain = KeychainStore()
    private var claudeProvider: ClaudeRateLimitProvider!
    private let codexProvider = CodexQuotaProvider()
    private var notificationPolicy = NotificationPolicy()
    private var pollTask: Task<Void, Never>?
    /// True for the fixed-data model used by the screenshot pipeline. Guards
    /// every path that would otherwise reach real disk, Keychain, or network
    /// state — including `loadHistory()`, which views call from `.task` and
    /// which would otherwise replace the sample history with the machine's
    /// actual project names.
    private let isSample: Bool

    /// Providers the user can switch on beyond Claude.
    static let availableExtraProviders: [(id: String, name: String, detail: String)] = [
        ("codex", "Codex", "Reads OpenAI Codex CLI's own local session logs — no API key, no network request.")
    ]

    /// Builds a model populated with fixed sample data and **no** polling,
    /// keychain access, or network calls. Used by `--render-screenshots`
    /// (see `ScreenshotRenderer`) so the images in the README come from the
    /// real views rather than mock-ups, without depending on whatever the
    /// build machine's account happens to look like.
    static func sample(preferences: Preferences = .default) -> UsageModel {
        let model = UsageModel(sampleWith: preferences)
        return model
    }

    /// The model the app actually launches with.
    ///
    /// Screenshot runs get the sample model rather than the live one. That's
    /// not cosmetic: a real run would put the machine's own project names,
    /// token counts, and a populated API-key field into images destined for
    /// a public README — so anyone regenerating the screenshots would
    /// publish their own local data. Sample data also makes the images
    /// deterministic, so they don't churn in git on every regeneration.
    static func makeForLaunch() -> UsageModel {
        guard isScreenshotLaunch else { return UsageModel() }
        var showcase = Preferences.default
        showcase.enabledExtraProviderIDs = ["codex"]
        return .sample(preferences: showcase)
    }

    static var isScreenshotLaunch: Bool {
        let arguments = CommandLine.arguments
        return arguments.contains(AppDelegate.openWindowsArgument)
            || arguments.contains(ScreenshotRenderer.launchArgument)
    }

    private init(sampleWith preferences: Preferences) {
        isSample = true
        self.preferences = preferences
        apiKeyDraft = ""
        launchAtLogin = true
        snapshot = UsageSnapshot(
            sessionPercent: 68,
            weeklyPercent: 41,
            sessionResetMinutes: 97,
            weeklyResetMinutes: 3_180,
            fetchedAt: Date(),
            source: .claudeCodeOAuth,
            account: AccountInfo(
                subscriptionType: "max",
                rateLimitTier: "default_claude_max_20x",
                expiresAt: Date().addingTimeInterval(60 * 60 * 24 * 30),
                scopes: ["user:inference"]
            )
        )
        extraSnapshots = [
            "codex": UsageSnapshot(
                sessionPercent: 24,
                weeklyPercent: 57,
                sessionResetMinutes: 42,
                weeklyResetMinutes: 6_000,
                fetchedAt: Date().addingTimeInterval(-3_600),
                source: .claudeCodeOAuth,
                account: AccountInfo(subscriptionType: "plus"),
                providerID: "codex",
                labelOverrides: .init(primary: "5-hour", secondary: "Weekly")
            )
        ]
        history = TranscriptUsageReport(
            daily: Self.sampleDaily(),
            projects: [
                ProjectTokenUsage(directoryName: "-Users-you-code-claudegauge", displayName: "claudegauge",
                                  totalTokens: 4_812_000, sessionCount: 37, lastUsed: Date()),
                ProjectTokenUsage(directoryName: "-Users-you-code-api-server", displayName: "api-server",
                                  totalTokens: 2_140_500, sessionCount: 19,
                                  lastUsed: Date().addingTimeInterval(-86_400)),
                ProjectTokenUsage(directoryName: "-Users-you-code-website", displayName: "website",
                                  totalTokens: 903_200, sessionCount: 11,
                                  lastUsed: Date().addingTimeInterval(-3 * 86_400))
            ]
        )
        claudeProvider = nil
    }

    /// Adjusts the sample reading, for animating the demo GIF across a
    /// range of values. No-op on a live model — this must never be a way to
    /// put made-up numbers in front of a real user.
    func overrideSampleUsage(session: Double, weekly: Double) {
        guard isSample else { return }
        snapshot.sessionPercent = session
        snapshot.weeklyPercent = weekly
    }

    private static func sampleDaily() -> [DailyTokenUsage] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // A fixed, plausible-looking series — deterministic so regenerated
        // screenshots don't churn in git for no reason.
        let totals = [
            120, 340, 90, 610, 480, 220, 55, 700, 830, 410,
            260, 950, 620, 380, 140, 720, 540, 300, 880, 460,
            210, 640, 990, 350, 180, 770, 520, 290, 860, 430
        ]
        return totals.enumerated().compactMap { index, value in
            guard let date = calendar.date(byAdding: .day, value: -(totals.count - 1 - index), to: today) else {
                return nil
            }
            return DailyTokenUsage(
                date: date,
                inputTokens: value * 90,
                outputTokens: value * 30,
                cacheReadTokens: value * 620,
                cacheCreationTokens: value * 110
            )
        }
    }

    init() {
        isSample = false
        let loadedPreferences = storage.readPreferences()
        preferences = loadedPreferences
        apiKeyDraft = keychain.read() ?? ""
        launchAtLogin = SMAppService.mainApp.status == .enabled
        snapshot = storage.read() ?? .empty

        let keychainRef = keychain
        let storageRef = storage
        claudeProvider = ClaudeRateLimitProvider(
            apiKeyProvider: { keychainRef.read() },
            // Read through shared storage rather than capturing `self`:
            // the provider is used from a background task, and this keeps a
            // settings change effective on the very next poll without
            // rebuilding the provider or touching the main actor.
            credentialSourceProvider: { storageRef.readPreferences().credentialSource }
        )

        // Write preferences back out on launch, not just when the user
        // changes one: a fresh install has nothing in the App Group, so the
        // widget would render with library defaults that silently disagree
        // with what the app itself is using.
        storage.writePreferences(loadedPreferences)
        storage.writeRefreshInterval(TimeInterval(loadedPreferences.refreshIntervalMinutes * 60))
        refreshNotificationAuthorization()
        startPolling()
        loadHistory()
    }

    // MARK: - Refresh

    func refreshNow() {
        guard !isSample else { return }
        startPolling(immediate: true)
        loadHistory()
    }

    private func startPolling(immediate: Bool = true) {
        guard !isSample else { return }
        pollTask?.cancel()
        let intervalSeconds = Double(preferences.refreshIntervalMinutes) * 60
        pollTask = Task { [weak self] in
            guard let self else { return }
            if immediate {
                await self.fetch()
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(intervalSeconds))
                if Task.isCancelled { return }
                await self.fetch()
            }
        }
    }

    private func fetch() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result = try await claudeProvider.fetchSnapshot()
            snapshot = result
            lastErrorMessage = nil
            storage.write(result)
            WidgetCenter.shared.reloadAllTimelines()
            deliver(notificationPolicy.evaluate(snapshot: result, preferences: preferences))
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        await fetchExtraProviders()
    }

    private func fetchExtraProviders() async {
        let enabled = preferences.enabledExtraProviderIDs
        guard !enabled.isEmpty else {
            extraSnapshots = [:]
            extraErrors = [:]
            return
        }

        for id in enabled where id == codexProvider.id {
            do {
                extraSnapshots[id] = try await codexProvider.fetchSnapshot()
                extraErrors[id] = nil
            } catch {
                extraErrors[id] = error.localizedDescription
            }
        }

        // Drop anything the user just turned off so the popover doesn't keep
        // rendering a stale row.
        extraSnapshots = extraSnapshots.filter { enabled.contains($0.key) }
        extraErrors = extraErrors.filter { enabled.contains($0.key) }
    }

    // MARK: - History

    func loadHistory() {
        guard !isSample, !isLoadingHistory else { return }
        isLoadingHistory = true
        Task { [weak self] in
            // Parsing the transcript tree is disk-bound and can span
            // thousands of files, so it must not run on the main actor.
            let report = await Task.detached(priority: .utility) {
                TranscriptLogParser.report()
            }.value
            await MainActor.run {
                self?.history = report
                self?.isLoadingHistory = false
            }
        }
    }

    // MARK: - Preferences

    /// Single funnel for every settings change: normalizes, persists to the
    /// App Group (so the widget sees it), and reacts to the ones that need
    /// more than a redraw.
    func update(_ transform: (inout Preferences) -> Void) {
        var updated = preferences
        transform(&updated)
        let normalized = updated.normalized()
        guard normalized != preferences else { return }

        let intervalChanged = normalized.refreshIntervalMinutes != preferences.refreshIntervalMinutes
        let sourceChanged = normalized.credentialSource != preferences.credentialSource
        let providersChanged = normalized.enabledExtraProviderIDs != preferences.enabledExtraProviderIDs

        preferences = normalized
        storage.writePreferences(normalized)
        storage.writeRefreshInterval(TimeInterval(normalized.refreshIntervalMinutes * 60))
        WidgetCenter.shared.reloadAllTimelines()

        if normalized.notificationsEnabled {
            requestNotificationAuthorizationIfNeeded()
        }
        if intervalChanged {
            startPolling(immediate: false)
        }
        if sourceChanged || providersChanged {
            refreshNow()
        }
    }

    func saveAPIKey() {
        keychain.save(apiKeyDraft)
        refreshNow()
    }

    func clearAPIKey() {
        apiKeyDraft = ""
        keychain.save("")
        refreshNow()
    }

    var hasStoredAPIKey: Bool {
        !(keychain.read() ?? "").isEmpty
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !enabled, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
        } catch {
            lastErrorMessage = "Couldn't change Launch at Login: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Notifications

    private func refreshNotificationAuthorization() {
        Task { [weak self] in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run { self?.notificationAuthorization = settings.authorizationStatus }
        }
    }

    func requestNotificationAuthorizationIfNeeded() {
        Task { [weak self] in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else {
                await MainActor.run { self?.notificationAuthorization = settings.authorizationStatus }
                return
            }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            let updated = await center.notificationSettings()
            await MainActor.run { self?.notificationAuthorization = updated.authorizationStatus }
        }
    }

    private func deliver(_ alerts: [UsageAlert]) {
        guard !alerts.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            center.add(UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            ))
        }
    }

    // MARK: - Derived

    var statusThresholds: UsageStatus.Thresholds { preferences.statusThresholds }

    /// What the popover's header should say about where data is coming from.
    var credentialSummary: String {
        switch preferences.credentialSource {
        case .automatic:
            return snapshot.hasData ? snapshot.source.displayName : "Automatic"
        case .claudeCodeOnly:
            return "Claude Code login"
        case .apiKeyOnly:
            return "API key"
        }
    }
}
