import XCTest
@testable import ClaudeGaugeCore

final class PreferencesTests: XCTestCase {
    func testNormalizeKeepsCriticalAboveWarning() {
        var p = Preferences.default
        p.warningThreshold = 90
        p.criticalThreshold = 50 // nonsensical: critical below warning

        let normalized = p.normalized()
        XCTAssertGreaterThan(normalized.criticalThreshold, normalized.warningThreshold)
    }

    func testNormalizeClampsOutOfRangeThresholds() {
        var p = Preferences.default
        p.warningThreshold = -20
        p.criticalThreshold = 500

        let normalized = p.normalized()
        XCTAssertGreaterThanOrEqual(normalized.warningThreshold, 1)
        XCTAssertLessThanOrEqual(normalized.criticalThreshold, 100)
    }

    func testNormalizeDeduplicatesAndSortsNotificationThresholds() {
        var p = Preferences.default
        p.notificationThresholds = [95, 80, 95, 0, 150, 50]

        XCTAssertEqual(p.normalized().notificationThresholds, [50, 80, 95])
    }

    func testNormalizeRejectsUnsupportedInterval() {
        var p = Preferences.default
        p.refreshIntervalMinutes = 7

        XCTAssertEqual(p.normalized().refreshIntervalMinutes, Preferences.default.refreshIntervalMinutes)
    }

    func testCustomThresholdsDriveStatus() {
        var p = Preferences.default
        p.warningThreshold = 30
        p.criticalThreshold = 50

        XCTAssertEqual(UsageStatus(percent: 20, thresholds: p.statusThresholds), .ok)
        XCTAssertEqual(UsageStatus(percent: 35, thresholds: p.statusThresholds), .warning)
        XCTAssertEqual(UsageStatus(percent: 60, thresholds: p.statusThresholds), .critical)
    }

    func testRoundTripsThroughSharedStorage() {
        let suite = "dev.claudegauge.tests.\(UUID().uuidString)"
        let storage = SharedStorage(appGroupIdentifier: suite)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        var p = Preferences.default
        p.credentialSource = .apiKeyOnly
        p.menuBarStyle = .percentOnly
        p.accent = .purple
        storage.writePreferences(p)

        let loaded = storage.readPreferences()
        XCTAssertEqual(loaded.credentialSource, .apiKeyOnly)
        XCTAssertEqual(loaded.menuBarStyle, .percentOnly)
        XCTAssertEqual(loaded.accent, .purple)
    }

    func testReadingPreferencesBeforeAnyWriteReturnsDefaults() {
        let suite = "dev.claudegauge.tests.\(UUID().uuidString)"
        let storage = SharedStorage(appGroupIdentifier: suite)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        XCTAssertEqual(storage.readPreferences(), .default)
    }

    func testMenuBarMetricSelection() {
        let snapshot = UsageSnapshot(
            sessionPercent: 30, weeklyPercent: 70,
            sessionResetMinutes: nil, weeklyResetMinutes: nil,
            fetchedAt: Date(), source: .claudeCodeOAuth
        )
        XCTAssertEqual(MenuBarMetric.highest.value(from: snapshot), 70)
        XCTAssertEqual(MenuBarMetric.session.value(from: snapshot), 30)
        XCTAssertEqual(MenuBarMetric.weekly.value(from: snapshot), 70)
        XCTAssertEqual(MenuBarMetric.highest.label(from: snapshot), "Weekly")
    }
}
