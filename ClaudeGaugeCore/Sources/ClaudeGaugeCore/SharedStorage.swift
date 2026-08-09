import Foundation

/// The one-way handoff between the menu bar app (writer) and the widget
/// extension (reader). The app fetches from Anthropic and calls `write`,
/// then tells WidgetKit to reload; the widget's `TimelineProvider` only
/// ever calls `read` — it never touches the network itself, which keeps it
/// within WidgetKit's tight background execution budget and means a widget
/// can never disagree with the menu bar about what's "live".
///
/// Preferences ride the same channel so the widget renders with the user's
/// chosen thresholds and accent without either target having to duplicate
/// defaults or key names.
/// `@unchecked Sendable` rather than plain `Sendable`: the only stored
/// property is a `UserDefaults`, which Apple documents as thread-safe but
/// hasn't annotated as `Sendable`. Declaring plain conformance compiles
/// today with a warning that the Swift 6 language mode turns into an
/// error — so this states the guarantee explicitly instead of leaving a
/// build break waiting on the next toolchain.
public struct SharedStorage: @unchecked Sendable {
    public static let appGroupIdentifier = "group.dev.claudegauge.shared"
    private static let snapshotKey = "usageSnapshot"
    private static let refreshIntervalKey = "refreshIntervalSeconds"
    private static let preferencesKey = "preferences"

    private let defaults: UserDefaults?

    public init(appGroupIdentifier: String = SharedStorage.appGroupIdentifier) {
        self.defaults = UserDefaults(suiteName: appGroupIdentifier)
    }

    // MARK: - Snapshot

    public func write(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder.claudeGauge.encode(snapshot) else { return }
        defaults?.set(data, forKey: Self.snapshotKey)
    }

    public func read() -> UsageSnapshot? {
        guard let data = defaults?.data(forKey: Self.snapshotKey) else { return nil }
        return try? JSONDecoder.claudeGauge.decode(UsageSnapshot.self, from: data)
    }

    // MARK: - Preferences

    public func writePreferences(_ preferences: Preferences) {
        guard let data = try? JSONEncoder.claudeGauge.encode(preferences.normalized()) else { return }
        defaults?.set(data, forKey: Self.preferencesKey)
    }

    /// Never returns nil: a widget with no stored preferences yet should
    /// render with defaults rather than refuse to draw.
    public func readPreferences() -> Preferences {
        guard
            let data = defaults?.data(forKey: Self.preferencesKey),
            let decoded = try? JSONDecoder.claudeGauge.decode(Preferences.self, from: data)
        else {
            return .default
        }
        return decoded.normalized()
    }

    // MARK: - Refresh cadence

    /// So the widget's `TimelineProvider` can schedule its next entry in
    /// step with however often the app is actually refreshing, instead of
    /// guessing at a fixed cadence.
    public func writeRefreshInterval(_ seconds: TimeInterval) {
        defaults?.set(seconds, forKey: Self.refreshIntervalKey)
    }

    public func readRefreshInterval() -> TimeInterval? {
        guard let defaults, defaults.object(forKey: Self.refreshIntervalKey) != nil else { return nil }
        let value = defaults.double(forKey: Self.refreshIntervalKey)
        return value > 0 ? value : nil
    }
}

extension JSONEncoder {
    static let claudeGauge: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let claudeGauge: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
