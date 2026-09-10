import SwiftUI

/// The dynamic loading screen: a live checklist of analyzer stages plus a
/// rotating status line while the engine runs.
struct AnalysisView: View {
    @Environment(AppState.self) private var appState
    @State private var statusIndex = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let deterministicMessages = [
        "Reading project.pbxproj…",
        "Scanning source files…",
        "Checking privacy manifest…",
        "Reviewing build settings…",
        "Looking for common review blockers…",
    ]

    private static let aiMessages = [
        "Calling Apple Intelligence…",
        "Scanning source code…",
        "Checking privacy manifest…",
        "Reviewing entitlements…",
        "Analyzing usage descriptions…",
        "Cross-referencing app configuration…",
        "Verifying IAP configuration…",
        "Generating semantic insights…",
    ]

    private var currentMessages: [String] {
        switch appState.aiInvestigationStage {
        case .running:
            return Self.aiMessages
        case .complete:
            return ["Analysis complete."]
        case .idle:
            return Self.deterministicMessages
        }
    }

    private var orderedCategories: [AnalysisCategory] {
        AnalysisCategory.allCases.filter { appState.analysisStages.keys.contains($0) }
    }

    private var showAIRow: Bool {
        appState.aiInvestigationStage != .idle
    }

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Text("Analyzing \(appState.currentProject?.name ?? "Project")")
                    .font(.title.bold())

                Text(currentMessages[statusIndex % currentMessages.count])
                    .foregroundStyle(.secondary)
                    .id(statusIndex)
                    .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 16) {
                ForEach(orderedCategories, id: \.self) { category in
                    stageRow(for: category)
                }
                if showAIRow {
                    Divider()
                    aiInvestigationRow()
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
                withAnimation(reduceMotion ? nil : .smooth) {
                    statusIndex += 1
                }
            }
        }
        .onChange(of: appState.aiInvestigationStage) { _, newStage in
            if case .running = newStage {
                withAnimation(reduceMotion ? nil : .smooth) { statusIndex = 0 }
            }
        }
    }

    private func stageRow(for category: AnalysisCategory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.systemImage)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(category.displayName)

            Spacer(minLength: 32)

            stageIndicator(for: appState.analysisStages[category] ?? .pending)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stageRowLabel(for: category))
    }

    private func stageRowLabel(for category: AnalysisCategory) -> String {
        switch appState.analysisStages[category] ?? .pending {
        case .pending:  return "\(category.displayName), pending"
        case .running:  return "\(category.displayName), analyzing"
        case .finished: return "\(category.displayName), complete"
        }
    }

    private func aiInvestigationRow() -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text("Apple Intelligence")

            Spacer(minLength: 32)

            aiStageIndicator()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(aiRowLabel)
    }

    private var aiRowLabel: String {
        switch appState.aiInvestigationStage {
        case .idle:               return "Apple Intelligence, pending"
        case .running:            return "Apple Intelligence, analyzing"
        case .complete(let count): return count > 0
            ? "Apple Intelligence, complete, \(count) finding\(count == 1 ? "" : "s")"
            : "Apple Intelligence, complete"
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
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func aiStageIndicator() -> some View {
        switch appState.aiInvestigationStage {
        case .idle:
            EmptyView()
        case .running:
            ProgressView()
                .controlSize(.small)
        case .complete(let count):
            HStack(spacing: 6) {
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
        }
    }
}
