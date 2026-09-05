import Foundation

/// Checks privacy requirements: usage-description strings for sensitive APIs,
/// the presence of a privacy manifest, and whether detected third-party SDKs
/// have their expected data types declared in PrivacyInfo.xcprivacy.
/// Framework usage is inferred from source text, so those findings are
/// observations, not facts.
struct PrivacyAnalyzer: Analyzer {
    let category = AnalysisCategory.privacy

    /// Source patterns that trigger a required Info.plist usage description.
    /// All patterns are assembled at runtime via string concatenation so that
    /// PreFlight analyzing its own project doesn't match its own rules.
    private struct UsageRule {
        let sourcePatterns: [String]   // any match triggers the rule
        let plistKey: String
        let capability: String
    }

    private static let usageRules: [UsageRule] = {[
        UsageRule(
            sourcePatterns: [
                "AV" + "CaptureDevice.requestAccess",
                "AV" + "CaptureSession()",
                "AV" + "CaptureDeviceInput("
            ],
            plistKey: "NSCameraUsageDescription",
            capability: "the camera"
        ),
        UsageRule(
            sourcePatterns: [
                "AV" + "AudioRecorder(",
                "AV" + "AudioEngine().inputNode"
            ],
            plistKey: "NSMicrophoneUsageDescription",
            capability: "the microphone"
        ),
        UsageRule(
            sourcePatterns: [
                "CLLocation" + "Manager()",
                "requestWhenInUseAuthorization()",
                "requestAlwaysAuthorization()"
            ],
            plistKey: "NSLocationWhenInUseUsageDescription",
            capability: "location"
        ),
        UsageRule(
            sourcePatterns: [
                "CNContact" + "Store()",
                "CNContact" + "FetchRequest("
            ],
            plistKey: "NSContactsUsageDescription",
            capability: "contacts"
        ),
        UsageRule(
            sourcePatterns: [
                "EKEvent" + "Store()",
                "EKEvent" + "Store.init"
            ],
            plistKey: "NSCalendarsUsageDescription",
            capability: "the calendar"
        ),
        UsageRule(
            sourcePatterns: [
                "CBCentral" + "Manager(",
                "CBPeripheral" + "Manager("
            ],
            plistKey: "NSBluetoothAlwaysUsageDescription",
            capability: "Bluetooth"
        ),
        UsageRule(
            sourcePatterns: [
                "SFSpeech" + "Recognizer(",
                "SFSpeech" + "AudioBufferRecognitionRequest("
            ],
            plistKey: "NSSpeechRecognitionUsageDescription",
            capability: "speech recognition"
        ),
        UsageRule(
            sourcePatterns: [
                "HKHealth" + "Store()",
                "requestAuthorization(toShare:"
            ],
            plistKey: "NSHealthShareUsageDescription",
            capability: "health data"
        ),
        UsageRule(
            sourcePatterns: [
                "ATTracking" + "Manager.requestTrackingAuthorization",
                "AppTracking" + "Transparency"
            ],
            plistKey: "NSUserTrackingUsageDescription",
            capability: "tracking"
        ),
        UsageRule(
            sourcePatterns: [
                "PHPhoto" + "Library.requestAuthorization",
                "PHPhoto" + "Library.shared()"
            ],
            plistKey: "NSPhotoLibraryUsageDescription",
            capability: "the photo library"
        ),
        UsageRule(
            sourcePatterns: [
                "evaluatePolicy(.deviceOwnerAuthentication",
                "canEvaluatePolicy(.deviceOwnerAuthentication"
            ],
            plistKey: "NSFaceIDUsageDescription",
            capability: "Face ID or Touch ID"
        ),
    ]}()

    /// Required-reason APIs: source evidence mapped to the xcprivacy category key.
    private struct RequiredReasonRule {
        let sourcePatterns: [String]
        let categoryKey: String
        let apiName: String
    }

    private static let requiredReasonRules: [RequiredReasonRule] = {[
        RequiredReasonRule(
            sourcePatterns: ["User" + "Defaults"],
            categoryKey: "NSPrivacyAccessedAPICategoryUser" + "Defaults",
            apiName: "UserDefaults"
        ),
        RequiredReasonRule(
            sourcePatterns: [".systemUptime", "ProcessInfo.processInfo.systemUptime"],
            categoryKey: "NSPrivacyAccessedAPICategorySystemBootTime",
            apiName: "systemUptime / SystemBootTime"
        ),
        RequiredReasonRule(
            sourcePatterns: [".creationDate", "NSURLCreationDate", ".modificationDate"],
            categoryKey: "NSPrivacyAccessedAPICategoryFileTimestamp",
            apiName: "file timestamps"
        ),
        RequiredReasonRule(
            sourcePatterns: ["volumeAvailableCapacity", "volumeTotalCapacity"],
            categoryKey: "NSPrivacyAccessedAPICategoryDiskSpace",
            apiName: "disk space"
        ),
    ]}()

    /// Apple's documented valid reason codes per NSPrivacyAccessedAPICategory.
    private static let validReasonCodes: [String: Set<String>] = [
        "NSPrivacyAccessedAPICategoryUser" + "Defaults": ["CA92.1", "1C8F.1"],
        "NSPrivacyAccessedAPICategorySystemBootTime":     ["35F9.1", "8FFB.1", "3D61.1"],
        "NSPrivacyAccessedAPICategoryFileTimestamp":      ["DDA9.1", "C617.1", "3B52.1", "0A2A.1"],
        "NSPrivacyAccessedAPICategoryDiskSpace":          ["E174.1", "85F4.1"],
        "NSPrivacyAccessedAPICategoryActiveKeyboards":    ["3EC4.1", "54BD.1"],
    ]

    func analyze(_ context: AnalysisContext) async -> AnalysisResult {
        var findings: [Finding] = []
        var checks = 0

        let allSource = context.combinedSource()
        // Strip #if DEBUG ... #endif blocks before checking — those paths don't
        // run in production builds and shouldn't trigger privacy requirement findings.
        let productionSource = sourceStrippingDebugBlocks(allSource)
        let allPresentKeys = Set(context.infoPlists.values.flatMap(\.presentKeys))
        let allStringValues = context.infoPlists.values.reduce(into: [String: String]()) { merged, plist in
            merged.merge(plist.stringValues) { existing, _ in existing }
        }

        // MARK: Usage-description checks

        for rule in Self.usageRules {
            checks += 1
            guard rule.sourcePatterns.contains(where: { productionSource.contains($0) }) else { continue }

            if !allPresentKeys.contains(rule.plistKey) {
                let matched = rule.sourcePatterns.first { productionSource.contains($0) } ?? rule.sourcePatterns[0]
                findings.append(Finding(
                    category: category,
                    severity: .warning,
                    confidence: .observation,
                    rejectionLikelihood: .likely,
                    title: "Missing \(rule.plistKey)",
                    detail: "The code appears to use \(rule.capability), but no \(rule.plistKey) was found in the Info.plist or build settings.",
                    whyItMatters: "If the app really accesses \(rule.capability), a missing usage description is an automatic rejection — it's one of the most common App Review blockers.",
                    evidence: "Found \"\(matched)\" in production source; \(rule.plistKey) is not present in any Info.plist or INFOPLIST_KEY build setting.",
                    guidelineReference: "5.1.1",
                    suggestedFix: "Add \(rule.plistKey) to the target's Info settings with a sentence explaining why the app needs \(rule.capability).",
                    estimatedFixMinutes: 5
                ))
            } else if let value = allStringValues[rule.plistKey],
                      value.trimmingCharacters(in: .whitespaces).count < 10 {
                findings.append(Finding(
                    category: category,
                    severity: .warning,
                    confidence: .fact,
                    rejectionLikelihood: .possible,
                    title: "\(rule.plistKey) looks too short",
                    detail: "The usage description for \(rule.capability) is only a few characters long.",
                    whyItMatters: "Reviewers reject purpose strings that don't actually explain why the app needs access — users must be able to make an informed decision from this text.",
                    evidence: "\(rule.plistKey) is \"\(value)\".",
                    guidelineReference: "5.1.1",
                    suggestedFix: "Write a full sentence describing why the app needs \(rule.capability).",
                    estimatedFixMinutes: 5
                ))
            }
        }

        // MARK: Privacy manifest checks

        checks += 1
        let manifestURLs = context.resourceFileURLs.filter { $0.lastPathComponent == "PrivacyInfo.xcprivacy" }

        if manifestURLs.isEmpty {
            let matchedAPIs = Self.requiredReasonRules.flatMap(\.sourcePatterns)
                .filter { productionSource.contains($0) }
            if !matchedAPIs.isEmpty {
                findings.append(Finding(
                    category: category,
                    severity: .warning,
                    confidence: .observation,
                    rejectionLikelihood: .likely,
                    title: "No privacy manifest, but required-reason APIs in use",
                    detail: "The code appears to use APIs that Apple classifies as \"required reason\" APIs, and there is no PrivacyInfo.xcprivacy declaring those reasons.",
                    whyItMatters: "Apple validates required-reason API declarations at submission; missing reasons generate ITMS warnings and can block the build from review.",
                    evidence: "Found in source: \(Array(Set(matchedAPIs)).joined(separator: ", ")). No PrivacyInfo.xcprivacy in the project.",
                    suggestedFix: "Add a PrivacyInfo.xcprivacy file to the app target and declare the required-reason API categories the app uses.",
                    estimatedFixMinutes: 20
                ))
            } else {
                findings.append(Finding(
                    category: category,
                    severity: .suggestion,
                    confidence: .fact,
                    rejectionLikelihood: .possible,
                    title: "No privacy manifest",
                    detail: "The app has no PrivacyInfo.xcprivacy file.",
                    whyItMatters: "Privacy manifests are increasingly expected for App Store submissions and feed the privacy nutrition label reviewers check against the app's behavior.",
                    evidence: "No PrivacyInfo.xcprivacy found among the project's resource files.",
                    suggestedFix: "Add a PrivacyInfo.xcprivacy file describing data collection and required-reason API use.",
                    estimatedFixMinutes: 15
                ))
            }
        } else if let manifestURL = manifestURLs.first,
                  let manifest = parsePrivacyManifest(at: manifestURL) {

            // Third-party SDK data-type cross-check.
            checks += 1
            for sdk in KnownDataCollector.all where sdk.sourcePatterns.contains(where: { productionSource.contains($0) }) {
                let undeclared = sdk.xcprivacyTypes.filter { !manifest.collectedDataTypes.contains($0) }
                guard !undeclared.isEmpty else { continue }
                let detectedVia = sdk.sourcePatterns.first { productionSource.contains($0) } ?? sdk.name
                let missingReadable = undeclared
                    .map { $0.replacingOccurrences(of: "NSPrivacyCollectedDataType", with: "") }
                    .joined(separator: ", ")
                findings.append(Finding(
                    category: category,
                    severity: .warning,
                    confidence: .observation,
                    rejectionLikelihood: .likely,
                    title: "\(sdk.name) data types missing from privacy manifest",
                    detail: "\(sdk.name) is detected in source and is known to collect user data, but the corresponding NSPrivacyCollectedDataType entries are missing from PrivacyInfo.xcprivacy.",
                    whyItMatters: "Apple validates your privacy manifest against what your app and its third-party SDKs actually collect. An undeclared SDK's data collection is a documented App Review rejection cause.",
                    evidence: "Detected via \"\(detectedVia)\". Missing from NSPrivacyCollectedDataTypes: \(missingReadable).",
                    guidelineReference: "5.1.2",
                    suggestedFix: "Add these entries to NSPrivacyCollectedDataTypes in PrivacyInfo.xcprivacy: \(undeclared.joined(separator: ", ")).",
                    estimatedFixMinutes: 10
                ))
            }

            // NSPrivacyTracking contradiction check.
            checks += 1
            let hasTrackingCode = productionSource.contains("ATTracking" + "Manager")
                || productionSource.contains("ASIdentifier" + "Manager")
                || productionSource.contains("advertising" + "Identifier")
            if !manifest.privacyTracking && (hasTrackingCode || !manifest.trackingDomains.isEmpty) {
                let evidence: String
                if !manifest.trackingDomains.isEmpty {
                    evidence = "NSPrivacyTracking = false, but NSPrivacyTrackingDomains lists: \(manifest.trackingDomains.prefix(3).joined(separator: ", "))."
                } else {
                    evidence = "NSPrivacyTracking = false, but tracking-capable API (ATTrackingManager / advertisingIdentifier) found in production source."
                }
                findings.append(Finding(
                    category: category,
                    severity: .warning,
                    confidence: .observation,
                    rejectionLikelihood: .likely,
                    title: "NSPrivacyTracking contradicts tracking evidence",
                    detail: "The privacy manifest declares NSPrivacyTracking as false, but evidence of cross-app tracking code or declared tracking domains was found.",
                    whyItMatters: "A false NSPrivacyTracking declaration misrepresents the app's behavior to users and to Apple's privacy review process.",
                    evidence: evidence,
                    guidelineReference: "5.1.2",
                    suggestedFix: "Set NSPrivacyTracking = true in PrivacyInfo.xcprivacy if the app tracks users, and list all tracking domains in NSPrivacyTrackingDomains.",
                    estimatedFixMinutes: 10
                ))
            }

            // Required-reason API presence vs. manifest declaration.
            checks += 1
            let declaredCategories = Set(manifest.accessedAPITypes.map(\.categoryKey))
            for rule in Self.requiredReasonRules {
                guard rule.sourcePatterns.contains(where: { productionSource.contains($0) }) else { continue }
                guard !declaredCategories.contains(rule.categoryKey) else { continue }
                let matched = rule.sourcePatterns.first { productionSource.contains($0) } ?? rule.sourcePatterns[0]
                findings.append(Finding(
                    category: category,
                    severity: .warning,
                    confidence: .observation,
                    rejectionLikelihood: .likely,
                    title: "Required-reason API not declared in privacy manifest",
                    detail: "\(rule.apiName) appears in source but \(rule.categoryKey) is not declared in PrivacyInfo.xcprivacy's NSPrivacyAccessedAPITypes.",
                    whyItMatters: "Apple validates required-reason API declarations at submission; missing entries generate ITMS errors that block the build.",
                    evidence: "\"\(matched)\" found in source; \(rule.categoryKey) is absent from NSPrivacyAccessedAPITypes.",
                    suggestedFix: "Add a \(rule.categoryKey) entry with an appropriate reason code to NSPrivacyAccessedAPITypes in PrivacyInfo.xcprivacy.",
                    estimatedFixMinutes: 10
                ))
            }

            // Reason code validity check.
            checks += 1
            for entry in manifest.accessedAPITypes {
                guard let validCodes = Self.validReasonCodes[entry.categoryKey] else { continue }
                let invalid = entry.reasonCodes.filter { !validCodes.contains($0) }
                guard !invalid.isEmpty else { continue }
                findings.append(Finding(
                    category: category,
                    severity: .warning,
                    confidence: .fact,
                    rejectionLikelihood: .likely,
                    title: "Invalid required-reason code in privacy manifest",
                    detail: "\(entry.categoryKey) declares a reason code that is not in Apple's approved list.",
                    whyItMatters: "Submission with invalid reason codes is rejected at ITMS validation — codes must exactly match Apple's documented approved values.",
                    evidence: "Invalid code(s) for \(entry.categoryKey): \(invalid.joined(separator: ", ")). Valid codes: \(validCodes.sorted().joined(separator: ", ")).",
                    suggestedFix: "Replace the invalid reason code with one from Apple's approved list for this API category.",
                    estimatedFixMinutes: 5
                ))
            }
        }

        return AnalysisResult(category: category, findings: findings, checksPerformed: checks)
    }

    // MARK: - Helpers

    /// Removes #if DEBUG … #endif blocks so debug-only code paths don't
    /// trigger production privacy requirement findings.
    private func sourceStrippingDebugBlocks(_ source: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "#if\\s+DEBUG\\b[\\s\\S]*?#endif",
            options: []
        ) else { return source }
        let range = NSRange(source.startIndex..., in: source)
        return regex.stringByReplacingMatches(in: source, range: range, withTemplate: "")
    }

    private struct PrivacyManifest {
        struct AccessedAPIEntry {
            let categoryKey: String
            let reasonCodes: [String]
        }
        let collectedDataTypes: Set<String>
        let privacyTracking: Bool
        let trackingDomains: [String]
        let accessedAPITypes: [AccessedAPIEntry]
    }

    private func parsePrivacyManifest(at url: URL) -> PrivacyManifest? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        let collectedEntries = plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? []
        let collectedTypes = Set(collectedEntries.compactMap { $0["NSPrivacyCollectedDataType"] as? String })

        let privacyTracking = plist["NSPrivacyTracking"] as? Bool ?? false
        let trackingDomains = plist["NSPrivacyTrackingDomains"] as? [String] ?? []

        let apiEntries = plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        let accessedAPITypes: [PrivacyManifest.AccessedAPIEntry] = apiEntries.compactMap { entry in
            guard let key = entry["NSPrivacyAccessedAPIType"] as? String else { return nil }
            let reasons = entry["NSPrivacyAccessedAPITypeReasonCodes"] as? [String] ?? []
            return PrivacyManifest.AccessedAPIEntry(categoryKey: key, reasonCodes: reasons)
        }

        return PrivacyManifest(
            collectedDataTypes: collectedTypes,
            privacyTracking: privacyTracking,
            trackingDomains: trackingDomains,
            accessedAPITypes: accessedAPITypes
        )
    }
}
