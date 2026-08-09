import Foundation

/// Who the credentials belong to, as reported by the credential itself —
/// not by any extra network call. Claude Code's stored login already
/// carries the plan and rate-limit tier; surfacing it answers "which
/// account is this actually reading?", which is otherwise invisible and is
/// exactly the confusion that made a silently-ignored API key so hard to
/// notice.
public struct AccountInfo: Codable, Equatable, Sendable {
    /// e.g. "max", "pro", "team" — verbatim from the credential.
    public var subscriptionType: String?
    /// e.g. "default_claude_max_20x" — Anthropic's internal tier label.
    public var rateLimitTier: String?
    /// When the OAuth token itself expires (not a usage window reset).
    public var expiresAt: Date?
    /// OAuth scopes the token carries.
    public var scopes: [String]

    public init(
        subscriptionType: String? = nil,
        rateLimitTier: String? = nil,
        expiresAt: Date? = nil,
        scopes: [String] = []
    ) {
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
        self.expiresAt = expiresAt
        self.scopes = scopes
    }

    public var isEmpty: Bool {
        subscriptionType == nil && rateLimitTier == nil && expiresAt == nil && scopes.isEmpty
    }

    /// "Max" from "max", "Team" from "team" — Anthropic writes these
    /// lowercase, but they're product names in the UI.
    public var displayPlan: String? {
        guard let subscriptionType, !subscriptionType.isEmpty else { return nil }
        return subscriptionType.split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

/// A point-in-time reading of a user's Claude usage, as reported by
/// Anthropic's own rate-limit headers. This is the single source of truth
/// that both the menu bar app and the widget extension render — the app
/// fetches it and writes it to shared storage; the widget only ever reads.
public struct UsageSnapshot: Codable, Equatable, Sendable {
    /// 0...100. Utilization of the rolling 5-hour session window
    /// (or per-minute token limit on a pay-as-you-go key — see `kind`).
    public var sessionPercent: Double
    /// 0...100. Utilization of the rolling 7-day window
    /// (or per-minute request limit on a pay-as-you-go key).
    public var weeklyPercent: Double
    /// Minutes remaining until the session window resets. Nil if unknown.
    public var sessionResetMinutes: Int?
    /// Minutes remaining until the weekly window resets. Nil if unknown.
    public var weeklyResetMinutes: Int?
    /// When this snapshot was fetched from Anthropic.
    public var fetchedAt: Date
    /// Which credential path produced this snapshot.
    public var source: Source
    /// Which *shape* of rate-limit data this snapshot holds. A Claude Code
    /// login and a manually-entered API key report genuinely different
    /// things — see `RateLimitHeaders` — so the UI must not always caption
    /// the two numbers "Session" / "Weekly"; for `.classicAPIKey` they mean
    /// "Tokens" / "Requests" instead. Use `primaryLabel`/`secondaryLabel`
    /// rather than hardcoding a caption.
    public var kind: Kind
    /// Plan/tier details read straight off the credential, when available.
    public var account: AccountInfo
    /// Which provider produced this (`"claude"`, `"codex"`, …). Lets one
    /// storage slot serve several providers as they're added.
    public var providerID: String
    /// Overrides for the two gauge captions. Providers whose windows aren't
    /// "session/weekly" (Codex reports whatever window its plan uses —
    /// 5-hour, weekly, or monthly) set these rather than mislabeling their
    /// numbers with Anthropic's vocabulary.
    public var labelOverrides: LabelOverrides?
    /// Set when the last refresh attempt failed; the snapshot above (if any)
    /// is then a stale last-known-good value, not necessarily the current one.
    public var lastError: String?

    public struct LabelOverrides: Codable, Equatable, Sendable {
        public var primary: String
        public var secondary: String

        public init(primary: String, secondary: String) {
            self.primary = primary
            self.secondary = secondary
        }
    }

    public enum Source: String, Codable, Sendable {
        case claudeCodeOAuth
        case manualAPIKey
        case none

        public var displayName: String {
            switch self {
            case .claudeCodeOAuth: return "Claude Code login"
            case .manualAPIKey: return "API key"
            case .none: return "Not configured"
            }
        }
    }

    public enum Kind: String, Codable, Sendable {
        /// Rolling 5-hour / 7-day windows on a Claude Pro/Max/Team plan.
        case unifiedSubscription
        /// Per-minute token/request limits on a pay-as-you-go Console API key.
        case classicAPIKey
    }

    public init(
        sessionPercent: Double,
        weeklyPercent: Double,
        sessionResetMinutes: Int?,
        weeklyResetMinutes: Int?,
        fetchedAt: Date,
        source: Source,
        kind: Kind = .unifiedSubscription,
        account: AccountInfo = AccountInfo(),
        providerID: String = "claude",
        labelOverrides: LabelOverrides? = nil,
        lastError: String? = nil
    ) {
        self.sessionPercent = sessionPercent
        self.weeklyPercent = weeklyPercent
        self.sessionResetMinutes = sessionResetMinutes
        self.weeklyResetMinutes = weeklyResetMinutes
        self.fetchedAt = fetchedAt
        self.source = source
        self.kind = kind
        self.account = account
        self.providerID = providerID
        self.labelOverrides = labelOverrides
        self.lastError = lastError
    }

    // Snapshots persist across app versions in the App Group container, so a
    // v0.1 blob (which predates `account`/`providerID`) must still decode
    // rather than wiping the user's last-known-good reading on upgrade.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionPercent = try container.decode(Double.self, forKey: .sessionPercent)
        weeklyPercent = try container.decode(Double.self, forKey: .weeklyPercent)
        sessionResetMinutes = try container.decodeIfPresent(Int.self, forKey: .sessionResetMinutes)
        weeklyResetMinutes = try container.decodeIfPresent(Int.self, forKey: .weeklyResetMinutes)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        source = try container.decode(Source.self, forKey: .source)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .unifiedSubscription
        account = try container.decodeIfPresent(AccountInfo.self, forKey: .account) ?? AccountInfo()
        providerID = try container.decodeIfPresent(String.self, forKey: .providerID) ?? "claude"
        labelOverrides = try container.decodeIfPresent(LabelOverrides.self, forKey: .labelOverrides)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }

    /// A neutral placeholder shown before the first successful fetch.
    public static var empty: UsageSnapshot {
        UsageSnapshot(
            sessionPercent: 0,
            weeklyPercent: 0,
            sessionResetMinutes: nil,
            weeklyResetMinutes: nil,
            fetchedAt: .distantPast,
            source: .none
        )
    }

    public var hasData: Bool { source != .none && fetchedAt > .distantPast }

    /// Caption for `sessionPercent` — "Session" on a subscription, "Tokens"
    /// on a pay-as-you-go API key, or whatever a non-Anthropic provider
    /// supplied.
    public var primaryLabel: String {
        if let labelOverrides { return labelOverrides.primary }
        return kind == .classicAPIKey ? "Tokens" : "Session"
    }

    /// Caption for `weeklyPercent` — "Weekly" on a subscription, "Requests"
    /// on a pay-as-you-go API key, or whatever a non-Anthropic provider
    /// supplied.
    public var secondaryLabel: String {
        if let labelOverrides { return labelOverrides.secondary }
        return kind == .classicAPIKey ? "Requests" : "Weekly"
    }

    /// Traffic-light status derived from the higher of the two percentages,
    /// used for the menu bar glyph and widget accent color.
    public func status(thresholds: UsageStatus.Thresholds = .default) -> UsageStatus {
        UsageStatus(percent: max(sessionPercent, weeklyPercent), thresholds: thresholds)
    }

    /// Convenience for callers that haven't got user preferences to hand
    /// (previews, tests, the widget's placeholder entry).
    public var status: UsageStatus { status() }
}

public enum UsageStatus: Sendable, Equatable {
    case ok
    case warning
    case critical

    /// Where the color changes. User-configurable — some people want to be
    /// warned at 50%, others not until 90%.
    public struct Thresholds: Equatable, Sendable {
        public var warning: Double
        public var critical: Double

        public init(warning: Double = 60, critical: Double = 85) {
            self.warning = warning
            self.critical = critical
        }

        public static let `default` = Thresholds()
    }

    public init(percent: Double, thresholds: Thresholds = .default) {
        if percent >= thresholds.critical {
            self = .critical
        } else if percent >= thresholds.warning {
            self = .warning
        } else {
            self = .ok
        }
    }
}
