import SwiftUI

/// How serious a finding is for App Review, from guaranteed rejection to nice-to-have.
enum Severity: String, Codable, CaseIterable, Sendable {
    case critical
    case warning
    case suggestion
}

extension Severity {
    var displayName: String {
        switch self {
        case .critical: "Critical"
        case .warning: "Warning"
        case .suggestion: "Suggestion"
        }
    }

    var systemImage: String {
        switch self {
        case .critical: "exclamationmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .suggestion: "lightbulb.fill"
        }
    }

    var color: Color {
        switch self {
        case .critical: .red
        case .warning: .orange
        case .suggestion: .blue
        }
    }

    /// Points removed from a category's score for each finding of this severity.
    var pointDeduction: Int {
        switch self {
        case .critical: 25
        case .warning: 10
        case .suggestion: 3
        }
    }

    /// Rough time to resolve one finding, used for the report's estimated fix time.
    var estimatedFixMinutes: Int {
        switch self {
        case .critical: 30
        case .warning: 15
        case .suggestion: 5
        }
    }
}

extension Severity: Comparable {
    private var sortOrder: Int {
        switch self {
        case .critical: 0
        case .warning: 1
        case .suggestion: 2
        }
    }

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}
