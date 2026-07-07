import Foundation

/// The five areas the analyzer engine inspects.
enum AnalysisCategory: String, Codable, CaseIterable, Sendable {
    case project
    case metadata
    case privacy
    case storeKit
    case review
}

extension AnalysisCategory {
    var displayName: String {
        switch self {
        case .project: "Project Configuration"
        case .metadata: "App Store Metadata"
        case .privacy: "Privacy"
        case .storeKit: "StoreKit"
        case .review: "Review Readiness"
        }
    }

    var systemImage: String {
        switch self {
        case .project: "hammer.fill"
        case .metadata: "doc.text.fill"
        case .privacy: "hand.raised.fill"
        case .storeKit: "cart.fill"
        case .review: "checkmark.seal.fill"
        }
    }

    /// Relative influence on the overall Release Readiness score. Weights sum to 100.
    var weight: Int {
        switch self {
        case .project: 25
        case .privacy: 25
        case .review: 20
        case .metadata: 15
        case .storeKit: 15
        }
    }
}
