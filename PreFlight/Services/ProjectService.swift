import Foundation

/// Opens Xcode projects and prepares analysis input. Callers are responsible
/// for holding security-scoped access to the project URL while using this.
struct ProjectService: Sendable {
    private let parser = XcodeProjectParser()

    private static let skippedDirectories: Set<String> = [
        ".git", ".build", "DerivedData", "Pods", "Carthage", ".swiftpm",
    ]

    private static let deploymentTargetKeys: [String: String] = [
        "MACOSX_DEPLOYMENT_TARGET": "macOS",
        "IPHONEOS_DEPLOYMENT_TARGET": "iOS",
        "XROS_DEPLOYMENT_TARGET": "visionOS",
        "WATCHOS_DEPLOYMENT_TARGET": "watchOS",
        "TVOS_DEPLOYMENT_TARGET": "tvOS",
    ]

    func openProject(at url: URL) throws -> Project {
        let parsed = try parser.parse(projectFileURL: url)
        let appTarget = parsed.targets.first { $0.isApplication } ?? parsed.targets.first
        let directoryURL = url.deletingLastPathComponent()

        var deploymentTargets: [String: String] = [:]
        if let appTarget {
            for (key, platform) in Self.deploymentTargetKeys {
                if let value = appTarget.setting(key) {
                    deploymentTargets[platform] = value
                }
            }
        }

        return Project(
            name: url.deletingPathExtension().lastPathComponent,
            projectFileURL: url,
            directoryURL: directoryURL,
            bundleIdentifier: appTarget?.setting("PRODUCT_BUNDLE_IDENTIFIER"),
            deploymentTargets: deploymentTargets,
            targetNames: parsed.targets.map(\.name),
            appIconImageData: appIconData(in: directoryURL)
        )
    }

    func makeContext(for project: Project, credentials: ASCCredentials?) throws -> AnalysisContext {
        let parsed = try parser.parse(projectFileURL: project.projectFileURL)

        var sources: [URL] = []
        var resources: [URL] = []
        for url in projectFiles(in: project.directoryURL) {
            switch url.pathExtension.lowercased() {
            case "swift", "m", "mm":
                sources.append(url)
            case "plist", "xcprivacy", "storekit", "entitlements":
                resources.append(url)
            default:
                break
            }
        }

        var infoPlists: [String: InfoPlistData] = [:]
        for target in parsed.targets where target.isApplication {
            infoPlists[target.name] = infoPlistData(for: target, in: project.directoryURL)
        }

        return AnalysisContext(
            project: project,
            targets: parsed.targets,
            infoPlists: infoPlists,
            sourceFileURLs: sources,
            resourceFileURLs: resources,
            ascCredentials: credentials
        )
    }

    /// Walks the project directory once, skipping dependency and build folders.
    /// The filesystem is the source of truth for files because modern projects
    /// use synchronized folder groups that don't list files in the pbxproj.
    private func projectFiles(in directory: URL) -> [URL] {
        var files: [URL] = []
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                if Self.skippedDirectories.contains(url.lastPathComponent) || url.pathExtension == "xcodeproj" {
                    enumerator?.skipDescendants()
                }
                continue
            }
            files.append(url)
        }
        return files
    }

    /// Combines INFOPLIST_KEY_* build settings (the generated-plist workflow)
    /// with an explicit Info.plist file when the target has one.
    private func infoPlistData(for target: TargetInfo, in directory: URL) -> InfoPlistData {
        var stringValues: [String: String] = [:]
        var presentKeys = Set<String>()

        for settings in target.buildSettings.values {
            for (key, value) in settings where key.hasPrefix("INFOPLIST_KEY_") {
                let plistKey = String(key.dropFirst("INFOPLIST_KEY_".count))
                stringValues[plistKey] = value
                presentKeys.insert(plistKey)
            }
        }

        if let plistPath = target.setting("INFOPLIST_FILE") {
            let plistURL = directory.appending(path: plistPath)
            if let data = try? Data(contentsOf: plistURL),
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                for (key, value) in plist {
                    presentKeys.insert(key)
                    if let string = value as? String {
                        stringValues[key] = string
                    }
                }
            }
        }

        return InfoPlistData(stringValues: stringValues, presentKeys: presentKeys)
    }

    private func appIconData(in directory: URL) -> Data? {
        // Only extract from classic .appiconset — these contain the final
        // rendered PNG. Icon Composer .icon bundles only contain layer files
        // (not the composed output), so extracting from them produces a broken
        // partial image; fall back to the system generic app icon instead.
        let iconFiles = projectFiles(in: directory).filter { url in
            url.path.contains("AppIcon.appiconset") && url.pathExtension.lowercased() == "png"
        }
        let best = iconFiles.max { fileSize($0) < fileSize($1) }
        guard let best,
              let data = try? Data(contentsOf: best),
              data.count <= 2_000_000 else {
            return nil
        }
        return data
    }

    private func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }
}
