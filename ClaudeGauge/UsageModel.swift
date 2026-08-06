import Foundation
import WidgetKit
import ServiceManagement
import ClaudeGaugeCore

/// The app's single source of truth: owns the poll loop, talks to
/// `ClaudeRateLimitProvider`, and is the only thing that ever writes to
/// `SharedStorage` (the widget only reads). Every UI-facing mutation goes
/// through an explicit method rather than a `didSet` observer, so settings
/// changes never fire side effects during `init`.
@MainActor
final class UsageModel: ObservableObject {
    static let availableIntervalsMinutes = [1, 5, 10, 15, 30]
    private static let refreshIntervalDefaultsKey = "refreshIntervalMinutes"

    @Published private(set) var snapshot: UsageSnapshot
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastErrorMessage: String?
    @Published var apiKey: String
    @Published private(set) var refreshIntervalMinutes: Int
    @Published private(set) var launchAtLogin: Bool

    private let provider: ClaudeRateLimitProvider
    private let storage = SharedStorage()
    private let keychain = KeychainStore()
    private var pollTask: Task<Void, Never>?

    init() {
        apiKey = keychain.read() ?? ""

        let savedInterval = UserDefaults.standard.integer(forKey: Self.refreshIntervalDefaultsKey)
        refreshIntervalMinutes = Self.availableIntervalsMinutes.contains(savedInterval) ? savedInterval : 5

        launchAtLogin = SMAppService.mainApp.status == .enabled
        snapshot = storage.read() ?? .empty

        let keychainRef = keychain
        provider = ClaudeRateLimitProvider(apiKeyProvider: { keychainRef.read() })

        storage.writeRefreshInterval(TimeInterval(refreshIntervalMinutes * 60))
        startPolling()
    }

    func refreshNow() {
        startPolling(immediate: true)
    }

    func saveAPIKey() {
        keychain.save(apiKey)
        refreshNow()
    }

    func updateRefreshInterval(_ minutes: Int) {
        guard Self.availableIntervalsMinutes.contains(minutes) else { return }
        refreshIntervalMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: Self.refreshIntervalDefaultsKey)
        storage.writeRefreshInterval(TimeInterval(minutes * 60))
        startPolling(immediate: false)
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

    private func startPolling(immediate: Bool = true) {
        pollTask?.cancel()
        let intervalSeconds = Double(refreshIntervalMinutes) * 60
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
            let result = try await provider.fetchSnapshot()
            snapshot = result
            lastErrorMessage = nil
            storage.write(result)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
