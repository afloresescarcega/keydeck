import Foundation
import Security

public enum APIKeySlot: String, CaseIterable, Sendable {
    case openAI = "openai_api_key"
    case gemini = "gemini_api_key"
}

public enum KeychainError: LocalizedError, Sendable {
    case unhandledStatus(OSStatus)
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            "Keychain error (\(status)). Ensure Keychain Sharing is enabled."
        case .encodingFailed:
            "Failed to encode secret as UTF-8."
        }
    }
}

public struct SharedKeychain: Sendable {
    private let service: String
    private let accessGroup: String?

    public init(
        service: String = KeyDeckConstants.keychainService,
        accessGroup: String? = SharedKeychain.resolvedAccessGroup()
    ) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public static func resolvedAccessGroup() -> String? {
        // Resolve the app identifier prefix at runtime from entitlements if available.
        // Falling back to nil works cleanly on simulator and `swift test`.
        if let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
           !prefix.isEmpty {
            return "\(prefix)\(KeyDeckConstants.keychainAccessGroupSuffix)"
        }
        return nil
    }

    public func save(_ value: String, for slot: APIKeySlot) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            delete(slot)
            return
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let status = writeData(data, account: slot.rawValue, useAccessGroup: accessGroup != nil)
        if status == errSecMissingEntitlement && accessGroup != nil {
            let fallback = writeData(data, account: slot.rawValue, useAccessGroup: false)
            if fallback != errSecSuccess {
                throw KeychainError.unhandledStatus(fallback)
            }
            return
        }
        if status != errSecSuccess {
            throw KeychainError.unhandledStatus(status)
        }
    }

    public func read(_ slot: APIKeySlot) -> String? {
        if let accessGroup, let value = readData(account: slot.rawValue, accessGroup: accessGroup) {
            return value
        }
        return readData(account: slot.rawValue, accessGroup: nil)
    }

    public func delete(_ slot: APIKeySlot) {
        if let accessGroup {
            deleteItem(account: slot.rawValue, accessGroup: accessGroup)
        }
        deleteItem(account: slot.rawValue, accessGroup: nil)
    }

    public func hasKey(_ slot: APIKeySlot) -> Bool {
        guard let value = read(slot) else { return false }
        return !value.isEmpty
    }

    private func writeData(_ data: Data, account: String, useAccessGroup: Bool) -> OSStatus {
        let group = useAccessGroup ? accessGroup : nil
        deleteItem(account: account, accessGroup: group)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        if let group {
            query[kSecAttrAccessGroup as String] = group
        }
        return SecItemAdd(query as CFDictionary, nil) // NOSONAR: the keyboard extension must read keys without a user-presence prompt; access is limited to this device after first unlock
    }

    private func readData(account: String, accessGroup: String?) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func deleteItem(account: String, accessGroup: String?) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        SecItemDelete(query as CFDictionary)
    }
}
