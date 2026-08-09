import Foundation
import Security

/// Reads Claude Code CLI's own login — the same OAuth token `claude` itself
/// uses — no browser-cookie scraping, no separate login flow.
///
/// Where that login actually lives has changed across Claude Code versions:
/// current releases store it in the macOS Keychain under the service name
/// `"Claude Code-credentials"` (moved off plaintext storage for security);
/// older releases, and non-macOS installs, wrote it to a plaintext
/// `~/.claude/.credentials.json` file instead. `read()` tries the Keychain
/// first and falls back to the file, so ClaudeGauge keeps working across
/// that migration instead of silently reporting "no credentials" for
/// anyone on a current Claude Code version — which is exactly what an
/// earlier, file-only version of this reader did. Both are read-only:
/// ClaudeGauge never writes to either, it only reads what Claude Code
/// itself already put there.
public struct ClaudeCodeCredentials: Equatable, Sendable {
    public let token: String
    public let isOAuth: Bool
    /// Plan/tier metadata that ships alongside the token in the same blob.
    /// Free to read — no extra API call — and it's the only place
    /// ClaudeGauge can learn which account it's actually reporting on.
    public let account: AccountInfo
}

public enum ClaudeCodeCredentialsReader {
    /// The service name Claude Code (2.x) stores its OAuth login under in
    /// the macOS Keychain. Not a ClaudeGauge-owned entry — read-only. Public
    /// (not `private`) only because it's used as a default-parameter value
    /// on the `public` `read(from:keychainService:)` below — Swift requires
    /// default-value expressions to be at least as visible as the function
    /// they default for.
    public static let keychainService = "Claude Code-credentials"

    public static var defaultCredentialsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent(".credentials.json", isDirectory: false)
    }

    /// - Parameter keychainService: overridable so tests can point at a
    ///   service name guaranteed not to exist, instead of accidentally
    ///   depending on whatever this machine's real Claude Code Keychain
    ///   item happens to contain. Production callers always use the default.
    public static func read(
        from fileURL: URL = defaultCredentialsURL,
        keychainService: String = ClaudeCodeCredentialsReader.keychainService
    ) -> ClaudeCodeCredentials? {
        if let fromKeychain = readFromKeychain(service: keychainService) {
            return fromKeychain
        }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return parse(data: data)
    }

    private static func readFromKeychain(service: String) -> ClaudeCodeCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return parse(data: data)
    }

    /// Exposed separately so tests can exercise both the current nested
    /// `claudeAiOauth.accessToken` schema and the older flat-key schema
    /// without touching disk or the Keychain — the same JSON shape is used
    /// whether Claude Code wrote it to the Keychain or to a file.
    public static func parse(data: Data) -> ClaudeCodeCredentials? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let nested = json["claudeAiOauth"] as? [String: Any],
           let token = nested["accessToken"] as? String,
           !token.isEmpty {
            return ClaudeCodeCredentials(token: token, isOAuth: true, account: accountInfo(from: nested))
        }

        for key in ["claudeAiOauthToken", "oauthToken", "access_token"] {
            if let token = json[key] as? String, !token.isEmpty {
                // Legacy flat schema carried no plan metadata; fall back to
                // reading it off the top level in case a variant did.
                return ClaudeCodeCredentials(token: token, isOAuth: true, account: accountInfo(from: json))
            }
        }

        return nil
    }

    private static func accountInfo(from json: [String: Any]) -> AccountInfo {
        // `expiresAt` is milliseconds since epoch in Claude Code's blob, not
        // seconds — treating it as seconds would place expiry in 1970 and
        // make every token look long-expired.
        let expiresAt: Date? = {
            guard let millis = json["expiresAt"] as? Double, millis > 0 else { return nil }
            return Date(timeIntervalSince1970: millis / 1000)
        }()

        return AccountInfo(
            subscriptionType: json["subscriptionType"] as? String,
            rateLimitTier: json["rateLimitTier"] as? String,
            expiresAt: expiresAt,
            scopes: json["scopes"] as? [String] ?? []
        )
    }
}

/// The V1 `UsageProvider`: resolves credentials according to the user's
/// chosen `CredentialSource` and reads the live session/weekly utilization
/// straight from Anthropic's rate-limit response headers via a minimal
/// (`max_tokens: 1`) request. No usage data is ever stored or sent anywhere
/// except to Anthropic itself and this device's local disk.
public final class ClaudeRateLimitProvider: UsageProvider, @unchecked Sendable {
    public let id = "claude"
    public let displayName = "Claude"

    private let session: URLSession
    private let apiKeyProvider: @Sendable () -> String?
    /// Read fresh on each fetch so changing the setting takes effect on the
    /// next poll without rebuilding the provider.
    private let credentialSourceProvider: @Sendable () -> CredentialSource
    private let credentialsURL: URL
    /// Which Keychain entry to read Claude Code's login from. Injectable so
    /// tests can point at a service name that cannot exist — otherwise they
    /// silently read (and, on failure, print) the real login of whoever runs
    /// the suite, which is both flaky and a credential-leak hazard.
    private let keychainService: String
    private let endpoint: URL

    public init(
        session: URLSession = .shared,
        credentialsURL: URL = ClaudeCodeCredentialsReader.defaultCredentialsURL,
        keychainService: String = ClaudeCodeCredentialsReader.keychainService,
        endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        apiKeyProvider: @escaping @Sendable () -> String? = { nil },
        credentialSourceProvider: @escaping @Sendable () -> CredentialSource = { .automatic }
    ) {
        self.session = session
        self.credentialsURL = credentialsURL
        self.keychainService = keychainService
        self.endpoint = endpoint
        self.apiKeyProvider = apiKeyProvider
        self.credentialSourceProvider = credentialSourceProvider
    }

    /// Resolves which credential to actually use.
    ///
    /// Split out from `fetchSnapshot()` and made `internal` so tests can
    /// verify the precedence rules without any networking — this is the
    /// logic that was silently wrong before (an API key was unreachable
    /// whenever a Claude Code login existed), so it's worth pinning down.
    struct ResolvedCredential {
        let token: String
        let isOAuth: Bool
        let account: AccountInfo
    }

    func resolveCredential() throws -> ResolvedCredential {
        let source = credentialSourceProvider()
        let claudeCode = source == .apiKeyOnly
            ? nil
            : ClaudeCodeCredentialsReader.read(from: credentialsURL, keychainService: keychainService)
        let apiKey = source == .claudeCodeOnly ? nil : apiKeyProvider().flatMap { $0.isEmpty ? nil : $0 }

        // The stored login carries its own expiry, so an expired token can
        // be spotted without spending a network round-trip on a request
        // Anthropic will answer with 401. This matters in `.automatic`:
        // an expired OAuth token should hand over to a working API key
        // rather than failing the whole refresh, which is what made a
        // configured key look like it was being ignored.
        let claudeCodeUsable = claudeCode.map { !$0.account.isExpired } ?? false

        switch source {
        case .automatic:
            if let claudeCode, claudeCodeUsable {
                return ResolvedCredential(token: claudeCode.token, isOAuth: true, account: claudeCode.account)
            }
            if let apiKey {
                return ResolvedCredential(token: apiKey, isOAuth: false, account: AccountInfo())
            }
            if claudeCode != nil {
                throw UsageProviderError.expiredClaudeCodeLogin
            }
            throw UsageProviderError.noCredentials

        case .claudeCodeOnly:
            guard let claudeCode else { throw UsageProviderError.noClaudeCodeLogin }
            guard claudeCodeUsable else { throw UsageProviderError.expiredClaudeCodeLogin }
            return ResolvedCredential(token: claudeCode.token, isOAuth: true, account: claudeCode.account)

        case .apiKeyOnly:
            guard let apiKey else { throw UsageProviderError.noAPIKey }
            return ResolvedCredential(token: apiKey, isOAuth: false, account: AccountInfo())
        }
    }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        let credential = try resolveCredential()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if credential.isOAuth {
            request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue(credential.token, forHTTPHeaderField: "x-api-key")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "."]]
        ])

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw UsageProviderError.network("No HTTP response from Anthropic.")
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw credential.isOAuth ? UsageProviderError.expiredClaudeCodeLogin : UsageProviderError.invalidAPIKey
        }

        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                headers[k] = v
            }
        }

        guard let parsed = RateLimitHeaders.parse(headers) else {
            if http.statusCode >= 400 {
                let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw UsageProviderError.network(body)
            }
            throw UsageProviderError.rateLimitHeadersMissing
        }

        return UsageSnapshot(
            sessionPercent: parsed.sessionPercent,
            weeklyPercent: parsed.weeklyPercent,
            sessionResetMinutes: parsed.sessionResetMinutes,
            weeklyResetMinutes: parsed.weeklyResetMinutes,
            fetchedAt: Date(),
            source: credential.isOAuth ? .claudeCodeOAuth : .manualAPIKey,
            kind: parsed.kind,
            account: credential.account,
            providerID: id
        )
    }
}
