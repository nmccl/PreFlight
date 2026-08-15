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
    /// Concatenates all readable source files into one searchable string.
    /// Unreadable files are skipped rather than failing the run.
    func combinedSource() -> String {
        var combined = ""
        for url in sourceFileURLs {
            if let contents = try? String(contentsOf: url, encoding: .utf8) {
                combined.append(contents)
                combined.append("\n")
            }
        }
        return combined
    }
}
