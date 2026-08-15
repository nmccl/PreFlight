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
    static let all: [KnownDataCollector] = [
        KnownDataCollector(
            name: "RevenueCat",
            sourcePatterns: ["import RevenueCat", "Purchases.configure"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypePurchaseHistory",
                "NSPrivacyCollectedDataTypeDeviceID",
            ],
            ascCategories: ["PURCHASE_HISTORY", "DEVICE_ID"]
        ),
        KnownDataCollector(
            name: "Firebase Analytics",
            sourcePatterns: ["import FirebaseAnalytics", "FirebaseApp.configure", "Analytics.logEvent"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeProductInteraction",
                "NSPrivacyCollectedDataTypeDeviceID",
            ],
            ascCategories: ["PRODUCT_INTERACTION", "DEVICE_ID"]
        ),
        KnownDataCollector(
            name: "Firebase Crashlytics",
            sourcePatterns: ["import FirebaseCrashlytics", "Crashlytics.crashlytics()"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeCrashData",
                "NSPrivacyCollectedDataTypePerformanceData",
            ],
            ascCategories: ["CRASH_DATA", "PERFORMANCE_DATA"]
        ),
        KnownDataCollector(
            name: "Amplitude",
            sourcePatterns: ["import Amplitude", "import AmplitudeSwift"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeProductInteraction",
                "NSPrivacyCollectedDataTypeDeviceID",
            ],
            ascCategories: ["PRODUCT_INTERACTION", "DEVICE_ID"]
        ),
        KnownDataCollector(
            name: "Mixpanel",
            sourcePatterns: ["import Mixpanel"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeProductInteraction",
                "NSPrivacyCollectedDataTypeDeviceID",
            ],
            ascCategories: ["PRODUCT_INTERACTION", "DEVICE_ID"]
        ),
        KnownDataCollector(
            name: "Sentry",
            sourcePatterns: ["import Sentry", "SentrySDK.start"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeCrashData",
                "NSPrivacyCollectedDataTypePerformanceData",
            ],
            ascCategories: ["CRASH_DATA", "PERFORMANCE_DATA"]
        ),
        KnownDataCollector(
            name: "Segment",
            sourcePatterns: ["import Segment", "SEGAnalytics.setup"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeProductInteraction",
                "NSPrivacyCollectedDataTypeDeviceID",
            ],
            ascCategories: ["PRODUCT_INTERACTION", "DEVICE_ID"]
        ),
        KnownDataCollector(
            name: "AppsFlyer",
            sourcePatterns: ["import AppsFlyerLib"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeDeviceID",
                "NSPrivacyCollectedDataTypeOtherUsageData",
            ],
            ascCategories: ["DEVICE_ID", "OTHER_USAGE_DATA"]
        ),
        KnownDataCollector(
            name: "Adjust",
            sourcePatterns: ["import Adjust"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeDeviceID",
                "NSPrivacyCollectedDataTypeOtherUsageData",
            ],
            ascCategories: ["DEVICE_ID", "OTHER_USAGE_DATA"]
        ),
        KnownDataCollector(
            name: "Intercom",
            sourcePatterns: ["import Intercom"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeEmailAddress",
                "NSPrivacyCollectedDataTypeName",
            ],
            ascCategories: ["EMAIL_ADDRESS", "NAME"]
        ),
        KnownDataCollector(
            name: "PostHog",
            sourcePatterns: ["import PostHog"],
            xcprivacyTypes: [
                "NSPrivacyCollectedDataTypeProductInteraction",
                "NSPrivacyCollectedDataTypeDeviceID",
            ],
            ascCategories: ["PRODUCT_INTERACTION", "DEVICE_ID"]
        ),
    ]
}
