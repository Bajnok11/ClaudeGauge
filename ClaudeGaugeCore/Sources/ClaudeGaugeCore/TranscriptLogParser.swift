import Foundation

/// Token totals for one calendar day, rolled up from local Claude Code
/// transcript logs. This is the "bonus" data source live-limit-only trackers
/// don't offer: a local history you can chart, with nothing ever leaving
/// the machine.
public struct DailyTokenUsage: Equatable, Sendable, Identifiable {
    public var date: Date
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheCreationTokens: Int

    public var id: Date { date }

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }

    public init(
        date: Date,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheCreationTokens: Int = 0
    ) {
        self.date = date
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
    }
}

/// Token totals for one project directory. Claude Code names each project
/// folder after the working directory it was launched in, path separators
/// replaced with dashes (`-Users-you-code-myapp`), so the readable name has
/// to be reconstructed.
public struct ProjectTokenUsage: Equatable, Sendable, Identifiable {
    /// The on-disk folder name, e.g. `-Users-you-code-myapp`.
    public var directoryName: String
    /// Best-effort human name, e.g. `myapp`.
    public var displayName: String
    public var totalTokens: Int
    public var sessionCount: Int
    public var lastUsed: Date

    public var id: String { directoryName }

    public init(
        directoryName: String,
        displayName: String,
        totalTokens: Int,
        sessionCount: Int,
        lastUsed: Date
    ) {
        self.directoryName = directoryName
        self.displayName = displayName
        self.totalTokens = totalTokens
        self.sessionCount = sessionCount
        self.lastUsed = lastUsed
    }
}

/// Everything the parser found in one pass. Bundled because walking the
/// transcript tree is the expensive part (potentially thousands of JSONL
/// lines) — callers that want both daily and per-project views shouldn't
/// pay for it twice.
public struct TranscriptUsageReport: Equatable, Sendable {
    public var daily: [DailyTokenUsage]
    public var projects: [ProjectTokenUsage]

    public init(daily: [DailyTokenUsage] = [], projects: [ProjectTokenUsage] = []) {
        self.daily = daily
        self.projects = projects
    }

    public var isEmpty: Bool { daily.isEmpty && projects.isEmpty }

    public var totalTokens: Int { daily.reduce(0) { $0 + $1.totalTokens } }

    /// Daily totals padded so every day in the window has an entry, which
    /// keeps charts from drawing a misleading straight line across days
    /// where nothing happened.
    public func dailyPadded(days: Int, calendar: Calendar = .current, now: Date = Date()) -> [DailyTokenUsage] {
        let today = calendar.startOfDay(for: now)
        let byDay = Dictionary(uniqueKeysWithValues: daily.map { (calendar.startOfDay(for: $0.date), $0) })
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return byDay[day] ?? DailyTokenUsage(date: day)
        }
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

    /// One pass over the transcript tree producing both rollups.
    ///
    /// - Parameter sinceDays: ignore entries older than this many days.
    ///   Transcript directories grow without bound, and the UI only ever
    ///   charts a recent window — parsing years of history to throw it away
    ///   is the difference between an instant and a multi-second refresh.
    public static func report(
        under directory: URL = defaultProjectsDirectory,
        sinceDays: Int? = 90,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> TranscriptUsageReport {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return TranscriptUsageReport()
        }

        let cutoff: Date? = sinceDays.flatMap {
            calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: now))
        }

        var dailyTotals: [Date: DailyTokenUsage] = [:]
        var projectTotals: [String: ProjectTokenUsage] = [:]

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let projectDirectory = projectDirectoryName(for: fileURL, under: directory)
            var fileTokens = 0
            var fileLatest: Date?

            for line in text.split(separator: "\n") {
                guard let entry = parseLine(String(line)) else { continue }
                if let cutoff, entry.timestamp < cutoff { continue }

                let day = calendar.startOfDay(for: entry.timestamp)
                var bucket = dailyTotals[day] ?? DailyTokenUsage(date: day)
                bucket.inputTokens += entry.inputTokens
                bucket.outputTokens += entry.outputTokens
                bucket.cacheReadTokens += entry.cacheReadTokens
                bucket.cacheCreationTokens += entry.cacheCreationTokens
                dailyTotals[day] = bucket

                fileTokens += entry.totalTokens
                if fileLatest == nil || entry.timestamp > fileLatest! {
                    fileLatest = entry.timestamp
                }
            }

            guard let projectDirectory, fileTokens > 0, let fileLatest else { continue }
            var project = projectTotals[projectDirectory] ?? ProjectTokenUsage(
                directoryName: projectDirectory,
                displayName: displayName(forProjectDirectory: projectDirectory),
                totalTokens: 0,
                sessionCount: 0,
                lastUsed: fileLatest
            )
            project.totalTokens += fileTokens
            // One .jsonl file is one Claude Code session.
            project.sessionCount += 1
            project.lastUsed = max(project.lastUsed, fileLatest)
            projectTotals[projectDirectory] = project
        }

        return TranscriptUsageReport(
            daily: dailyTotals.values.sorted { $0.date < $1.date },
            projects: projectTotals.values.sorted { $0.totalTokens > $1.totalTokens }
        )
    }

    /// Kept for source compatibility with callers that only want the daily
    /// series.
    public static func dailyUsage(
        under directory: URL = defaultProjectsDirectory,
        calendar: Calendar = .current
    ) -> [DailyTokenUsage] {
        report(under: directory, sinceDays: nil, calendar: calendar).daily
    }

    /// The immediate child of the projects directory that a transcript sits
    /// under. Returns nil for a file directly in the root (no project to
    /// attribute it to).
    static func projectDirectoryName(for fileURL: URL, under root: URL) -> String? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count + 1,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents else {
            return nil
        }
        return fileComponents[rootComponents.count]
    }

    /// `-Users-you-code-my-app` → `my-app`.
    ///
    /// Claude Code flattens the working directory path into the folder name
    /// by replacing `/` with `-`, which is lossy: a real dash in a directory
    /// name is indistinguishable from a path separator. Taking everything
    /// after the last path-ish segment would mangle `my-app` into `app`, so
    /// this instead strips the known `-Users-<username>-` prefix and keeps
    /// the remainder's last component — right for the common case, and it
    /// degrades to showing more of the path rather than less when it can't
    /// tell.
    static func displayName(forProjectDirectory name: String) -> String {
        var working = name
        if working.hasPrefix("-") { working.removeFirst() }

        let components = working.split(separator: "-", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { return name }

        // Drop a leading Users/<username> pair when present.
        var remainder = components
        if remainder.first?.lowercased() == "users", remainder.count > 2 {
            remainder.removeFirst(2)
        }
        guard let last = remainder.last else { return name }
        return last
    }

    struct ParsedEntry: Equatable {
        let timestamp: Date
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
        let cacheCreationTokens: Int

        var totalTokens: Int {
            inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
        }
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
