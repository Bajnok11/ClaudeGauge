import Foundation

/// Reads Claude Code's own CLI login (`~/.claude/.credentials.json`), the
/// same OAuth token `claude` itself uses — no browser-cookie scraping, no
/// separate login flow.
public struct ClaudeCodeCredentials: Equatable, Sendable {
    public let token: String
    public let isOAuth: Bool
}

public enum ClaudeCodeCredentialsReader {
    public static var defaultCredentialsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent(".credentials.json", isDirectory: false)
    }

    public static func read(from url: URL = defaultCredentialsURL) -> ClaudeCodeCredentials? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data: data)
    }

    /// Exposed separately so tests can exercise both the current nested
    /// `claudeAiOauth.accessToken` schema and the older flat-key schema
    /// without touching disk.
    public static func parse(data: Data) -> ClaudeCodeCredentials? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let nested = json["claudeAiOauth"] as? [String: Any],
           let token = nested["accessToken"] as? String,
           !token.isEmpty {
            return ClaudeCodeCredentials(token: token, isOAuth: true)
        }

        for key in ["claudeAiOauthToken", "oauthToken", "access_token"] {
            if let token = json[key] as? String, !token.isEmpty {
                return ClaudeCodeCredentials(token: token, isOAuth: true)
            }
        }

        return nil
    }
}

/// The V1 `UsageProvider`: resolves credentials (Claude Code login first,
/// then a manually-entered API key) and reads the live session/weekly
/// utilization straight from Anthropic's rate-limit response headers via a
/// minimal (`max_tokens: 1`) request. No usage data is ever stored or sent
/// anywhere except to Anthropic itself and this device's local disk.
public final class ClaudeRateLimitProvider: UsageProvider, @unchecked Sendable {
    public let id = "claude"
    public let displayName = "Claude"

    private let session: URLSession
    private let apiKeyProvider: @Sendable () -> String?
    private let credentialsURL: URL
    private let endpoint: URL

    public init(
        session: URLSession = .shared,
        credentialsURL: URL = ClaudeCodeCredentialsReader.defaultCredentialsURL,
        endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        apiKeyProvider: @escaping @Sendable () -> String? = { nil }
    ) {
        self.session = session
        self.credentialsURL = credentialsURL
        self.endpoint = endpoint
        self.apiKeyProvider = apiKeyProvider
    }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        let token: String
        let isOAuth: Bool

        if let creds = ClaudeCodeCredentialsReader.read(from: credentialsURL) {
            token = creds.token
            isOAuth = true
        } else if let key = apiKeyProvider(), !key.isEmpty {
            token = key
            isOAuth = false
        } else {
            throw UsageProviderError.noCredentials
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if isOAuth {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue(token, forHTTPHeaderField: "x-api-key")
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
            throw isOAuth ? UsageProviderError.noCredentials : UsageProviderError.invalidAPIKey
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
            source: isOAuth ? .claudeCodeOAuth : .manualAPIKey,
            kind: parsed.kind
        )
    }
}
