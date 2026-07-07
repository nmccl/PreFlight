import Foundation

/// An opened Xcode project, holding just the details the UI and analyzers need.
struct Project: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let projectFileURL: URL
    let directoryURL: URL
    let bundleIdentifier: String?
    let deploymentTargets: [String: String]
    let targetNames: [String]
    let appIconImageData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        projectFileURL: URL,
        directoryURL: URL,
        bundleIdentifier: String? = nil,
        deploymentTargets: [String: String] = [:],
        targetNames: [String] = [],
        appIconImageData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.projectFileURL = projectFileURL
        self.directoryURL = directoryURL
        self.bundleIdentifier = bundleIdentifier
        self.deploymentTargets = deploymentTargets
        self.targetNames = targetNames
        self.appIconImageData = appIconImageData
    }
}
