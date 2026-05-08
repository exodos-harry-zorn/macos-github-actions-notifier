import Foundation
import Security

protocol KeychainStore: TokenProvider {
    func saveToken(_ token: String) throws
    func readToken() throws -> String
    func deleteToken() throws
}

final class KeychainTokenStore: KeychainStore, @unchecked Sendable {
    private let service = "com.exodoslabs.MacGHActionsNotifier"
    private let account = "github-oauth-token"

    func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        let query = baseQuery()
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppError.keychain("Could not save token to Keychain (\(status)).")
        }
    }

    func readToken() throws -> String {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw AppError.authentication("No GitHub token is stored.")
        }
        guard let data = item as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            throw AppError.keychain("The stored GitHub token is unreadable.")
        }
        return token
    }

    func deleteToken() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.keychain("Could not remove token from Keychain (\(status)).")
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
