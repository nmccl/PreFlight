import Foundation
import Observation

/// A card on the Home screen. Carries enough display data (icon, score) that
/// the card renders without touching the sandboxed project on disk.
struct RecentProject: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var bundleIdentifier: String?
    var projectPath: String
    var bookmarkData: Data
    var lastOpened: Date
    var lastScore: Int?
    var appIconImageData: Data?
}

@MainActor
@Observable
final class RecentProjectsService {
    private(set) var recents: [RecentProject] = []

    private let defaults: UserDefaults
    private static let storageKey = "recentProjects"
    private static let maximumCount = 8

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode([RecentProject].self, from: data) {
            recents = stored
        }
    }

    /// Records an opened project. Must be called while security-scoped access
    /// to the project URL is active, or bookmark creation fails.
    func noteOpened(_ project: Project) {
        guard let bookmarkData = try? Self.bookmarkData(for: project.projectFileURL) else {
            return
        }
        let existing = recents.first { $0.projectPath == project.projectFileURL.path }
        let recent = RecentProject(
            id: existing?.id ?? UUID(),
            name: project.name,
            bundleIdentifier: project.bundleIdentifier,
            projectPath: project.projectFileURL.path,
            bookmarkData: bookmarkData,
            lastOpened: .now,
            lastScore: existing?.lastScore,
            appIconImageData: project.appIconImageData ?? existing?.appIconImageData
        )
        recents.removeAll { $0.id == recent.id }
        recents.insert(recent, at: 0)
        if recents.count > Self.maximumCount {
            recents.removeLast(recents.count - Self.maximumCount)
        }
        save()
    }

    func noteAnalyzed(projectPath: String, score: Int) {
        guard let index = recents.firstIndex(where: { $0.projectPath == projectPath }) else {
            return
        }
        recents[index].lastScore = score
        save()
    }

    func remove(_ recent: RecentProject) {
        recents.removeAll { $0.id == recent.id }
        save()
    }

    /// Re-establishes sandbox access from the stored bookmark. Refreshes the
    /// bookmark when the system reports it stale (project moved or renamed).
    func resolveURL(for recent: RecentProject) throws -> URL {
        var isStale = false
        #if os(macOS)
        let url = try URL(
            resolvingBookmarkData: recent.bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #else
        let url = try URL(
            resolvingBookmarkData: recent.bookmarkData,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #endif
        if isStale,
           let index = recents.firstIndex(where: { $0.id == recent.id }),
           let refreshed = try? Self.bookmarkData(for: url) {
            recents[index].bookmarkData = refreshed
            save()
        }
        return url
    }

    private static func bookmarkData(for url: URL) throws -> Data {
        #if os(macOS)
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        try url.bookmarkData()
        #endif
    }

    private func save() {
        if let data = try? JSONEncoder().encode(recents) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
