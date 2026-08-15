import Foundation
import Observation

/// Where each category is in the current analysis run, for the loading screen.
enum AnalysisStageState: Sendable {
    case pending
    case running
    case finished
}

/// The app's single source of truth, created once at launch and shared with
/// every view through the SwiftUI environment.
@MainActor
@Observable
final class AppState {
    let settings: SettingsService
    let router: Router
    let recents: RecentProjectsService
    let purchases: PurchaseService
    private let projectService = ProjectService()
    private let reportGenerator = AIReportGenerator()
    private let reportStore = ReportStore()

    var currentProject: Project?
    var currentReport: Report?
    var errorMessage: String?
    private(set) var analysisStages: [AnalysisCategory: AnalysisStageState] = [:]
    /// All stored reports for the current project, newest first (up to 10).
    private(set) var reportHistory: [Report] = []

    /// Holds the sandbox grant for the open project so files stay readable
    /// for the whole session; released in closeProject().
    private var securityScopedURL: URL?

    // Defaults are nil because default-argument expressions evaluate outside
    // the main actor; the real instances are created here, inside actor isolation.
    init(
        settings: SettingsService? = nil,
        router: Router? = nil,
        recents: RecentProjectsService? = nil,
        purchases: PurchaseService? = nil
    ) {
        self.settings = settings ?? SettingsService()
        self.router = router ?? Router()
        self.recents = recents ?? RecentProjectsService()
        self.purchases = purchases ?? PurchaseService()
    }

    func openProject(at url: URL) {
        closeProject()
        let hasScope = url.startAccessingSecurityScopedResource()
        do {
            let project = try projectService.openProject(at: url)
            currentProject = project
            securityScopedURL = hasScope ? url : nil
            recents.noteOpened(project)
            // Restore the previous report, if any, so yesterday's findings
            // are one click away.
            currentReport = reportStore.load(forProjectPath: project.projectFileURL.path)
            reportHistory = reportStore.loadHistory(forProjectPath: project.projectFileURL.path)
            router.showProject()
        } catch {
            if hasScope {
                url.stopAccessingSecurityScopedResource()
            }
            errorMessage = error.localizedDescription
        }
    }

    func openRecent(_ recent: RecentProject) {
        do {
            let url = try recents.resolveURL(for: recent)
            openProject(at: url)
        } catch {
            errorMessage = "This project could not be found. It may have been moved or deleted."
        }
    }

    func startAnalysis() async {
        guard let project = currentProject else { return }
        let projectPath = project.projectFileURL.path

        // Paid analyzers (Metadata + StoreKit) only run after the Pro unlock.
        // Free users still get Project, Privacy, Accessibility, DeviceSupport, Review.
        var analyzers: [any Analyzer] = [
            ProjectAnalyzer(),
            PrivacyAnalyzer(),
            AccessibilityAnalyzer(),
            DeviceSupportAnalyzer(),
            ReviewAnalyzer(),
        ]
        if purchases.isPurchased {
            analyzers += [MetadataAnalyzer(), StoreKitAnalyzer()]
        }

        let engine = AnalyzerEngine(analyzers: analyzers)
        analysisStages = Dictionary(
            uniqueKeysWithValues: engine.analyzers.map { ($0.category, AnalysisStageState.pending) }
        )
        router.showAnalysis()

        do {
            let context = try projectService.makeContext(for: project, credentials: settings.ascCredentials)
            let results = await engine.run(context: context) { [weak self] progress in
                Task { @MainActor in
                    self?.applyProgress(progress)
                }
            }
            let report = Report(project: project, results: results)

            // Give the loading screen a beat so stage changes stay readable.
            try? await Task.sleep(for: .seconds(1.0))

            currentReport = report
            reportStore.save(report, forProjectPath: projectPath)
            reportHistory = reportStore.loadHistory(forProjectPath: projectPath)
            recents.noteAnalyzed(projectPath: projectPath, score: report.overallScore)
            router.showResults()

            // AI summary only generates for Pro users; free users see the locked state in ResultsView.
            // Re-save so the summary persists for next launch.
            if purchases.isPurchased {
                let summary = await reportGenerator.summary(for: report, aiEnabled: settings.isAIEnabled)
                currentReport?.aiSummary = summary
                if let finished = currentReport {
                    reportStore.save(finished, forProjectPath: projectPath)
                    reportHistory = reportStore.loadHistory(forProjectPath: projectPath)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            router.showProject()
        }
    }

    func closeProject() {
        if let securityScopedURL {
            securityScopedURL.stopAccessingSecurityScopedResource()
        }
        securityScopedURL = nil
        currentProject = nil
        currentReport = nil
        reportHistory = []
        analysisStages = [:]
    }

    func returnHome() {
        closeProject()
        router.popToHome()
    }

    private func applyProgress(_ progress: AnalysisProgress) {
        switch progress {
        case .started(let category):
            analysisStages[category] = .running
        case .finished(let category):
            analysisStages[category] = .finished
        }
    }
}
