import Foundation

/// A point-in-time reading of a user's Claude usage, as reported by
/// Anthropic's own rate-limit headers. This is the single source of truth
/// that both the menu bar app and the widget extension render — the app
/// fetches it and writes it to shared storage; the widget only ever reads.
public struct UsageSnapshot: Codable, Equatable, Sendable {
    /// 0...100. Utilization of the rolling 5-hour session window.
    public var sessionPercent: Double
    /// 0...100. Utilization of the rolling 7-day (weekly) window.
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
    /// Set when the last refresh attempt failed; the snapshot above (if any)
    /// is then a stale last-known-good value, not necessarily the current one.
    public var lastError: String?

    public enum Source: String, Codable, Sendable {
        case claudeCodeOAuth
        case manualAPIKey
        case none
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
        lastError: String? = nil
    ) {
        self.sessionPercent = sessionPercent
        self.weeklyPercent = weeklyPercent
        self.sessionResetMinutes = sessionResetMinutes
        self.weeklyResetMinutes = weeklyResetMinutes
        self.fetchedAt = fetchedAt
        self.source = source
        self.kind = kind
        self.lastError = lastError
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

    /// Caption for `sessionPercent` — "Session" on a subscription, "Tokens"
    /// on a pay-as-you-go API key.
    public var primaryLabel: String {
        kind == .classicAPIKey ? "Tokens" : "Session"
    }

    /// Caption for `weeklyPercent` — "Weekly" on a subscription, "Requests"
    /// on a pay-as-you-go API key.
    public var secondaryLabel: String {
        kind == .classicAPIKey ? "Requests" : "Weekly"
    }

    /// Traffic-light status derived from the higher of the two percentages,
    /// used for the menu bar glyph and widget accent color.
    public var status: UsageStatus {
        UsageStatus(percent: max(sessionPercent, weeklyPercent))
    }
}

public enum UsageStatus: Sendable, Equatable {
    case ok
    case warning
    case critical

    public init(percent: Double) {
        switch percent {
        case ..<60: self = .ok
        case 60..<85: self = .warning
        default: self = .critical
        }
    }
}
