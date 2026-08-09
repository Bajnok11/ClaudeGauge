import XCTest
@testable import ClaudeGaugeCore

final class CodexQuotaProviderTests: XCTestCase {
    /// A real line shape captured from `~/.codex/sessions/.../rollout-*.jsonl`.
    private let realLine = """
    {"timestamp":"2026-07-14T09:04:26.838Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":23800,"output_tokens":179,"total_tokens":23979}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":36.0,"window_minutes":43200,"resets_at":1786610929},"secondary":null,"plan_type":"free"}}}
    """

    func testParsesRealCodexLine() throws {
        let snapshot = try XCTUnwrap(CodexQuotaProvider.parseRateLimitLine(realLine))

        XCTAssertEqual(snapshot.sessionPercent, 36)
        XCTAssertEqual(snapshot.providerID, "codex")
        XCTAssertEqual(snapshot.account.subscriptionType, "free")
        // 43200 minutes == 30 days, so the caption must read Monthly, not
        // Anthropic's "Session".
        XCTAssertEqual(snapshot.primaryLabel, "Monthly")
    }

    func testUsesLineTimestampNotNow() throws {
        let snapshot = try XCTUnwrap(CodexQuotaProvider.parseRateLimitLine(realLine))
        // The reading is from July 2026; reporting it as "just now" would
        // make stale Codex data look live.
        XCTAssertLessThan(snapshot.fetchedAt, Date().addingTimeInterval(-60))
    }

    func testParsesBothWindows() throws {
        let line = """
        {"timestamp":"2026-08-01T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":12.5,"window_minutes":300},"secondary":{"used_percent":48.0,"window_minutes":10080},"plan_type":"plus"}}}
        """
        let snapshot = try XCTUnwrap(CodexQuotaProvider.parseRateLimitLine(line))

        // Raw precision is preserved; rounding is a display concern.
        XCTAssertEqual(snapshot.sessionPercent, 12.5)
        XCTAssertEqual(snapshot.weeklyPercent, 48)
        XCTAssertEqual(snapshot.primaryLabel, "5-hour")
        XCTAssertEqual(snapshot.secondaryLabel, "Weekly")
    }

    func testIgnoresNonRateLimitLines() {
        XCTAssertNil(CodexQuotaProvider.parseRateLimitLine("{\"type\":\"agent_message\"}"))
        XCTAssertNil(CodexQuotaProvider.parseRateLimitLine(""))
        XCTAssertNil(CodexQuotaProvider.parseRateLimitLine("not json at all"))
    }

    func testWindowWithNoUsableDataIsIgnored() {
        let line = """
        {"timestamp":"2026-08-01T10:00:00.000Z","payload":{"rate_limits":{"primary":null,"secondary":null}}}
        """
        XCTAssertNil(CodexQuotaProvider.parseRateLimitLine(line))
    }

    func testWindowLabels() {
        func label(_ minutes: Int) -> String {
            CodexQuotaProvider.QuotaWindow(usedPercent: 0, windowMinutes: minutes, resetsAt: nil).label
        }
        XCTAssertEqual(label(300), "5-hour")
        XCTAssertEqual(label(1_440), "Daily")
        XCTAssertEqual(label(10_080), "Weekly")
        XCTAssertEqual(label(43_200), "Monthly")
        XCTAssertEqual(label(30), "30-min")
    }

    func testSupportsLegacyResetsInSeconds() throws {
        let line = """
        {"timestamp":"2026-08-01T10:00:00.000Z","payload":{"rate_limits":{"primary":{"used_percent":50.0,"window_minutes":300,"resets_in_seconds":1800}}}}
        """
        let snapshot = try XCTUnwrap(CodexQuotaProvider.parseRateLimitLine(line))
        XCTAssertNotNil(snapshot.sessionResetMinutes)
    }

    func testMissingSessionsDirectoryReportsNotInstalled() async {
        let provider = CodexQuotaProvider(
            sessionsDirectory: URL(fileURLWithPath: "/tmp/no-codex-\(UUID().uuidString)")
        )
        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("Expected notInstalled")
        } catch {
            XCTAssertEqual(error as? UsageProviderError, .notInstalled("Codex CLI"))
        }
    }
}
