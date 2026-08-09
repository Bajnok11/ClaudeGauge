import Foundation

/// Reads OpenAI Codex CLI's quota straight off the rollout transcripts it
/// already writes to `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
///
/// Codex emits a `token_count` event after each turn whose payload carries a
/// `rate_limits` block — the same numbers the CLI shows you — so ClaudeGauge
/// can report Codex usage with **no network call, no API key, and no
/// credentials of any kind**. That's a stronger privacy position than the
/// Claude provider needs to take (which must make one authenticated request
/// because Anthropic only exposes utilization in response headers).
///
/// The trade-off is freshness: this data is only as current as the last time
/// Codex actually ran. `UsageSnapshot.fetchedAt` is therefore set to the
/// timestamp of the reading itself, not to "now" — so the UI's "updated 3
/// days ago" is honest rather than implying a live poll.
public struct CodexQuotaProvider: UsageProvider {
    public let id = "codex"
    public let displayName = "Codex"

    private let sessionsDirectory: URL

    public init(sessionsDirectory: URL = CodexQuotaProvider.defaultSessionsDirectory) {
        self.sessionsDirectory = sessionsDirectory
    }

    public static var defaultSessionsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        guard FileManager.default.fileExists(atPath: sessionsDirectory.path) else {
            throw UsageProviderError.notInstalled("Codex CLI")
        }
        guard let latest = Self.mostRecentRateLimits(in: sessionsDirectory) else {
            throw UsageProviderError.notInstalled("Codex CLI")
        }
        return latest
    }

    /// Walks the rollout tree newest-file-first and returns the last
    /// `rate_limits` block found.
    ///
    /// Newest-first matters: rollout files are named
    /// `rollout-<ISO8601>-<uuid>.jsonl`, so a lexicographic sort of the
    /// filenames is also a chronological sort, and stopping at the first
    /// file that yields a reading avoids parsing an entire history of
    /// sessions to answer "what's my quota right now".
    static func mostRecentRateLimits(in directory: URL) -> UsageSnapshot? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var rolloutFiles: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            rolloutFiles.append(url)
        }
        guard !rolloutFiles.isEmpty else { return nil }

        rolloutFiles.sort { $0.lastPathComponent > $1.lastPathComponent }

        for file in rolloutFiles {
            if let snapshot = lastRateLimitSnapshot(inFileAt: file) {
                return snapshot
            }
        }
        return nil
    }

    static func lastRateLimitSnapshot(inFileAt url: URL) -> UsageSnapshot? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // Scan backwards: the newest reading in a session is the last one,
        // and quota lines tend to cluster at the end of a long transcript.
        for line in text.split(separator: "\n").reversed() {
            if let snapshot = parseRateLimitLine(String(line)) {
                return snapshot
            }
        }
        return nil
    }

    /// `internal` so tests can drive it with hand-written JSONL and no disk.
    static func parseRateLimitLine(_ line: String) -> UsageSnapshot? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.contains("rate_limits"), let data = trimmed.data(using: .utf8) else {
            return nil
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let payload = json["payload"] as? [String: Any],
            let rateLimits = payload["rate_limits"] as? [String: Any]
        else {
            return nil
        }

        let primary = window(from: rateLimits["primary"] as? [String: Any])
        let secondary = window(from: rateLimits["secondary"] as? [String: Any])
        guard primary != nil || secondary != nil else { return nil }

        // The line's own timestamp is when Codex actually observed this
        // quota — using it (rather than Date()) keeps "last updated" honest
        // for a CLI that may not have run in days.
        let observedAt = (json["timestamp"] as? String).flatMap(parseTimestamp) ?? Date()

        let planType = rateLimits["plan_type"] as? String

        return UsageSnapshot(
            sessionPercent: primary?.usedPercent ?? 0,
            weeklyPercent: secondary?.usedPercent ?? 0,
            sessionResetMinutes: primary?.resetMinutes(from: observedAt),
            weeklyResetMinutes: secondary?.resetMinutes(from: observedAt),
            fetchedAt: observedAt,
            source: .claudeCodeOAuth,
            kind: .unifiedSubscription,
            account: AccountInfo(subscriptionType: planType),
            providerID: "codex",
            labelOverrides: UsageSnapshot.LabelOverrides(
                primary: primary?.label ?? "Primary",
                secondary: secondary?.label ?? "Secondary"
            )
        )
    }

    struct QuotaWindow: Equatable {
        var usedPercent: Double
        var windowMinutes: Int?
        var resetsAt: Date?

        /// Codex describes a window by its length in minutes; turning that
        /// into "5-hour"/"Weekly"/"Monthly" keeps the gauge caption
        /// meaningful across plans that use different windows.
        var label: String {
            guard let windowMinutes else { return "Usage" }
            switch windowMinutes {
            case ..<60: return "\(windowMinutes)-min"
            case 60..<1_440:
                let hours = windowMinutes / 60
                return "\(hours)-hour"
            case 1_440..<10_080:
                let days = windowMinutes / 1_440
                return days == 1 ? "Daily" : "\(days)-day"
            case 10_080..<43_200:
                let weeks = windowMinutes / 10_080
                return weeks == 1 ? "Weekly" : "\(weeks)-week"
            default:
                let months = max(1, windowMinutes / 43_200)
                return months == 1 ? "Monthly" : "\(months)-month"
            }
        }

        func resetMinutes(from reference: Date) -> Int? {
            guard let resetsAt else { return nil }
            let seconds = resetsAt.timeIntervalSince(reference)
            guard seconds > 0 else { return nil }
            return Int((seconds / 60).rounded(.up))
        }
    }

    static func window(from json: [String: Any]?) -> QuotaWindow? {
        guard let json, let usedPercent = json["used_percent"] as? Double else { return nil }
        let resetsAt: Date? = {
            // `resets_at` is a Unix timestamp in seconds. Older Codex builds
            // emitted `resets_in_seconds` (a duration) instead, so support
            // both rather than silently losing the countdown.
            if let epoch = json["resets_at"] as? Double, epoch > 0 {
                return Date(timeIntervalSince1970: epoch)
            }
            if let seconds = json["resets_in_seconds"] as? Double, seconds > 0 {
                return Date().addingTimeInterval(seconds)
            }
            return nil
        }()
        return QuotaWindow(
            usedPercent: min(max(usedPercent, 0), 100),
            windowMinutes: json["window_minutes"] as? Int,
            resetsAt: resetsAt
        )
    }

    private static func parseTimestamp(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
