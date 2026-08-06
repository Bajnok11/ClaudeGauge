import XCTest
@testable import ClaudeGaugeCore

final class ClaudeCodeCredentialsReaderTests: XCTestCase {
    func testParsesCurrentNestedSchema() {
        let json = """
        { "claudeAiOauth": { "accessToken": "sk-nested-token", "refreshToken": "r" } }
        """
        let creds = ClaudeCodeCredentialsReader.parse(data: Data(json.utf8))
        XCTAssertEqual(creds?.token, "sk-nested-token")
        XCTAssertEqual(creds?.isOAuth, true)
    }

    func testFallsBackToLegacyFlatKey() {
        let json = """
        { "claudeAiOauthToken": "sk-legacy-token" }
        """
        let creds = ClaudeCodeCredentialsReader.parse(data: Data(json.utf8))
        XCTAssertEqual(creds?.token, "sk-legacy-token")
    }

    func testReturnsNilForEmptyToken() {
        let json = """
        { "claudeAiOauth": { "accessToken": "" } }
        """
        let creds = ClaudeCodeCredentialsReader.parse(data: Data(json.utf8))
        XCTAssertNil(creds)
    }

    func testReturnsNilForGarbage() {
        XCTAssertNil(ClaudeCodeCredentialsReader.parse(data: Data("not json".utf8)))
    }

    func testReadFromMissingFileAndMissingKeychainItemReturnsNil() {
        // Both the file path AND the Keychain service name are isolated
        // per-test-run values, so this can't accidentally pass by reading
        // whatever the real Claude Code login on the machine running the
        // test happens to be.
        let missingFile = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).json")
        let missingService = "dev.claudegauge.tests.no-such-service-\(UUID().uuidString)"
        XCTAssertNil(ClaudeCodeCredentialsReader.read(from: missingFile, keychainService: missingService))
    }
}
