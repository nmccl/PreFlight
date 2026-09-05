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
    /// Holds the sandbox grant for the project's parent directory (where Swift
    /// source, plists, and .storekit configs live). Without this, the file
    /// enumerator returns nil and all source-based analyzers skip.
    private var securityScopedParentURL: URL?

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

    func openProject(at url: URL, parentBookmarkData: Data? = nil, source: ProjectOpenSource = .filePicker) {
        closeProject()
        let hasScope = url.startAccessingSecurityScopedResource()

        // Activate parent directory scope before reading any project files.
        // When called from a fileImporter callback, makeParentBookmarkData creates
        // a fresh bookmark using the open panel's powerbox grant. When called from
        // openRecent, the previously stored bookmark is passed in directly.
        let effectiveParentData = parentBookmarkData
            ?? RecentProjectsService.makeParentBookmarkData(for: url)
        var parentScopeURL: URL? = nil
        if let parentData = effectiveParentData {
            var isStale = false
            if let pURL = try? URL(
                resolvingBookmarkData: parentData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), pURL.startAccessingSecurityScopedResource() {
                parentScopeURL = pURL
            }
        }

        do {
            let project = try projectService.openProject(at: url)
            currentProject = project
            securityScopedURL = hasScope ? url : nil
            securityScopedParentURL = parentScopeURL
            recents.noteOpened(project, parentBookmarkData: effectiveParentData)
            // Restore the previous report, if any, so yesterday's findings
            // are one click away.
            currentReport = reportStore.load(forProjectPath: project.projectFileURL.path)
            reportHistory = reportStore.loadHistory(forProjectPath: project.projectFileURL.path)
            router.showProject()
            AnalyticsService.shared.projectOpened(source: source)
        } catch {
            if hasScope {
                url.stopAccessingSecurityScopedResource()
            }
            parentScopeURL?.stopAccessingSecurityScopedResource()
            errorMessage = error.localizedDescription
        }
    }

    func openRecent(_ recent: RecentProject) {
        do {
            let url = try recents.resolveURL(for: recent)
            openProject(at: url, parentBookmarkData: recent.parentBookmarkData, source: .recents)
        } catch {
            errorMessage = "This project could not be found. It may have been moved or deleted."
        }
    }

    func startAnalysis() async {
        guard let project = currentProject else { return }
        let projectPath = project.projectFileURL.path
        let analysisStart = Date()

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

        AnalyticsService.shared.analysisStarted(
            isPro: purchases.isPurchased,
            analyzerCount: analyzers.count,
            hasASCCredentials: settings.ascCredentials != nil
        )

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

            AnalyticsService.shared.analysisCompleted(
                score: report.overallScore,
                criticalCount: report.allFindings.filter { $0.severity == .critical }.count,
                warningCount: report.allFindings.filter { $0.severity == .warning }.count,
                suggestionCount: report.allFindings.filter { $0.severity == .suggestion }.count,
                categoriesRun: results.filter { !$0.wasSkipped }.count,
                categoriesSkipped: results.filter { $0.wasSkipped }.count,
                durationSeconds: Date().timeIntervalSince(analysisStart),
                isPro: purchases.isPurchased
            )

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
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedParentURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
        securityScopedParentURL = nil
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
