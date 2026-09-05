import Foundation

/// A third-party SDK known to collect user data, with source-detection patterns
/// and the privacy identifiers that should accompany it in documentation.
struct KnownDataCollector: Sendable {
    let name: String
    /// Any of these strings appearing in source suggests the SDK is in use.
    let sourcePatterns: [String]
    /// NSPrivacyCollectedDataType values expected in PrivacyInfo.xcprivacy.
    let xcprivacyTypes: [String]
    /// App Store Connect app-privacy declaration category strings expected.
    let ascCategories: [String]
}

extension KnownDataCollector {
    // Patterns assembled at runtime — same self-match avoidance as PrivacyAnalyzer.usageRules.
    // A literal import string would make PreFlight flag its own source as using the SDK.
    static let all: [KnownDataCollector] = {[
        KnownDataCollector(
            name: "RevenueCat",
            sourcePatterns: ["import Revenue" + "Cat", "Pur" + "chases.configure"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypePurchaseHistory",
                "NSPrivacyCollectedDataTypeDeviceID",
            ],
            ascCategories: ["PURCHASE_HISTORY", "DEVICE_ID"]
        ),
        KnownDataCollector(
            name: "Firebase Analytics",
            sourcePatterns: ["import Firebase" + "Analytics", "Firebase" + "App.configure", "Analytics" + ".logEvent"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeProductInteraction",
                "NSPrivacyCollectedDataTypeDeviceID",
            ],
            ascCategories: ["PRODUCT_INTERACTION", "DEVICE_ID"]
        ),
        KnownDataCollector(
            name: "Firebase Crashlytics",
            sourcePatterns: ["import Firebase" + "Crashlytics", "Crash" + "lytics.crashlytics()"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeCrashData",
                "NSPrivacyCollectedDataTypePerformanceData",
            ],
            ascCategories: ["CRASH_DATA", "PERFORMANCE_DATA"]
        ),
        KnownDataCollector(
            name: "Amplitude",
            sourcePatterns: ["import Ampli" + "tude", "import Amplitude" + "Swift"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeProductInteraction",
                "NSPrivacyCollectedDataTypeDeviceID",
            ],
            ascCategories: ["PRODUCT_INTERACTION", "DEVICE_ID"]
        ),
        KnownDataCollector(
            name: "Mixpanel",
            sourcePatterns: ["import Mix" + "panel"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeProductInteraction",
                "NSPrivacyCollectedDataTypeDeviceID",
            ],
            ascCategories: ["PRODUCT_INTERACTION", "DEVICE_ID"]
        ),
        KnownDataCollector(
            name: "Sentry",
            sourcePatterns: ["import Sen" + "try", "Sentry" + "SDK.start"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeCrashData",
                "NSPrivacyCollectedDataTypePerformanceData",
            ],
            ascCategories: ["CRASH_DATA", "PERFORMANCE_DATA"]
        ),
        KnownDataCollector(
            name: "Segment",
            sourcePatterns: ["import Seg" + "ment", "SEG" + "Analytics.setup"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeProductInteraction",
                "NSPrivacyCollectedDataTypeDeviceID",
            ],
            ascCategories: ["PRODUCT_INTERACTION", "DEVICE_ID"]
        ),
        KnownDataCollector(
            name: "AppsFlyer",
            sourcePatterns: ["import AppsFlyer" + "Lib"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeDeviceID",
                "NSPrivacyCollectedDataTypeOtherUsageData",
            ],
            ascCategories: ["DEVICE_ID", "OTHER_USAGE_DATA"]
        ),
        KnownDataCollector(
            name: "Adjust",
            sourcePatterns: ["import Ad" + "just"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeDeviceID",
                "NSPrivacyCollectedDataTypeOtherUsageData",
            ],
            ascCategories: ["DEVICE_ID", "OTHER_USAGE_DATA"]
        ),
        KnownDataCollector(
            name: "Intercom",
            sourcePatterns: ["import Inter" + "com"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeEmailAddress",
                "NSPrivacyCollectedDataTypeName",
            ],
            ascCategories: ["EMAIL_ADDRESS", "NAME"]
        ),
        KnownDataCollector(
            name: "PostHog",
            sourcePatterns: ["import Post" + "Hog"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeProductInteraction",
                "NSPrivacyCollectedDataTypeDeviceID",
            ],
            ascCategories: ["PRODUCT_INTERACTION", "DEVICE_ID"]
        ),
    ]}()
}
