import Foundation

/// Token totals for one calendar day, rolled up from local Claude Code
/// transcript logs. This is the "bonus" data source live-limit-only trackers
/// don't offer: a local history you can chart, with nothing ever leaving
/// the machine.
public struct DailyTokenUsage: Equatable, Sendable {
    public var date: Date
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheCreationTokens: Int

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }
}

/// Parses Claude Code's local `~/.claude/projects/**/*.jsonl` transcripts.
/// These are append-only, per-session logs Claude Code itself writes on
/// every turn — reading them is pure local file I/O, no network, no
/// credentials, and (deliberately) no cost estimate: token→USD pricing
/// changes across models and plans often enough that a hard-coded table
/// would silently drift wrong, which is exactly the "overstates usage"
/// complaint aimed at some competing trackers. Token counts are reported
/// as-is; cost estimation is tracked as a roadmap item once there's a
/// reliable pricing source to pull from.
public enum TranscriptLogParser {
    public static var defaultProjectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    public static func dailyUsage(
        under directory: URL = defaultProjectsDirectory,
        calendar: Calendar = .current
    ) -> [DailyTokenUsage] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var totals: [Date: DailyTokenUsage] = [:]

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                guard let entry = parseLine(String(line)) else { continue }
                let day = calendar.startOfDay(for: entry.timestamp)
                var bucket = totals[day] ?? DailyTokenUsage(
                    date: day, inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: 0
                )
                bucket.inputTokens += entry.inputTokens
                bucket.outputTokens += entry.outputTokens
                bucket.cacheReadTokens += entry.cacheReadTokens
                bucket.cacheCreationTokens += entry.cacheCreationTokens
                totals[day] = bucket
            }
        }

        return totals.values.sorted { $0.date < $1.date }
    }

    struct ParsedEntry: Equatable {
        let timestamp: Date
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
        let cacheCreationTokens: Int
    }

    /// `internal` (not `private`) so unit tests can feed hand-written JSONL
    /// lines straight in, without touching disk.
    static func parseLine(_ line: String) -> ParsedEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        guard
            let timestampString = json["timestamp"] as? String,
            let timestamp = parseTimestamp(timestampString)
        else {
            return nil
        }

        guard
            let message = json["message"] as? [String: Any],
            let usage = message["usage"] as? [String: Any]
        else {
            return nil
        }

        return ParsedEntry(
            timestamp: timestamp,
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
            cacheCreationTokens: usage["cache_creation_input_tokens"] as? Int ?? 0
        )
    }

    private static func parseTimestamp(_ string: String) -> Date? {
        ISO8601DateFormatter.withFractionalSeconds.date(from: string)
            ?? ISO8601DateFormatter.standard.date(from: string)
    }
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
