import Foundation

/// Checks project configuration: bundle identifier, versioning, code signing,
/// build configuration, and entitlements. Everything here is read directly
/// from build settings, so all findings are facts.
struct ProjectAnalyzer: Analyzer {
    let category = AnalysisCategory.project

    private static let placeholderPrefixes = [
        "com.example.", "com.yourcompany.", "com.mycompany.", "com.test.", "com.testing.",
        "com.placeholder.", "com.sample.", "com.demo.", "com.yourapp.", "com.company.",
    ]

    /// Entitlements that grant access to a capability, paired with source
    /// patterns that would indicate the capability is actually used.
    private struct EntitlementRule {
        let key: String
        let usagePatterns: [String]
        let capability: String
        /// Defaults to .possible. Raised for entitlements Apple's automated
        /// pre-review analysis rejects outright.
        var likelihood: RejectionLikelihood = .possible
        var whyItMatters = "Reviewers ask for unused entitlements to be removed — requesting access the app never uses looks like over-collection and delays review."
        var suggestedFix = "Remove the entitlement in Signing & Capabilities, or keep it and use the capability."
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
        EntitlementRule(key: "com.apple.developer.healthkit",                    usagePatterns: ["HKHealth" + "Store", "HKObject" + "Query", "HKQuery", "import Health" + "Kit"],   capability: "HealthKit"),
        EntitlementRule(key: "com.apple.developer.applesignin",                  usagePatterns: ["AuthenticationServices", "SignInWithApple", "ASAuthorization"],                           capability: "Sign in with Apple"),
        EntitlementRule(key: "aps-environment",                                  usagePatterns: ["UserNotifications", "registerForRemoteNotifications", "UNUserNotificationCenter"],        capability: "push notifications"),
        EntitlementRule(key: "com.apple.developer.icloud-services",              usagePatterns: ["NSPersistentCloud" + "KitContainer", "CKContainer" + ".default()", "CKContainer(", "NSUbiquitousKeyValueStore"], capability: "iCloud"),
        EntitlementRule(key: "com.apple.security.application-groups",            usagePatterns: ["UserDefaults(suiteName:", "containerURL(forSecurityApplicationGroupIdentifier:"],         capability: "App Groups"),

        // Apple's automated pre-review analysis rejects this one specifically:
        // an app that only makes outgoing requests needs network.client, and
        // network.server is for apps that listen for incoming connections.
        // Patterns are listener APIs only — an outbound URLSession call is not
        // evidence of a server.
        EntitlementRule(
            key: "com.apple.security.network.server",
            usagePatterns: ["NW" + "Listener", "NSNet" + "Service", "NSSocket" + "Port", "CFSocket" + "Create", "GCDWeb" + "Server", "HTTP" + "Server"],
            capability: "incoming network connections",
            likelihood: .likely,
            whyItMatters: "Apple runs an automated check for this before review. An app that only initiates outgoing connections needs com.apple.security.network.client; the server entitlement is for apps that listen for and respond to incoming connections. Declaring it without matching functionality halts the submission before a human reviewer sees it.",
            suggestedFix: "Set Incoming Connections (Server) to off under Signing & Capabilities — the build setting is ENABLE_INCOMING_NETWORK_CONNECTIONS. Keep Outgoing Connections (Client) on for network requests."
        ),

        // Hardened runtime exceptions. Each disables a protection, and an
        // unjustified one draws the same "minimum set of entitlements" response.
        EntitlementRule(
            key: "com.apple.security.cs.allow-jit",
            usagePatterns: ["mmap", "MAP_JIT", "JavaScript" + "Core", "JSContext"],
            capability: "JIT compilation",
            whyItMatters: "Hardened runtime exceptions weaken code-signing protections. Reviewers ask for ones the app doesn't need to be removed."
        ),
        EntitlementRule(
            key: "com.apple.security.cs.disable-library-validation",
            usagePatterns: ["dlopen", "Bundle(path:", "NSBundle", "loadAndReturnError", "plugin"],
            capability: "loading unsigned libraries",
            whyItMatters: "Disabling library validation lets the app load code signed by other teams. Reviewers ask for it to be removed unless the app genuinely loads third-party plug-ins."
        ),
        EntitlementRule(
            key: "com.apple.security.cs.allow-unsigned-executable-memory",
            usagePatterns: ["mprotect", "PROT_EXEC", "JavaScript" + "Core"],
            capability: "unsigned executable memory",
            whyItMatters: "This exception removes a core hardened-runtime protection and is rarely justified outside interpreters and VMs."
        ),
        EntitlementRule(
            key: "com.apple.security.cs.debugger",
            usagePatterns: ["task_for_pid", "ptrace", "NSTask"],
            capability: "debugging other processes",
            likelihood: .likely,
            whyItMatters: "The debugging-tool entitlement lets the app inspect other processes. Shipping it in a production app is almost always a mistake and draws immediate reviewer attention.",
            suggestedFix: "Turn off the Debugging Tool hardened runtime exception before archiving."
        ),
        EntitlementRule(
            key: "com.apple.security.automation.apple-events",
            usagePatterns: ["NSAppleScript", "NSApple" + "EventDescriptor", "AEDeterminePermissionToAutomateTarget", "osascript"],
            capability: "sending Apple Events to other apps",
            whyItMatters: "Apple Events automation can control other applications, so an unused grant is both a privacy prompt users don't expect and an entitlement reviewers question."
        ),
    ]}()

    func analyze(_ context: AnalysisContext) async -> AnalysisResult {
        var findings: [Finding] = []
        var checks = 0
        let productionSource = context.productionSource()
        // Capability usage must come from the app's own code with comments and
        // string literals stripped, so an API named in prose can't count as use.
        let applicationCode = context.applicationCode()

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

            let entitlementsPath = target.setting("CODE_SIGN_ENTITLEMENTS") ?? ""
            if !entitlementsPath.isEmpty {
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
                }
            }

            // Runs regardless of whether an entitlements file exists: the
            // evidence bundle merges the file with the entitlements Xcode
            // generates from build settings, which is the only source for most
            // projects.
            if let entitlements = context.evidenceBundle.entitlements[target.name] {
                checks += 1
                findings.append(contentsOf: unusedEntitlementFindings(
                    in: entitlements,
                    targetName: target.name,
                    code: applicationCode
                ))
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
        in entitlements: EvidenceEntitlements,
        targetName: String,
        code: String
    ) -> [Finding] {
        var findings: [Finding] = []
        for rule in Self.entitlementRules {
            guard let value = entitlements.keys[rule.key] else { continue }
            // Entitlements explicitly set to false don't grant anything.
            if value.lowercased() == "false" { continue }
            guard !rule.usagePatterns.contains(where: { code.contains($0) }) else { continue }

            findings.append(Finding(
                category: category,
                severity: .warning,
                confidence: .observation,
                rejectionLikelihood: rule.likelihood,
                title: "Entitlement for \(rule.capability) may be unused",
                detail: "Target \"\(targetName)\" requests \(rule.capability), but no code that uses it was found.",
                whyItMatters: rule.whyItMatters,
                evidence: "\(rule.key) is granted by \(entitlements.path); none of \(rule.usagePatterns.joined(separator: ", ")) appear in the app's own code.",
                suggestedFix: rule.suggestedFix,
                estimatedFixMinutes: 5,
                affectedPath: entitlements.path
            ))
        }
        return findings
    }
}
