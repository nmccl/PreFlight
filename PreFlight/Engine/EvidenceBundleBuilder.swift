import Foundation

/// Constructs an EvidenceBundle from pre-collected file lists and parsed targets.
/// Synchronous — the caller is responsible for supplying the async ASC snapshot.
struct EvidenceBundleBuilder: Sendable {

    func build(
        projectFileURL: URL,
        directoryURL: URL,
        sourceURLs: [URL],
        resourceURLs: [URL],
        localizationURLs: [URL],
        targets: [TargetInfo],
        infoPlists: [String: InfoPlistData],
        ascSnapshot: EvidenceASCSnapshot?
    ) -> EvidenceBundle {
        // Dependencies are resolved first so source files can be classified as
        // application code or vendored dependency code as they're read.
        let dependencies = findDependencies(projectFileURL: projectFileURL, directoryURL: directoryURL)
        let sourceFiles = buildSourceFiles(
            from: sourceURLs,
            relativeTo: directoryURL,
            packageRootDirectories: packageRootDirectories(in: directoryURL),
            resolvedPackageNames: Set((dependencies?.packageNames ?? []).map(SourceEvidence.normalizePackageName))
        )
        let buildSettings = Dictionary(uniqueKeysWithValues: targets.map { ($0.name, $0.buildSettings) })
        let entitlements = buildEntitlements(targets: targets, directoryURL: directoryURL)
        let privacyManifest = resourceURLs
            .first { $0.lastPathComponent == "PrivacyInfo.xcprivacy" }
            .flatMap { parsePrivacyManifest(at: $0) }
        let storeKitConfigs = resourceURLs
            .filter { $0.pathExtension.lowercased() == "storekit" }
            .compactMap { readStoreKitConfig(at: $0) }
        let localizationFiles = buildLocalizationFiles(from: localizationURLs, relativeTo: directoryURL)

        return EvidenceBundle(
            sourceFiles: sourceFiles,
            buildSettings: buildSettings,
            infoPlists: infoPlists,
            entitlements: entitlements,
            privacyManifest: privacyManifest,
            storeKitConfigs: storeKitConfigs,
            dependencies: dependencies,
            localizationFiles: localizationFiles,
            ascSnapshot: ascSnapshot
        )
    }

    // MARK: - Source Files

    private func buildSourceFiles(
        from urls: [URL],
        relativeTo base: URL,
        packageRootDirectories: Set<String>,
        resolvedPackageNames: Set<String>
    ) -> [EvidenceSourceFile] {
        urls.compactMap { url -> EvidenceSourceFile? in
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let relativePath = relativePathString(url, relativeTo: base)
            return EvidenceSourceFile(
                relativePath: relativePath,
                content: content,
                isTestFile: Self.detectIsTestFile(relativePath),
                isVendored: SourceEvidence.isVendored(
                    relativePath,
                    packageRootDirectories: packageRootDirectories,
                    resolvedPackageNames: resolvedPackageNames
                )
            )
        }
    }

    /// Top-level directories that contain their own `Package.swift`. Those are
    /// separate Swift packages checked in beside the project, so their source
    /// describes the dependency's behavior, not the application's.
    private func packageRootDirectories(in directoryURL: URL) -> Set<String> {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var roots: Set<String> = []
        for url in contents {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDirectory else { continue }
            if FileManager.default.fileExists(atPath: url.appending(path: "Package.swift").path) {
                roots.insert(url.lastPathComponent.lowercased())
            }
        }
        return roots
    }

    /// Classifies a file as a test file by inspecting its path components.
    /// Checks directory names (e.g. "MyAppTests/") and file suffixes (e.g. "FooTests.swift").
    static func detectIsTestFile(_ relativePath: String) -> Bool {
        let components = relativePath.components(separatedBy: "/")
        let directoryMatch = components.dropLast().contains { component in
            let lower = component.lowercased()
            return lower.hasSuffix("tests") || lower.hasSuffix("test")
                || lower == "mock" || lower == "mocks"
                || lower == "stub" || lower == "stubs"
                || lower == "spec" || lower == "specs"
        }
        if directoryMatch { return true }
        let filename = (components.last ?? "").lowercased()
        return filename.hasSuffix("test.swift") || filename.hasSuffix("tests.swift")
            || filename.hasSuffix("spec.swift") || filename.hasSuffix("specs.swift")
    }

    // MARK: - Entitlements

    /// Entitlements for each app target, from both sources that can produce
    /// them: an explicit `.entitlements` file and the `ENABLE_*` build settings
    /// Xcode synthesizes entitlements from. Most modern projects have only the
    /// second, so reading the file alone leaves the analyzers blind.
    private func buildEntitlements(targets: [TargetInfo], directoryURL: URL) -> [String: EvidenceEntitlements] {
        var result: [String: EvidenceEntitlements] = [:]
        for target in targets where target.isApplication {
            // Start from the build settings, then let an explicit file win on
            // any key it also defines.
            var keys = GeneratedEntitlements.keys(for: target)
            var sources = keys.isEmpty ? [] : ["Signing & Capabilities (build settings)"]

            let path = target.setting("CODE_SIGN_ENTITLEMENTS") ?? ""
            if !path.isEmpty,
               let data = try? Data(contentsOf: directoryURL.appending(path: path)),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                let fileKeys = plist.mapValues { value -> String in
                    switch value {
                    case let s as String: return s
                    case let b as Bool: return b ? "true" : "false"
                    case let a as [Any]: return a.map { String(describing: $0) }.joined(separator: ", ")
                    default: return String(describing: value)
                    }
                }
                keys.merge(fileKeys) { _, fromFile in fromFile }
                sources.append(path)
            }

            guard !keys.isEmpty else { continue }
            result[target.name] = EvidenceEntitlements(
                path: sources.joined(separator: " + "),
                keys: keys
            )
        }
        return result
    }

    // MARK: - Privacy Manifest

    private func parsePrivacyManifest(at url: URL) -> EvidencePrivacyManifest? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let rawContent = String(data: data, encoding: .utf8)
        else { return nil }

        let collectedEntries = plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? []
        let collectedTypes = collectedEntries.compactMap { $0["NSPrivacyCollectedDataType"] as? String }
        let privacyTracking = plist["NSPrivacyTracking"] as? Bool ?? false
        let trackingDomains = plist["NSPrivacyTrackingDomains"] as? [String] ?? []

        let apiEntries = plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        let accessedAPITypes: [EvidenceAPITypeEntry] = apiEntries.compactMap { entry in
            guard let key = entry["NSPrivacyAccessedAPIType"] as? String else { return nil }
            // The key is NSPrivacyAccessedAPITypeReasons. "...ReasonCodes" is not
            // a real key, so reading it silently yielded an empty array for every
            // entry in every project. See TN3183.
            let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
            return EvidenceAPITypeEntry(categoryKey: key, reasonCodes: reasons)
        }

        return EvidencePrivacyManifest(
            collectedDataTypes: collectedTypes,
            privacyTracking: privacyTracking,
            trackingDomains: trackingDomains,
            accessedAPITypes: accessedAPITypes,
            rawContent: rawContent
        )
    }

    // MARK: - StoreKit

    private func readStoreKitConfig(at url: URL) -> EvidenceStoreKitConfig? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return EvidenceStoreKitConfig(filename: url.lastPathComponent, rawContent: content)
    }

    // MARK: - Dependencies

    private func findDependencies(projectFileURL: URL, directoryURL: URL) -> EvidenceDependencies? {
        let projectName = projectFileURL.deletingPathExtension().lastPathComponent
        let candidates: [URL] = [
            directoryURL.appending(path: "Package.resolved"),
            projectFileURL.appending(path: "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"),
            directoryURL.appending(path: "\(projectName).xcworkspace/xcshareddata/swiftpm/Package.resolved"),
        ]
        for url in candidates {
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  let content = String(data: data, encoding: .utf8)
            else { continue }
            return EvidenceDependencies(
                packageNames: extractPackageNames(from: data),
                rawContent: content
            )
        }
        return nil
    }

    private func extractPackageNames(from data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pins = json["pins"] as? [[String: Any]]
        else { return [] }
        return pins.compactMap { ($0["identity"] as? String) ?? ($0["package"] as? String) }
    }

    // MARK: - Localization

    private func buildLocalizationFiles(from urls: [URL], relativeTo base: URL) -> [EvidenceLocalizationFile] {
        urls.compactMap { url -> EvidenceLocalizationFile? in
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return EvidenceLocalizationFile(
                relativePath: relativePathString(url, relativeTo: base),
                content: content
            )
        }
    }

    // MARK: - Helpers

    private func relativePathString(_ url: URL, relativeTo base: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(basePath) else { return url.lastPathComponent }
        let relative = String(filePath.dropFirst(basePath.count))
        return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
    }
}
