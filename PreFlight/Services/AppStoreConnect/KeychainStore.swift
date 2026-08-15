import Foundation
import Security

nonisolated enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            "Couldn't save the key to the Keychain (error \(status))."
        }
    }
}

/// Stores the ASC private key as a generic-password item. Sandboxed apps can
/// use their own Keychain items without any extra entitlement.
nonisolated struct KeychainStore: Sendable {
    private static let service = "com.noahmcclung.PreFlight.asc"
    private static let account = "asc-private-key"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    func savePrivateKey(_ pem: String) throws {
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(pem.utf8)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func loadPrivateKey() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func deletePrivateKey() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    var hasPrivateKey: Bool {
        loadPrivateKey() != nil
    }
}
