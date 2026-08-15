import Foundation

/// Live updates for the analysis loading screen.
enum AnalysisProgress: Sendable {
    case started(AnalysisCategory)
    case finished(AnalysisCategory)
}

/// Runs all analyzers concurrently and collects their results.
struct AnalyzerEngine: Sendable {
    let analyzers: [any Analyzer]

    func run(
        context: AnalysisContext,
        progress: @escaping @Sendable (AnalysisProgress) -> Void
    ) async -> [AnalysisResult] {
        let results = await withTaskGroup(of: AnalysisResult.self) { group in
            for analyzer in analyzers {
                group.addTask {
                    progress(.started(analyzer.category))
                    let result = await analyzer.analyze(context)
                    progress(.finished(analyzer.category))
                    return result
                }
            }
            var collected: [AnalysisResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // Task-group completion order is nondeterministic; present categories
        // in their declared order.
        return results.sorted { lhs, rhs in
            categoryIndex(lhs.category) < categoryIndex(rhs.category)
        }
    }

    private func categoryIndex(_ category: AnalysisCategory) -> Int {
        AnalysisCategory.allCases.firstIndex(of: category) ?? 0
    }
}
