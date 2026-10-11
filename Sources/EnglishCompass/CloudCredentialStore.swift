import Foundation
import Security
import AssistantCore

/// Only the API key is persisted here; drafts never enter Keychain.
enum CloudCredentialStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.zook.EnglishCompass.bailian",
         kSecAttrAccount as String: "api-key"]
    }
    static var containsKey: Bool {
        var lookup = query
        lookup[kSecReturnAttributes as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        lookup[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        return SecItemCopyMatching(lookup as CFDictionary, nil) == errSecSuccess
    }
    static func read() throws -> String {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status != errSecSuccess && status != errSecItemNotFound { throw AssistantFailure.cloudKeychainAccess }
        guard status == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            throw AssistantFailure.cloudKeyMissing
        }
        return key
    }
    static func save(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= 4096, !key.contains("\n"), !key.contains("\r") else {
            throw AssistantFailure.cloudKeyMissing
        }
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw AssistantFailure.cloudKeyMissing }
        var entry = query
        entry.merge(attributes) { _, new in new }
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else {
            throw AssistantFailure.cloudKeyMissing
        }
    }
}
