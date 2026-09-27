import SwiftUI
import StoreKit
#if os(macOS)
import AppKit
#endif

/// The report: score ring, readiness state, AI summary, category cards, and
/// a manual checklist. Category cards are the primary navigation surface —
/// they show status at a glance and expand into their findings.
struct ResultsView: View {
    @Environment(AppState.self) private var appState
    @State private var ringProgress: Double = 0
    @State private var didCopyChecklist = false
    @State private var showPaywall = false
    @State private var paywallSource: PaywallSource = .summaryCard
    @State private var expandedCategories: Set<AnalysisCategory> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        if let report = appState.currentReport {
            content(for: report)
        } else {
            ContentUnavailableView("No Report", systemImage: "doc.questionmark")
        }
    }

    private func content(for report: Report) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                scoreHeader(for: report)
                readinessBanner(for: report)
                summaryCard(for: report)
                categoryPillars(for: report)
                manualChecklist(for: report)
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
                    if appState.hasFullAccess {
                        copyChecklist(for: report)
                    } else {
                        paywallSource = .copyChecklist
                        showPaywall = true
                    }
                } label: {
                    Label(
                        didCopyChecklist ? "Copied" : "Copy Checklist",
                        systemImage: didCopyChecklist ? "checkmark" : (appState.hasFullAccess ? "list.clipboard" : "lock.fill")
                    )
                }
                .help(appState.hasFullAccess
                      ? "Copy the report as a Markdown fix checklist"
                      : "Unlock PreFlight to copy the fix checklist")
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 1.0)) {
                ringProgress = Double(report.overallScore) / 100
            }
            // Default: expand any category that has blockers or high-risk findings.
            expandedCategories = Set(
                report.results.filter { result in
                    result.categoryState == .blocked || result.categoryState == .highRisk
                }.map(\.category)
            )
            AnalyticsService.shared.resultsViewed(
                score: report.overallScore,
                findingsCount: report.allFindings.count,
                hasAISummary: report.aiSummary != nil
            )
        }
        .task {
            await maybeAskForReview()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(purchases: appState.purchases, source: paywallSource)
        }
    }

    /// Asks for a review after a completed analysis — the end of a sequence
    /// the person successfully finished, which is where Apple recommends
    /// asking. The delay keeps the sheet from landing on top of the report
    /// the moment it appears, and it's skipped entirely while the paywall
    /// could be showing.
    private func maybeAskForReview() async {
        guard appState.reviewRequests.shouldRequestReview(hasFullAccess: appState.hasFullAccess) else {
            return
        }
        try? await Task.sleep(for: .seconds(3))
        // Re-check: the sheet may have been presented during the delay.
        guard !showPaywall else { return }
        appState.reviewRequests.markRequested()
        requestReview()
    }

    private func copyChecklist(for report: Report) {
        let markdown = ReportExporter.markdownChecklist(for: report)
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        #else
        UIPasteboard.general.string = markdown
        #endif
        didCopyChecklist = true
        AnalyticsService.shared.checklistCopied()
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Release Readiness score")
            .accessibilityValue("\(report.overallScore) out of 100")

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

            Text("Checked against App Store Review Guidelines · September 2026")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func coverageDescription(for report: Report) -> String {
        var text = "Based on \(report.totalChecksPerformed) automated checks"
        let skipped = report.skippedResults.count
        if skipped > 0 {
            text += " · \(skipped) area\(skipped == 1 ? "" : "s") not checked"
        }
        text += " · some review criteria need manual verification"
        return text
    }

    // MARK: Readiness banner

    private func readinessBanner(for report: Report) -> some View {
        let state = report.readinessState
        return HStack(spacing: 12) {
            Image(systemName: state.systemImage)
                .font(.headline)
            Text(state.displayTitle)
                .font(.headline)
            Spacer()
            if report.blockerCount > 0 {
                severityCountPill(report.blockerCount, severity: .critical)
            }
            if report.highRiskCount > 0 {
                severityCountPill(report.highRiskCount, severity: .warning)
            }
            if report.reviewCount > 0 {
                severityCountPill(report.reviewCount, severity: .review)
            }
        }
        .foregroundStyle(state.foregroundColor)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(state.backgroundColor, in: .rect(cornerRadius: 14))
    }

    private func severityCountPill(_ count: Int, severity: Severity) -> some View {
        Text("\(count) \(severity.displayName)")
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(severity.color.opacity(0.18), in: .capsule)
            .foregroundStyle(severity.color)
    }

    // MARK: Summary

    private func summaryCard(for report: Report) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Summary", systemImage: "sparkles")
                .font(.headline)

            if !appState.hasFullAccess {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.tertiary)
                        .frame(width: 22)
                    Text("On-device AI overview of your report's top priorities")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Unlock") { paywallSource = .summaryCard; showPaywall = true }
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

    // MARK: Category cards

    private func categoryPillars(for report: Report) -> some View {
        VStack(spacing: 20) {
            ForEach(Pillar.allCases, id: \.self) { pillar in
                let results = report.results.filter { $0.category.pillar == pillar }
                if !results.isEmpty {
                    pillarSection(pillar: pillar, results: results, aiFindings: report.aiFindings)
                }
            }
        }
    }

    private func pillarSection(pillar: Pillar, results: [AnalysisResult], aiFindings: [Finding]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(pillar.displayName)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 8) {
                ForEach(results, id: \.category) { result in
                    categoryCard(for: result, aiFindings: aiFindings.filter { $0.category == result.category })
                }
            }
        }
    }

    private func categoryCard(for result: AnalysisResult, aiFindings: [Finding]) -> some View {
        let isExpanded = Binding(
            get: { expandedCategories.contains(result.category) },
            set: { if $0 { expandedCategories.insert(result.category) } else { expandedCategories.remove(result.category) } }
        )
        let allFindings = (result.findings + aiFindings).sorted { $0.severity < $1.severity }

        return DisclosureGroup(isExpanded: isExpanded) {
            if result.wasSkipped && allFindings.isEmpty {
                EmptyView()
            } else if allFindings.isEmpty {
                Label("No issues found in this category.", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(allFindings) { finding in
                        FindingRow(finding: finding)
                    }
                }
                .padding(.top, 6)
            }
        } label: {
            categoryCardLabel(for: result)
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }

    private func categoryCardLabel(for result: AnalysisResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: result.category.systemImage)
                .foregroundStyle(.tint)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text(result.category.displayName)
                .font(.body.weight(.medium))

            Spacer()

            if result.wasSkipped {
                Text(result.skipReason ?? "Not checked")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                categoryStateBadge(result.categoryState)
                Text("\(result.score)/100")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func categoryStateBadge(_ state: AnalysisResult.CategoryState) -> some View {
        switch state {
        case .blocked:
            categoryBadge("BLOCKED", color: .red)
        case .highRisk:
            categoryBadge("HIGH RISK", color: .orange)
        case .review:
            categoryBadge("REVIEW", color: Severity.review.color)
        case .recommendation:
            categoryBadge("SUGGESTIONS", color: .blue)
        case .clean:
            categoryBadge("OK", color: .green)
        }
    }

    private func categoryBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.bold())
            .tracking(0.5)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
    }

    // MARK: Manual checklist

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

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case ..<60: .red
        case ..<85: .orange
        default: .green
        }
    }
}

// MARK: - Readiness state display

private extension Report.ReadinessState {
    var displayTitle: String {
        switch self {
        case .notReady:          "NOT READY"
        case .needsAttention:    "NEEDS ATTENTION"
        case .reviewRecommended: "REVIEW RECOMMENDED"
        case .ready:             "READY FOR SUBMISSION"
        }
    }

    var systemImage: String {
        switch self {
        case .notReady:          "xmark.octagon.fill"
        case .needsAttention:    "exclamationmark.triangle.fill"
        case .reviewRecommended: "magnifyingglass.circle.fill"
        case .ready:             "checkmark.seal.fill"
        }
    }

    var foregroundColor: Color {
        switch self {
        case .notReady:          .red
        case .needsAttention:    .orange
        case .reviewRecommended: Severity.review.color
        case .ready:             .green
        }
    }

    var backgroundColor: Color {
        foregroundColor.opacity(0.12)
    }
}

// MARK: - Finding row

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
                    .accessibilityHidden(true)
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
        .padding(12)
        .background(.background.opacity(0.5), in: .rect(cornerRadius: 10))
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                AnalyticsService.shared.findingExpanded(severity: finding.severity.rawValue)
            }
        }
    }

    private func tagColor(for likelihood: RejectionLikelihood) -> Color {
        switch likelihood {
        case .certain: .red
        case .likely:  .orange
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
