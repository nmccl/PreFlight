import Foundation

/// Everything the analyzers need, gathered once per run so no analyzer has to
/// re-parse the project. Fully value-typed to stay Sendable under strict
/// concurrency.
struct AnalysisContext: Sendable {
    let project: Project
    let targets: [TargetInfo]
    /// Info.plist content per application target name.
    let infoPlists: [String: InfoPlistData]
    let sourceFileURLs: [URL]
    let resourceFileURLs: [URL]
    /// nil when the user hasn't configured App Store Connect; the
    /// MetadataAnalyzer skips in that case.
    let ascCredentials: ASCCredentials?
    /// Structured evidence collected once per run; shared by all analyzers
    /// and (in Phase B) the AI investigation layer.
    let evidenceBundle: EvidenceBundle
}

/// The parts of an Info.plist that analyzers care about, extracted into plain
/// values instead of carrying non-Sendable [String: Any] plist dictionaries.
struct InfoPlistData: Sendable {
    /// Top-level keys whose values are strings (usage descriptions, URLs...).
    let stringValues: [String: String]
    /// Every top-level key, regardless of value type.
    let presentKeys: Set<String>
}

extension AnalysisContext {
    /// Concatenates all source files into one searchable string.
    /// Uses the pre-read EvidenceBundle so files are not re-read from disk on
    /// each call. Unreadable files were already excluded when the bundle was built.
    func combinedSource() -> String {
        evidenceBundle.sourceFiles
            .map(\.content)
            .joined(separator: "\n")
    }

    /// Like combinedSource but excludes test/mock/spec files.
    /// Use for entitlement and capability checks — test files may import frameworks
    /// the production app never uses, causing false non-matches.
    func productionSource() -> String {
        evidenceBundle.sourceFiles
            .filter { !$0.isTestFile }
            .map(\.content)
            .joined(separator: "\n")
    }

    /// The application's own source: no tests, no vendored dependencies.
    /// Use when the literal text is itself the issue (placeholder copy,
    /// hardcoded URLs) — string literals are preserved.
    func applicationSource() -> String {
        evidenceBundle.sourceFiles
            .filter(\.isApplicationCode)
            .map(\.content)
            .joined(separator: "\n")
    }

    /// The application's own source with comments and string-literal contents
    /// removed. Use whenever a keyword match is meant to prove the app *calls*
    /// something, so a rule quoted in a comment or a pattern stored in a string
    /// can't masquerade as real usage.
    func applicationCode() -> String {
        SourceEvidence.codeOnly(applicationSource())
    }

    /// Platforms the app targets, for gating platform-specific checks.
    var platforms: TargetPlatforms {
        TargetPlatforms(appTargets: targets.filter(\.isApplication))
    }
}
