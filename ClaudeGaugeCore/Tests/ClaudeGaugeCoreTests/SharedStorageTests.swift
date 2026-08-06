import XCTest
@testable import ClaudeGaugeCore

final class SharedStorageTests: XCTestCase {
    private var suiteName: String!
    private var storage: SharedStorage!

    override func setUp() {
        super.setUp()
        suiteName = "dev.claudegauge.tests.\(UUID().uuidString)"
        storage = SharedStorage(appGroupIdentifier: suiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testReadBeforeWriteReturnsNil() {
        XCTAssertNil(storage.read())
    }

    func testRoundTripsASnapshot() {
        let snapshot = UsageSnapshot(
            sessionPercent: 37,
            weeklyPercent: 12,
            sessionResetMinutes: 90,
            weeklyResetMinutes: 4000,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            source: .claudeCodeOAuth
        )

        storage.write(snapshot)

        XCTAssertEqual(storage.read(), snapshot)
    }

    func testRefreshIntervalRoundTripsAndIgnoresZero() {
        XCTAssertNil(storage.readRefreshInterval())

        storage.writeRefreshInterval(120)
        XCTAssertEqual(storage.readRefreshInterval(), 120)

        storage.writeRefreshInterval(0)
        XCTAssertNil(storage.readRefreshInterval())
    }
}
