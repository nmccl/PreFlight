import Foundation
import FoundationModels

/// Runs the on-device Foundation Models investigation layer, producing
/// AIFindingCandidate values that are later validated by AIFindingValidator.
///
/// Evidence-first: the model is given tools that query the EvidenceBundle and is
/// instructed to call them before drawing any conclusions. The prompt deliberately
/// excludes raw source content — the model must use tools to see code.
///
/// Split into several small passes rather than one large session. The on-device
/// model has a 4,096-token context window, and instructions, every tool
/// definition, every tool result, and the generated output all share it. A single
/// session holding ten tool definitions plus accumulated results exhausts the
/// window before it can finish, which is what Apple means by "break your data
/// into smaller chunks, process each chunk in a separate session, and then
/// combine the results." Each pass here gets a fresh window, three or four
/// tools, and one narrow brief.
struct AIInvestigator: Sendable {

    func investigate(
        evidenceBundle: EvidenceBundle,
        projectName: String,
        bundleID: String?,
        deterministicFindings: [Finding]
    ) async -> [AIFindingCandidate] {

        guard SystemLanguageModel.default.availability == .available else {
            print("[PreFlight AI] Model unavailable — skipping investigation")
            return []
        }

        print("[PreFlight AI] Bundle: \(evidenceBundle.sourceFiles.count) src files, \(evidenceBundle.infoPlists.count) info plists, manifest=\(evidenceBundle.privacyManifest != nil), storekit=\(evidenceBundle.storeKitConfigs.count), asc=\(evidenceBundle.ascSnapshot != nil), deps=\(evidenceBundle.dependencies != nil)")

        let passes = InvestigationPass.all(for: evidenceBundle)
        let alreadyFound = alreadyDetectedBlock(deterministicFindings)

        var candidates: [AIFindingCandidate] = []
        for pass in passes {
            let passCandidates = await run(
                pass,
                evidenceBundle: evidenceBundle,
                projectName: projectName,
                bundleID: bundleID,
                alreadyFound: alreadyFound
            )
            candidates.append(contentsOf: passCandidates)
        }

        let deduped = deduplicated(candidates)
        print("[PreFlight AI] \(passes.count) passes produced \(candidates.count) candidates, \(deduped.count) after dedupe")
        return deduped
    }

    // MARK: - One pass

    /// Runs a single pass in its own session. A pass that fails — including by
    /// exhausting its context window — is logged and skipped so the remaining
    /// passes still contribute findings.
    private func run(
        _ pass: InvestigationPass,
        evidenceBundle: EvidenceBundle,
        projectName: String,
        bundleID: String?,
        alreadyFound: String
    ) async -> [AIFindingCandidate] {

        let session = LanguageModelSession(
            tools: pass.tools(for: evidenceBundle),
            instructions: instructions(for: pass, projectName: projectName)
        )
        // Instructions and tool definitions form a stable prefix; caching them
        // before the prompt lands cuts first-token latency.
        session.prewarm()

        let prompt = """
            Project: \(projectName)
            Bundle ID: \(bundleID ?? "(not set)")

            ALREADY-DETECTED FINDINGS — do not report these again:
            \(alreadyFound)

            \(pass.brief)
            """

        do {
            let response = try await session.respond(to: prompt, generating: AIFindingList.self)
            let found = response.content.findings
            print("[PreFlight AI] Pass '\(pass.name)': \(found.count) candidates")
            return found
        } catch LanguageModelError.contextSizeExceeded(let info) {
            print("[PreFlight AI] Pass '\(pass.name)' exceeded context (\(info.tokenCount)/\(info.contextSize) tokens) — skipping")
            return []
        } catch {
            print("[PreFlight AI] Pass '\(pass.name)' failed: \(error)")
            return []
        }
    }

    // MARK: - Prompt construction

    private func instructions(for pass: InvestigationPass, projectName: String) -> String {
        """
        You are an App Store Review compliance investigator for \(projectName). \
        Find issues likely to cause App Review rejection. Compliance only, not code quality.

        EVIDENCE RULES — mandatory:
        - Call a tool before reporting anything.
        - Never claim a pattern exists without searchSource confirming it in production code.
        - If searchSource says "found only in test files" or "not found", do NOT report it.
        - evidenceQuote must be verbatim from tool output.
        - If evidence is ambiguous, omit the finding. One well-supported finding beats three weak ones.

        \(pass.guidelines)
        """
    }

    /// Caps the already-detected list so it can't crowd out the context window.
    /// `allFindings` is already sorted severity-first.
    private func alreadyDetectedBlock(_ findings: [Finding]) -> String {
        let maxFindings = 6
        let capped = Array(findings.prefix(maxFindings))
        guard !capped.isEmpty else { return "  (none)" }

        let lines = capped.map { finding -> String in
            let ref = finding.guidelineReference.map { " [\($0)]" } ?? ""
            return "  - \(finding.title)\(ref)"
        }.joined(separator: "\n")

        let overflow = findings.count - capped.count
        return overflow > 0 ? lines + "\n  (+ \(overflow) more)" : lines
    }

    /// Passes are independent, so two of them can surface the same issue.
    /// Matches on title because that's what the user ultimately sees.
    private func deduplicated(_ candidates: [AIFindingCandidate]) -> [AIFindingCandidate] {
        var seen: Set<String> = []
        return candidates.filter { candidate in
            let key = candidate.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return seen.insert(key).inserted
        }
    }
}

// MARK: - Investigation passes

/// One focused investigation, sized to fit comfortably in a single context window.
private struct InvestigationPass: Sendable {
    let name: String
    let guidelines: String
    let brief: String
    let makeTools: @Sendable (EvidenceBundle) -> [any Tool]

    func tools(for bundle: EvidenceBundle) -> [any Tool] { makeTools(bundle) }

    /// The passes worth running for this bundle. A pass whose evidence is absent
    /// is skipped rather than burning a model round trip to discover that.
    static func all(for bundle: EvidenceBundle) -> [InvestigationPass] {
        var passes: [InvestigationPass] = [privacy, configuration]
        if !bundle.storeKitConfigs.isEmpty || bundle.ascSnapshot != nil {
            passes.insert(commerce, at: 1)
        }
        return passes
    }

    static let privacy = InvestigationPass(
        name: "privacy",
        guidelines: AIGuidelineKnowledge.privacy,
        brief: """
            Investigate privacy and data handling. Look for sensitive APIs used in \
            production source without a matching usage description, privacy manifest \
            declarations that contradict the source, and tracking declarations that \
            don't match the dependencies. Report at most 3 findings.
            """,
        makeTools: { bundle in
            [
                SearchSourceTool(evidenceBundle: bundle),
                ReadInfoPlistTool(evidenceBundle: bundle),
                ReadPrivacyManifestTool(evidenceBundle: bundle),
                ReadDependenciesTool(evidenceBundle: bundle),
            ]
        }
    )

    static let commerce = InvestigationPass(
        name: "commerce",
        guidelines: AIGuidelineKnowledge.commerce,
        brief: """
            Investigate purchases and review readiness. Look for product IDs in source \
            that don't match the StoreKit configuration, purchase flows that bypass \
            Apple IAP, links to external payment, purchase screens missing Privacy \
            Policy or Terms links, and missing App Store Connect review information. \
            Report at most 3 findings.
            """,
        makeTools: { bundle in
            [
                SearchSourceTool(evidenceBundle: bundle),
                ReadStoreKitConfigTool(evidenceBundle: bundle),
                ReadASCDataTool(evidenceBundle: bundle),
            ]
        }
    )

    static let configuration = InvestigationPass(
        name: "configuration",
        guidelines: AIGuidelineKnowledge.configuration,
        brief: """
            Investigate configuration and capabilities. Look for entitlements declared \
            but never used in production source, features gated behind build \
            configuration that change behavior in Release, and sign-in flows without \
            account deletion. Report at most 3 findings.
            """,
        makeTools: { bundle in
            [
                SearchSourceTool(evidenceBundle: bundle),
                ReadEntitlementsTool(evidenceBundle: bundle),
                ReadBuildSettingsTool(evidenceBundle: bundle),
            ]
        }
    )
}
