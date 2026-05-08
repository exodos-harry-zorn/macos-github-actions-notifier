import Foundation
import Security

protocol KeychainStore: TokenProvider {
    func saveToken(_ token: String) throws
    func readToken() throws -> String
    func deleteToken() throws
    func saveClientID(_ clientID: String) throws
    func readClientID() throws -> String
    func deleteClientID() throws
}

final class KeychainTokenStore: KeychainStore, @unchecked Sendable {
    private let service = "com.exodoslabs.MacGHActionsNotifier"
    private let tokenAccount = "github-oauth-token"
    private let clientIDAccount = "github-oauth-client-id"

    func saveToken(_ token: String) throws {
        try saveSecret(token, account: tokenAccount, label: "token")
    }

    func readToken() throws -> String {
        try readSecret(account: tokenAccount, missingMessage: "No GitHub token is stored.", unreadableMessage: "The stored GitHub token is unreadable.")
    }

    func deleteToken() throws {
        try deleteSecret(account: tokenAccount, label: "token")
    }

    func saveClientID(_ clientID: String) throws {
        try saveSecret(clientID, account: clientIDAccount, label: "OAuth client ID")
    }

    func readClientID() throws -> String {
        try readSecret(account: clientIDAccount, missingMessage: "No GitHub OAuth client ID is stored.", unreadableMessage: "The stored GitHub OAuth client ID is unreadable.")
    }

    func deleteClientID() throws {
        try deleteSecret(account: clientIDAccount, label: "OAuth client ID")
    }

    private func saveSecret(_ value: String, account: String, label: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppError.keychain("Could not save \(label) to Keychain (\(status)).")
        }
    }

    private func readSecret(account: String, missingMessage: String, unreadableMessage: String) throws -> String {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw AppError.authentication(missingMessage)
        }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            throw AppError.keychain(unreadableMessage)
        }
        return value
    }

    private func deleteSecret(account: String, label: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.keychain("Could not remove \(label) from Keychain (\(status)).")
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
