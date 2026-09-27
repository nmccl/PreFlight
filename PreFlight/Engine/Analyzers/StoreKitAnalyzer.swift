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
        // Transaction.currentEntitlements is for launch-time entitlement
        // verification, not a user-facing restore path. Only AppStore.sync()
        // (StoreKit 2) or restoreCompletedTransactions (StoreKit 1) counts.
        let hasRestorePath = source.contains("AppStore" + ".sync")
            || source.contains("restoreCompletedTransactions")
        if startsPurchases && !hasRestorePath {
            findings.append(Finding(
                category: .review,
                severity: .warning,
                confidence: .observation,
                rejectionLikelihood: .likely,
                title: "No way to restore purchases",
                detail: "The code appears to start purchases but no restore path was found. Checking Transaction.currentEntitlements at launch verifies ownership but does not substitute for a Restore Purchases button.",
                whyItMatters: "Apps that sell content must let users restore it on a new device. Reviewers test the restore path explicitly — its absence is a reliable rejection.",
                evidence: "\".purchase(\" found in source; no AppStore.sync() or restoreCompletedTransactions reference found.",
                guidelineReference: "3.1.1",
                suggestedFix: "Add a Restore Purchases button that calls AppStore.sync(). You can also check Transaction.currentEntitlements at launch to auto-restore silently.",
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

        // MARK: Commerce account prerequisites
        //
        // Selling anything requires the Paid Applications Agreement to be
        // active and tax forms to be complete. Neither is exposed by the App
        // Store Connect API, so this can't be verified — but an unsigned
        // agreement or a missing W-9 blocks the submission regardless of how
        // correct the code is, and it's invisible until the rejection arrives.
        // Reported as Review severity: something to confirm, not a defect.
        checks += 1
        findings.append(Finding(
            category: category,
            severity: .review,
            confidence: .observation,
            rejectionLikelihood: .possible,
            title: "Confirm Paid Applications Agreement and tax forms are active",
            detail: "This app sells through StoreKit. Selling requires an active Paid Applications Agreement plus completed tax and banking information in App Store Connect under Business.",
            whyItMatters: "An unsigned Paid Applications Agreement or an incomplete tax form (W-9 for US entities, W-8BEN or W-8BEN-E otherwise) blocks a paid submission no matter how the app is built. Purchases also fail in review when the agreement isn't active.",
            evidence: "StoreKit purchase code found in the project. Agreement, tax, and banking status are not exposed by the App Store Connect API, so PreFlight cannot verify them.",
            suggestedFix: "In App Store Connect, open Business and confirm: the Paid Applications Agreement shows Active, bank details are added, and the correct tax form is complete for every relevant region.",
            estimatedFixMinutes: 20
        ))

        // The App Store product page needs a functional Terms of Use link for
        // subscription apps. MetadataAnalyzer verifies this against the live
        // description when credentials exist; without them nobody checks it,
        // which is precisely how a submission reaches Apple's automated
        // pre-review check and bounces.
        if hasAutoRenewableSubscriptions(in: configFiles),
           context.evidenceBundle.ascSnapshot == nil {
            checks += 1
            findings.append(Finding(
                category: category,
                severity: .review,
                confidence: .observation,
                rejectionLikelihood: .likely,
                title: "Confirm the App Store description links to Terms of Use",
                detail: "This app sells auto-renewable subscriptions. The App Store product page must carry a functional Terms of Use (EULA) link.",
                whyItMatters: "Apple runs an automated check before review: a subscription app whose product page has no working Terms of Use link is returned immediately, before a human sees it. The words \"Terms of Use\" without a URL do not satisfy it.",
                evidence: "Auto-renewable subscriptions found in the StoreKit configuration; no App Store Connect credentials are configured, so the live description could not be checked.",
                guidelineReference: "3.1.2",
                suggestedFix: "Paste the full Terms of Use URL into the App Description (Apple's standard EULA is https://www.apple.com/legal/internet-services/itunes/dev/stdeula/), or set a custom EULA in App Store Connect. Add App Store Connect credentials in Settings to have PreFlight verify this automatically.",
                estimatedFixMinutes: 10
            ))
        }

        return AnalysisResult(category: category, findings: findings, checksPerformed: checks)
    }

    /// True when any StoreKit configuration declares a subscription group,
    /// which is how auto-renewable subscriptions are represented.
    private func hasAutoRenewableSubscriptions(in configFiles: [URL]) -> Bool {
        configFiles.contains { url in
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let groups = json["subscriptionGroups"] as? [[String: Any]]
            else { return false }
            return groups.contains { group in
                !((group["subscriptions"] as? [[String: Any]]) ?? []).isEmpty
            }
        }
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
