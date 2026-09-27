import Foundation
import Observation

/// Where each category is in the current analysis run, for the loading screen.
enum AnalysisStageState: Sendable {
    case pending
    case running
    case finished
}

/// The Apple Intelligence investigation phase, for the loading screen AI row.
enum AIInvestigationStage: Sendable, Equatable {
    case idle
    case running
    case complete(count: Int)
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
    let trial: TrialManager
    let reviewRequests: ReviewRequestService
    private let projectService = ProjectService()
    private let reportGenerator = AIReportGenerator()
    private let reportStore = ReportStore()

    var currentProject: Project?
    var currentReport: Report?
    var errorMessage: String?
    private(set) var analysisStages: [AnalysisCategory: AnalysisStageState] = [:]
    private(set) var aiInvestigationStage: AIInvestigationStage = .idle
    /// All stored reports for the current project, newest first (up to 10).
    private(set) var reportHistory: [Report] = []

    /// Full access = StoreKit entitlement confirmed OR 7-day trial still active.
    /// Purchase always takes precedence — trial expiry cannot revoke a purchased entitlement.
    var hasFullAccess: Bool { purchases.isPurchased || trial.isTrialActive }

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
        purchases: PurchaseService? = nil,
        trial: TrialManager? = nil,
        reviewRequests: ReviewRequestService? = nil
    ) {
        self.settings = settings ?? SettingsService()
        self.router = router ?? Router()
        self.recents = recents ?? RecentProjectsService()
        self.purchases = purchases ?? PurchaseService()
        self.trial = trial ?? TrialManager()
        self.reviewRequests = reviewRequests ?? ReviewRequestService()
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

        // All analyzers run regardless of purchase/trial state.
        // Access is gated at the project view before analysis starts.
        let analyzers: [any Analyzer] = [
            ProjectAnalyzer(),
            PrivacyAnalyzer(),
            AccessibilityAnalyzer(),
            DeviceSupportAnalyzer(),
            ReviewAnalyzer(),
            MetadataAnalyzer(),
            StoreKitAnalyzer(),
        ]

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
            let context = try await projectService.makeContext(for: project, credentials: settings.ascCredentials)
            var results = await engine.run(context: context) { [weak self] progress in
                Task { @MainActor in
                    self?.applyProgress(progress)
                }
            }

            // Semantic verification: heuristic candidates are checked against
            // compact facts about the app before they reach the report, so
            // false positives are dropped and unverifiable ones are downgraded
            // rather than shown as confident findings. Deterministic facts
            // bypass this entirely.
            if hasFullAccess && settings.isAIEnabled {
                results = await AIFindingVerifier().verify(
                    results: results,
                    facts: ApplicationFacts.build(from: context)
                )
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

            currentReport = report
            reportStore.save(report, forProjectPath: projectPath)

            // AI investigation runs when the user has full access (trial or purchase).
            // The loading screen shows a live Apple Intelligence row while this runs.
            if hasFullAccess {
                aiInvestigationStage = .running

                if settings.isAIEnabled {
                    print("[PreFlight AI] Starting investigation (hasFullAccess=true, isAIEnabled=true)")
                    let candidates = await AIInvestigator().investigate(
                        evidenceBundle: context.evidenceBundle,
                        projectName: project.name,
                        bundleID: project.bundleIdentifier,
                        deterministicFindings: report.allFindings
                    )
                    print("[PreFlight AI] Validator input: \(candidates.count) candidates")
                    let aiFindings = AIFindingValidator().validate(
                        candidates: candidates,
                        against: context.evidenceBundle,
                        existingFindings: report.allFindings
                    )
                    print("[PreFlight AI] Validator output: \(aiFindings.count) findings")
                    currentReport?.aiFindings = aiFindings
                    print("[PreFlight AI] currentReport.aiFindings assigned (\(aiFindings.count))")
                }

                let enrichedReport = currentReport ?? report
                let summary = await reportGenerator.summary(for: enrichedReport, aiEnabled: settings.isAIEnabled)
                currentReport?.aiSummary = summary
                aiInvestigationStage = .complete(count: currentReport?.aiFindings.count ?? 0)

                if let finished = currentReport {
                    reportStore.save(finished, forProjectPath: projectPath)
                }
            }

            reportHistory = reportStore.loadHistory(forProjectPath: projectPath)
            recents.noteAnalyzed(projectPath: projectPath, score: report.overallScore)
            // Counts toward the review prompt. Only successful runs count —
            // the catch below returns before reaching this.
            reviewRequests.noteAnalysisCompleted()

            // Brief pause so the completion state on the loading screen is readable.
            try? await Task.sleep(for: .seconds(1.0))
            router.showResults()
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
        aiInvestigationStage = .idle
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
