import SwiftUI

/// User preferences, persisted to UserDefaults. Injecting the defaults
/// instance lets tests run against a throwaway suite instead of the real one.
/// The ASC private key is the exception: it's a secret, so it lives in the
/// Keychain via KeychainStore.
@MainActor
@Observable
final class SettingsService {
    enum Appearance: String, CaseIterable {
        case system
        case light
        case dark

        var displayName: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    var isAIEnabled: Bool {
        didSet { defaults.set(isAIEnabled, forKey: Keys.isAIEnabled) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    var isAnalyticsEnabled: Bool {
        didSet {
            defaults.set(isAnalyticsEnabled, forKey: Keys.isAnalyticsEnabled)
            AnalyticsService.shared.setEnabled(isAnalyticsEnabled)
        }
    }

    // MARK: App Store Connect

    var ascIssuerID: String {
        didSet { defaults.set(ascIssuerID, forKey: Keys.ascIssuerID) }
    }

    var ascKeyID: String {
        didSet { defaults.set(ascKeyID, forKey: Keys.ascKeyID) }
    }

    private(set) var ascKeyStored: Bool

    /// Complete credentials, or nil while any piece is missing.
    var ascCredentials: ASCCredentials? {
        guard !ascIssuerID.isEmpty, !ascKeyID.isEmpty,
              let pem = keychain.loadPrivateKey() else {
            return nil
        }
        return ASCCredentials(issuerID: ascIssuerID, keyID: ascKeyID, privateKeyPEM: pem)
    }

    func storePrivateKey(_ pem: String) throws {
        try keychain.savePrivateKey(pem)
        ascKeyStored = true
    }

    func removePrivateKey() {
        keychain.deletePrivateKey()
        ascKeyStored = false
    }

    // MARK: Storage

    private let defaults: UserDefaults
    private let keychain = KeychainStore()

    private enum Keys {
        static let appearance = "appearance"
        static let isAIEnabled = "isAIEnabled"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let isAnalyticsEnabled = "isAnalyticsEnabled"
        static let ascIssuerID = "ascIssuerID"
        static let ascKeyID = "ascKeyID"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        self.isAIEnabled = defaults.object(forKey: Keys.isAIEnabled) as? Bool ?? true
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        self.isAnalyticsEnabled = defaults.object(forKey: Keys.isAnalyticsEnabled) as? Bool ?? true
        self.ascIssuerID = defaults.string(forKey: Keys.ascIssuerID) ?? ""
        self.ascKeyID = defaults.string(forKey: Keys.ascKeyID) ?? ""
        self.ascKeyStored = KeychainStore().hasPrivateKey
    }
}
