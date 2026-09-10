import Foundation

/// Distinguishes what the application actually *does* from text that merely
/// *describes* behavior.
///
/// Text is not behavior. A rule written in a string literal, a guideline quoted
/// in a comment, a framework named in documentation, and an analyzer's own
/// detection pattern all contain the same words as real usage — but none of
/// them mean the app performs the behavior. Matching raw file text against a
/// keyword conflates the two and produces confident false positives.
///
/// Two filters address this, and analyzers should apply both before treating a
/// keyword match as evidence of behavior:
/// - `codeOnly` removes comments and string-literal contents, leaving
///   identifiers, calls, and imports.
/// - `isVendored` marks files belonging to a checked-in dependency, which is
///   third-party behavior rather than the application's.
enum SourceEvidence {

    // MARK: - Code vs. prose

    /// Strips comments and the contents of string literals, leaving only code.
    ///
    /// Use this whenever a keyword match is meant to prove the app *calls*
    /// something. Do not use it when the literal text itself is the problem —
    /// placeholder copy like "Lorem ipsum" lives in string literals by
    /// definition, so that check needs the unstripped source.
    static func codeOnly(_ source: String) -> String {
        let chars = Array(source)
        let count = chars.count
        var output = String()
        output.reserveCapacity(count)
        var index = 0

        while index < count {
            let character = chars[index]

            // Line comment: drop through end of line, keeping the newline so
            // line-oriented checks downstream still line up.
            if character == "/", index + 1 < count, chars[index + 1] == "/" {
                while index < count, chars[index] != "\n" { index += 1 }
                continue
            }

            // Block comment, which nests in Swift.
            if character == "/", index + 1 < count, chars[index + 1] == "*" {
                var depth = 1
                index += 2
                while index < count, depth > 0 {
                    if chars[index] == "/", index + 1 < count, chars[index + 1] == "*" {
                        depth += 1
                        index += 2
                    } else if chars[index] == "*", index + 1 < count, chars[index + 1] == "/" {
                        depth -= 1
                        index += 2
                    } else {
                        index += 1
                    }
                }
                continue
            }

            // Multiline string literal.
            if character == "\"", index + 2 < count, chars[index + 1] == "\"", chars[index + 2] == "\"" {
                index += 3
                while index < count {
                    if chars[index] == "\\" {
                        index += 2
                        continue
                    }
                    if chars[index] == "\"", index + 2 < count,
                       chars[index + 1] == "\"", chars[index + 2] == "\"" {
                        index += 3
                        break
                    }
                    index += 1
                }
                output += "\"\""
                continue
            }

            // Single-line string literal.
            if character == "\"" {
                index += 1
                while index < count {
                    if chars[index] == "\\" {
                        index += 2
                        continue
                    }
                    if chars[index] == "\"" {
                        index += 1
                        break
                    }
                    // An unterminated literal shouldn't swallow the rest of the file.
                    if chars[index] == "\n" { break }
                    index += 1
                }
                output += "\"\""
                continue
            }

            output.append(character)
            index += 1
        }

        return output
    }

    // MARK: - Vendored dependency detection

    /// Directory names that conventionally hold third-party code.
    /// "Packages" is deliberately absent: it's the usual home for a developer's
    /// own local packages, which are part of the application.
    private static let vendorDirectories: Set<String> = [
        "pods", "carthage", ".build", "checkouts", "sourcepackages",
        "deriveddata", "vendor", "vendored", "thirdparty", "third_party",
        "externals", "submodules", "node_modules", ".swiftpm",
    ]

    /// True when the file belongs to a checked-in dependency rather than to the
    /// application being analyzed.
    ///
    /// - Parameters:
    ///   - packageRootDirectories: top-level directory names that contain their
    ///     own `Package.swift`, so they are separate packages.
    ///   - resolvedPackageNames: package identities from Package.resolved,
    ///     matched loosely because an identity like "posthog-ios" is usually
    ///     checked out into a directory named "PostHog".
    static func isVendored(
        _ relativePath: String,
        packageRootDirectories: Set<String>,
        resolvedPackageNames: Set<String>
    ) -> Bool {
        let components = relativePath.components(separatedBy: "/").dropLast()
        guard !components.isEmpty else { return false }

        if components.contains(where: { vendorDirectories.contains($0.lowercased()) }) {
            return true
        }

        guard let root = components.first else { return false }
        if packageRootDirectories.contains(root.lowercased()) { return true }
        return resolvedPackageNames.contains(normalizePackageName(root))
    }

    /// Collapses a package identity and a directory name onto the same key:
    /// "posthog-ios", "PostHog", and "posthog_swift" all become "posthog".
    static func normalizePackageName(_ name: String) -> String {
        var normalized = name.lowercased().filter { $0.isLetter || $0.isNumber }
        for suffix in ["ios", "swift", "macos", "apple", "sdk", "kit"] where normalized.hasSuffix(suffix) {
            // Only strip when something meaningful remains.
            let trimmed = String(normalized.dropLast(suffix.count))
            if trimmed.count >= 3 {
                normalized = trimmed
                break
            }
        }
        return normalized
    }
}

// MARK: - Platform targeting

/// Which Apple platforms the application targets, so platform-specific rules
/// only fire where they apply. A macOS-only app has no UIKit and no Dynamic
/// Type, so iOS-only checks are noise there.
struct TargetPlatforms: Sendable {
    let supportsIOS: Bool
    let supportsMac: Bool

    /// Derived from the same build settings DeviceSupportAnalyzer already uses
    /// to decide whether it can run at all.
    init(appTargets: [TargetInfo]) {
        var ios = false
        var mac = false

        for target in appTargets {
            let platforms = (target.setting("SUPPORTED_PLATFORMS") ?? "").lowercased()
            let deviceFamily = target.setting("TARGETED_DEVICE_FAMILY") ?? ""

            if platforms.contains("iphoneos") || platforms.contains("iphonesimulator")
                || platforms.contains("appletvos") || platforms.contains("watchos")
                || platforms.contains("xros") || platforms.contains("visionos")
                || !deviceFamily.isEmpty
                || target.setting("SUPPORTS_MACCATALYST") == "YES" {
                ios = true
            }

            if platforms.contains("macosx") || target.setting("SUPPORTS_MACCATALYST") == "YES" {
                mac = true
            }
        }

        // A project with no usable platform settings shouldn't silently lose
        // every platform-gated check, so fall back to running them.
        if !ios && !mac {
            ios = true
            mac = true
        }

        self.supportsIOS = ios
        self.supportsMac = mac
    }

    var displayName: String {
        switch (supportsIOS, supportsMac) {
        case (true, true): "iOS and macOS"
        case (true, false): "iOS"
        case (false, true): "macOS"
        case (false, false): "unknown"
        }
    }
}
