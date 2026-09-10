import Foundation
import Testing
@testable import PreFlight

/// Each test uses its own Keychain service so the real trial anchor is never
/// read or written, and so tests don't leak state into each other.
@MainActor
@Suite("Free trial window")
struct TrialManagerTests {
    private func makeStore() -> TrialAnchorStore {
        let store = TrialAnchorStore(service: "com.noahmcclung.PreFlight.tests.\(UUID().uuidString)")
        store.clear()
        return store
    }

    /// A throwaway defaults suite, so the "Simulate Expired Trial" developer
    /// toggle in the real suite can't decide the outcome of these tests.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "com.noahmcclung.PreFlight.tests.\(UUID().uuidString)") ?? .standard
    }

    @Test("Access is granted before the user starts the trial")
    func accessGrantedBeforeStart() {
        let trial = TrialManager(anchorStore: makeStore(), defaults: makeDefaults())
        #expect(trial.hasStarted == false)
        #expect(trial.isTrialActive)
        #expect(trial.daysRemaining == TrialManager.trialDays)
    }

    @Test("Starting the trial records an anchor and opens the window")
    func beginTrialStartsWindow() {
        let store = makeStore()
        defer { store.clear() }
        let trial = TrialManager(anchorStore: store, defaults: makeDefaults())

        trial.beginTrial()

        #expect(trial.hasStarted)
        #expect(trial.isTrialActive)
        #expect(trial.hasTrialExpired == false)
        #expect(store.startDate != nil)
    }

    @Test("Restarting the trial can't extend it")
    func beginTrialIsIdempotent() {
        let store = makeStore()
        defer { store.clear() }

        // Simulate a trial that started 6 days ago.
        let sixDaysAgo = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
        store.recordStartIfNeeded(sixDaysAgo)

        let trial = TrialManager(anchorStore: store, defaults: makeDefaults())
        let originalStart = trial.startDate

        // A reinstall would call beginTrial() again on the next onboarding run.
        trial.beginTrial()

        #expect(trial.startDate == originalStart)
        #expect(trial.daysRemaining == 0)
        #expect(trial.isTrialActive)
    }

    @Test("The trial expires after seven days")
    func trialExpires() {
        let store = makeStore()
        defer { store.clear() }

        let eightDaysAgo = Calendar.current.date(byAdding: .day, value: -8, to: Date())!
        store.recordStartIfNeeded(eightDaysAgo)

        let trial = TrialManager(anchorStore: store, defaults: makeDefaults())

        #expect(trial.hasStarted)
        #expect(trial.hasTrialExpired)
        #expect(trial.isTrialActive == false)
        #expect(trial.daysRemaining == 0)
    }

    @Test("Resetting clears the anchor so the trial can be replayed in testing")
    func resetClearsAnchor() {
        let store = makeStore()
        defer { store.clear() }
        let trial = TrialManager(anchorStore: store, defaults: makeDefaults())

        trial.beginTrial()
        #expect(trial.hasStarted)

        trial.resetForTesting()

        #expect(trial.hasStarted == false)
        #expect(store.startDate == nil)
    }

    @Test("The anchor survives a new manager instance, as a reinstall would")
    func anchorSurvivesNewInstance() {
        let store = makeStore()
        defer { store.clear() }

        let firstRun = TrialManager(anchorStore: store, defaults: makeDefaults())
        firstRun.beginTrial()
        let recordedStart = firstRun.startDate

        // A fresh install reads the same Keychain item back.
        let secondRun = TrialManager(
            anchorStore: TrialAnchorStore(service: store.serviceName),
            defaults: makeDefaults()
        )

        #expect(secondRun.hasStarted)
        #expect(secondRun.startDate == recordedStart)
    }
}
