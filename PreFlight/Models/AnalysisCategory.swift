import Foundation

/// How Apple evaluates apps: deterministic configuration checks, the quality
/// of the experience itself, and App Review compliance. Categories group
/// under pillars; the report presents analysis pillar-first.
enum Pillar: String, Codable, CaseIterable, Sendable {
    case configuration
    case experience
    case compliance

    var displayName: String {
        switch self {
        case .configuration: "Configuration"
        case .experience: "Experience"
        case .compliance: "Compliance"
        }
    }
}

/// The areas the analyzer engine inspects.
enum AnalysisCategory: String, Codable, CaseIterable, Sendable {
    case project
    case metadata
    case privacy
    case storeKit
    case accessibility
    case deviceSupport
    case review
}

extension AnalysisCategory {
    var pillar: Pillar {
        switch self {
        case .project, .metadata, .privacy, .storeKit: .configuration
        case .accessibility, .deviceSupport: .experience
        case .review: .compliance
        }
    }

    var displayName: String {
        switch self {
        case .project: "Project Configuration"
        case .metadata: "App Store Metadata"
        case .privacy: "Privacy"
        case .storeKit: "StoreKit"
        case .accessibility: "Accessibility"
        case .deviceSupport: "Device Support"
        case .review: "Review Readiness"
        }
    }

    var systemImage: String {
        switch self {
        case .project: "hammer.fill"
        case .metadata: "doc.text.fill"
        case .privacy: "hand.raised.fill"
        case .storeKit: "cart.fill"
        case .accessibility: "accessibility"
        case .deviceSupport: "ipad.and.iphone"
        case .review: "checkmark.seal.fill"
        }
    }

    /// True for categories that require the $12.99 Pro unlock.
    var requiresPurchase: Bool {
        switch self {
        case .metadata, .storeKit: true
        default: false
        }
    }

    /// Relative influence on the overall Release Readiness score. The overall
    /// score normalizes by the total weight of the categories that ran, so
    /// these are proportions, not percentages.
    var weight: Int {
        switch self {
        case .project: 25
        case .privacy: 25
        case .review: 20
        case .metadata: 15
        case .storeKit: 15
        case .accessibility: 15
        case .deviceSupport: 10
        }
    }
}
