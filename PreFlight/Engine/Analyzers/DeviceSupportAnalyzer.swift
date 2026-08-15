import Foundation

/// Checks that the app is prepared for the devices it declares support for.
/// Currently covers: iPad multitasking readiness and Mac Catalyst adaptations.
/// Skips for projects that don't target iPhone or iPad at all.
struct DeviceSupportAnalyzer: Analyzer {
    let category = AnalysisCategory.deviceSupport

    /// Source patterns that indicate the layout adapts to larger screens.
    private static let adaptiveLayoutPatterns = [
        "horizontalSizeClass",
        "NavigationSplitView",
        "GeometryReader",
        "ViewThatFits",
    ]

    func analyze(_ context: AnalysisContext) async -> AnalysisResult {
        let appTargets = context.targets.filter(\.isApplication)
        let iOSTargets = appTargets.filter { target in
            (target.setting("TARGETED_DEVICE_FAMILY") ?? "").isEmpty == false
                || (target.setting("SUPPORTED_PLATFORMS") ?? "").contains("iphoneos")
        }
        guard !iOSTargets.isEmpty else {
            return .skipped(category, reason: "The project doesn't target iPhone or iPad.")
        }

        var findings: [Finding] = []
        var checks = 0
        let source = context.combinedSource()

        for target in iOSTargets {
            let deviceFamily = target.setting("TARGETED_DEVICE_FAMILY") ?? ""
            let supportsIPad = deviceFamily.contains("2")
            guard supportsIPad else { continue }

            checks += 1
            let requiresFullScreen = target.setting("INFOPLIST_KEY_UIRequiresFullScreen") == "YES"
                || context.infoPlists.values.contains { $0.presentKeys.contains("UIRequiresFullScreen") }
            if requiresFullScreen {
                findings.append(Finding(
                    category: category,
                    severity: .warning,
                    confidence: .fact,
                    rejectionLikelihood: .possible,
                    title: "iPad app opts out of multitasking",
                    detail: "Target \"\(target.name)\" supports iPad but requires full screen, opting out of Split View and Stage Manager.",
                    whyItMatters: "iPad apps are expected to support multitasking; full-screen-only apps need to support every orientation and stand out to reviewers as unadapted.",
                    evidence: "TARGETED_DEVICE_FAMILY includes iPad and UIRequiresFullScreen is set.",
                    suggestedFix: "Remove the Requires Full Screen setting and verify the layout works in Split View.",
                    estimatedFixMinutes: 30
                ))
            }

            checks += 1
            let hasAdaptiveLayout = Self.adaptiveLayoutPatterns.contains { source.contains($0) }
            if !hasAdaptiveLayout {
                findings.append(Finding(
                    category: category,
                    severity: .warning,
                    confidence: .observation,
                    rejectionLikelihood: .possible,
                    title: "iPad layout may not be adapted",
                    detail: "Target \"\(target.name)\" supports iPad, but no adaptive-layout code was found — the UI may be a stretched iPhone layout.",
                    whyItMatters: "Reviewers run iPad-compatible apps on an iPad; a stretched phone interface with dead space reads as unfinished and draws rejections for iPad experience.",
                    evidence: "TARGETED_DEVICE_FAMILY includes iPad; none of \(Self.adaptiveLayoutPatterns.joined(separator: ", ")) appear in source.",
                    suggestedFix: "Adapt the layout for large screens (NavigationSplitView, size classes), or drop iPad from Targeted Device Families until it's ready.",
                    estimatedFixMinutes: 60
                ))
            }
        }

        // Mac Catalyst: check for Mac-specific UI adaptations
        for target in appTargets {
            guard target.setting("SUPPORTS_MACCATALYST") == "YES" else { continue }

            checks += 1
            let hasMacAdaptations = source.contains("targetEnvironment(macCatalyst)")
                || source.contains("UIUserInterfaceIdiom.mac")
                || source.contains("sizeRestrictions")
                || source.contains("NSApplication")
            if !hasMacAdaptations {
                findings.append(Finding(
                    category: category,
                    severity: .suggestion,
                    confidence: .observation,
                    title: "Mac Catalyst app may lack Mac-specific adaptations",
                    detail: "Target \"\(target.name)\" enables Mac Catalyst, but no #if targetEnvironment(macCatalyst) or UIUserInterfaceIdiom.mac checks were found. The app may look like a stretched iPad UI on Mac.",
                    whyItMatters: "Mac Catalyst apps are reviewed as Mac apps. Reviewers expect at minimum a sensible minimum window size and layouts that don't have large areas of dead space at typical Mac window sizes.",
                    evidence: "SUPPORTS_MACCATALYST = YES; no targetEnvironment(macCatalyst), UIUserInterfaceIdiom.mac, sizeRestrictions, or NSApplication reference found in source.",
                    suggestedFix: "Add #if targetEnvironment(macCatalyst) blocks for window sizing (UIScene.sizeRestrictions), toolbar customization, and any iPad-specific UI that looks wrong at Mac window sizes.",
                    estimatedFixMinutes: 60
                ))
            }
        }

        return AnalysisResult(category: category, findings: findings, checksPerformed: checks)
    }
}
