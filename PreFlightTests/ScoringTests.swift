import Foundation
import Testing
@testable import PreFlight

@Suite("Scoring")
struct ScoringTests {
    private func makeProject() -> Project {
        Project(
            name: "Fixture",
            projectFileURL: URL(filePath: "/tmp/Fixture.xcodeproj"),
            directoryURL: URL(filePath: "/tmp")
        )
    }

    private func finding(_ severity: Severity, category: AnalysisCategory = .project) -> Finding {
        Finding(
            category: category,
            severity: severity,
            confidence: .fact,
            title: "t", detail: "d", suggestedFix: "f"
        )
    }

    @Test("Category score deducts per severity and clamps at zero")
    func categoryScoreDeductions() {
        let one = AnalysisResult(category: .project, findings: [finding(.critical)], checksPerformed: 1)
        #expect(one.score == 75)

        let mixed = AnalysisResult(
            category: .project,
            findings: [finding(.critical), finding(.warning), finding(.suggestion)],
            checksPerformed: 3
        )
        #expect(mixed.score == 100 - 25 - 10 - 3)

        let flooded = AnalysisResult(
            category: .project,
            findings: Array(repeating: finding(.critical), count: 5),
            checksPerformed: 5
        )
        #expect(flooded.score == 0)
    }

    @Test("Overall score is the weighted average of unskipped categories")
    func weightedOverall() {
        let project = AnalysisResult(category: .project, findings: [finding(.critical)], checksPerformed: 1)   // 75, weight 25
        let privacy = AnalysisResult(category: .privacy, findings: [], checksPerformed: 1)                      // 100, weight 25
        let report = Report(project: makeProject(), results: [project, privacy])
        #expect(report.overallScore == (75 * 25 + 100 * 25) / 50)
    }

    @Test("Skipped categories don't drag the score down")
    func skippedCategoriesExcluded() {
        let clean = AnalysisResult(category: .project, findings: [], checksPerformed: 3)
        let skipped = AnalysisResult.skipped(.metadata, reason: "No credentials")
        let report = Report(project: makeProject(), results: [clean, skipped])
        #expect(report.overallScore == 100)
        #expect(report.skippedResults.count == 1)
    }

    @Test("Estimated fix time honors per-finding overrides")
    func fixTimeUsesOverrides() {
        let custom = Finding(
            category: .project,
            severity: .warning,
            confidence: .fact,
            title: "t", detail: "d", suggestedFix: "f",
            estimatedFixMinutes: 60
        )
        let result = AnalysisResult(
            category: .project,
            findings: [custom, finding(.suggestion)],
            checksPerformed: 2
        )
        let report = Report(project: makeProject(), results: [result])
        let expectedMinutes = 60 + Severity.suggestion.estimatedFixMinutes
        #expect(report.estimatedFixTime == .seconds(expectedMinutes * 60))
    }

    @Test("Total checks sum across categories")
    func totalChecks() {
        let a = AnalysisResult(category: .project, findings: [], checksPerformed: 7)
        let b = AnalysisResult(category: .privacy, findings: [], checksPerformed: 12)
        let report = Report(project: makeProject(), results: [a, b])
        #expect(report.totalChecksPerformed == 19)
    }
}
