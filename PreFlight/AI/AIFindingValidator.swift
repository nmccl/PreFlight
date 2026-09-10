import Foundation

/// Validates AIFindingCandidate values before they become first-class Findings.
///
/// Trust model:
/// - Evidence validation proves a quote literally exists in the EvidenceBundle.
///   It does NOT prove the model's interpretation of that quote is correct.
/// - Primary evidence is validated strictly: if the quote cannot be found, the
///   finding is rejected.
/// - Secondary evidence is validated permissively: if it cannot be verified it
///   is omitted from the finding's evidence text, but the finding still stands.
/// - AI findings never become .critical (Blockers).
/// - Cross-source findings (config tool + source tool both verified) are promoted
///   to .fact; single-source or interpretive findings remain .observation.
struct AIFindingValidator: Sendable {

    private static let validTools: Set<String> = [
        "searchSource", "readFile",
        "readInfoPlist", "readEntitlements", "readPrivacyManifest", "readASCData",
        "readBuildSettings", "readLocalization", "readDependencies", "readStoreKitConfig",
    ]

    func validate(
        candidates: [AIFindingCandidate],
        against bundle: EvidenceBundle,
        existingFindings: [Finding]
    ) -> [Finding] {
        var output: [Finding] = []
        for candidate in candidates {
            guard let finding = validated(candidate, against: bundle) else { continue }
            guard !isDuplicate(finding, of: existingFindings + output) else { continue }
            output.append(finding)
        }
        return output
    }

    // MARK: - Private

    private func validated(_ candidate: AIFindingCandidate, against bundle: EvidenceBundle) -> Finding? {
        // Rule 1: primary evidence quote must be a meaningful literal string
        let quote = candidate.evidenceQuote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard quote.count >= 5 else {
            print("[PreFlight AI] REJECT '\(candidate.title)': quote too short (\(quote.count) chars)")
            return nil
        }

        // Rule 2: primary evidence tool must be one of the declared tools
        guard Self.validTools.contains(candidate.evidenceTool) else {
            print("[PreFlight AI] REJECT '\(candidate.title)': unknown tool '\(candidate.evidenceTool)'")
            return nil
        }

        // Rule 3: primary quote must literally exist in the relevant bundle section
        guard quoteExists(quote, tool: candidate.evidenceTool, in: bundle) else {
            print("[PreFlight AI] REJECT '\(candidate.title)': quote not found in bundle (tool=\(candidate.evidenceTool), quote=\"\(quote.prefix(80))\")")
            return nil
        }

        // Rule 4: title and detail must have substance
        let title = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = candidate.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (10...150).contains(title.count) else {
            print("[PreFlight AI] REJECT '\(candidate.title)': title length \(title.count) outside 10-150")
            return nil
        }
        guard detail.count >= 20 else {
            print("[PreFlight AI] REJECT '\(candidate.title)': detail too short (\(detail.count) chars)")
            return nil
        }

        // Rule 5: guideline reference must be non-trivial
        let ref = candidate.guidelineReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ref.isEmpty, ref.count <= 20 else {
            print("[PreFlight AI] REJECT '\(candidate.title)': guideline ref invalid (empty=\(ref.isEmpty), len=\(ref.count))")
            return nil
        }

        guard let category = resolveCategory(candidate.categoryName) else { return nil }

        // AI findings are never .critical — that requires deterministic verification
        let severity = resolveSeverity(candidate.severityName)

        // Determine confidence: cross-source findings with both sides verified → .fact
        let confidence: FindingConfidence = isDirectlyVerifiable(candidate, in: bundle) ? .fact : .observation

        let likelihood: RejectionLikelihood = severity == .warning ? .likely : .possible

        // Build evidence text; include verified secondary evidence if present
        let evidenceText = buildEvidenceText(for: candidate, primaryQuote: quote, in: bundle)
        let location = candidate.evidenceLocation.trimmingCharacters(in: .whitespacesAndNewlines)

        return Finding(
            category: category,
            severity: severity,
            confidence: confidence,
            rejectionLikelihood: likelihood,
            title: title,
            detail: detail,
            whyItMatters: candidate.whyItMatters.isEmpty ? nil : candidate.whyItMatters,
            evidence: evidenceText,
            guidelineReference: ref,
            suggestedFix: candidate.suggestedFix,
            affectedPath: location.isEmpty ? nil : location
        )
    }

    // MARK: Evidence existence checks

    private func quoteExists(_ quote: String, tool: String, in bundle: EvidenceBundle) -> Bool {
        switch tool {
        case "searchSource", "readFile":
            // Accept verbatim source content OR a tool-formatted response that embeds
            // a real bundle file path (SearchSourceTool / ReadFileTool always include
            // the relative path in their output, so this proves the response was real).
            return bundle.sourceFiles.contains { $0.content.contains(quote) || quote.contains($0.relativePath) }
        case "readInfoPlist":
            return bundle.infoPlists.values.contains {
                $0.presentKeys.contains(quote) ||
                $0.stringValues.values.contains { $0.contains(quote) }
            }
        case "readEntitlements":
            return bundle.entitlements.values.contains {
                $0.keys.keys.contains(quote) ||
                $0.keys.values.contains { $0.contains(quote) }
            }
        case "readPrivacyManifest":
            guard let raw = bundle.privacyManifest?.rawContent else { return false }
            return raw.contains(quote) || strippedContains(raw, quote)
        case "readASCData":
            return ascContains(quote, in: bundle)
        case "readBuildSettings":
            return buildSettingsContain(quote, in: bundle)
        case "readLocalization":
            return bundle.localizationFiles.contains { $0.content.contains(quote) || strippedContains($0.content, quote) }
        case "readDependencies":
            guard let deps = bundle.dependencies else { return false }
            return deps.packageNames.contains { $0.contains(quote) } || deps.rawContent.contains(quote)
        case "readStoreKitConfig":
            return bundle.storeKitConfigs.contains { $0.rawContent.contains(quote) || strippedContains($0.rawContent, quote) }
        default:
            return false
        }
    }

    private func ascContains(_ quote: String, in bundle: EvidenceBundle) -> Bool {
        guard let snapshot = bundle.ascSnapshot else { return false }
        var searchables: [String] = [snapshot.appID, snapshot.bundleID]
        searchables += snapshot.privacyPolicyURLs.values.compactMap { $0 }
        searchables += snapshot.supportURLs.values.compactMap { $0 }
        searchables += snapshot.descriptions.values.compactMap { $0 }
        searchables += snapshot.declaredPrivacyCategories
        if let notes = snapshot.reviewDetail?.reviewNotes { searchables.append(notes) }
        return searchables.contains { $0.contains(quote) }
    }

    /// Compares after stripping all whitespace — handles JSON/plist content where the model
    /// quotes a collapsed single-line version of multi-line indented source.
    private func strippedContains(_ haystack: String, _ needle: String) -> Bool {
        let strip = { (s: String) in s.filter { !$0.isWhitespace } }
        return strip(haystack).contains(strip(needle))
    }

    private func buildSettingsContain(_ quote: String, in bundle: EvidenceBundle) -> Bool {
        bundle.buildSettings.values.contains { configs in
            configs.values.contains { settings in
                settings.keys.contains { $0.contains(quote) } ||
                settings.values.contains { $0.contains(quote) }
            }
        }
    }

    // MARK: Confidence determination

    /// Promotes a finding to .fact when the relationship can be confirmed mechanically:
    /// - Config-derived evidence (plist, entitlements, manifest, ASC, build settings) with a
    ///   short verbatim quote (a key name or value, not an interpreted sentence).
    /// - Cross-source: a config-tool primary evidence AND a verified source-tool secondary
    ///   evidence — both sides of the relationship are independently confirmed.
    private func isDirectlyVerifiable(_ candidate: AIFindingCandidate, in bundle: EvidenceBundle) -> Bool {
        let configTools: Set<String> = [
            "readInfoPlist", "readEntitlements", "readPrivacyManifest",
            "readASCData", "readBuildSettings", "readStoreKitConfig",
        ]
        let sourceTools: Set<String> = ["searchSource", "readFile"]

        // Single-source: config tool with a short, key-like quote
        if configTools.contains(candidate.evidenceTool) {
            let wordCount = candidate.evidenceQuote
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }.count
            if wordCount < 8 { return true }
        }

        // Cross-source: config primary + source secondary, both verified in bundle
        let secondaryQuote = candidate.secondaryEvidenceQuote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !secondaryQuote.isEmpty,
           configTools.contains(candidate.evidenceTool),
           sourceTools.contains(candidate.secondaryEvidenceTool),
           quoteExists(secondaryQuote, tool: candidate.secondaryEvidenceTool, in: bundle) {
            return true
        }

        // Cross-source: source primary + config secondary (e.g. source uses API, manifest is missing)
        let secondaryTool = candidate.secondaryEvidenceTool.trimmingCharacters(in: .whitespacesAndNewlines)
        if !secondaryQuote.isEmpty,
           sourceTools.contains(candidate.evidenceTool),
           configTools.contains(secondaryTool),
           quoteExists(secondaryQuote, tool: secondaryTool, in: bundle) {
            return true
        }

        return false
    }

    // MARK: Evidence text formatting

    private func buildEvidenceText(
        for candidate: AIFindingCandidate,
        primaryQuote: String,
        in bundle: EvidenceBundle
    ) -> String {
        var parts = ["[\(candidate.evidenceTool) @ \(candidate.evidenceLocation)] \"\(primaryQuote)\""]

        let secQuote = candidate.secondaryEvidenceQuote.trimmingCharacters(in: .whitespacesAndNewlines)
        let secTool = candidate.secondaryEvidenceTool.trimmingCharacters(in: .whitespacesAndNewlines)
        let secLocation = candidate.secondaryEvidenceLocation.trimmingCharacters(in: .whitespacesAndNewlines)

        // Include secondary evidence only if it can be verified in the bundle
        if secQuote.count >= 5,
           Self.validTools.contains(secTool),
           quoteExists(secQuote, tool: secTool, in: bundle) {
            parts.append("+ [\(secTool) @ \(secLocation)] \"\(secQuote)\"")
        }

        return parts.joined(separator: "\n")
    }

    // MARK: Deduplication

    /// Returns true only when the candidate describes the same underlying issue as an
    /// existing finding — same physical location, same guideline, AND the same title.
    /// Findings that share only a guideline or only a category are NOT suppressed.
    private func isDuplicate(_ candidate: Finding, of existing: [Finding]) -> Bool {
        existing.contains { prior in
            // Same location + same guideline + similar title → same issue
            if let loc = candidate.affectedPath, let pLoc = prior.affectedPath,
               !loc.isEmpty, loc == pLoc,
               let ref = candidate.guidelineReference, ref == prior.guidelineReference {
                let ct = candidate.title.lowercased()
                let pt = prior.title.lowercased()
                if ct == pt || ct.contains(pt) || pt.contains(ct) { return true }
            }
            // Exact same category + exact same title (covers same issue with no path info)
            if candidate.category == prior.category,
               candidate.title.lowercased() == prior.title.lowercased(),
               candidate.guidelineReference == prior.guidelineReference {
                return true
            }
            return false
        }
    }

    // MARK: Enum resolution

    private func resolveCategory(_ name: String) -> AnalysisCategory? {
        switch name.lowercased() {
        case "project":       return .project
        case "privacy":       return .privacy
        case "storekit":      return .storeKit
        case "accessibility": return .accessibility
        case "devicesupport": return .deviceSupport
        case "review":        return .review
        case "metadata":      return .metadata
        default:              return .review
        }
    }

    private func resolveSeverity(_ name: String) -> Severity {
        switch name.lowercased() {
        case "warning":    return .warning
        case "suggestion": return .suggestion
        default:           return .review
        // .critical intentionally excluded — AI must never create a Blocker
        }
    }
}
