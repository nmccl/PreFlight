import Foundation

/// Whether a finding is a verified fact or a heuristic guess. Deterministic
/// analyzers report facts; source-scanning heuristics report observations,
/// and observations are never presented as guaranteed App Review failures.
enum FindingConfidence: String, Codable, Sendable {
    case fact
    case observation
}

/// How likely a finding is to actually impact App Review — separate from
/// severity, which measures how serious the issue is if true.
enum RejectionLikelihood: String, Codable, CaseIterable, Sendable {
    case certain
    case likely
    case possible

    var displayName: String {
        switch self {
        case .certain: "Certain rejection"
        case .likely: "Likely rejection"
        case .possible: "Possible rejection"
        }
    }
}

/// A single issue discovered by an analyzer, written to read like feedback
/// from an App Review engineer rather than a compiler diagnostic.
struct Finding: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let category: AnalysisCategory
    let severity: Severity
    let confidence: FindingConfidence
    let rejectionLikelihood: RejectionLikelihood?
    let title: String
    let detail: String
    /// The App Review framing: why a reviewer cares about this.
    let whyItMatters: String?
    /// What the analyzer actually observed (paths, matched patterns, locales).
    let evidence: String?
    /// App Review guideline number, e.g. "3.1.1".
    let guidelineReference: String?
    let suggestedFix: String
    /// Per-finding estimate; when nil, the severity default applies.
    let estimatedFixMinutes: Int?
    let affectedPath: String?

    init(
        id: UUID = UUID(),
        category: AnalysisCategory,
        severity: Severity,
        confidence: FindingConfidence,
        rejectionLikelihood: RejectionLikelihood? = nil,
        title: String,
        detail: String,
        whyItMatters: String? = nil,
        evidence: String? = nil,
        guidelineReference: String? = nil,
        suggestedFix: String,
        estimatedFixMinutes: Int? = nil,
        affectedPath: String? = nil
    ) {
        self.id = id
        self.category = category
        // An observation is a heuristic guess, so it can never claim to be a
        // guaranteed failure: critical severity and certain rejection are
        // reserved for facts.
        if confidence == .observation {
            self.severity = severity == .critical ? .warning : severity
            self.rejectionLikelihood = rejectionLikelihood == .certain ? .likely : rejectionLikelihood
        } else {
            self.severity = severity
            self.rejectionLikelihood = rejectionLikelihood
        }
        self.confidence = confidence
        self.title = title
        self.detail = detail
        self.whyItMatters = whyItMatters
        self.evidence = evidence
        self.guidelineReference = guidelineReference
        self.suggestedFix = suggestedFix
        self.estimatedFixMinutes = estimatedFixMinutes
        self.affectedPath = affectedPath
    }
}

extension Finding {
    /// The fix-time estimate used in report totals: the finding's own
    /// estimate when set, otherwise the severity default.
    var effectiveFixMinutes: Int {
        estimatedFixMinutes ?? severity.estimatedFixMinutes
    }
}
