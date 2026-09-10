import Foundation
import Observation
import StoreKit

/// Manages the 7-day free trial that precedes the one-time PreFlight unlock.
///
/// The trial window is anchored to two dates, and the earlier one wins:
///
/// - `AppTransaction.originalPurchaseDate` — the App Store-signed date the
///   customer first downloaded PreFlight. It's tied to their Apple Account and
///   is unchanged by deleting and reinstalling the app, so it can't be reset.
/// - A Keychain-recorded start date, written once when the user taps Start
///   Free Trial at the end of onboarding. Keychain items outlive the app
///   bundle, so this survives a reinstall too.
///
/// Taking the earlier of the two means neither wiping UserDefaults nor
/// reinstalling extends the trial. The cost is that someone who downloads
/// PreFlight and doesn't open it for over a week arrives to an expired trial;
/// the App Store date is the authoritative one in that case.
///
/// `originalPurchaseDate` is hardcoded to 2013-08-01 outside production, so in
/// TestFlight, sandbox, and Xcode it's ignored and the Keychain date is used
/// alone — otherwise every tester would open the app to a dead trial.
@MainActor
@Observable
final class TrialManager {
    static let trialDays = 7

    /// The resolved start of the trial window, or nil if the user hasn't
    /// tapped Start Free Trial yet.
    private(set) var startDate: Date?
    /// Whether the App Store anchor has been fetched. Access is granted while
    /// this is still false so a slow network can't flash the paywall at launch.
    private(set) var hasLoaded = false

    private let anchorStore: TrialAnchorStore
    /// The App Store download date, or nil outside production.
    private var appStoreStartDate: Date?

    /// Injected so tests run against a throwaway suite instead of the real one,
    /// the same way SettingsService does it.
    private let defaults: UserDefaults

    #if DEBUG
    private static let forceExpiredKey = "preflight_dev_forceTrialExpired"

    /// Dev-only: reports the trial as expired regardless of the real dates, so
    /// the paywall can be reached on demand for App Review screenshots without
    /// waiting seven days. Persisted so it survives relaunches mid-session.
    var debugForceExpired: Bool {
        didSet { defaults.set(debugForceExpired, forKey: Self.forceExpiredKey) }
    }
    #endif

    init(anchorStore: TrialAnchorStore = TrialAnchorStore(), defaults: UserDefaults = .standard) {
        self.anchorStore = anchorStore
        self.defaults = defaults
        #if DEBUG
        self.debugForceExpired = defaults.bool(forKey: Self.forceExpiredKey)
        #endif
        resolveStartDate()
    }

    /// Fetches the App Store anchor. Call once at launch, before showing UI.
    func load() async {
        appStoreStartDate = await fetchAppStoreOriginalPurchaseDate()
        hasLoaded = true
        resolveStartDate()
    }

    /// Records the trial start. Called when the user taps Start Free Trial on
    /// the last onboarding page. Safe to call repeatedly — the anchor is only
    /// ever written once, so the trial can't be restarted.
    func beginTrial() {
        anchorStore.recordStartIfNeeded(Date())
        resolveStartDate()
    }

    var hasStarted: Bool { startDate != nil }

    var expirationDate: Date? {
        guard let startDate else { return nil }
        return Calendar.current.date(byAdding: .day, value: Self.trialDays, to: startDate)
    }

    /// True while the trial still grants access. Also true before the trial
    /// has started, since onboarding blocks the app until the user starts it.
    var isTrialActive: Bool {
        #if DEBUG
        if debugForceExpired { return false }
        #endif
        guard let expirationDate else { return true }
        return Date() < expirationDate
    }

    var hasTrialExpired: Bool { !isTrialActive }

    /// Days left, rounded down. Returns 0 on the last day (< 24 h remaining).
    var daysRemaining: Int {
        guard let expirationDate else { return Self.trialDays }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0)
    }

    /// Dev-only: clears the Keychain anchor so the trial can be replayed.
    /// The App Store date still applies in production, so this only fully
    /// resets the trial in TestFlight, sandbox, and Xcode.
    func resetForTesting() {
        anchorStore.clear()
        resolveStartDate()
    }

    private func resolveStartDate() {
        guard let localStart = anchorStore.startDate else {
            startDate = nil
            return
        }
        guard let appStoreStartDate else {
            startDate = localStart
            return
        }
        startDate = min(appStoreStartDate, localStart)
    }

    private func fetchAppStoreOriginalPurchaseDate() async -> Date? {
        do {
            guard case .verified(let appTransaction) = try await AppTransaction.shared else {
                return nil
            }
            // Outside production this date is a fixed 2013 sentinel value.
            guard appTransaction.environment == .production else { return nil }
            return appTransaction.originalPurchaseDate
        } catch {
            // No App Store record reachable (offline, not signed in). Fall
            // back to the Keychain anchor rather than locking the user out.
            return nil
        }
    }
}
