import Foundation

/// Checks privacy requirements: usage-description strings for sensitive APIs,
/// the presence of a privacy manifest, and whether detected third-party SDKs
/// have their expected data types declared in PrivacyInfo.xcprivacy.
/// Framework usage is inferred from source text, so those findings are
/// observations, not facts.
struct PrivacyAnalyzer: Analyzer {
    let category = AnalysisCategory.privacy

    /// Source patterns that trigger a required Info.plist usage description.
    /// Accessing these capabilities without a description is an automatic
    /// App Review rejection.
    private struct UsageRule {
        let sourcePattern: String
        let plistKey: String
        let capability: String
    }

    private static let usageRules = [
        UsageRule(sourcePattern: "AVCaptureDevice", plistKey: "NSCameraUsageDescription", capability: "the camera"),
        UsageRule(sourcePattern: "AVAudioRecorder", plistKey: "NSMicrophoneUsageDescription", capability: "the microphone"),
        UsageRule(sourcePattern: "import CoreLocation", plistKey: "NSLocationWhenInUseUsageDescription", capability: "location"),
        UsageRule(sourcePattern: "import Contacts", plistKey: "NSContactsUsageDescription", capability: "contacts"),
        UsageRule(sourcePattern: "import EventKit", plistKey: "NSCalendarsUsageDescription", capability: "the calendar"),
        UsageRule(sourcePattern: "import CoreBluetooth", plistKey: "NSBluetoothAlwaysUsageDescription", capability: "Bluetooth"),
        UsageRule(sourcePattern: "import Speech", plistKey: "NSSpeechRecognitionUsageDescription", capability: "speech recognition"),
        UsageRule(sourcePattern: "import HealthKit", plistKey: "NSHealthShareUsageDescription", capability: "health data"),
        UsageRule(sourcePattern: "import AppTrackingTransparency", plistKey: "NSUserTrackingUsageDescription", capability: "tracking"),
        UsageRule(sourcePattern: "import Photos", plistKey: "NSPhotoLibraryUsageDescription", capability: "the photo library"),
        UsageRule(sourcePattern: "LAContext", plistKey: "NSFaceIDUsageDescription", capability: "Face ID or Touch ID"),
    ]

    /// APIs that require a documented reason in a privacy manifest.
    private static let requiredReasonPatterns = ["UserDefaults", ".systemUptime", "creationDate", "volumeAvailableCapacity"]

    func analyze(_ context: AnalysisContext) async -> AnalysisResult {
        var findings: [Finding] = []
        var checks = 0

        let allSource = context.combinedSource()
        let allPresentKeys = Set(context.infoPlists.values.flatMap(\.presentKeys))
        let allStringValues = context.infoPlists.values.reduce(into: [String: String]()) { merged, plist in
            merged.merge(plist.stringValues) { existing, _ in existing }
        }

        for rule in Self.usageRules {
            checks += 1
            guard allSource.contains(rule.sourcePattern) else { continue }

            if !allPresentKeys.contains(rule.plistKey) {
                findings.append(Finding(
                    category: category,
                    severity: .warning,
                    confidence: .observation,
                    rejectionLikelihood: .likely,
                    title: "Missing \(rule.plistKey)",
                    detail: "The code appears to use \(rule.capability), but no \(rule.plistKey) was found in the Info.plist or build settings.",
                    whyItMatters: "If the app really accesses \(rule.capability), a missing usage description is an automatic rejection — it's one of the most common App Review blockers.",
                    evidence: "Found \"\(rule.sourcePattern)\" in source; \(rule.plistKey) is not present in any Info.plist or INFOPLIST_KEY build setting.",
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

        checks += 1
        let hasPrivacyManifest = context.resourceFileURLs.contains { $0.lastPathComponent == "PrivacyInfo.xcprivacy" }
        if !hasPrivacyManifest {
            let matchedReasonAPIs = Self.requiredReasonPatterns.filter { allSource.contains($0) }
            if !matchedReasonAPIs.isEmpty {
                findings.append(Finding(
                    category: category,
                    severity: .warning,
                    confidence: .observation,
                    rejectionLikelihood: .likely,
                    title: "No privacy manifest, but required-reason APIs in use",
                    detail: "The code appears to use APIs that Apple classifies as \"required reason\" APIs, and there is no PrivacyInfo.xcprivacy declaring those reasons.",
                    whyItMatters: "Apple validates required-reason API declarations at submission; missing reasons generate ITMS warnings and can block the build from review.",
                    evidence: "Found in source: \(matchedReasonAPIs.joined(separator: ", ")). No PrivacyInfo.xcprivacy in the project.",
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
        } else {
            // Third-party SDK vs. privacy manifest data-type cross-check.
            // Only runs when a manifest is present — the finding above handles the absent case.
            checks += 1
            if let declaredTypes = parsePrivacyManifestDataTypes(in: context.resourceFileURLs) {
                for sdk in KnownDataCollector.all where sdk.sourcePatterns.contains(where: { allSource.contains($0) }) {
                    let undeclared = sdk.xcprivacyTypes.filter { !declaredTypes.contains($0) }
                    guard !undeclared.isEmpty else { continue }
                    let detectedVia = sdk.sourcePatterns.first { allSource.contains($0) } ?? sdk.name
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
            }
        }

        return AnalysisResult(category: category, findings: findings, checksPerformed: checks)
    }

    /// Parses PrivacyInfo.xcprivacy and returns the set of declared
    /// NSPrivacyCollectedDataType strings, or nil if the file can't be read.
    private func parsePrivacyManifestDataTypes(in urls: [URL]) -> Set<String>? {
        guard let url = urls.first(where: { $0.lastPathComponent == "PrivacyInfo.xcprivacy" }),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        let entries = plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? []
        return Set(entries.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
    }
}
