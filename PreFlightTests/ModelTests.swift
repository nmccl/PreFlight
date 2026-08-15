import Foundation
import Testing
@testable import PreFlight

@Suite("Finding invariants")
struct FindingTests {
    @Test("Observations can never be critical")
    func observationSeverityClamps() {
        let finding = Finding(
            category: .review,
            severity: .critical,
            confidence: .observation,
            title: "Heuristic guess",
            detail: "detail",
            suggestedFix: "fix"
        )
        #expect(finding.severity == .warning)
    }

    @Test("Observations can never claim certain rejection")
    func observationLikelihoodClamps() {
        let finding = Finding(
            category: .review,
            severity: .warning,
            confidence: .observation,
            rejectionLikelihood: .certain,
            title: "Heuristic guess",
            detail: "detail",
            suggestedFix: "fix"
        )
        #expect(finding.rejectionLikelihood == .likely)
    }

    @Test("Facts keep critical severity and certain likelihood")
    func factsAreNotClamped() {
        let finding = Finding(
            category: .project,
            severity: .critical,
            confidence: .fact,
            rejectionLikelihood: .certain,
            title: "Verified blocker",
            detail: "detail",
            suggestedFix: "fix"
        )
        #expect(finding.severity == .critical)
        #expect(finding.rejectionLikelihood == .certain)
    }

    @Test("Fix time falls back to the severity default")
    func effectiveFixMinutesFallback() {
        let defaulted = Finding(
            category: .project,
            severity: .warning,
            confidence: .fact,
            title: "t", detail: "d", suggestedFix: "f"
        )
        #expect(defaulted.effectiveFixMinutes == Severity.warning.estimatedFixMinutes)

        let overridden = Finding(
            category: .project,
            severity: .warning,
            confidence: .fact,
            title: "t", detail: "d", suggestedFix: "f",
            estimatedFixMinutes: 45
        )
        #expect(overridden.effectiveFixMinutes == 45)
    }
}

@Suite("Pillars")
struct PillarTests {
    @Test("Every category maps to the expected pillar")
    func pillarMapping() {
        #expect(AnalysisCategory.project.pillar == .configuration)
        #expect(AnalysisCategory.metadata.pillar == .configuration)
        #expect(AnalysisCategory.privacy.pillar == .configuration)
        #expect(AnalysisCategory.storeKit.pillar == .configuration)
        #expect(AnalysisCategory.accessibility.pillar == .experience)
        #expect(AnalysisCategory.deviceSupport.pillar == .experience)
        #expect(AnalysisCategory.review.pillar == .compliance)
    }

    @Test("Every category has a positive weight")
    func positiveWeights() {
        for category in AnalysisCategory.allCases {
            #expect(category.weight > 0)
        }
    }
}
