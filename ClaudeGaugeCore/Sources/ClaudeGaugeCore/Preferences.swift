import Foundation

/// Which credential ClaudeGauge should authenticate with.
///
/// This exists because "just prefer the Claude Code login" — the original
/// behavior — silently ignored a manually-entered API key for anyone who
/// also had the CLI logged in, with no way to tell or override. Making the
/// choice explicit means a user who deliberately pastes an API key gets
/// that key used, and the UI can always say which one is actually live.
public enum CredentialSource: String, Codable, CaseIterable, Sendable {
    /// Claude Code login if present, otherwise the saved API key.
    case automatic
    /// Only the Claude Code CLI login; error out rather than silently
    /// falling back to an API key.
    case claudeCodeOnly
    /// Only the manually-entered API key; ignore the CLI login entirely.
    case apiKeyOnly

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .claudeCodeOnly: return "Claude Code login"
        case .apiKeyOnly: return "API key"
        }
    }
}

/// What the menu bar glyph shows.
public enum MenuBarStyle: String, Codable, CaseIterable, Sendable {
    case iconOnly
    case percentOnly
    case iconAndPercent
    case iconAndBar

    public var displayName: String {
        switch self {
        case .iconOnly: return "Icon only"
        case .percentOnly: return "Percentage only"
        case .iconAndPercent: return "Icon + percentage"
        case .iconAndBar: return "Icon + bar"
        }
    }
}

/// Which number the menu bar shows when there are two to choose from.
public enum MenuBarMetric: String, Codable, CaseIterable, Sendable {
    case highest
    case session
    case weekly

    public var displayName: String {
        switch self {
        case .highest: return "Whichever is higher"
        case .session: return "Session / Tokens"
        case .weekly: return "Weekly / Requests"
        }
    }

    /// Resolves against a snapshot. `.highest` deliberately picks the more
    /// alarming of the two — the menu bar is a glanceable warning surface,
    /// so under-reporting is worse than over-reporting.
    public func value(from snapshot: UsageSnapshot) -> Double {
        switch self {
        case .highest: return max(snapshot.sessionPercent, snapshot.weeklyPercent)
        case .session: return snapshot.sessionPercent
        case .weekly: return snapshot.weeklyPercent
        }
    }

    public func label(from snapshot: UsageSnapshot) -> String {
        switch self {
        case .highest:
            return snapshot.sessionPercent >= snapshot.weeklyPercent
                ? snapshot.primaryLabel : snapshot.secondaryLabel
        case .session: return snapshot.primaryLabel
        case .weekly: return snapshot.secondaryLabel
        }
    }
}

/// A named accent choice. Stored as a string rather than a `Color` because
/// `ClaudeGaugeCore` is deliberately SwiftUI-free (see ARCHITECTURE.md §1) —
/// the UI layer maps these to actual colors.
public enum AccentChoice: String, Codable, CaseIterable, Sendable {
    case status
    case blue
    case purple
    case pink
    case orange
    case green
    case graphite

    public var displayName: String {
        switch self {
        case .status: return "Status (green → red)"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .orange: return "Orange"
        case .green: return "Green"
        case .graphite: return "Graphite"
        }
    }
}

/// Everything the user can configure. One `Codable` struct rather than a
/// scatter of `UserDefaults` keys so it round-trips through the App Group in
/// a single blob — the widget extension reads the exact same preferences the
/// app wrote, without duplicating key names across two targets.
public struct Preferences: Codable, Equatable, Sendable {
    // MARK: Credentials
    public var credentialSource: CredentialSource

    // MARK: Thresholds (percent, 0...100)
    public var warningThreshold: Double
    public var criticalThreshold: Double

    // MARK: Menu bar
    public var menuBarStyle: MenuBarStyle
    public var menuBarMetric: MenuBarMetric
    /// Off by default: Apple's HIG wants menu bar glyphs monochrome so they
    /// match the rest of the system. Opt-in for people who value the
    /// at-a-glance color more than consistency.
    public var menuBarColored: Bool

    // MARK: Popover layout
    public var showAccountSection: Bool
    public var showHistorySparkline: Bool
    public var compactPopover: Bool

    // MARK: Appearance
    public var accent: AccentChoice

    // MARK: Notifications
    public var notificationsEnabled: Bool
    /// Percent thresholds that fire a notification when first crossed.
    public var notificationThresholds: [Int]
    public var notifyOnReset: Bool

    // MARK: Refresh
    public var refreshIntervalMinutes: Int

    // MARK: Providers
    /// Extra providers to show alongside Claude. Claude is always the
    /// primary (it's what drives the menu bar glyph); these render as
    /// additional rows in the popover.
    public var enabledExtraProviderIDs: [String]

    public static let availableIntervalsMinutes = [1, 5, 10, 15, 30, 60]

    public init(
        credentialSource: CredentialSource = .automatic,
        warningThreshold: Double = 60,
        criticalThreshold: Double = 85,
        menuBarStyle: MenuBarStyle = .iconAndPercent,
        menuBarMetric: MenuBarMetric = .highest,
        menuBarColored: Bool = false,
        showAccountSection: Bool = true,
        showHistorySparkline: Bool = true,
        compactPopover: Bool = false,
        accent: AccentChoice = .status,
        notificationsEnabled: Bool = false,
        notificationThresholds: [Int] = [80, 95],
        notifyOnReset: Bool = false,
        refreshIntervalMinutes: Int = 5,
        enabledExtraProviderIDs: [String] = []
    ) {
        self.credentialSource = credentialSource
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
        self.menuBarStyle = menuBarStyle
        self.menuBarMetric = menuBarMetric
        self.menuBarColored = menuBarColored
        self.showAccountSection = showAccountSection
        self.showHistorySparkline = showHistorySparkline
        self.compactPopover = compactPopover
        self.accent = accent
        self.notificationsEnabled = notificationsEnabled
        self.notificationThresholds = notificationThresholds
        self.notifyOnReset = notifyOnReset
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.enabledExtraProviderIDs = enabledExtraProviderIDs
    }

    // Preferences persist across app versions in the App Group container, so
    // a blob written by an older build (missing keys added since) must decode
    // to defaults rather than throwing and silently resetting everything.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences.default
        credentialSource = try c.decodeIfPresent(CredentialSource.self, forKey: .credentialSource) ?? d.credentialSource
        warningThreshold = try c.decodeIfPresent(Double.self, forKey: .warningThreshold) ?? d.warningThreshold
        criticalThreshold = try c.decodeIfPresent(Double.self, forKey: .criticalThreshold) ?? d.criticalThreshold
        menuBarStyle = try c.decodeIfPresent(MenuBarStyle.self, forKey: .menuBarStyle) ?? d.menuBarStyle
        menuBarMetric = try c.decodeIfPresent(MenuBarMetric.self, forKey: .menuBarMetric) ?? d.menuBarMetric
        menuBarColored = try c.decodeIfPresent(Bool.self, forKey: .menuBarColored) ?? d.menuBarColored
        showAccountSection = try c.decodeIfPresent(Bool.self, forKey: .showAccountSection) ?? d.showAccountSection
        showHistorySparkline = try c.decodeIfPresent(Bool.self, forKey: .showHistorySparkline) ?? d.showHistorySparkline
        compactPopover = try c.decodeIfPresent(Bool.self, forKey: .compactPopover) ?? d.compactPopover
        accent = try c.decodeIfPresent(AccentChoice.self, forKey: .accent) ?? d.accent
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? d.notificationsEnabled
        notificationThresholds = try c.decodeIfPresent([Int].self, forKey: .notificationThresholds) ?? d.notificationThresholds
        notifyOnReset = try c.decodeIfPresent(Bool.self, forKey: .notifyOnReset) ?? d.notifyOnReset
        refreshIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .refreshIntervalMinutes) ?? d.refreshIntervalMinutes
        enabledExtraProviderIDs = try c.decodeIfPresent([String].self, forKey: .enabledExtraProviderIDs) ?? d.enabledExtraProviderIDs
    }

    public static let `default` = Preferences()

    /// Clamps user-entered values into a coherent state. Called on write so
    /// a hand-edited plist (or a future settings bug) can't produce e.g. a
    /// critical threshold below the warning one, which would make the
    /// status color jump backwards as usage climbs.
    public func normalized() -> Preferences {
        var copy = self
        copy.warningThreshold = min(max(warningThreshold, 1), 99)
        copy.criticalThreshold = min(max(criticalThreshold, copy.warningThreshold + 1), 100)
        copy.notificationThresholds = Array(Set(notificationThresholds.filter { $0 > 0 && $0 <= 100 })).sorted()
        if !Self.availableIntervalsMinutes.contains(copy.refreshIntervalMinutes) {
            copy.refreshIntervalMinutes = Preferences.default.refreshIntervalMinutes
        }
        return copy
    }

    /// The status thresholds as `UsageStatus` expects them.
    public var statusThresholds: UsageStatus.Thresholds {
        UsageStatus.Thresholds(warning: warningThreshold, critical: criticalThreshold)
    }
}
