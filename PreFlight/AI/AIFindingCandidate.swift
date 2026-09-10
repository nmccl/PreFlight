import FoundationModels

/// The structured intermediate type that the on-device model generates for each
/// potential finding. Validated by AIFindingValidator before becoming a Finding.
///
/// Secondary evidence fields support cross-source relationships (e.g. a build setting
/// that enables a feature whose API is missing from the privacy manifest). Leave all
/// secondary fields as empty strings when a single source is sufficient.
@Generable
struct AIFindingCandidate: Sendable {
    @Guide(description: "App Review Guideline number, e.g. '3.1.1'")
    let guidelineReference: String

    @Guide(description: "Category: project|privacy|storeKit|accessibility|deviceSupport|review|metadata")
    let categoryName: String

    @Guide(description: "Severity: warning|review|suggestion")
    let severityName: String

    @Guide(description: "Issue title, 5–10 words")
    let title: String

    @Guide(description: "1–2 sentence description of the finding")
    let detail: String

    @Guide(description: "Why App Review flags this")
    let whyItMatters: String

    @Guide(description: "Concrete fix for the developer")
    let suggestedFix: String

    // MARK: Primary evidence — required; strictly validated against EvidenceBundle

    @Guide(description: "Verbatim text copied from tool output")
    let evidenceQuote: String

    @Guide(description: "Name of the tool that returned the evidence")
    let evidenceTool: String

    @Guide(description: "File path, plist key, or config location of the evidence")
    let evidenceLocation: String

    // MARK: Secondary evidence — used when a cross-source relationship supports the finding

    @Guide(description: "Verbatim quote from a second tool for cross-source findings; empty otherwise")
    let secondaryEvidenceQuote: String

    @Guide(description: "Tool for secondary evidence; empty when unused")
    let secondaryEvidenceTool: String

    @Guide(description: "Location of secondary evidence; empty when unused")
    let secondaryEvidenceLocation: String
}

/// The top-level generated response wrapping the candidate list.
@Generable
struct AIFindingList: Sendable {
    /// Capped at 3 per pass: each finding costs roughly 120 generated tokens
    /// across its twelve fields, and the pass shares one 4,096-token window
    /// with its instructions, tool definitions, and every tool result.
    @Guide(description: "Findings grounded in tool evidence. One well-supported finding over several weak ones. Empty array when nothing concerning was found.", .maximumCount(3))
    let findings: [AIFindingCandidate]
}
