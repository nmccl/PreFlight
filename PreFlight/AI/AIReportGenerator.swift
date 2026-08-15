import Foundation

/// Produces the report summary: Apple Intelligence when available and
/// enabled, otherwise a deterministic template. Always returns something.
struct AIReportGenerator: Sendable {
    let provider: any AIProvider

    init(provider: any AIProvider = AppleIntelligenceProvider()) {
        self.provider = provider
    }

    func summary(for report: Report, aiEnabled: Bool) async -> ReportSummaryText {
        if aiEnabled, case .available = await provider.availability() {
            let input = Self.input(for: report)
            if let generated = try? await provider.generateSummary(from: input) {
                return generated
            }
        }
        return Self.templateSummary(for: report)
    }

    /// Digests the report into a bounded prompt input: one line per category
    /// and only the top findings. The on-device context window is small, so
    /// never feed it every finding.
    static func input(for report: Report) -> ReportSummaryInput {
        let categoryLines = report.results.map { result in
            let name = "\(result.category.pillar.displayName) / \(result.category.displayName)"
            if result.wasSkipped {
                return "\(name): not checked (\(result.skipReason ?? "skipped"))"
            }
            let criticals = result.findings.count { $0.severity == .critical }
            let warnings = result.findings.count { $0.severity == .warning }
            return "\(name): \(result.score)/100, \(criticals) critical, \(warnings) warnings"
        }

        let topFindings = report.allFindings.prefix(8).map { finding in
            var markers = [finding.severity.displayName]
            if let likelihood = finding.rejectionLikelihood {
                markers.append(likelihood.displayName.lowercased())
            }
            if finding.confidence == .observation {
                markers.append("observation")
            }
            return "- [\(markers.joined(separator: ", "))] \(finding.title): \(finding.detail)"
        }

        return ReportSummaryInput(
            projectName: report.projectName,
            overallScore: report.overallScore,
            categoryLines: categoryLines,
            topFindings: Array(topFindings)
        )
    }

    /// Fallback used when AI is off, unavailable, or fails. Pure function of
    /// the report, so it's trivially testable.
    static func templateSummary(for report: Report) -> ReportSummaryText {
        // Openings claim only what the automated checks can support — a
        // clean run is never presented as "ready for review".
        let opening = switch report.overallScore {
        case 100 where report.allFindings.isEmpty:
            "\(report.projectName) passes every automated check PreFlight can run. Apple reviews more than any tool can verify, so walk through the manual checklist before submitting."
        case 85...:
            "\(report.projectName) passes nearly all of PreFlight's automated checks."
        case 60..<85:
            "\(report.projectName) has a few blockers to clear before submission."
        default:
            "\(report.projectName) needs significant work before it's ready for review."
        }

        let counts = "The analysis found "
            + countPhrase(report.criticalCount, "critical issue") + ", "
            + countPhrase(report.warningCount, "warning") + ", and "
            + countPhrase(report.suggestionCount, "suggestion") + "."

        let priorities = report.allFindings.prefix(3).map(\.title)

        return ReportSummaryText(
            overview: opening + " " + counts,
            topPriorities: Array(priorities),
            isAIGenerated: false
        )
    }

    private static func countPhrase(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}
