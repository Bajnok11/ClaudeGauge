import XCTest
@testable import ClaudeGaugeCore

final class TranscriptLogParserTests: XCTestCase {
    func testParsesAssistantUsageLine() {
        let line = """
        {"timestamp":"2026-08-06T10:15:00.123Z","message":{"model":"claude-sonnet-5","usage":{"input_tokens":120,"output_tokens":340,"cache_read_input_tokens":50,"cache_creation_input_tokens":10}}}
        """
        let entry = TranscriptLogParser.parseLine(line)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.inputTokens, 120)
        XCTAssertEqual(entry?.outputTokens, 340)
        XCTAssertEqual(entry?.cacheReadTokens, 50)
        XCTAssertEqual(entry?.cacheCreationTokens, 10)
    }

    func testParsesTimestampWithoutFractionalSeconds() {
        let line = """
        {"timestamp":"2026-08-06T10:15:00Z","message":{"usage":{"input_tokens":1,"output_tokens":1}}}
        """
        XCTAssertNotNil(TranscriptLogParser.parseLine(line))
    }

    func testIgnoresLinesWithoutUsage() {
        let line = """
        {"timestamp":"2026-08-06T10:15:00Z","message":{"role":"user","content":"hi"}}
        """
        XCTAssertNil(TranscriptLogParser.parseLine(line))
    }

    func testIgnoresBlankAndMalformedLines() {
        XCTAssertNil(TranscriptLogParser.parseLine(""))
        XCTAssertNil(TranscriptLogParser.parseLine("   "))
        XCTAssertNil(TranscriptLogParser.parseLine("{not valid json"))
    }

    func testDailyUsageAggregatesAcrossFilesAndSkipsBadLines() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeGaugeTests-\(UUID().uuidString)", isDirectory: true)
        let projectDir = root.appendingPathComponent("some-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let day = "2026-08-06T09:00:00Z"
        let sameDayLater = "2026-08-06T20:00:00Z"
        let content = """
        {"timestamp":"\(day)","message":{"usage":{"input_tokens":100,"output_tokens":50}}}
        this is not json and should be skipped
        {"timestamp":"\(sameDayLater)","message":{"usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":2}}}
        """
        let fileURL = projectDir.appendingPathComponent("session.jsonl")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        let usage = TranscriptLogParser.dailyUsage(under: root, calendar: utc)

        XCTAssertEqual(usage.count, 1)
        XCTAssertEqual(usage.first?.inputTokens, 110)
        XCTAssertEqual(usage.first?.outputTokens, 55)
        XCTAssertEqual(usage.first?.cacheReadTokens, 2)
        XCTAssertEqual(usage.first?.totalTokens, 167)
    }

    func testDailyUsageOnMissingDirectoryReturnsEmpty() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        XCTAssertEqual(TranscriptLogParser.dailyUsage(under: missing), [])
    }
}
