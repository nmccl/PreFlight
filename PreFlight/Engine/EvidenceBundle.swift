import Foundation

/// Per-file view of a source file with path attribution and origin classification.
struct EvidenceSourceFile: Sendable {
    let relativePath: String
    let content: String
    /// True when the file's path indicates it belongs to a test, mock, or spec target.
    let isTestFile: Bool
    /// True when the file belongs to a checked-in dependency (SPM checkout,
    /// Pods, Carthage, a sibling package). Third-party code is not the
    /// application's behavior and must not be evidence about it.
    let isVendored: Bool

    /// The application's own code: neither a test fixture nor a dependency.
    /// This is the only source that proves what the app actually does.
    var isApplicationCode: Bool { !isTestFile && !isVendored }
}

/// Parsed entitlements for one application target.
struct EvidenceEntitlements: Sendable {
    let path: String
    /// All top-level plist keys mapped to their string representation.
    let keys: [String: String]
}

struct EvidenceAPITypeEntry: Sendable {
    let categoryKey: String
    let reasonCodes: [String]
}

/// Structured representation of a PrivacyInfo.xcprivacy file.
struct EvidencePrivacyManifest: Sendable {
    let collectedDataTypes: [String]
    let privacyTracking: Bool
    let trackingDomains: [String]
    let accessedAPITypes: [EvidenceAPITypeEntry]
    /// Raw UTF-8 content for AI inspection.
    let rawContent: String
}

struct EvidenceStoreKitConfig: Sendable {
    let filename: String
    let rawContent: String
}

/// Swift Package Manager dependencies resolved from Package.resolved.
struct EvidenceDependencies: Sendable {
    let packageNames: [String]
    let rawContent: String
}

struct EvidenceLocalizationFile: Sendable {
    let relativePath: String
    let content: String
}

struct EvidenceReviewDetail: Sendable {
    let demoAccountRequired: Bool
    let demoAccountName: String?
    let reviewNotes: String?
}

/// Minimal snapshot of App Store Connect data fetched at context-build time.
struct EvidenceASCSnapshot: Sendable {
    let appID: String
    let bundleID: String
    /// Locale → privacy policy URL (nil value means the field is unset on ASC).
    let privacyPolicyURLs: [String: String?]
    let supportURLs: [String: String?]
    let descriptions: [String: String?]
    let reviewDetail: EvidenceReviewDetail?
    let declaredPrivacyCategories: [String]
    /// Product ID → ASC subscription state string.
    let subscriptionStates: [String: String]
}

/// All project evidence collected once per analysis run and shared across the
/// deterministic analyzers and the AI investigation layer.
struct EvidenceBundle: Sendable {
    /// Individual source files with path attribution and test classification.
    let sourceFiles: [EvidenceSourceFile]
    /// Build settings keyed by target name, then configuration name, then setting key.
    let buildSettings: [String: [String: [String: String]]]
    /// Info.plist data per application target name.
    let infoPlists: [String: InfoPlistData]
    /// Parsed entitlements per application target name.
    let entitlements: [String: EvidenceEntitlements]
    /// The app's PrivacyInfo.xcprivacy, if present.
    let privacyManifest: EvidencePrivacyManifest?
    /// StoreKit configuration files found in the project.
    let storeKitConfigs: [EvidenceStoreKitConfig]
    /// Swift Package Manager dependencies from Package.resolved, if present.
    let dependencies: EvidenceDependencies?
    /// Localization files (.strings and .xcstrings).
    let localizationFiles: [EvidenceLocalizationFile]
    /// App Store Connect snapshot, populated when credentials are configured. Nil otherwise.
    let ascSnapshot: EvidenceASCSnapshot?
}
