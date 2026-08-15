import Foundation

/// One category of checks. Analyzers never throw: internal failures become
/// warning findings so a single broken check can't kill the whole run.
protocol Analyzer: Sendable {
    var category: AnalysisCategory { get }
    func analyze(_ context: AnalysisContext) async -> AnalysisResult
}
