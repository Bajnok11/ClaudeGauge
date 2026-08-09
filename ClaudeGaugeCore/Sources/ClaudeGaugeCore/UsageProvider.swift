import Foundation

/// Something that can fetch a current `UsageSnapshot` for one AI provider.
///
/// ClaudeGauge ships `ClaudeRateLimitProvider` plus a set of local-quota
/// providers for other coding assistants; every screen in the app is
/// written against this protocol so adding another one is a new conformance
/// rather than a rewrite.
public protocol UsageProvider: Sendable {
    /// Stable identifier, e.g. "claude". Used as a settings/storage key.
    var id: String { get }
    /// Display name shown in the UI, e.g. "Claude".
    var displayName: String { get }
    /// Fetches the latest usage snapshot. Throws on network/auth failure —
    /// callers are expected to fall back to the last cached snapshot.
    func fetchSnapshot() async throws -> UsageSnapshot
}

public enum UsageProviderError: Error, LocalizedError, Equatable {
    /// Nothing configured at all.
    case noCredentials
    /// User pinned the source to Claude Code, but there's no CLI login.
    case noClaudeCodeLogin
    /// User pinned the source to an API key, but none is saved.
    case noAPIKey
    /// The CLI login exists but Anthropic rejected it (usually expired).
    case expiredClaudeCodeLogin
    case invalidAPIKey
    case rateLimitHeadersMissing
    case notInstalled(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .noCredentials:
            return "No Claude Code login or API key found. Run `claude` in Terminal to log in, or add an API key in Settings."
        case .noClaudeCodeLogin:
            return "Credential source is set to Claude Code login, but no login was found. Run `claude` in Terminal, or switch the source in Settings."
        case .noAPIKey:
            return "Credential source is set to API key, but no key is saved. Add one in Settings."
        case .expiredClaudeCodeLogin:
            return "Your Claude Code login was rejected — it may have expired. Run `claude` in Terminal to log in again."
        case .invalidAPIKey:
            return "The Anthropic API key was rejected."
        case .rateLimitHeadersMissing:
            return "Anthropic didn't return usage headers for this account."
        case .notInstalled(let tool):
            return "\(tool) doesn't appear to be installed, or hasn't written any usage data yet."
        case .network(let message):
            return message
        }
    }
}
