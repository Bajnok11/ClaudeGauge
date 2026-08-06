import XCTest
@testable import ClaudeGaugeCore

final class RateLimitHeadersTests: XCTestCase {
    func testParsesSubscriptionHeaders() {
        let headers = [
            "anthropic-ratelimit-unified-5h-utilization": "0.42",
            "anthropic-ratelimit-unified-weekly-utilization": "0.107",
            "anthropic-ratelimit-unified-5h-remaining": "9000",
            "anthropic-ratelimit-unified-weekly-remaining": "259200"
        ]

        let parsed = RateLimitHeaders.parse(headers)

        XCTAssertEqual(parsed?.sessionPercent, 42)
        XCTAssertEqual(parsed?.weeklyPercent, 11) // 10.7 rounds to 11
        XCTAssertEqual(parsed?.sessionResetMinutes, 150) // 9000s / 60
        XCTAssertEqual(parsed?.weeklyResetMinutes, 4320) // 259200s / 60
    }

    func testIsCaseInsensitiveToHeaderKeys() {
        let headers = [
            "Anthropic-Ratelimit-Unified-5h-Utilization": "0.5",
            "ANTHROPIC-RATELIMIT-UNIFIED-WEEKLY-UTILIZATION": "0.2"
        ]

        let parsed = RateLimitHeaders.parse(headers)

        XCTAssertEqual(parsed?.sessionPercent, 50)
        XCTAssertEqual(parsed?.weeklyPercent, 20)
    }

    func testMissingSessionHeaderReturnsNil() {
        let parsed = RateLimitHeaders.parse(["some-other-header": "1"])
        XCTAssertNil(parsed)
    }

    func testMissingWeeklyHeaderDefaultsToZero() {
        let headers = ["anthropic-ratelimit-unified-5h-utilization": "0.3"]
        let parsed = RateLimitHeaders.parse(headers)
        XCTAssertEqual(parsed?.sessionPercent, 30)
        XCTAssertEqual(parsed?.weeklyPercent, 0)
        XCTAssertNil(parsed?.weeklyResetMinutes)
    }

    func testClampsOutOfRangeValues() {
        let headers = [
            "anthropic-ratelimit-unified-5h-utilization": "1.5",
            "anthropic-ratelimit-unified-weekly-utilization": "-0.2"
        ]
        let parsed = RateLimitHeaders.parse(headers)
        XCTAssertEqual(parsed?.sessionPercent, 100)
        XCTAssertEqual(parsed?.weeklyPercent, 0)
    }

    func testSubscriptionHeadersReportUnifiedKind() {
        let headers = ["anthropic-ratelimit-unified-5h-utilization": "0.1"]
        XCTAssertEqual(RateLimitHeaders.parse(headers)?.kind, .unifiedSubscription)
    }

    // MARK: - Pay-as-you-go Console API key (classic per-minute limits)

    func testParsesClassicAPIKeyHeaders() {
        let headers = [
            "anthropic-ratelimit-tokens-limit": "40000",
            "anthropic-ratelimit-tokens-remaining": "30000",
            "anthropic-ratelimit-requests-limit": "50",
            "anthropic-ratelimit-requests-remaining": "45"
        ]

        let parsed = RateLimitHeaders.parse(headers)

        XCTAssertEqual(parsed?.kind, .classicAPIKey)
        XCTAssertEqual(parsed?.sessionPercent, 25) // (40000-30000)/40000
        XCTAssertEqual(parsed?.weeklyPercent, 10) // (50-45)/50
    }

    func testClassicAPIKeyMissingRequestsDefaultsToZero() {
        let headers = [
            "anthropic-ratelimit-tokens-limit": "1000",
            "anthropic-ratelimit-tokens-remaining": "500"
        ]

        let parsed = RateLimitHeaders.parse(headers)

        XCTAssertEqual(parsed?.kind, .classicAPIKey)
        XCTAssertEqual(parsed?.sessionPercent, 50)
        XCTAssertEqual(parsed?.weeklyPercent, 0)
    }

    func testNeitherHeaderShapePresentReturnsNil() {
        XCTAssertNil(RateLimitHeaders.parse(["x-request-id": "abc"]))
    }

    func testClassicAPIKeyZeroLimitIsIgnoredNotDividedByZero() {
        let headers = [
            "anthropic-ratelimit-tokens-limit": "0",
            "anthropic-ratelimit-tokens-remaining": "0"
        ]
        XCTAssertNil(RateLimitHeaders.parse(headers))
    }

    func testUnifiedHeadersTakePriorityOverClassicIfBothPresent() {
        let headers = [
            "anthropic-ratelimit-unified-5h-utilization": "0.3",
            "anthropic-ratelimit-tokens-limit": "1000",
            "anthropic-ratelimit-tokens-remaining": "0"
        ]
        let parsed = RateLimitHeaders.parse(headers)
        XCTAssertEqual(parsed?.kind, .unifiedSubscription)
        XCTAssertEqual(parsed?.sessionPercent, 30)
    }
}
