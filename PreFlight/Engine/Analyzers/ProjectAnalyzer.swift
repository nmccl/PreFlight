import Foundation

/// Checks project configuration: bundle identifier, versioning, code signing,
/// build configuration, and entitlements. Everything here is read directly
/// from build settings, so all findings are facts.
struct ProjectAnalyzer: Analyzer {
    let category = AnalysisCategory.project

    private static let placeholderPrefixes = ["com.example.", "com.yourcompany.", "com.mycompany."]

    /// Entitlements that grant access to a capability, paired with source
    /// patterns that would indicate the capability is actually used.
    private struct EntitlementRule {
        let key: String
        let usagePatterns: [String]
        let capability: String
    }

    // Patterns assembled at runtime — same self-match avoidance as PrivacyAnalyzer.usageRules.
    private static let entitlementRules: [EntitlementRule] = {[
        EntitlementRule(key: "com.apple.security.device.bluetooth",              usagePatterns: ["Core" + "Bluetooth", "CBCentral" + "Manager", "CBPeripheral" + "Manager"],                 capability: "Bluetooth"),
        EntitlementRule(key: "com.apple.security.device.camera",                 usagePatterns: ["AV" + "CaptureDevice", "UIImagePickerController"],                                          capability: "the camera"),
        EntitlementRule(key: "com.apple.security.device.audio-input",            usagePatterns: ["AV" + "AudioRecorder", "AV" + "CaptureDevice", "AVAudioEngine"],                           capability: "the microphone"),
        EntitlementRule(key: "com.apple.security.personal-information.location", usagePatterns: ["Core" + "Location", "CLLocation" + "Manager"],                                             capability: "location"),
        EntitlementRule(key: "com.apple.security.personal-information.addressbook", usagePatterns: ["import Con" + "tacts", "CNContact" + "Store"],                                          capability: "contacts"),
        EntitlementRule(key: "com.apple.security.personal-information.calendars",   usagePatterns: ["import Event" + "Kit", "EKEvent" + "Store"],                                            capability: "the calendar"),
        EntitlementRule(key: "com.apple.security.personal-information.photos-library", usagePatterns: ["import Pho" + "tos", "PHPhoto" + "Library"],                                         capability: "the photo library"),
        EntitlementRule(key: "com.apple.developer.healthkit",                    usagePatterns: ["HKHealth" + "Store"],                                                                    capability: "HealthKit"),
        EntitlementRule(key: "com.apple.developer.applesignin",                  usagePatterns: ["AuthenticationServices", "SignInWithApple", "ASAuthorization"],                           capability: "Sign in with Apple"),
        EntitlementRule(key: "aps-environment",                                  usagePatterns: ["UserNotifications", "registerForRemoteNotifications", "UNUserNotificationCenter"],        capability: "push notifications"),
        EntitlementRule(key: "com.apple.developer.icloud-services",              usagePatterns: ["NSPersistentCloud" + "KitContainer", "CKContainer" + ".default()", "CKContainer(", "NSUbiquitousKeyValueStore"], capability: "iCloud"),
        EntitlementRule(key: "com.apple.security.application-groups",            usagePatterns: ["UserDefaults(suiteName:", "containerURL(forSecurityApplicationGroupIdentifier:"],         capability: "App Groups"),
    ]}()

    func analyze(_ context: AnalysisContext) async -> AnalysisResult {
        var findings: [Finding] = []
        var checks = 0
        let source = context.combinedSource()

        let appTargets = context.targets.filter(\.isApplication)
        guard !appTargets.isEmpty else {
            return AnalysisResult(
                category: category,
                findings: [
                    Finding(
                        category: category,
                        severity: .warning,
                        confidence: .fact,
                        title: "No application target found",
                        detail: "The project has no target that builds an app, so most configuration checks could not run.",
                        suggestedFix: "Open the project in Xcode and confirm it contains an application target."
                    )
                ],
                checksPerformed: 1
            )
        }

        for target in appTargets {
            checks += 5

            let bundleID = target.setting("PRODUCT_BUNDLE_IDENTIFIER") ?? ""
            if bundleID.isEmpty {
                findings.append(Finding(
                    category: category,
                    severity: .critical,
                    confidence: .fact,
                    rejectionLikelihood: .certain,
                    title: "Missing bundle identifier",
                    detail: "Target \"\(target.name)\" has no bundle identifier.",
                    whyItMatters: "Without a bundle identifier the app can't be archived, uploaded, or matched to an App Store Connect record — there is nothing App Review could evaluate.",
                    evidence: "PRODUCT_BUNDLE_IDENTIFIER is empty for target \"\(target.name)\".",
                    suggestedFix: "Set a bundle identifier under Signing & Capabilities for the \"\(target.name)\" target.",
                    estimatedFixMinutes: 5
                ))
            } else if Self.placeholderPrefixes.contains(where: { bundleID.hasPrefix($0) }) {
                findings.append(Finding(
                    category: category,
                    severity: .critical,
                    confidence: .fact,
                    rejectionLikelihood: .certain,
                    title: "Placeholder bundle identifier",
                    detail: "Target \"\(target.name)\" uses an identifier that looks like template placeholder text.",
                    whyItMatters: "App Store Connect only accepts identifiers registered to your developer account; template placeholders fail at upload, before review even starts.",
                    evidence: "PRODUCT_BUNDLE_IDENTIFIER is \"\(bundleID)\".",
                    suggestedFix: "Register a real bundle identifier in the Apple Developer portal and set it on the target.",
                    estimatedFixMinutes: 15
                ))
            }

            if target.setting("MARKETING_VERSION") == nil {
                findings.append(Finding(
                    category: category,
                    severity: .warning,
                    confidence: .fact,
                    rejectionLikelihood: .likely,
                    title: "No marketing version set",
                    detail: "Target \"\(target.name)\" has no user-facing version number (like 1.0).",
                    whyItMatters: "Every App Store submission needs a marketing version; uploads without one are rejected by App Store Connect before review starts.",
                    evidence: "MARKETING_VERSION is not set for target \"\(target.name)\".",
                    suggestedFix: "Set a Version value in the target's General tab.",
                    estimatedFixMinutes: 5
                ))
            }

            if target.setting("CURRENT_PROJECT_VERSION") == nil {
                findings.append(Finding(
                    category: category,
                    severity: .warning,
                    confidence: .fact,
                    rejectionLikelihood: .likely,
                    title: "No build number set",
                    detail: "Target \"\(target.name)\" has no build number.",
                    whyItMatters: "Every upload to App Store Connect needs a unique build number; without one the archive can't be submitted for review.",
                    evidence: "CURRENT_PROJECT_VERSION is not set for target \"\(target.name)\".",
                    suggestedFix: "Set a Build value in the target's General tab.",
                    estimatedFixMinutes: 5
                ))
            }

            let team = target.setting("DEVELOPMENT_TEAM") ?? ""
            if team.isEmpty {
                findings.append(Finding(
                    category: category,
                    severity: .warning,
                    confidence: .fact,
                    rejectionLikelihood: .likely,
                    title: "No development team selected",
                    detail: "Target \"\(target.name)\" has no signing team.",
                    whyItMatters: "Release builds must be signed by a developer team before they can be uploaded — distribution fails at archive time without one.",
                    evidence: "DEVELOPMENT_TEAM is empty for target \"\(target.name)\".",
                    suggestedFix: "Choose your team under Signing & Capabilities.",
                    estimatedFixMinutes: 5
                ))
            }

            if let entitlementsPath = target.setting("CODE_SIGN_ENTITLEMENTS") {
                let entitlementsURL = context.project.directoryURL.appending(path: entitlementsPath)
                if !FileManager.default.fileExists(atPath: entitlementsURL.path) {
                    findings.append(Finding(
                        category: category,
                        severity: .critical,
                        confidence: .fact,
                        rejectionLikelihood: .certain,
                        title: "Entitlements file is missing",
                        detail: "Target \"\(target.name)\" references an entitlements file that doesn't exist on disk.",
                        whyItMatters: "The build fails at code signing, so no binary can be produced for submission.",
                        evidence: "CODE_SIGN_ENTITLEMENTS points to \"\(entitlementsPath)\", which was not found.",
                        suggestedFix: "Restore the entitlements file or remove the CODE_SIGN_ENTITLEMENTS build setting.",
                        estimatedFixMinutes: 15,
                        affectedPath: entitlementsPath
                    ))
                } else {
                    checks += 1
                    findings.append(contentsOf: unusedEntitlementFindings(
                        at: entitlementsURL,
                        path: entitlementsPath,
                        targetName: target.name,
                        source: source
                    ))
                }
            }

            if let optimization = target.buildSettings["Release"]?["SWIFT_OPTIMIZATION_LEVEL"], optimization == "-Onone" {
                checks += 1
                findings.append(Finding(
                    category: category,
                    severity: .warning,
                    confidence: .fact,
                    title: "Release build has optimization disabled",
                    detail: "Target \"\(target.name)\" builds Release with optimization off, which ships debug-speed code to users.",
                    whyItMatters: "Apps that feel sluggish get flagged for performance during review and reviewed poorly by users.",
                    evidence: "SWIFT_OPTIMIZATION_LEVEL is -Onone in the Release configuration.",
                    suggestedFix: "Set Release optimization to -O (or remove the override) in Build Settings.",
                    estimatedFixMinutes: 5
                ))
            }
        }

        return AnalysisResult(category: category, findings: findings, checksPerformed: checks)
    }

    /// Flags entitlements that grant access to capabilities no code appears
    /// to use — reviewers ask for these to be removed.
    private func unusedEntitlementFindings(
        at url: URL,
        path: String,
        targetName: String,
        source: String
    ) -> [Finding] {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return []
        }

        var findings: [Finding] = []
        for rule in Self.entitlementRules {
            guard let value = plist[rule.key] else { continue }
            // Boolean entitlements explicitly set to false don't grant anything.
            if let flag = value as? Bool, !flag { continue }
            guard !rule.usagePatterns.contains(where: { source.contains($0) }) else { continue }

            findings.append(Finding(
                category: category,
                severity: .warning,
                confidence: .observation,
                rejectionLikelihood: .possible,
                title: "Entitlement for \(rule.capability) may be unused",
                detail: "Target \"\(targetName)\" requests access to \(rule.capability), but no code that uses it was found.",
                whyItMatters: "Reviewers ask for unused entitlements to be removed — requesting access the app never uses looks like over-collection and delays review.",
                evidence: "\(rule.key) is present in \(path); none of \(rule.usagePatterns.joined(separator: ", ")) appear in source.",
                suggestedFix: "Remove the \(rule.capability) entitlement in Signing & Capabilities, or keep it and use the capability.",
                estimatedFixMinutes: 5,
                affectedPath: path
            ))
        }
        return findings
    }
}
