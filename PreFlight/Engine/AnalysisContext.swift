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
}

/// The parts of an Info.plist that analyzers care about, extracted into plain
/// values instead of carrying non-Sendable [String: Any] plist dictionaries.
struct InfoPlistData: Sendable {
    /// Top-level keys whose values are strings (usage descriptions, URLs...).
    let stringValues: [String: String]
    /// Every top-level key, regardless of value type.
    let presentKeys: Set<String>
}
