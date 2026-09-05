import Foundation

/// The outcome of one analyzer's run: its findings and a 0–100 category score.
/// Codable so reports containing it can be persisted between launches.
struct AnalysisResult: Codable, Sendable {
    let category: AnalysisCategory
    let findings: [Finding]
    let score: Int
    let checksPerformed: Int
    let wasSkipped: Bool
    let skipReason: String?

    init(category: AnalysisCategory, findings: [Finding], checksPerformed: Int) {
        self.category = category
        self.findings = findings.sorted { $0.severity < $1.severity }
        self.score = max(0, 100 - findings.reduce(0) { $0 + $1.severity.pointDeduction })
        self.checksPerformed = checksPerformed
        self.wasSkipped = false
        self.skipReason = nil
    }

    /// A category the engine could not or should not evaluate, e.g. Metadata
    /// without App Store Connect credentials. Skipped categories are excluded
    /// from the overall score instead of counting as zero.
    static func skipped(_ category: AnalysisCategory, reason: String) -> AnalysisResult {
        AnalysisResult(skippedCategory: category, reason: reason)
    }

    private init(skippedCategory: AnalysisCategory, reason: String) {
        self.category = skippedCategory
        self.findings = []
        self.score = 0
        self.checksPerformed = 0
        self.wasSkipped = true
        self.skipReason = reason
    }

    /// The worst severity present in this result's findings, used for the
    /// category status badge in the results UI.
    enum CategoryState: Sendable {
        case blocked        // has .critical findings
        case highRisk       // has .warning findings
        case review         // has .review findings
        case recommendation // only .suggestion findings
        case clean          // no findings
    }

    var categoryState: CategoryState {
        if findings.contains(where: { $0.severity == .critical })   { return .blocked }
        if findings.contains(where: { $0.severity == .warning })    { return .highRisk }
        if findings.contains(where: { $0.severity == .review })     { return .review }
        if findings.contains(where: { $0.severity == .suggestion }) { return .recommendation }
        return .clean
    }
}
