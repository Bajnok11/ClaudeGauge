import XCTest
@testable import ClaudeGaugeCore

final class UsageSnapshotTests: XCTestCase {
    func testDefaultKindIsUnifiedSubscriptionWithSessionWeeklyLabels() {
        let snapshot = UsageSnapshot(
            sessionPercent: 10, weeklyPercent: 5,
            sessionResetMinutes: nil, weeklyResetMinutes: nil,
            fetchedAt: Date(), source: .claudeCodeOAuth
        )
        XCTAssertEqual(snapshot.kind, .unifiedSubscription)
        XCTAssertEqual(snapshot.primaryLabel, "Session")
        XCTAssertEqual(snapshot.secondaryLabel, "Weekly")
    }

    func testClassicAPIKeyKindUsesTokensRequestsLabels() {
        let snapshot = UsageSnapshot(
            sessionPercent: 10, weeklyPercent: 5,
            sessionResetMinutes: nil, weeklyResetMinutes: nil,
            fetchedAt: Date(), source: .manualAPIKey, kind: .classicAPIKey
        )
        XCTAssertEqual(snapshot.primaryLabel, "Tokens")
        XCTAssertEqual(snapshot.secondaryLabel, "Requests")
    }

    func testStatusThresholds() {
        XCTAssertEqual(UsageStatus(percent: 0), .ok)
        XCTAssertEqual(UsageStatus(percent: 59), .ok)
        XCTAssertEqual(UsageStatus(percent: 60), .warning)
        XCTAssertEqual(UsageStatus(percent: 84), .warning)
        XCTAssertEqual(UsageStatus(percent: 85), .critical)
        XCTAssertEqual(UsageStatus(percent: 100), .critical)
    }
}
