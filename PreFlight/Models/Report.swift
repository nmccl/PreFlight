import Foundation

/// The complete result of an analysis run, ready for the Results screen.
struct Report: Identifiable, Sendable {
    let id: UUID
    let projectName: String
    let bundleIdentifier: String?
    let generatedAt: Date
    let results: [AnalysisResult]
    let overallScore: Int
    var aiSummary: ReportSummaryText?

    init(project: Project, results: [AnalysisResult]) {
        self.id = UUID()
        self.projectName = project.name
        self.bundleIdentifier = project.bundleIdentifier
        self.generatedAt = .now
        self.results = results
        self.overallScore = Self.weightedScore(for: results)
        self.aiSummary = nil
    }

    /// Weighted average of category scores. Skipped categories are excluded
    /// entirely so a check the user can't run doesn't drag the score down.
    private static func weightedScore(for results: [AnalysisResult]) -> Int {
        let scored = results.filter { !$0.wasSkipped }
        let totalWeight = scored.reduce(0) { $0 + $1.category.weight }
        guard totalWeight > 0 else { return 0 }
        let weightedSum = scored.reduce(0) { $0 + $1.score * $1.category.weight }
        return weightedSum / totalWeight
    }
}

extension Report {
    var allFindings: [Finding] {
        results.flatMap(\.findings).sorted { $0.severity < $1.severity }
    }

    var criticalCount: Int { count(of: .critical) }
    var warningCount: Int { count(of: .warning) }
    var suggestionCount: Int { count(of: .suggestion) }

    var estimatedFixTime: Duration {
        .seconds(allFindings.reduce(0) { $0 + $1.severity.estimatedFixMinutes } * 60)
    }

    private func count(of severity: Severity) -> Int {
        allFindings.count { $0.severity == severity }
    }
}

/// The summary shown at the top of the report, written either by Apple
/// Intelligence or by the deterministic fallback template.
struct ReportSummaryText: Sendable {
    let overview: String
    let topPriorities: [String]
    let isAIGenerated: Bool
}
