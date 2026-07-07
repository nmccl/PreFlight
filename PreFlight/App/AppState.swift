import Foundation
import Observation

/// The app's single source of truth, created once at launch and shared with
/// every view through the SwiftUI environment.
@MainActor
@Observable
final class AppState {
    let settings: SettingsService
    let router: Router
    let recents: RecentProjectsService
    private let projectService = ProjectService()

    var currentProject: Project?
    var currentReport: Report?
    var errorMessage: String?

    /// Holds the sandbox grant for the open project so files stay readable
    /// for the whole session; released in closeProject().
    private var securityScopedURL: URL?

    // Defaults are nil because default-argument expressions evaluate outside
    // the main actor; the real instances are created here, inside actor isolation.
    init(
        settings: SettingsService? = nil,
        router: Router? = nil,
        recents: RecentProjectsService? = nil
    ) {
        self.settings = settings ?? SettingsService()
        self.router = router ?? Router()
        self.recents = recents ?? RecentProjectsService()
    }

    func openProject(at url: URL) {
        closeProject()
        let hasScope = url.startAccessingSecurityScopedResource()
        do {
            let project = try projectService.openProject(at: url)
            currentProject = project
            securityScopedURL = hasScope ? url : nil
            recents.noteOpened(project)
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

    func closeProject() {
        if let securityScopedURL {
            securityScopedURL.stopAccessingSecurityScopedResource()
        }
        securityScopedURL = nil
        currentProject = nil
        currentReport = nil
    }

    func returnHome() {
        closeProject()
        router.popToHome()
    }
}
