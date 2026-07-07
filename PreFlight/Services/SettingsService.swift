import SwiftUI

/// User preferences, persisted to UserDefaults. Injecting the defaults
/// instance lets tests run against a throwaway suite instead of the real one.
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

    private let defaults: UserDefaults

    private enum Keys {
        static let appearance = "appearance"
        static let isAIEnabled = "isAIEnabled"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        self.isAIEnabled = defaults.object(forKey: Keys.isAIEnabled) as? Bool ?? true
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
    }
}
