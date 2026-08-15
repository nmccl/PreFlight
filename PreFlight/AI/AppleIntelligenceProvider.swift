import Foundation
import FoundationModels

/// Guided generation schema: the model must return exactly this shape,
/// so the UI never has to parse free-form text.
@Generable
struct GeneratedSummary {
    @Guide(description: "A 2-3 sentence plain-language assessment of how ready the app is for App Store submission")
    let overview: String

    @Guide(description: "Up to 3 highest-impact actions, most important first", .maximumCount(3))
    let topPriorities: [String]
}

/// Summarizes reports with the on-device Apple Intelligence model.
struct AppleIntelligenceProvider: AIProvider {
    let name = "Apple Intelligence"

    func availability() async -> AIAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            .available
        case .unavailable(.deviceNotEligible):
            .unavailable(reason: "This Mac doesn't support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            .unavailable(reason: "Apple Intelligence is turned off in System Settings.")
        case .unavailable(.modelNotReady):
            .unavailable(reason: "The on-device model is still downloading.")
        case .unavailable:
            .unavailable(reason: "Apple Intelligence is currently unavailable.")
        }
    }

    func generateSummary(from input: ReportSummaryInput) async throws -> ReportSummaryText {
        let session = LanguageModelSession(instructions: """
            You explain App Store review-readiness reports to the developer who ran them, \
            the way an experienced App Review engineer would. Be concise, factual, and \
            encouraging. Never invent findings that are not in the input, and never \
            suggest the score is different from the one given. Findings marked \
            "observation" are heuristic: describe them as things a reviewer may question, \
            never as certain rejections. Never describe the app as guaranteed to pass \
            review — automated checks cover only part of what Apple evaluates.
            """)

        let prompt = """
            Project: \(input.projectName)
            Release readiness score: \(input.overallScore) out of 100

            Category results:
            \(input.categoryLines.joined(separator: "\n"))

            Most important findings:
            \(input.topFindings.joined(separator: "\n"))

            Summarize this report and list the highest-impact fixes.
            """

        let response = try await session.respond(to: prompt, generating: GeneratedSummary.self)
        return ReportSummaryText(
            overview: response.content.overview,
            topPriorities: response.content.topPriorities,
            isAIGenerated: true
        )
    }
}
