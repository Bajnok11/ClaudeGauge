import Foundation

/// Something that can fetch a current `UsageSnapshot` for one AI provider.
///
/// ClaudeGauge ships one implementation (`ClaudeRateLimitProvider`) in V1,
/// but every screen in the app is written against this protocol so a future
/// Codex/Gemini/etc. provider is a new conformance, not a rewrite — see
/// ROADMAP.md.
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
    case noCredentials
    case invalidAPIKey
    case rateLimitHeadersMissing
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .noCredentials:
            return "No Claude Code login or API key found."
        case .invalidAPIKey:
            return "The Anthropic API key was rejected."
        case .rateLimitHeadersMissing:
            return "Anthropic didn't return usage headers for this account."
        case .network(let message):
            return message
        }
    }
}
