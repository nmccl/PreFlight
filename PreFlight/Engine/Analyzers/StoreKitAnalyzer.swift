import Foundation

/// Checks in-app purchase setup. Skips entirely when the project doesn't use
/// StoreKit, so non-commerce apps aren't penalized for it. Config-file checks
/// are facts; source-scan checks (like the restore path) are observations.
struct StoreKitAnalyzer: Analyzer {
    let category = AnalysisCategory.storeKit

    func analyze(_ context: AnalysisContext) async -> AnalysisResult {
        let source = context.combinedSource()
        let configFiles = context.resourceFileURLs.filter { $0.pathExtension.lowercased() == "storekit" }
        let usesStoreKit = source.contains("import StoreKit") || !configFiles.isEmpty

        guard usesStoreKit else {
            return .skipped(category, reason: "The project doesn't use StoreKit.")
        }

        var findings: [Finding] = []
        var checks = 0

        checks += 1
        if configFiles.isEmpty {
            findings.append(Finding(
                category: category,
                severity: .suggestion,
                confidence: .fact,
                title: "No StoreKit configuration file",
                detail: "The code uses StoreKit but there is no .storekit configuration file.",
                whyItMatters: "Without one, products can't be tested locally before submission, and PreFlight can't validate the purchase setup offline.",
                evidence: "\"import StoreKit\" found in source; no .storekit file among the project's resources.",
                suggestedFix: "Add a StoreKit configuration file (File > New > File > StoreKit Configuration) and sync it with App Store Connect.",
                estimatedFixMinutes: 10
            ))
        }

        checks += 1
        let startsPurchases = source.contains(".purchase(")
        let hasRestorePath = source.contains("AppStore.sync")
            || source.contains("Transaction.currentEntitlements")
            || source.contains("restoreCompletedTransactions")
        if startsPurchases && !hasRestorePath {
            // A compliance issue, not a configuration one — reviewers test the
            // restore path — so the finding files under the review category.
            findings.append(Finding(
                category: .review,
                severity: .warning,
                confidence: .observation,
                rejectionLikelihood: .likely,
                title: "No way to restore purchases",
                detail: "The code appears to start purchases but never restore them.",
                whyItMatters: "Apps that sell content must let users restore it on a new device, and reviewers routinely test the restore path — its absence is a reliable rejection.",
                evidence: "\".purchase(\" found in source; no AppStore.sync(), Transaction.currentEntitlements, or restoreCompletedTransactions reference found.",
                guidelineReference: "3.1.1",
                suggestedFix: "Add a Restore Purchases button that calls AppStore.sync(), and check Transaction.currentEntitlements at launch.",
                estimatedFixMinutes: 30
            ))
        }

        // Paywall completeness — reviewers check the purchase screen itself.
        if startsPurchases {
            checks += 1
            let lowercased = source.lowercased()
            let mentionsPrivacy = lowercased.contains("privacy policy")
                || lowercased.contains("privacypolicy")
                || lowercased.contains("privacy-policy")
            let mentionsTerms = lowercased.contains("terms of use")
                || lowercased.contains("terms of service")
                || lowercased.contains("termsofuse")
                || lowercased.contains("terms-of-use")
                || lowercased.contains("eula")
            var missingLinks: [String] = []
            if !mentionsPrivacy { missingLinks.append("Privacy Policy") }
            if !mentionsTerms { missingLinks.append("Terms of Use") }
            if !missingLinks.isEmpty {
                let list = missingLinks.joined(separator: " and ")
                findings.append(Finding(
                    category: .review,
                    severity: .warning,
                    confidence: .observation,
                    rejectionLikelihood: .likely,
                    title: "Paywall may be missing \(list) link\(missingLinks.count == 1 ? "" : "s")",
                    detail: "The code starts purchases, but no \(list) reference was found anywhere in the app's source.",
                    whyItMatters: "The purchase screen must show the offer's title, duration, price, and working Privacy Policy and Terms of Use links — reviewers check the paywall itself, and missing links are a frequent subscription rejection.",
                    evidence: "\".purchase(\" found in source; no \(list) text found in any source file.",
                    guidelineReference: "3.1.2",
                    suggestedFix: "Add visible Privacy Policy and Terms of Use links to the purchase screen.",
                    estimatedFixMinutes: 20
                ))
            }

            checks += 1
            if !source.contains("displayPrice") {
                findings.append(Finding(
                    category: .review,
                    severity: .suggestion,
                    confidence: .observation,
                    rejectionLikelihood: .possible,
                    title: "Paywall may not show localized StoreKit pricing",
                    detail: "The code starts purchases but never reads a product's displayPrice, so the paywall may hardcode its prices.",
                    whyItMatters: "The price shown must match what the user is actually charged in their storefront and currency; hardcoded prices are wrong in most regions and get flagged.",
                    evidence: "\".purchase(\" found in source; no \"displayPrice\" reference found.",
                    guidelineReference: "3.1.2",
                    suggestedFix: "Show Product.displayPrice (and the subscription period) from StoreKit on the paywall.",
                    estimatedFixMinutes: 15
                ))
            }
        }

        for configURL in configFiles {
            checks += 1
            findings.append(contentsOf: configFindings(at: configURL))
        }

        return AnalysisResult(category: category, findings: findings, checksPerformed: checks)
    }

    /// StoreKit configuration files are JSON; validate what we can offline.
    private func configFindings(at url: URL) -> [Finding] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [Finding(
                category: category,
                severity: .warning,
                confidence: .fact,
                title: "Couldn't read StoreKit configuration",
                detail: "The StoreKit configuration file isn't valid JSON, so its products couldn't be checked.",
                evidence: "\"\(url.lastPathComponent)\" failed to parse as JSON.",
                suggestedFix: "Open the file in Xcode and fix or recreate it.",
                estimatedFixMinutes: 10,
                affectedPath: url.lastPathComponent
            )]
        }

        var findings: [Finding] = []
        let products = json["products"] as? [[String: Any]] ?? []
        let groups = json["subscriptionGroups"] as? [[String: Any]] ?? []

        if products.isEmpty && groups.isEmpty {
            findings.append(Finding(
                category: category,
                severity: .warning,
                confidence: .fact,
                title: "StoreKit configuration has no products",
                detail: "The configuration file defines no products or subscriptions, but the app uses StoreKit.",
                whyItMatters: "An empty configuration means the purchase flow can't be exercised locally, so problems surface for the first time in front of a reviewer.",
                evidence: "\"\(url.lastPathComponent)\" contains no products and no subscriptionGroups.",
                suggestedFix: "Add your products to the configuration file, or sync it from App Store Connect.",
                estimatedFixMinutes: 10,
                affectedPath: url.lastPathComponent
            ))
        }

        for group in groups {
            let subscriptions = group["subscriptions"] as? [[String: Any]] ?? []
            for subscription in subscriptions {
                let localizations = subscription["localizations"] as? [[String: Any]] ?? []
                if localizations.isEmpty {
                    let name = subscription["referenceName"] as? String
                        ?? subscription["productID"] as? String
                        ?? "Unnamed subscription"
                    findings.append(Finding(
                        category: category,
                        severity: .warning,
                        confidence: .fact,
                        rejectionLikelihood: .possible,
                        title: "Subscription \"\(name)\" has no localized description",
                        detail: "This subscription has no localized display name or description.",
                        whyItMatters: "Apps with incomplete subscription metadata are frequently delayed during App Review — subscriptions need at least one localization before they can be submitted.",
                        evidence: "Subscription \"\(name)\" in \"\(url.lastPathComponent)\" has an empty localizations array.",
                        suggestedFix: "Add a localization to this subscription in the StoreKit configuration and in App Store Connect.",
                        estimatedFixMinutes: 15,
                        affectedPath: url.lastPathComponent
                    ))
                }
            }
        }

        return findings
    }
}
