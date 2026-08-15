import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The report: score ring, AI summary, category breakdown, and findings.
struct ResultsView: View {
    @Environment(AppState.self) private var appState
    @State private var ringProgress: Double = 0
    @State private var didCopyChecklist = false
    @State private var showPaywall = false

    var body: some View {
        if let report = appState.currentReport {
            content(for: report)
        } else {
            ContentUnavailableView("No Report", systemImage: "doc.questionmark")
        }
    }

    private func content(for report: Report) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                scoreHeader(for: report)
                summaryCard(for: report)
                categoryBreakdown(for: report)
                findingsSections(for: report)
                manualChecklist(for: report)

//                Button {
//                    appState.returnHome()
//                } label: {
//                    Label("Back to Home", systemImage: "house")
//                        .padding(.horizontal, 8)
//                }
//                .buttonStyle(.glass)
//                .controlSize(.large)
//                .padding(.top, 8)
            }
            .padding(32)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .navigationTitle("Report")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    appState.returnHome()
                } label: {
                    Label("Home", systemImage: "chevron.left")
                }
                .help("Return to Home")
            }
            ToolbarItem {
                Button {
                    if appState.purchases.isPurchased {
                        copyChecklist(for: report)
                    } else {
                        showPaywall = true
                    }
                } label: {
                    Label(
                        didCopyChecklist ? "Copied" : "Copy Checklist",
                        systemImage: didCopyChecklist ? "checkmark" : (appState.purchases.isPurchased ? "list.clipboard" : "lock.fill")
                    )
                }
                .help(appState.purchases.isPurchased
                      ? "Copy the report as a Markdown fix checklist"
                      : "Unlock Full Analysis to copy the fix checklist")
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                ringProgress = Double(report.overallScore) / 100
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(purchases: appState.purchases)
        }
    }

    /// Puts the Markdown checklist on the pasteboard, with brief feedback.
    private func copyChecklist(for report: Report) {
        let markdown = ReportExporter.markdownChecklist(for: report)
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        #else
        UIPasteboard.general.string = markdown
        #endif
        didCopyChecklist = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopyChecklist = false
        }
    }

    // MARK: Score

    private func scoreHeader(for report: Report) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 12)
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(scoreColor(report.overallScore), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(report.overallScore)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Release Readiness")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 170, height: 170)

            if !report.allFindings.isEmpty {
                Label(
                    "Estimated fix time: \(report.estimatedFixTime.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))",
                    systemImage: "clock"
                )
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.quaternary.opacity(0.6), in: .capsule)
            }

            Text(coverageDescription(for: report))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The score only speaks for the checks that ran; say so right under it.
    private func coverageDescription(for report: Report) -> String {
        var text = "Based on \(report.totalChecksPerformed) automated checks"
        let skipped = report.skippedResults.count
        let locked = appState.purchases.isPurchased ? 0 : AnalysisCategory.allCases.filter(\.requiresPurchase).count
        let unchecked = skipped + locked
        if unchecked > 0 {
            text += " · \(unchecked) area\(unchecked == 1 ? "" : "s") not checked"
        }
        text += " · some review criteria need manual verification"
        return text
    }

    // MARK: Summary

    private func summaryCard(for report: Report) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Summary", systemImage: "sparkles")
                .font(.headline)

            if !appState.purchases.isPurchased {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.tertiary)
                        .frame(width: 22)
                    Text("On-device AI overview of your report's top priorities")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Unlock") { showPaywall = true }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            } else if let summary = report.aiSummary {
                Text(summary.overview)

                if !summary.topPriorities.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(summary.topPriorities.enumerated()), id: \.offset) { index, priority in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(index + 1).")
                                    .bold()
                                    .foregroundStyle(.tint)
                                Text(priority)
                            }
                        }
                    }
                }

                if !summary.isAIGenerated {
                    Text("Generated without Apple Intelligence")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating summary…")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    // MARK: Categories

    private func categoryBreakdown(for report: Report) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Pillar.allCases, id: \.self) { pillar in
                let results = report.results.filter { $0.category.pillar == pillar }
                let locked = lockedCategories(for: pillar)
                if !results.isEmpty || !locked.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(pillar.displayName)
                            .font(.headline)

                        ForEach(results, id: \.category) { result in
                            categoryRow(for: result)
                        }
                        ForEach(locked, id: \.self) { category in
                            lockedCategoryRow(for: category)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    private func lockedCategories(for pillar: Pillar) -> [AnalysisCategory] {
        guard !appState.purchases.isPurchased else { return [] }
        return AnalysisCategory.allCases.filter { $0.pillar == pillar && $0.requiresPurchase }
    }

    private func categoryRow(for result: AnalysisResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: result.category.systemImage)
                .foregroundStyle(.tint)
                .frame(width: 22)

            Text(result.category.displayName)

            Spacer()

            if result.wasSkipped {
                Text("Not checked")
                    .foregroundStyle(.tertiary)
                    .help(result.skipReason ?? "")
            } else {
                ProgressView(value: Double(result.score) / 100)
                    .tint(scoreColor(result.score))
                    .frame(width: 110)
                Text("\(result.score)/100")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .trailing)
            }
        }
    }

    private func lockedCategoryRow(for category: AnalysisCategory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.systemImage)
                .foregroundStyle(.tertiary)
                .frame(width: 22)

            Text(category.displayName)
                .foregroundStyle(.secondary)

            Spacer()

            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("Unlock") { showPaywall = true }
                .buttonStyle(.glass)
                .controlSize(.mini)
        }
    }

    // MARK: Findings

    @ViewBuilder
    private func findingsSections(for report: Report) -> some View {
        if report.allFindings.isEmpty {
            ContentUnavailableView {
                Label("No issues found", systemImage: "checkmark.seal.fill")
            } description: {
                Text("Everything PreFlight can check automatically passed. Apple reviews more than any tool can verify — walk through the checklist below before submitting.")
            }
        } else {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(Severity.allCases, id: \.self) { severity in
                    let findings = report.allFindings.filter { $0.severity == severity }
                    if !findings.isEmpty {
                        severitySection(severity, findings: findings)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func severitySection(_ severity: Severity, findings: [Finding]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: severity.systemImage)
                    .foregroundStyle(severity.color)
                Text(sectionTitle(for: severity))
                    .font(.headline)
                Text("\(findings.count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(severity.color.opacity(0.15), in: .capsule)
                    .foregroundStyle(severity.color)
            }

            ForEach(findings) { finding in
                FindingRow(finding: finding)
            }
        }
    }

    // MARK: Manual checklist

    /// Everything Apple reviews that PreFlight can't verify automatically —
    /// shown on every report so a clean score never reads as "guaranteed".
    private func manualChecklist(for report: Report) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Not Verified by PreFlight", systemImage: "checklist")
                .font(.headline)

            Text("Apple reviews these too, but they can't be checked automatically yet. Walk through them before submitting.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(ManualCheck.checklist(for: report)) { check in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "circle.dashed")
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.title)
                            .font(.body.weight(.medium))
                        Text(check.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    private func sectionTitle(for severity: Severity) -> String {
        switch severity {
        case .critical: "Critical Issues"
        case .warning: "Warnings"
        case .suggestion: "Suggestions"
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case ..<60: .red
        case ..<85: .orange
        default: .green
        }
    }
}

/// One expandable finding, presented like reviewer feedback: what was found,
/// why App Review cares, the evidence, and how to fix it.
private struct FindingRow: View {
    let finding: Finding
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text(finding.detail)
                    .foregroundStyle(.secondary)

                if let whyItMatters = finding.whyItMatters {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Why This Matters", systemImage: "checkmark.seal")
                            .font(.caption.bold())
                        Text(whyItMatters)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Label("Suggested Fix", systemImage: "wrench.and.screwdriver")
                        .font(.caption.bold())
                    Text(finding.suggestedFix)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.tint.opacity(0.08), in: .rect(cornerRadius: 8))

                if let evidence = finding.evidence {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Evidence", systemImage: "text.magnifyingglass")
                            .font(.caption.bold())
                        Text(evidence)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                if let path = finding.affectedPath {
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: finding.severity.systemImage)
                    .foregroundStyle(finding.severity.color)
                Text(finding.title)
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.leading)

                Spacer()

                if let likelihood = finding.rejectionLikelihood {
                    FindingTag(text: likelihood.displayName, color: tagColor(for: likelihood))
                }
                if let guideline = finding.guidelineReference {
                    FindingTag(text: "Guideline \(guideline)", color: .blue)
                }
                if finding.confidence == .observation {
                    FindingTag(text: "Heuristic", color: .secondary)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }

    private func tagColor(for likelihood: RejectionLikelihood) -> Color {
        switch likelihood {
        case .certain: .red
        case .likely: .orange
        case .possible: .yellow
        }
    }
}

/// A small capsule tag on a finding row (rejection likelihood, guideline, heuristic).
private struct FindingTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: .capsule)
            .foregroundStyle(color)
            .fixedSize()
    }
}
