import XCTest
@testable import ClaudeGaugeCore

final class NotificationPolicyTests: XCTestCase {
    private func snapshot(session: Double, weekly: Double = 0) -> UsageSnapshot {
        UsageSnapshot(
            sessionPercent: session,
            weeklyPercent: weekly,
            sessionResetMinutes: nil,
            weeklyResetMinutes: nil,
            fetchedAt: Date(),
            source: .claudeCodeOAuth
        )
    }

    private var prefs: Preferences {
        var p = Preferences.default
        p.notificationsEnabled = true
        p.notificationThresholds = [80, 95]
        return p
    }

    func testDisabledNotificationsProduceNothing() {
        var policy = NotificationPolicy()
        var p = prefs
        p.notificationsEnabled = false

        _ = policy.evaluate(snapshot: snapshot(session: 10), preferences: p)
        XCTAssertTrue(policy.evaluate(snapshot: snapshot(session: 99), preferences: p).isEmpty)
    }

    func testFirstReadingArmsThresholdsWithoutFiring() {
        var policy = NotificationPolicy()
        // Launching the app when already at 90% should not retroactively
        // announce every threshold below that.
        let alerts = policy.evaluate(snapshot: snapshot(session: 90), preferences: prefs)
        XCTAssertTrue(alerts.isEmpty)
    }

    func testFiresOnceWhenThresholdCrossed() {
        var policy = NotificationPolicy()
        _ = policy.evaluate(snapshot: snapshot(session: 10), preferences: prefs)

        let alerts = policy.evaluate(snapshot: snapshot(session: 82), preferences: prefs)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first, .crossedThreshold(percent: 80, metric: "Session", current: 82))
    }

    func testDoesNotRepeatWhileStillAboveThreshold() {
        var policy = NotificationPolicy()
        _ = policy.evaluate(snapshot: snapshot(session: 10), preferences: prefs)
        _ = policy.evaluate(snapshot: snapshot(session: 82), preferences: prefs)

        // This is the spam case: polling every minute at 83%, 84%, 85% must
        // stay silent until the *next* configured threshold.
        XCTAssertTrue(policy.evaluate(snapshot: snapshot(session: 83), preferences: prefs).isEmpty)
        XCTAssertTrue(policy.evaluate(snapshot: snapshot(session: 90), preferences: prefs).isEmpty)
    }

    func testFiresAgainAtHigherThreshold() {
        var policy = NotificationPolicy()
        _ = policy.evaluate(snapshot: snapshot(session: 10), preferences: prefs)
        _ = policy.evaluate(snapshot: snapshot(session: 82), preferences: prefs)

        let alerts = policy.evaluate(snapshot: snapshot(session: 96), preferences: prefs)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first, .crossedThreshold(percent: 95, metric: "Session", current: 96))
    }

    func testWindowResetRearmsThresholds() {
        var policy = NotificationPolicy()
        _ = policy.evaluate(snapshot: snapshot(session: 10), preferences: prefs)
        _ = policy.evaluate(snapshot: snapshot(session: 82), preferences: prefs)

        // Window rolls over.
        _ = policy.evaluate(snapshot: snapshot(session: 3), preferences: prefs)

        let alerts = policy.evaluate(snapshot: snapshot(session: 81), preferences: prefs)
        XCTAssertEqual(alerts.first, .crossedThreshold(percent: 80, metric: "Session", current: 81))
    }

    func testSmallDipDoesNotCountAsReset() {
        var policy = NotificationPolicy()
        _ = policy.evaluate(snapshot: snapshot(session: 10), preferences: prefs)
        _ = policy.evaluate(snapshot: snapshot(session: 85), preferences: prefs)

        // Rolling windows drift down a little as old requests age out; that
        // must not re-arm and re-fire the same threshold.
        _ = policy.evaluate(snapshot: snapshot(session: 81), preferences: prefs)
        XCTAssertTrue(policy.evaluate(snapshot: snapshot(session: 84), preferences: prefs).isEmpty)
    }

    func testResetNotificationOptIn() {
        var policy = NotificationPolicy()
        var p = prefs
        p.notifyOnReset = true

        _ = policy.evaluate(snapshot: snapshot(session: 70), preferences: p)
        let alerts = policy.evaluate(snapshot: snapshot(session: 2), preferences: p)
        XCTAssertTrue(alerts.contains(.windowReset(metric: "Session")))
    }

    func testWeeklyMetricTrackedIndependently() {
        var policy = NotificationPolicy()
        _ = policy.evaluate(snapshot: snapshot(session: 10, weekly: 10), preferences: prefs)

        let alerts = policy.evaluate(snapshot: snapshot(session: 10, weekly: 85), preferences: prefs)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first, .crossedThreshold(percent: 80, metric: "Weekly", current: 85))
    }
}
