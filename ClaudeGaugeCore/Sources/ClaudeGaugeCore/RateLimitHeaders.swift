import Foundation

/// Pure parsing of Anthropic's rate-limit response headers into usage
/// percentages. Kept free of networking so it's trivially unit-testable.
///
/// Anthropic reports two genuinely different shapes of rate-limit data
/// depending on how the request was authenticated, and this deliberately
/// supports both rather than assuming everyone is on a subscription:
///
/// 1. **Subscription (Claude Code OAuth token)** — a Pro/Max/Team plan's
///    rolling 5-hour session and 7-day weekly windows, reported as a
///    ready-made utilization ratio (0...1):
///      - `anthropic-ratelimit-unified-5h-utilization`
///      - `anthropic-ratelimit-unified-weekly-utilization`
///      - `anthropic-ratelimit-unified-5h-remaining` (seconds until reset)
///      - `anthropic-ratelimit-unified-weekly-remaining` (seconds until reset)
///
/// 2. **Pay-as-you-go Console API key** — a completely different product
///    with no 5-hour/weekly session concept at all; instead it reports
///    classic per-minute token/request limits as (limit, remaining) pairs,
///    which have to be turned into a percentage ourselves:
///      - `anthropic-ratelimit-tokens-limit` / `-remaining` / `-reset` (timestamp)
///      - `anthropic-ratelimit-requests-limit` / `-remaining` / `-reset` (timestamp)
///
/// A manually-entered API key that isn't tied to a subscription will only
/// ever produce headers of the second shape — treating it as the first
/// shape (as an earlier version of this file did) silently fails for every
/// pay-as-you-go user. `ParsedRateLimits.kind` tells the caller which shape
/// was actually found so the UI can label the two gauges correctly
/// ("Session"/"Weekly" vs. "Tokens"/"Requests") instead of mislabeling one
/// as the other.
///
/// Reading either of these back is not scraping or ToS-adjacent — they're
/// intentionally public response headers on an authenticated request the
/// user's own credentials are entitled to make; it's the same signal
/// Claude Code itself uses to warn about limits.
public enum RateLimitHeaders {
    public static func parse(_ headers: [String: String]) -> ParsedRateLimits? {
        let lower = Dictionary(
            headers.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )

        if let subscription = parseSubscription(lower) {
            return subscription
        }
        return parseClassicAPIKey(lower)
    }

    private static func parseSubscription(_ lower: [String: String]) -> ParsedRateLimits? {
        guard
            let sessionUtilString = lower["anthropic-ratelimit-unified-5h-utilization"],
            let sessionUtil = Double(sessionUtilString)
        else {
            return nil
        }

        let weeklyUtil = lower["anthropic-ratelimit-unified-weekly-utilization"].flatMap(Double.init) ?? 0

        func resetMinutes(_ key: String) -> Int? {
            guard let raw = lower[key], let seconds = Double(raw) else { return nil }
            return Int((seconds / 60).rounded())
        }

        return ParsedRateLimits(
            kind: .unifiedSubscription,
            sessionPercent: clampPercent(sessionUtil * 100),
            weeklyPercent: clampPercent(weeklyUtil * 100),
            sessionResetMinutes: resetMinutes("anthropic-ratelimit-unified-5h-remaining"),
            weeklyResetMinutes: resetMinutes("anthropic-ratelimit-unified-weekly-remaining")
        )
    }

    private static func parseClassicAPIKey(_ lower: [String: String]) -> ParsedRateLimits? {
        guard let tokensPercent = classicPercent(
            limitKey: "anthropic-ratelimit-tokens-limit",
            remainingKey: "anthropic-ratelimit-tokens-remaining",
            in: lower
        ) else {
            return nil
        }

        let requestsPercent = classicPercent(
            limitKey: "anthropic-ratelimit-requests-limit",
            remainingKey: "anthropic-ratelimit-requests-remaining",
            in: lower
        ) ?? 0

        return ParsedRateLimits(
            kind: .classicAPIKey,
            sessionPercent: tokensPercent,
            weeklyPercent: requestsPercent,
            sessionResetMinutes: resetMinutesFromTimestamp(lower["anthropic-ratelimit-tokens-reset"]),
            weeklyResetMinutes: resetMinutesFromTimestamp(lower["anthropic-ratelimit-requests-reset"])
        )
    }

    private static func classicPercent(limitKey: String, remainingKey: String, in lower: [String: String]) -> Double? {
        guard
            let limitString = lower[limitKey], let limit = Double(limitString), limit > 0,
            let remainingString = lower[remainingKey], let remaining = Double(remainingString)
        else {
            return nil
        }
        return clampPercent((limit - remaining) / limit * 100)
    }

    private static func resetMinutesFromTimestamp(_ raw: String?) -> Int? {
        guard
            let raw,
            let date = ISO8601DateFormatter.rateLimitReset.date(from: raw)
                ?? ISO8601DateFormatter.rateLimitResetNoFraction.date(from: raw)
        else {
            return nil
        }
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return nil }
        return Int((seconds / 60).rounded(.up))
    }

    private static func clampPercent(_ value: Double) -> Double {
        min(100, max(0, value.rounded()))
    }
}

public struct ParsedRateLimits: Equatable, Sendable {
    public var kind: UsageSnapshot.Kind
    public var sessionPercent: Double
    public var weeklyPercent: Double
    public var sessionResetMinutes: Int?
    public var weeklyResetMinutes: Int?
}

private extension ISO8601DateFormatter {
    static let rateLimitReset: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let rateLimitResetNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
