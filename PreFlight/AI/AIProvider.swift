import Foundation

enum AIAvailability: Sendable {
    case available
    case unavailable(reason: String)
}

/// A pre-digested, size-bounded view of a report. Providers receive this
/// instead of the raw Report so prompts stay small and consistent.
struct ReportSummaryInput: Sendable {
    let projectName: String
    let overallScore: Int
    let categoryLines: [String]
    let topFindings: [String]
}

/// Abstracts the summary model so other providers can be added later
/// without touching the report pipeline.
protocol AIProvider: Sendable {
    var name: String { get }
    func availability() async -> AIAvailability
    func generateSummary(from input: ReportSummaryInput) async throws -> ReportSummaryText
}
