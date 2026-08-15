import SwiftUI

/// The dynamic loading screen: a live checklist of analyzer stages plus a
/// rotating status line while the engine runs.
struct AnalysisView: View {
    @Environment(AppState.self) private var appState
    @State private var statusIndex = 0

    private static let statusMessages = [
        "Reading project.pbxproj…",
        "Scanning source files…",
        "Checking privacy manifest…",
        "Reviewing build settings…",
        "Looking for common review blockers…",
    ]

    private var orderedCategories: [AnalysisCategory] {
        AnalysisCategory.allCases.filter { appState.analysisStages.keys.contains($0) }
    }

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Text("Analyzing \(appState.currentProject?.name ?? "Project")")
                    .font(.title.bold())

                Text(Self.statusMessages[statusIndex])
                    .foregroundStyle(.secondary)
                    .id(statusIndex)
                    .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 16) {
                ForEach(orderedCategories, id: \.self) { category in
                    stageRow(for: category)
                }
            }
            .padding(24)
            .frame(width: 340)
            .glassEffect(in: .rect(cornerRadius: 20))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.4))
                withAnimation(.smooth) {
                    statusIndex = (statusIndex + 1) % Self.statusMessages.count
                }
            }
        }
    }

    private func stageRow(for category: AnalysisCategory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.systemImage)
                .foregroundStyle(.tint)
                .frame(width: 24)

            Text(category.displayName)

            Spacer(minLength: 32)

            stageIndicator(for: appState.analysisStages[category] ?? .pending)
        }
    }

    @ViewBuilder
    private func stageIndicator(for state: AnalysisStageState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle.dotted")
                .foregroundStyle(.quaternary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
        }
    }
}
