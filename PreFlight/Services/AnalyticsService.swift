import PostHog
import Foundation

/// Central analytics hub. All PostHog calls go through here so event names and
/// property keys are defined in one place and never duplicated across the app.
/// Uses PostHog's anonymous UUID — no PII ever captured.
final class AnalyticsService {
    static let shared = AnalyticsService()
    private init() {}

    // Replace these with your PostHog project values after account setup.
    private static let apiKey = "phc_kL54MPgQ7rF7TTYVHNipgY2jojPVBg6DHdNW86VcYunk"
    private static let host = "https://us.i.posthog.com"

    func configure(analyticsEnabled: Bool) {
        let config = PostHogConfig(apiKey: Self.apiKey, host: Self.host)
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        PostHogSDK.shared.setup(config)
        if !analyticsEnabled {
            PostHogSDK.shared.optOut()
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            PostHogSDK.shared.optIn()
        } else {
            PostHogSDK.shared.optOut()
        }
    }

    // MARK: - App lifecycle

    func appLaunched(isFirstLaunch: Bool, isPro: Bool, hasASCCredentials: Bool) {
        PostHogSDK.shared.capture("app_launched", properties: [
            "is_first_launch": isFirstLaunch,
            "is_pro": isPro,
            "has_asc_credentials": hasASCCredentials,
        ])
    }

    func onboardingCompleted() {
        PostHogSDK.shared.capture("onboarding_completed")
    }

    // MARK: - Project & analysis

    func projectOpened(source: ProjectOpenSource) {
        PostHogSDK.shared.capture("project_opened", properties: [
            "source": source.rawValue,
        ])
    }

    func analysisStarted(isPro: Bool, analyzerCount: Int, hasASCCredentials: Bool) {
        PostHogSDK.shared.capture("analysis_started", properties: [
            "is_pro": isPro,
            "analyzer_count": analyzerCount,
            "has_asc_credentials": hasASCCredentials,
        ])
    }

    func analysisCompleted(
        score: Int,
        criticalCount: Int,
        warningCount: Int,
        suggestionCount: Int,
        categoriesRun: Int,
        categoriesSkipped: Int,
        durationSeconds: Double,
        isPro: Bool
    ) {
        PostHogSDK.shared.capture("analysis_completed", properties: [
            "score": score,
            "critical_count": criticalCount,
            "warning_count": warningCount,
            "suggestion_count": suggestionCount,
            "categories_run": categoriesRun,
            "categories_skipped": categoriesSkipped,
            "duration_seconds": durationSeconds,
            "is_pro": isPro,
        ])
    }

    // MARK: - Results

    func resultsViewed(score: Int, findingsCount: Int, hasAISummary: Bool) {
        PostHogSDK.shared.capture("results_viewed", properties: [
            "score": score,
            "findings_count": findingsCount,
            "has_ai_summary": hasAISummary,
        ])
    }

    func findingExpanded(severity: String) {
        PostHogSDK.shared.capture("finding_expanded", properties: [
            "severity": severity,
        ])
    }

    func checklistCopied() {
        PostHogSDK.shared.capture("checklist_copied")
    }

    // MARK: - ASC

    func ascCredentialsConnected() {
        PostHogSDK.shared.capture("asc_credentials_connected")
    }

    func ascCredentialsRemoved() {
        PostHogSDK.shared.capture("asc_credentials_removed")
    }

    // MARK: - Paywall

    func paywallShown(source: PaywallSource) {
        PostHogSDK.shared.capture("paywall_shown", properties: [
            "source": source.rawValue,
        ])
    }

    func paywallDismissed(source: PaywallSource, converted: Bool) {
        PostHogSDK.shared.capture("paywall_dismissed", properties: [
            "source": source.rawValue,
            "converted": converted,
        ])
    }

    // MARK: - Purchase

    func purchaseInitiated() {
        PostHogSDK.shared.capture("purchase_initiated")
    }

    func purchaseCompleted() {
        PostHogSDK.shared.capture("purchase_completed")
    }

    func purchaseFailed(userCancelled: Bool) {
        PostHogSDK.shared.capture("purchase_failed", properties: [
            "user_cancelled": userCancelled,
        ])
    }

    func purchaseRestored(foundEntitlement: Bool) {
        PostHogSDK.shared.capture("purchase_restored", properties: [
            "found_entitlement": foundEntitlement,
        ])
    }
}

// MARK: - Supporting enums

enum ProjectOpenSource: String {
    case filePicker = "file_picker"
    case recents
}

enum PaywallSource: String {
    case summaryCard = "summary_card"
    case lockedCategory = "locked_category"
    case copyChecklist = "copy_checklist"
}
