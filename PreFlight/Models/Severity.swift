import SwiftUI

/// How serious a finding is for App Review, ordered from most to least critical.
/// Internal case names are kept stable for Codable compatibility; display names
/// use the new terminology the UI presents.
enum Severity: String, Codable, CaseIterable, Sendable {
    case critical       // displayed as "Blocker"
    case warning        // displayed as "High Risk"
    case review         // displayed as "Review" — meaningful but needs user verification
    case suggestion     // displayed as "Recommendation"
}

extension Severity {
    var displayName: String {
        switch self {
        case .critical:   "Blocker"
        case .warning:    "High Risk"
        case .review:     "Review"
        case .suggestion: "Recommendation"
        }
    }

    var systemImage: String {
        switch self {
        case .critical:   "exclamationmark.octagon.fill"
        case .warning:    "exclamationmark.triangle.fill"
        case .review:     "magnifyingglass.circle.fill"
        case .suggestion: "lightbulb.fill"
        }
    }

    var color: Color {
        switch self {
        case .critical:   .red
        case .warning:    .orange
        case .review:     Color(hue: 0.13, saturation: 0.85, brightness: 0.9)
        case .suggestion: .blue
        }
    }

    /// Points removed from a category's score for each finding of this severity.
    var pointDeduction: Int {
        switch self {
        case .critical:   25
        case .warning:    10
        case .review:     5
        case .suggestion: 3
        }
    }

    /// Rough time to resolve one finding, used for the report's estimated fix time.
    var estimatedFixMinutes: Int {
        switch self {
        case .critical:   30
        case .warning:    15
        case .review:     10
        case .suggestion: 5
        }
    }
}

extension Severity: Comparable {
    private var sortOrder: Int {
        switch self {
        case .critical:   0
        case .warning:    1
        case .review:     2
        case .suggestion: 3
        }
    }

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}
