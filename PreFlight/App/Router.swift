import Observation

/// The screens reachable from Home. Payloads (Project, Report) live in
/// AppState so routes stay cheap to hash and compare.
enum Route: Hashable {
    case project
    case analysis
    case results
}

@MainActor
@Observable
final class Router {
    var path: [Route] = []

    func showProject() {
        path = [.project]
    }

    func showAnalysis() {
        path = [.project, .analysis]
    }

    /// Replaces the analysis screen so Back from Results returns to the
    /// project, not the finished loading screen.
    func showResults() {
        path = [.project, .results]
    }

    func popToHome() {
        path.removeAll()
    }
}
