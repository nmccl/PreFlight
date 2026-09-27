import Foundation

/// Compact App Review guideline knowledge injected into the AI investigator's
/// system instructions.
///
/// Split per investigation pass rather than sent as one block: every session
/// shares a 4,096-token context window with its tool definitions and outputs,
/// so each pass only pays for the guidelines it can actually act on.
/// Update `version` and the slices below when guidelines change.
enum AIGuidelineKnowledge {

    static let version = "2026-09"

    static let privacy = """
        GUIDELINES (\(version)) — privacy and data:
        • 5.1.2 Usage Descriptions: each sensitive API (camera, mic, location, contacts, \
        photos, health, Bluetooth) needs a matching NS*UsageDescription. Confirm with \
        readInfoPlist + searchSource, production code only.
        • 5.1.5 Privacy Manifest: required-reason API use must be declared in \
        PrivacyInfo.xcprivacy. Confirm with readPrivacyManifest + searchSource.
        • 5.1.1(iv) Privacy Policy: required whenever personal data is collected.
        • Tracking: NSPrivacyTracking and NSPrivacyTrackingDomains must match what \
        the source and dependencies actually do.
        """

    static let commerce = """
        GUIDELINES (\(version)) — purchases and review readiness:
        • 3.1.1 IAP: digital goods and services must use Apple In-App Purchase. \
        Confirm with readStoreKitConfig + searchSource.
        • 3.1.2 Subscriptions: auto-renewable subscriptions require price and term \
        disclosure on the purchase screen, AND a functional Terms of Use (EULA) \
        link on the App Store product page — either a URL in the description or a \
        custom EULA. The words "Terms of Use" without a URL fail Apple's automated \
        pre-review check.
        • Commerce prerequisites: selling requires an active Paid Applications \
        Agreement and completed tax forms. Neither is visible to static analysis, \
        so treat these as items to confirm, never as confirmed defects.
        • 3.1.3 Steering: links to external payment. searchSource evidence required \
        before reporting.
        • Paywall completeness: purchase screens need Privacy Policy and Terms links.
        • 2.1 Demo Account: apps requiring login must supply review credentials. \
        Confirm with readASCData.
        """

    static let configuration = """
        GUIDELINES (\(version)) — configuration and capabilities:
        • Unused entitlements: declared in the entitlements file but never referenced \
        in production source. Confirm with readEntitlements + searchSource.
        • Release-only features: readBuildSettings \
        (SWIFT_ACTIVE_COMPILATION_CONDITIONS) combined with searchSource.
        • 5.1.1(iii) Account Deletion: apps with login must offer account deletion.
        • Capability coherence: a declared capability with no supporting code, or code \
        for a capability that is not declared.
        """
}
