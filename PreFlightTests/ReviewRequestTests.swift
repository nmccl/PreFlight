import Foundation
import Testing
@testable import PreFlight

@MainActor
@Suite("Review prompt gating")
struct ReviewRequestTests {
    private func makeService() -> ReviewRequestService {
        let suite = "com.noahmcclung.PreFlight.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        return ReviewRequestService(defaults: defaults)
    }

    private func completeAnalyses(_ count: Int, on service: ReviewRequestService) {
        for _ in 0..<count { service.noteAnalysisCompleted() }
    }

    @Test("A brand-new user is not asked to review")
    func notAskedImmediately() {
        let service = makeService()
        #expect(!service.shouldRequestReview(hasFullAccess: true))
    }

    @Test("Not asked before enough analyses have completed")
    func notAskedBeforeThreshold() {
        let service = makeService()
        completeAnalyses(ReviewRequestService.analysesBeforeAsking - 1, on: service)
        #expect(!service.shouldRequestReview(hasFullAccess: true))
    }

    @Test("Asked once the analysis threshold is reached")
    func askedAtThreshold() {
        let service = makeService()
        completeAnalyses(ReviewRequestService.analysesBeforeAsking, on: service)
        #expect(service.shouldRequestReview(hasFullAccess: true))
    }

    @Test("Never asked while the person lacks full access")
    func notAskedWithoutFullAccess() {
        let service = makeService()
        completeAnalyses(ReviewRequestService.analysesBeforeAsking + 5, on: service)
        #expect(!service.shouldRequestReview(hasFullAccess: false))
    }

    @Test("Only asked once per app version")
    func askedOncePerVersion() {
        let service = makeService()
        completeAnalyses(ReviewRequestService.analysesBeforeAsking, on: service)
        #expect(service.shouldRequestReview(hasFullAccess: true))

        service.markRequested()
        #expect(!service.shouldRequestReview(hasFullAccess: true))

        // More usage on the same version must not re-trigger it.
        completeAnalyses(10, on: service)
        #expect(!service.shouldRequestReview(hasFullAccess: true))
    }

    @Test("A new app version becomes eligible again")
    func newVersionEligible() {
        let suite = "com.noahmcclung.PreFlight.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard

        let v1 = ReviewRequestService(defaults: defaults, bundle: BundleStub(version: "1.0", build: "1"))
        completeAnalyses(ReviewRequestService.analysesBeforeAsking, on: v1)
        v1.markRequested()
        #expect(!v1.shouldRequestReview(hasFullAccess: true))

        // Same defaults, newer version: the analysis count persists, so the
        // person is eligible again without having to re-earn the threshold.
        let v2 = ReviewRequestService(defaults: defaults, bundle: BundleStub(version: "1.1", build: "2"))
        #expect(v2.completedAnalysisCount >= ReviewRequestService.analysesBeforeAsking)
        #expect(v2.shouldRequestReview(hasFullAccess: true))
    }

    @Test("The analysis count survives a new service instance")
    func countPersists() {
        let suite = "com.noahmcclung.PreFlight.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard

        let first = ReviewRequestService(defaults: defaults)
        completeAnalyses(2, on: first)

        let second = ReviewRequestService(defaults: defaults)
        #expect(second.completedAnalysisCount == 2)
    }

    @Test("Resetting replays the prompt conditions")
    func resetReplays() {
        let service = makeService()
        completeAnalyses(ReviewRequestService.analysesBeforeAsking, on: service)
        service.markRequested()
        #expect(!service.shouldRequestReview(hasFullAccess: true))

        service.resetForTesting()
        #expect(service.completedAnalysisCount == 0)
        #expect(!service.shouldRequestReview(hasFullAccess: true))

        completeAnalyses(ReviewRequestService.analysesBeforeAsking, on: service)
        #expect(service.shouldRequestReview(hasFullAccess: true))
    }
}

/// Stands in for Bundle.main so version-change behavior is testable.
private final class BundleStub: Bundle, @unchecked Sendable {
    private let stubbed: [String: Any]

    init(version: String, build: String) {
        self.stubbed = ["CFBundleShortVersionString": version, "CFBundleVersion": build]
        super.init()
    }

    override var infoDictionary: [String: Any]? { stubbed }
}
