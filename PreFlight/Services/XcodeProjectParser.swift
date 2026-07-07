import Foundation

/// One target from the pbxproj, with per-configuration build settings already
/// merged (project-level settings overridden by target-level ones).
struct TargetInfo: Sendable {
    let name: String
    let productType: String?
    let buildSettings: [String: [String: String]]

    var isApplication: Bool {
        productType?.contains("application") == true
    }

    /// Looks a setting up in Release first, then any other configuration.
    func setting(_ key: String) -> String? {
        if let release = buildSettings["Release"]?[key] {
            return release
        }
        for settings in buildSettings.values {
            if let value = settings[key] {
                return value
            }
        }
        return nil
    }
}

struct ParsedXcodeProject: Sendable {
    let targets: [TargetInfo]
}

enum XcodeProjectParserError: LocalizedError {
    case missingPbxproj
    case malformedPbxproj

    var errorDescription: String? {
        switch self {
        case .missingPbxproj:
            "The project is missing its project.pbxproj file."
        case .malformedPbxproj:
            "The project.pbxproj file could not be read."
        }
    }
}

/// Reads project.pbxproj, which is an OpenStep-format property list, using
/// PropertyListSerialization — no regex and no third-party parser needed.
struct XcodeProjectParser: Sendable {
    func parse(projectFileURL: URL) throws -> ParsedXcodeProject {
        let pbxprojURL = projectFileURL.appending(path: "project.pbxproj")
        guard FileManager.default.fileExists(atPath: pbxprojURL.path) else {
            throw XcodeProjectParserError.missingPbxproj
        }

        let data = try Data(contentsOf: pbxprojURL)
        var format = PropertyListSerialization.PropertyListFormat.openStep
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any],
            let objects = plist["objects"] as? [String: [String: Any]],
            let rootID = plist["rootObject"] as? String,
            let projectObject = objects[rootID]
        else {
            throw XcodeProjectParserError.malformedPbxproj
        }

        let projectSettings = configurationSettings(of: projectObject, in: objects)
        let targetIDs = projectObject["targets"] as? [String] ?? []

        let targets = targetIDs.compactMap { targetID -> TargetInfo? in
            guard let target = objects[targetID], let name = target["name"] as? String else {
                return nil
            }
            let targetSettings = configurationSettings(of: target, in: objects)
            var merged: [String: [String: String]] = [:]
            for config in Set(projectSettings.keys).union(targetSettings.keys) {
                merged[config] = (projectSettings[config] ?? [:])
                    .merging(targetSettings[config] ?? [:]) { _, targetValue in targetValue }
            }
            return TargetInfo(
                name: name,
                productType: target["productType"] as? String,
                buildSettings: merged
            )
        }

        return ParsedXcodeProject(targets: targets)
    }

    /// Follows an object's buildConfigurationList reference and returns the
    /// build settings of every configuration, keyed by configuration name.
    private func configurationSettings(
        of object: [String: Any],
        in objects: [String: [String: Any]]
    ) -> [String: [String: String]] {
        guard
            let listID = object["buildConfigurationList"] as? String,
            let configIDs = objects[listID]?["buildConfigurations"] as? [String]
        else {
            return [:]
        }

        var result: [String: [String: String]] = [:]
        for configID in configIDs {
            guard
                let config = objects[configID],
                let name = config["name"] as? String,
                let rawSettings = config["buildSettings"] as? [String: Any]
            else {
                continue
            }
            result[name] = rawSettings.mapValues { value in
                if let string = value as? String {
                    return string
                }
                if let array = value as? [String] {
                    return array.joined(separator: " ")
                }
                return String(describing: value)
            }
        }
        return result
    }
}
