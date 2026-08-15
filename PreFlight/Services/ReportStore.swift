import CryptoKit
import Foundation

/// Persists up to 10 analysis reports per project in Application Support.
/// Each project gets its own subdirectory keyed by a hash of the project path;
/// each run is stored as a separate JSON file named by the report's UUID,
/// so saving an updated report (e.g. after AI summary) overwrites the same file.
nonisolated struct ReportStore: Sendable {
    private static let maxHistory = 10

    private var baseURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appending(path: "Reports")
    }

    func save(_ report: Report, forProjectPath path: String) {
        guard let dir = projectDirectory(forProjectPath: path) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appending(path: "\(report.id.uuidString).json")
        if let data = try? JSONEncoder().encode(report) {
            try? data.write(to: fileURL)
        }
        pruneOldReports(in: dir)
    }

    /// Returns the most recent report for the project, if any.
    func load(forProjectPath path: String) -> Report? {
        loadHistory(forProjectPath: path).first
    }

    /// Returns all stored reports for the project, newest first (up to `maxHistory`).
    func loadHistory(forProjectPath path: String) -> [Report] {
        guard let dir = projectDirectory(forProjectPath: path),
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: dir,
                  includingPropertiesForKeys: [.contentModificationDateKey],
                  options: .skipsHiddenFiles
              ) else {
            return []
        }

        let jsonFiles = contents
            .filter { $0.pathExtension == "json" }
            .sorted { modDate(of: $0) > modDate(of: $1) }

        return jsonFiles.compactMap { url -> Report? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            guard let report = try? JSONDecoder().decode(Report.self, from: data) else {
                // Predates a model change — remove so it doesn't linger as dead weight.
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return report
        }
    }

    func delete(forProjectPath path: String) {
        guard let dir = projectDirectory(forProjectPath: path) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    private func projectDirectory(forProjectPath path: String) -> URL? {
        guard let base = baseURL else { return nil }
        let digest = SHA256.hash(data: Data(path.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined().prefix(32)
        return base.appending(path: String(name))
    }

    private func pruneOldReports(in dir: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let sorted = contents
            .filter { $0.pathExtension == "json" }
            .sorted { modDate(of: $0) > modDate(of: $1) }

        for url in sorted.dropFirst(Self.maxHistory) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func modDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
