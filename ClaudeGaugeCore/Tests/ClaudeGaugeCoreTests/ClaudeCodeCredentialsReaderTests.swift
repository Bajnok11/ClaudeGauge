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

    func testReadFromMissingFileReturnsNil() {
        let missing = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).json")
        XCTAssertNil(ClaudeCodeCredentialsReader.read(from: missing))
    }
}
