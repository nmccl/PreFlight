import Foundation
import Observation

/// Decides *when* to ask for an App Store review. It never draws UI.
///
/// The prompt itself is Apple's — `RequestReviewAction` shows the system sheet
/// with the star rating and a "Write a Review" option. An app may not build its
/// own star control that submits to the App Store, so all this type does is
/// gate the moment the system prompt is requested.
///
/// The gating follows Apple's guidance in "Requesting App Store reviews":
/// ask after a sequence the person successfully completed, never at launch,
/// never in response to a tap, and at most once per app version. StoreKit
/// independently caps the real prompt at three times per 365 days and may
/// show nothing at all, so a request is a suggestion, not a guarantee.
///
/// Deliberately *not* gated on the report score. Asking only users who got a
/// good result is review gating — it skews the rating and Apple discourages it.
@MainActor
@Observable
final class ReviewRequestService {
    /// Completed analyses before the first ask. Enough that the person has
    /// really used PreFlight and can say something useful.
    static let analysesBeforeAsking = 3

    private enum Keys {
        static let completedAnalyses = "preflight_completedAnalysisCount"
        static let lastVersionPrompted = "preflight_lastVersionPromptedForReview"
    }

    private let defaults: UserDefaults
    private let currentVersion: String

    private(set) var completedAnalysisCount: Int

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        self.currentVersion = "\(short) (\(build))"
        self.completedAnalysisCount = defaults.integer(forKey: Keys.completedAnalyses)
    }

    /// Call when an analysis finishes successfully.
    func noteAnalysisCompleted() {
        completedAnalysisCount += 1
        defaults.set(completedAnalysisCount, forKey: Keys.completedAnalyses)
    }

    private var lastVersionPrompted: String? {
        defaults.string(forKey: Keys.lastVersionPrompted)
    }

    /// Whether this is a good moment to ask.
    ///
    /// - Parameter hasFullAccess: a person staring at a paywall is not being
    ///   asked to rate the app. Only ask when the app is fully usable.
    func shouldRequestReview(hasFullAccess: Bool) -> Bool {
        guard hasFullAccess else { return false }
        guard completedAnalysisCount >= Self.analysesBeforeAsking else { return false }
        return lastVersionPrompted != currentVersion
    }

    /// Records that the prompt was requested for this version, so the same
    /// version never asks twice even though StoreKit might have shown nothing.
    func markRequested() {
        defaults.set(currentVersion, forKey: Keys.lastVersionPrompted)
    }

    #if DEBUG
    /// Dev-only: replays the prompt conditions.
    func resetForTesting() {
        completedAnalysisCount = 0
        defaults.removeObject(forKey: Keys.completedAnalyses)
        defaults.removeObject(forKey: Keys.lastVersionPrompted)
    }
    #endif
}
