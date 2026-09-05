import Foundation

/// Renders a report as a Markdown checklist a developer can work through —
/// findings to fix, manual verifications, and the post-fix submission steps
/// reviewers expect (new build, review notes, evidence if replying to a
/// rejection).
nonisolated enum ReportExporter {
    static func markdownChecklist(for report: Report) -> String {
        var lines: [String] = []

        lines.append("# PreFlight Checklist — \(report.projectName)")
        var subtitle = "Generated \(report.generatedAt.formatted(date: .abbreviated, time: .shortened))"
        subtitle += " · Readiness \(report.overallScore)/100"
        subtitle += " · based on \(report.totalChecksPerformed) automated checks"
        lines.append(subtitle)
        lines.append("")

        let bySeverity = Dictionary(grouping: report.allFindings, by: \.severity)
        for severity in Severity.allCases {
            guard let findings = bySeverity[severity], !findings.isEmpty else { continue }
            lines.append("## \(sectionTitle(for: severity))")
            for finding in findings {
                lines.append(checklistLine(for: finding))
            }
            lines.append("")
        }

        let skipped = report.skippedResults
        if !skipped.isEmpty {
            lines.append("## Not checked")
            for result in skipped {
                lines.append("- \(result.category.displayName): \(result.skipReason ?? "skipped")")
            }
            lines.append("")
        }

        lines.append("## Verify manually")
        for check in ManualCheck.checklist(for: report) {
            lines.append("- [ ] \(check.title) — \(check.detail)")
        }
        lines.append("")

        lines.append("## After fixing everything")
        lines.append("- [ ] Re-run the PreFlight analysis and confirm the findings are gone")
        lines.append("- [ ] Upload a new build to App Store Connect")
        lines.append("- [ ] Mention what changed in the App Review notes")
        lines.append("- [ ] If replying to a rejection, attach a screen recording that shows the fixes")

        return lines.joined(separator: "\n")
    }

    private static func checklistLine(for finding: Finding) -> String {
        var line = "- [ ] \(finding.title) — \(finding.suggestedFix)"
        var tags: [String] = []
        if let guideline = finding.guidelineReference {
            tags.append("Guideline \(guideline)")
        }
        if finding.confidence == .observation {
            tags.append("needs verification")
        }
        if !tags.isEmpty {
            line += " (\(tags.joined(separator: "; ")))"
        }
        return line
    }

    private static func sectionTitle(for severity: Severity) -> String {
        switch severity {
        case .critical:   "Blockers — fix before submitting"
        case .warning:    "High Risk — fix or verify"
        case .review:     "Review — verify these apply"
        case .suggestion: "Recommendations — worth improving"
        }
    }
}
