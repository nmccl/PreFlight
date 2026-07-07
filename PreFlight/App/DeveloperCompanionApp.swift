import SwiftUI

@main
struct DeveloperCompanionApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(appState.settings.appearance.colorScheme)
        }
        #if os(macOS)
        Settings {
            SettingsView()
                .environment(appState)
        }
        #endif
    }
}

/// Hosts the navigation stack and gates the first launch behind onboarding.
struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var router = appState.router
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .project:
                        ProjectView()
                    case .analysis:
                        AnalysisView()
                    case .results:
                        ResultsView()
                    }
                }
        }
        .sheet(isPresented: showsOnboarding) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
    }

    private var showsOnboarding: Binding<Bool> {
        Binding(
            get: { !appState.settings.hasCompletedOnboarding },
            set: { appState.settings.hasCompletedOnboarding = !$0 }
        )
    }
}
