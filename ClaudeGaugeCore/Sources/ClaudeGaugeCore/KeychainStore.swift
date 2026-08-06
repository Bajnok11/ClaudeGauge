import Foundation
import Security

/// Minimal Keychain wrapper for the one secret ClaudeGauge ever stores: an
/// optional, user-supplied Anthropic API key (used only when there's no
/// Claude Code CLI login to read a token from). Never synced, never logged.
public struct KeychainStore: Sendable {
    private let service: String
    private let account: String

    public init(service: String = "dev.claudegauge.app", account: String = "anthropic-api-key") {
        self.service = service
        self.account = account
    }

    public func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func save(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        var query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            return addStatus == errSecSuccess
        }
        return updateStatus == errSecSuccess
    }

    @discardableResult
    public func delete() -> Bool {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
