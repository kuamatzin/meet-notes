import Foundation
import Security
import os

private let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "SecretsStore")

struct SecretsStore: Sendable {
    enum LLMProviderKey: String, CaseIterable, Sendable {
        case openAI = "openai-api-key"
        case anthropic = "anthropic-api-key"
    }

    private static let service = "com.kuamatzin.meet-notes"

    static func save(apiKey: String, for provider: LLMProviderKey) throws {
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                logger.error("Keychain update failed: \(updateStatus)")
                throw SecretsStoreError.keychainFailure(updateStatus)
            }
        } else if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                logger.error("Keychain add failed: \(addStatus)")
                throw SecretsStoreError.keychainFailure(addStatus)
            }
        } else {
            logger.error("Keychain query failed: \(status)")
            throw SecretsStoreError.keychainFailure(status)
        }
    }

    static func load(for provider: LLMProviderKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for provider: LLMProviderKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed: \(status)")
            throw SecretsStoreError.keychainFailure(status)
        }
    }
}

enum SecretsStoreError: Error, LocalizedError {
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainFailure(let status):
            return "Keychain operation failed with status \(status)"
        }
    }
}
