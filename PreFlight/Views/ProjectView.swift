import SwiftUI

/// Detail for the open project, with the Analyze action front and center.
struct ProjectView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let project = appState.currentProject {
            content(for: project)
        } else {
            ContentUnavailableView("No Project Open", systemImage: "folder.badge.questionmark")
        }
    }

    private func content(for project: Project) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                ProjectIconView(imageData: project.appIconImageData, cornerRadius: 20, symbolSize: 36)
                    .frame(width: 88, height: 88)

                VStack(spacing: 6) {
                    Text(project.name)
                        .font(.largeTitle.bold())

                    if let bundleIdentifier = project.bundleIdentifier {
                        Text(bundleIdentifier)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                detailChips(for: project)

                Button {
                    Task {
                        await appState.startAnalysis()
                    }
                } label: {
                    Label("Analyze", systemImage: "sparkle.magnifyingglass")
                        .font(.title3.bold())
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .padding(.top, 12)

                if let report = appState.currentReport {
                    Button {
                        appState.router.showResults()
                    } label: {
                        Label(
                            "Last report · \(report.generatedAt.formatted(date: .abbreviated, time: .shortened)) · \(report.overallScore)/100",
                            systemImage: "doc.text.magnifyingglass"
                        )
                    }
                    .buttonStyle(.glass)
                    .controlSize(.regular)

                    scoreDeltaBadge
                }

                if appState.reportHistory.count > 1 {
                    runHistory
                }

                if appState.settings.ascCredentials == nil {
                    Text("App Store metadata checks are skipped until App Store Connect credentials are added in Settings.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                } else {
                    Label("App Store Connect metadata checks enabled", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(40)
        }
        .navigationTitle(project.name)
    }

    @ViewBuilder
    private var scoreDeltaBadge: some View {
        let history = appState.reportHistory
        if history.count >= 2 {
            let delta = history[0].overallScore - history[1].overallScore
            let prevDate = history[1].generatedAt.formatted(date: .abbreviated, time: .omitted)
            HStack(spacing: 5) {
                Image(systemName: delta > 0 ? "arrow.up" : delta < 0 ? "arrow.down" : "minus")
                if delta == 0 {
                    Text("No change vs \(prevDate)")
                } else {
                    Text("\(delta > 0 ? "+" : "")\(delta) pts vs \(prevDate)")
                }
            }
            .font(.caption)
            .foregroundStyle(delta > 0 ? Color.green : delta < 0 ? Color.red : Color.secondary)
        }
    }

    private var runHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Runs")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ForEach(appState.reportHistory.prefix(5)) { report in
                HStack {
                    Text(report.generatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(report.overallScore)/100")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(scoreColor(report.overallScore))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 380)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case ..<60: .red
        case ..<85: .orange
        default: .green
        }
    }

    private func detailChips(for project: Project) -> some View {
        HStack(spacing: 8) {
            ForEach(project.deploymentTargets.sorted(by: { $0.key < $1.key }), id: \.key) { platform, version in
                Chip(text: "\(platform) \(version)+")
            }
            if !project.targetNames.isEmpty {
                Chip(text: "^[\(project.targetNames.count) target](inflect: true)")
            }
        }
    }
}

private struct Chip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary, in: .capsule)
    }
}
