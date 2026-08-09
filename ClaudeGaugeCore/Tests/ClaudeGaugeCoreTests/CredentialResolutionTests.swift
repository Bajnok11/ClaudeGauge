import XCTest
@testable import ClaudeGaugeCore

/// Pins down the precedence rules that were silently wrong before v0.2:
/// a manually-entered API key was unreachable for anyone who also had a
/// Claude Code login, with no way to tell or override.
final class CredentialResolutionTests: XCTestCase {
    /// A credentials file the reader will actually accept, written to a
    /// unique temp path per test.
    ///
    /// - Parameter expiresInSeconds: written as `expiresAt` in the
    ///   milliseconds-since-epoch form Claude Code uses. Negative values
    ///   produce an already-expired login.
    private func writeClaudeCodeCredentials(
        token: String = "oauth-token",
        expiresInSeconds: TimeInterval? = 3600
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("creds-\(UUID().uuidString).json")
        var fields = ["\"accessToken\": \"\(token)\"", "\"subscriptionType\": \"max\""]
        if let expiresInSeconds {
            let millis = (Date().timeIntervalSince1970 + expiresInSeconds) * 1000
            fields.append("\"expiresAt\": \(Int(millis))")
        }
        let json = "{ \"claudeAiOauth\": { \(fields.joined(separator: ", ")) } }"
        try Data(json.utf8).write(to: url)
        return url
    }

    /// Points the provider at a Keychain service that cannot exist, so these
    /// tests never depend on (or print) the real Claude Code login of
    /// whoever runs the suite.
    private func makeProvider(
        credentialsURL: URL,
        apiKey: String?,
        source: CredentialSource
    ) -> ClaudeRateLimitProvider {
        ClaudeRateLimitProvider(
            credentialsURL: credentialsURL,
            keychainService: "dev.claudegauge.tests.absent-\(UUID().uuidString)",
            apiKeyProvider: { apiKey },
            credentialSourceProvider: { source }
        )
    }

    private var missingCredentialsURL: URL {
        URL(fileURLWithPath: "/tmp/claudegauge-missing-\(UUID().uuidString).json")
    }

    // MARK: - .automatic

    func testAutomaticPrefersClaudeCodeWhenBothPresent() throws {
        let url = try writeClaudeCodeCredentials()
        defer { try? FileManager.default.removeItem(at: url) }

        let resolved = try makeProvider(credentialsURL: url, apiKey: "sk-ant-key", source: .automatic)
            .resolveCredential()

        XCTAssertTrue(resolved.isOAuth)
        XCTAssertEqual(resolved.token, "oauth-token")
    }

    func testAutomaticFallsBackToAPIKey() throws {
        let resolved = try makeProvider(
            credentialsURL: missingCredentialsURL,
            apiKey: "sk-ant-key",
            source: .automatic
        ).resolveCredential()

        XCTAssertFalse(resolved.isOAuth)
        XCTAssertEqual(resolved.token, "sk-ant-key")
    }

    func testAutomaticWithNothingConfiguredThrows() {
        XCTAssertThrowsError(
            try makeProvider(credentialsURL: missingCredentialsURL, apiKey: nil, source: .automatic)
                .resolveCredential()
        ) { error in
            XCTAssertEqual(error as? UsageProviderError, .noCredentials)
        }
    }

    // MARK: - .apiKeyOnly — the regression this whole enum exists to fix

    func testAPIKeyOnlyUsesAPIKeyEvenWhenClaudeCodeLoginExists() throws {
        let url = try writeClaudeCodeCredentials()
        defer { try? FileManager.default.removeItem(at: url) }

        let resolved = try makeProvider(credentialsURL: url, apiKey: "sk-ant-key", source: .apiKeyOnly)
            .resolveCredential()

        XCTAssertFalse(resolved.isOAuth, "API key must win when the user explicitly pinned it")
        XCTAssertEqual(resolved.token, "sk-ant-key")
    }

    func testAPIKeyOnlyWithNoKeyThrowsSpecificError() throws {
        let url = try writeClaudeCodeCredentials()
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(
            try makeProvider(credentialsURL: url, apiKey: nil, source: .apiKeyOnly).resolveCredential()
        ) { error in
            // Must not silently succeed via the OAuth login that's sitting
            // right there — the user asked for the key specifically.
            XCTAssertEqual(error as? UsageProviderError, .noAPIKey)
        }
    }

    func testAPIKeyOnlyTreatsEmptyStringAsMissing() throws {
        XCTAssertThrowsError(
            try makeProvider(credentialsURL: missingCredentialsURL, apiKey: "", source: .apiKeyOnly)
                .resolveCredential()
        ) { error in
            XCTAssertEqual(error as? UsageProviderError, .noAPIKey)
        }
    }

    // MARK: - .claudeCodeOnly

    func testClaudeCodeOnlyIgnoresAPIKey() {
        XCTAssertThrowsError(
            try makeProvider(
                credentialsURL: missingCredentialsURL,
                apiKey: "sk-ant-key",
                source: .claudeCodeOnly
            ).resolveCredential()
        ) { error in
            XCTAssertEqual(error as? UsageProviderError, .noClaudeCodeLogin)
        }
    }

    // MARK: - Expiry

    func testAutomaticFallsBackToAPIKeyWhenOAuthTokenExpired() throws {
        // The real-world case that made a saved API key look ignored: the
        // CLI login is present but stale, so every refresh 401'd.
        let url = try writeClaudeCodeCredentials(expiresInSeconds: -3600)
        defer { try? FileManager.default.removeItem(at: url) }

        let resolved = try makeProvider(credentialsURL: url, apiKey: "sk-ant-key", source: .automatic)
            .resolveCredential()

        XCTAssertFalse(resolved.isOAuth)
        XCTAssertEqual(resolved.token, "sk-ant-key")
    }

    func testAutomaticWithOnlyExpiredLoginReportsExpiryNotAbsence() throws {
        let url = try writeClaudeCodeCredentials(expiresInSeconds: -3600)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(
            try makeProvider(credentialsURL: url, apiKey: nil, source: .automatic).resolveCredential()
        ) { error in
            // "No credentials found" would send the user hunting for a
            // setting that's already correct; the real fix is re-running
            // `claude`.
            XCTAssertEqual(error as? UsageProviderError, .expiredClaudeCodeLogin)
        }
    }

    func testClaudeCodeOnlyRejectsExpiredLogin() throws {
        let url = try writeClaudeCodeCredentials(expiresInSeconds: -60)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(
            try makeProvider(credentialsURL: url, apiKey: nil, source: .claudeCodeOnly).resolveCredential()
        ) { error in
            XCTAssertEqual(error as? UsageProviderError, .expiredClaudeCodeLogin)
        }
    }

    func testCredentialsWithoutExpiryFieldAreTreatedAsValid() throws {
        // Older Claude Code builds didn't record an expiry; absence must not
        // be read as "expired".
        let url = try writeClaudeCodeCredentials(expiresInSeconds: nil)
        defer { try? FileManager.default.removeItem(at: url) }

        let resolved = try makeProvider(credentialsURL: url, apiKey: nil, source: .claudeCodeOnly)
            .resolveCredential()
        XCTAssertTrue(resolved.isOAuth)
    }

    func testClaudeCodeOnlyCarriesAccountInfoThrough() throws {
        let url = try writeClaudeCodeCredentials()
        defer { try? FileManager.default.removeItem(at: url) }

        let resolved = try makeProvider(credentialsURL: url, apiKey: nil, source: .claudeCodeOnly)
            .resolveCredential()

        XCTAssertEqual(resolved.account.subscriptionType, "max")
        XCTAssertEqual(resolved.account.displayPlan, "Max")
    }
}
