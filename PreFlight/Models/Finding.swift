import Foundation

/// A single issue discovered by an analyzer, with enough context for the user to fix it.
struct Finding: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let category: AnalysisCategory
    let severity: Severity
    let title: String
    let detail: String
    let suggestedFix: String
    let affectedPath: String?

    init(
        id: UUID = UUID(),
        category: AnalysisCategory,
        severity: Severity,
        title: String,
        detail: String,
        suggestedFix: String,
        affectedPath: String? = nil
    ) {
        self.id = id
        self.category = category
        self.severity = severity
        self.title = title
        self.detail = detail
        self.suggestedFix = suggestedFix
        self.affectedPath = affectedPath
    }
}
