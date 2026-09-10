import Foundation
import Security

/// Persists the date the user started their free trial.
///
/// This lives in the Keychain rather than UserDefaults on purpose: Keychain
/// items survive deleting and reinstalling the app, so a reinstall can't hand
/// out a second trial. Sandboxed apps may read and write their own generic
/// password items without any extra entitlement.
nonisolated struct TrialAnchorStore: Sendable {
    let serviceName: String
    private let account = "trial-start-date"

    /// Tests pass a throwaway service so they never touch the real anchor.
    init(service: String = "com.noahmcclung.PreFlight.trial") {
        self.serviceName = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]
    }

    /// The recorded trial start, or nil if the trial has never been started.
    var startDate: Date? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let iso = String(data: data, encoding: .utf8) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: iso)
    }

    /// Writes the trial start. Does nothing if one is already recorded, so the
    /// trial window can only ever be set once.
    func recordStartIfNeeded(_ date: Date) {
        guard startDate == nil else { return }
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(ISO8601DateFormatter().string(from: date).utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    /// Clears the recorded start. Only used by the dev reset in Settings.
    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
