import Foundation
import FoundationModels

// MARK: - Output budget

/// Every tool result is appended to the session transcript and counts against
/// the model's 4,096-token context window for the rest of the session. A single
/// unbounded result can exhaust the window on its own, so each tool caps its
/// output here. Roughly 3–4 characters per token, so 900 characters ≈ 250 tokens.
enum ToolOutputBudget {
    static let small = 500
    static let medium = 700
    static let large = 900

    /// Truncates to `limit` characters on a line boundary where possible.
    static func cap(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let clipped = text.prefix(limit)
        let body = clipped.lastIndex(of: "\n").map { String(clipped[clipped.startIndex..<$0]) }
            ?? String(clipped)
        return body + "\n[... truncated to fit the model's context window]"
    }

    /// Truncates a single line so one very long line can't dominate a result.
    static func capLine(_ line: String, to limit: Int = 160) -> String {
        line.count > limit ? String(line.prefix(limit)) + "…" : line
    }
}

// MARK: - searchSource

/// Searches production source files for a text pattern and returns matching
/// lines with surrounding context. The model must call this before claiming
/// any pattern exists (or is absent) in source code.
struct SearchSourceTool: Tool {
    let name = "searchSource"
    let description = "Search production source files for a text pattern. Returns file paths, line numbers, and surrounding context. Call this before claiming any pattern exists or is absent in source code."

    @Generable
    struct Arguments {
        @Guide(description: "Text to search for in source files")
        let pattern: String
    }

    let evidenceBundle: EvidenceBundle

    func call(arguments: Arguments) async throws -> String {
        let pattern = arguments.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return "Error: pattern must not be empty." }

        var productionHits: [String] = []
        var testOnlyFiles: [String] = []
        var vendoredOnlyFiles: [String] = []

        for file in evidenceBundle.sourceFiles {
            let lines = file.content.components(separatedBy: "\n")
            let matchingIndices = lines.indices.filter { lines[$0].contains(pattern) }
            guard !matchingIndices.isEmpty else { continue }

            if file.isVendored {
                vendoredOnlyFiles.append(file.relativePath)
            } else if file.isTestFile {
                testOnlyFiles.append(file.relativePath)
            } else {
                for index in matchingIndices.prefix(2) {
                    let context = contextLines(around: index, in: lines)
                    productionHits.append("\(file.relativePath):\(index + 1)\n\(context)")
                }
            }
        }

        if productionHits.isEmpty {
            if !vendoredOnlyFiles.isEmpty {
                let names = vendoredOnlyFiles.prefix(3).joined(separator: ", ")
                return "Pattern '\(pattern)' found only in third-party dependency code (\(names)) — this is not the application's own behavior. Do NOT report a finding."
            }
            if testOnlyFiles.isEmpty {
                return "Pattern '\(pattern)' not found in any source file."
            }
            let names = testOnlyFiles.prefix(3).joined(separator: ", ")
            return "Pattern '\(pattern)' found only in test files (\(names)) — not in production code."
        }

        let header = "Pattern '\(pattern)' found in \(productionHits.count) location(s):"
        let body = ([header] + productionHits.prefix(2)).joined(separator: "\n\n")
        return ToolOutputBudget.cap(body, to: ToolOutputBudget.large)
    }

    private func contextLines(around index: Int, in lines: [String]) -> String {
        let start = max(0, index - 1)
        let end = min(lines.count - 1, index + 1)
        return lines[start...end]
            .enumerated()
            .map { "\(start + $0.offset + 1): \(ToolOutputBudget.capLine($0.element))" }
            .joined(separator: "\n")
    }
}

// MARK: - readFile

/// Reads a specific source file from the evidence bundle. The model should
/// first call searchSource to get valid relative paths, then use this to
/// inspect the full file content.
struct ReadFileTool: Tool {
    let name = "readFile"
    let description = "Read the content of a source file. Only paths returned by searchSource are valid. Output is capped at 25 lines."

    @Generable
    struct Arguments {
        @Guide(description: "Relative file path exactly as returned by searchSource")
        let relativePath: String
    }

    let evidenceBundle: EvidenceBundle

    func call(arguments: Arguments) async throws -> String {
        let path = arguments.relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let file = evidenceBundle.sourceFiles.first(where: { $0.relativePath == path }) else {
            let available = evidenceBundle.sourceFiles.prefix(5).map(\.relativePath).joined(separator: ", ")
            return "File '\(path)' not found. Call searchSource first to get valid paths. Example paths: \(available)"
        }

        let lines = file.content.components(separatedBy: "\n")
        let capped = lines.prefix(25)
        let body = capped.enumerated()
            .map { "\($0.offset + 1): \(ToolOutputBudget.capLine($0.element))" }
            .joined(separator: "\n")
        let trailer = lines.count > 25 ? "\n[... \(lines.count - 25) more lines omitted]" : ""
        let testMarker = file.isTestFile ? " [TEST FILE — not production code]" : ""
        return ToolOutputBudget.cap("// \(file.relativePath)\(testMarker)\n\(body)\(trailer)", to: ToolOutputBudget.large)
    }
}

// MARK: - readInfoPlist

/// Reads Info.plist key-value pairs for one or all app targets.
struct ReadInfoPlistTool: Tool {
    let name = "readInfoPlist"
    let description = "Read Info.plist keys and string values for an app target. Use to verify usage descriptions, URL schemes, and other declared values."

    @Generable
    struct Arguments {
        @Guide(description: "Target name to read, or 'all' to read every target")
        let targetName: String
    }

    let evidenceBundle: EvidenceBundle

    func call(arguments: Arguments) async throws -> String {
        guard !evidenceBundle.infoPlists.isEmpty else {
            return "No Info.plist data found in the project."
        }

        let targets: [(String, InfoPlistData)]
        if arguments.targetName.lowercased() == "all" {
            targets = evidenceBundle.infoPlists.sorted { $0.key < $1.key }
        } else if let plist = evidenceBundle.infoPlists[arguments.targetName] {
            targets = [(arguments.targetName, plist)]
        } else {
            let names = evidenceBundle.infoPlists.keys.sorted().joined(separator: ", ")
            return "Target '\(arguments.targetName)' not found. Available targets: \(names)"
        }

        let body = targets.map { target, plist in
            let strings = plist.stringValues.sorted { $0.key < $1.key }
                .map { "  \($0.key): \(ToolOutputBudget.capLine($0.value))" }
                .joined(separator: "\n")
            let nonStrings = plist.presentKeys.subtracting(plist.stringValues.keys).sorted()
            let extra = nonStrings.isEmpty ? "" : "\n  (non-string keys: \(nonStrings.joined(separator: ", ")))"
            return "Target: \(target)\n\(strings.isEmpty ? "  (no string values)" : strings)\(extra)"
        }.joined(separator: "\n\n")
        return ToolOutputBudget.cap(body, to: ToolOutputBudget.large)
    }
}

// MARK: - readEntitlements

/// Reads the entitlements declared for a target.
struct ReadEntitlementsTool: Tool {
    let name = "readEntitlements"
    let description = "Read the entitlements file for an app target. Use to verify which capabilities are declared."

    @Generable
    struct Arguments {
        @Guide(description: "Target name, or 'all' for every target")
        let targetName: String
    }

    let evidenceBundle: EvidenceBundle

    func call(arguments: Arguments) async throws -> String {
        guard !evidenceBundle.entitlements.isEmpty else {
            return "No entitlements files found in the project."
        }

        let targets: [(String, EvidenceEntitlements)]
        if arguments.targetName.lowercased() == "all" {
            targets = evidenceBundle.entitlements.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        } else if let ents = evidenceBundle.entitlements[arguments.targetName] {
            targets = [(arguments.targetName, ents)]
        } else {
            let names = evidenceBundle.entitlements.keys.sorted().joined(separator: ", ")
            return "Target '\(arguments.targetName)' not found. Available: \(names)"
        }

        let body = targets.map { target, ents in
            let keys = ents.keys.sorted { $0.key < $1.key }
                .map { "  \($0.key): \(ToolOutputBudget.capLine($0.value))" }
                .joined(separator: "\n")
            return "Target: \(target) (\(ents.path))\n\(keys.isEmpty ? "  (no entitlements)" : keys)"
        }.joined(separator: "\n\n")
        return ToolOutputBudget.cap(body, to: ToolOutputBudget.medium)
    }
}

// MARK: - readPrivacyManifest

/// Reads the PrivacyInfo.xcprivacy content.
struct ReadPrivacyManifestTool: Tool {
    let name = "readPrivacyManifest"
    let description = "Read the app's PrivacyInfo.xcprivacy declarations. Use to verify required-reason API entries and data type disclosures."

    @Generable
    struct Arguments {}

    let evidenceBundle: EvidenceBundle

    func call(arguments: Arguments) async throws -> String {
        guard let manifest = evidenceBundle.privacyManifest else {
            return "No PrivacyInfo.xcprivacy found in the project."
        }

        var lines: [String] = []
        lines.append("NSPrivacyTracking: \(manifest.privacyTracking)")

        if manifest.trackingDomains.isEmpty {
            lines.append("NSPrivacyTrackingDomains: (none)")
        } else {
            lines.append("NSPrivacyTrackingDomains: \(manifest.trackingDomains.sorted().joined(separator: ", "))")
        }

        if manifest.collectedDataTypes.isEmpty {
            lines.append("NSPrivacyCollectedDataTypes: (none declared)")
        } else {
            lines.append("NSPrivacyCollectedDataTypes: \(manifest.collectedDataTypes.sorted().joined(separator: ", "))")
        }

        if manifest.accessedAPITypes.isEmpty {
            lines.append("NSPrivacyAccessedAPITypes: (none declared)")
        } else {
            let apiLines = manifest.accessedAPITypes
                .sorted { $0.categoryKey < $1.categoryKey }
                .map { "  \($0.categoryKey): \($0.reasonCodes.joined(separator: ", "))" }
            lines.append("NSPrivacyAccessedAPITypes:\n\(apiLines.joined(separator: "\n"))")
        }

        return ToolOutputBudget.cap(lines.joined(separator: "\n"), to: ToolOutputBudget.medium)
    }
}

// MARK: - readASCData

/// Reads the App Store Connect metadata snapshot. Only available when ASC
/// credentials are configured and a snapshot was fetched for this run.
/// SECURITY: Never exposes ASC credentials, JWT tokens, or Keychain contents.
struct ReadASCDataTool: Tool {
    let name = "readASCData"
    let description = "Read App Store Connect metadata: privacy policy URL, support URL, app descriptions, review notes, and privacy declarations. Only available when ASC credentials are configured."

    @Generable
    struct Arguments {}

    let evidenceBundle: EvidenceBundle

    func call(arguments: Arguments) async throws -> String {
        guard let snapshot = evidenceBundle.ascSnapshot else {
            return "No App Store Connect data available. ASC credentials may not be configured, or the snapshot fetch failed."
        }

        var lines: [String] = ["App ID: \(snapshot.appID)", "Bundle ID: \(snapshot.bundleID)"]

        let ppURLs = snapshot.privacyPolicyURLs
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value ?? "(not set)")" }
        lines.append("Privacy Policy URLs:\n  " + ppURLs.joined(separator: "\n  "))

        let supportURLs = snapshot.supportURLs
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value ?? "(not set)")" }
        lines.append("Support URLs:\n  " + supportURLs.joined(separator: "\n  "))

        let descs = snapshot.descriptions
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \(($0.value ?? "(not set)").prefix(120))" }
        lines.append("App Descriptions (first 120 chars):\n  " + descs.joined(separator: "\n  "))

        if let detail = snapshot.reviewDetail {
            lines.append("Review Demo Account Required: \(detail.demoAccountRequired)")
            // Intentionally omit the actual account name/password — they are secrets.
            lines.append("Review Demo Account Provided: \(detail.demoAccountName.map { !$0.isEmpty } ?? false)")
            if let notes = detail.reviewNotes, !notes.isEmpty {
                lines.append("Review Notes: \(notes.prefix(200))")
            } else {
                lines.append("Review Notes: (not provided)")
            }
        } else {
            lines.append("Review Detail: (not configured)")
        }

        if snapshot.declaredPrivacyCategories.isEmpty {
            lines.append("ASC Privacy Declarations: (none)")
        } else {
            lines.append("ASC Privacy Declarations: \(snapshot.declaredPrivacyCategories.sorted().joined(separator: ", "))")
        }

        return ToolOutputBudget.cap(lines.joined(separator: "\n"), to: ToolOutputBudget.large)
    }
}

// MARK: - readBuildSettings

/// Reads build settings for a target and configuration. Returns only the subset
/// of settings relevant to App Review investigations.
struct ReadBuildSettingsTool: Tool {
    let name = "readBuildSettings"
    let description = "Read build settings for a target and configuration. Use to investigate conditional compilation flags, configuration-dependent features, and deployment settings."

    @Generable
    struct Arguments {
        @Guide(description: "Target name, or 'all' for all targets")
        let targetName: String

        @Guide(description: "Configuration name like 'Debug' or 'Release', or 'all' for all configurations")
        let configuration: String

        @Guide(description: "Specific setting key to look up (e.g. 'SWIFT_ACTIVE_COMPILATION_CONDITIONS'), or empty string to return all investigation-relevant settings")
        let settingKey: String
    }

    // Settings most relevant for App Review investigations
    private static let relevantKeys: Set<String> = [
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS",
        "GCC_PREPROCESSOR_DEFINITIONS",
        "OTHER_SWIFT_FLAGS",
        "TARGETED_DEVICE_FAMILY",
        "SWIFT_VERSION",
        "IPHONEOS_DEPLOYMENT_TARGET",
        "MACOSX_DEPLOYMENT_TARGET",
        "PRODUCT_BUNDLE_IDENTIFIER",
        "MARKETING_VERSION",
        "CURRENT_PROJECT_VERSION",
        "CODE_SIGN_ENTITLEMENTS",
        "ENABLE_TESTABILITY",
        "DEBUG_INFORMATION_FORMAT",
    ]

    let evidenceBundle: EvidenceBundle

    func call(arguments: Arguments) async throws -> String {
        guard !evidenceBundle.buildSettings.isEmpty else {
            return "No build settings found in the project."
        }

        let targetArg = arguments.targetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let configArg = arguments.configuration.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyArg = arguments.settingKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let targets: [(String, [String: [String: String]])]
        if targetArg.lowercased() == "all" {
            targets = evidenceBundle.buildSettings.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        } else if let settings = evidenceBundle.buildSettings[targetArg] {
            targets = [(targetArg, settings)]
        } else {
            let match = evidenceBundle.buildSettings.first { $0.key.lowercased() == targetArg.lowercased() }
            if let match {
                targets = [(match.key, match.value)]
            } else {
                let available = evidenceBundle.buildSettings.keys.sorted().joined(separator: ", ")
                return "Target '\(targetArg)' not found. Available: \(available)"
            }
        }

        var output: [String] = []
        for (target, configs) in targets {
            let configPairs: [(String, [String: String])]
            if configArg.lowercased() == "all" {
                configPairs = configs.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
            } else if let settings = configs[configArg] {
                configPairs = [(configArg, settings)]
            } else {
                let match = configs.first { $0.key.lowercased() == configArg.lowercased() }
                configPairs = match.map { [($0.key, $0.value)] } ?? []
            }

            for (config, settings) in configPairs {
                if !keyArg.isEmpty {
                    let value = settings[keyArg] ?? "(not set)"
                    output.append("\(target) / \(config) — \(keyArg) = \(value)")
                } else {
                    let filtered = settings
                        .filter { Self.relevantKeys.contains($0.key) }
                        .sorted { $0.key < $1.key }
                        .map { "  \($0.key) = \($0.value)" }
                    if filtered.isEmpty {
                        output.append("\(target) / \(config): (no investigation-relevant settings found)")
                    } else {
                        output.append("\(target) / \(config):\n\(filtered.joined(separator: "\n"))")
                    }
                }
            }
        }

        guard !output.isEmpty else { return "No matching build settings found." }
        return ToolOutputBudget.cap(output.joined(separator: "\n\n"), to: ToolOutputBudget.large)
    }
}

// MARK: - readLocalization

/// Reads localization files (.strings, .xcstrings). Helps investigate whether
/// user-facing functionality is incomplete or inconsistent across locales.
struct ReadLocalizationTool: Tool {
    let name = "readLocalization"
    let description = "Read localization files. Empty string lists all files; a locale code like 'en' or 'fr' reads that locale; a filename reads a specific file."

    @Generable
    struct Arguments {
        @Guide(description: "Empty string to list all localization files, a locale code ('en', 'fr'), or a filename ('Localizable.strings')")
        let query: String
    }

    let evidenceBundle: EvidenceBundle

    func call(arguments: Arguments) async throws -> String {
        guard !evidenceBundle.localizationFiles.isEmpty else {
            return "No localization files (.strings or .xcstrings) found in the project."
        }

        let query = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)

        if query.isEmpty {
            let list = evidenceBundle.localizationFiles
                .sorted { $0.relativePath < $1.relativePath }
                .map { "  \($0.relativePath)" }
                .joined(separator: "\n")
            return "Localization files (\(evidenceBundle.localizationFiles.count)):\n\(list)"
        }

        let matching = evidenceBundle.localizationFiles.filter { file in
            let path = file.relativePath
            return path.contains("/\(query).lproj/")
                || path.hasSuffix("/\(query)")
                || path.hasSuffix(query)
                || path.lowercased().contains(query.lowercased())
        }

        if matching.isEmpty {
            let examples = evidenceBundle.localizationFiles.prefix(4).map(\.relativePath).joined(separator: ", ")
            return "No localization files matching '\(query)'. Available: \(examples)"
        }

        let body = matching.prefix(1).map { file in
            let lines = file.content.components(separatedBy: "\n")
            let preview = lines.prefix(20).map { ToolOutputBudget.capLine($0) }.joined(separator: "\n")
            let trailer = lines.count > 20 ? "\n[... \(lines.count - 20) more lines]" : ""
            return "// \(file.relativePath)\n\(preview)\(trailer)"
        }.joined(separator: "\n\n---\n\n")
        return ToolOutputBudget.cap(body, to: ToolOutputBudget.medium)
    }
}

// MARK: - readDependencies

/// Reads Swift Package Manager dependencies from Package.resolved.
struct ReadDependenciesTool: Tool {
    let name = "readDependencies"
    let description = "Read Swift Package Manager dependencies. Use to check whether analytics, tracking, or payment-related packages are present."

    @Generable
    struct Arguments {}

    let evidenceBundle: EvidenceBundle

    func call(arguments: Arguments) async throws -> String {
        guard let deps = evidenceBundle.dependencies else {
            return "No Package.resolved found. The project may not use Swift Package Manager, or Package.resolved was not found in expected locations."
        }
        if deps.packageNames.isEmpty {
            return "Package.resolved found but contains no dependencies."
        }
        let names = deps.packageNames.sorted().map { "  • \($0)" }.joined(separator: "\n")
        let body = "Swift Package Manager dependencies (\(deps.packageNames.count)):\n\(names)"
        return ToolOutputBudget.cap(body, to: ToolOutputBudget.small)
    }
}

// MARK: - readStoreKitConfig

/// Reads StoreKit configuration files (.storekit) to verify product IDs and types.
struct ReadStoreKitConfigTool: Tool {
    let name = "readStoreKitConfig"
    let description = "Read StoreKit configuration files (.storekit). Use to verify product IDs, product types, and subscription configuration."

    @Generable
    struct Arguments {
        @Guide(description: "StoreKit config filename (e.g. 'Products.storekit'), or empty string to read the only config or list all if multiple exist")
        let filename: String
    }

    let evidenceBundle: EvidenceBundle

    func call(arguments: Arguments) async throws -> String {
        guard !evidenceBundle.storeKitConfigs.isEmpty else {
            return "No StoreKit configuration files (.storekit) found in the project."
        }

        let query = arguments.filename.trimmingCharacters(in: .whitespacesAndNewlines)

        let target: EvidenceStoreKitConfig?
        if query.isEmpty {
            target = evidenceBundle.storeKitConfigs.count == 1 ? evidenceBundle.storeKitConfigs[0] : nil
        } else {
            target = evidenceBundle.storeKitConfigs.first { $0.filename == query || $0.filename.contains(query) }
        }

        if let config = target {
            let lines = config.rawContent.components(separatedBy: "\n")
            let body = lines.prefix(25).map { ToolOutputBudget.capLine($0) }.joined(separator: "\n")
            let trailer = lines.count > 25 ? "\n[... \(lines.count - 25) more lines]" : ""
            return ToolOutputBudget.cap("// \(config.filename)\n\(body)\(trailer)", to: ToolOutputBudget.large)
        }

        let list = evidenceBundle.storeKitConfigs.map { "  \($0.filename)" }.joined(separator: "\n")
        return "Multiple StoreKit configs found — specify a filename:\n\(list)"
    }
}
