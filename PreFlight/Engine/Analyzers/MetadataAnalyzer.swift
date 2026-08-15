import Foundation

/// Checks the app's real App Store Connect record: privacy policy, support
/// and marketing URLs, description, keywords, screenshots, subscriptions,
/// reviewer information, and the App Privacy nutrition label. Skips gracefully
/// when no credentials are configured. Everything fetched from ASC is a fact.
struct MetadataAnalyzer: Analyzer {
    let category = AnalysisCategory.metadata

    func analyze(_ context: AnalysisContext) async -> AnalysisResult {
        guard let credentials = context.ascCredentials else {
            return .skipped(category, reason: "Add App Store Connect credentials in Settings to check metadata.")
        }
        guard let bundleID = context.project.bundleIdentifier, !bundleID.isEmpty else {
            return .skipped(category, reason: "The project has no bundle identifier to look up on App Store Connect.")
        }

        let client = ASCClient(credentials: credentials)
        var findings: [Finding] = []
        var checks = 0

        do {
            checks += 1
            guard let app = try await client.app(forBundleID: bundleID) else {
                findings.append(Finding(
                    category: category,
                    severity: .critical,
                    confidence: .fact,
                    rejectionLikelihood: .certain,
                    title: "App not found on App Store Connect",
                    detail: "No app record matches this project's bundle identifier.",
                    whyItMatters: "Nothing can be submitted for review until the app exists in App Store Connect — reviewers can only evaluate an app that has a record.",
                    evidence: "GET /v1/apps returned no app for bundle ID \"\(bundleID)\".",
                    suggestedFix: "Create the app in App Store Connect (Apps > +), or fix the project's bundle identifier.",
                    estimatedFixMinutes: 15
                ))
                return AnalysisResult(category: category, findings: findings, checksPerformed: checks)
            }

            checks += 1
            let infoLocalizations = try await client.appInfoLocalizations(forAppID: app.id)
            let missingPrivacy = infoLocalizations
                .filter { ($0.attributes.privacyPolicyUrl ?? "").isEmpty }
                .compactMap(\.attributes.locale)
            if !missingPrivacy.isEmpty {
                findings.append(Finding(
                    category: category,
                    severity: .critical,
                    confidence: .fact,
                    rejectionLikelihood: .certain,
                    title: "Privacy Policy URL is missing",
                    detail: "The App Store Connect record has no privacy policy URL for one or more locales.",
                    whyItMatters: "This is a common App Review blocker: users must be able to read a privacy policy before downloading the app, and App Store Connect won't accept a submission without one.",
                    evidence: "privacyPolicyUrl is empty for: \(missingPrivacy.joined(separator: ", ")).",
                    guidelineReference: "5.1.1",
                    suggestedFix: "Add the privacy policy URL under App Information in App Store Connect.",
                    estimatedFixMinutes: 10
                ))
            }

            checks += 1
            guard let version = try await client.latestAppStoreVersion(forAppID: app.id) else {
                findings.append(Finding(
                    category: category,
                    severity: .critical,
                    confidence: .fact,
                    rejectionLikelihood: .certain,
                    title: "No App Store version created",
                    detail: "The app record exists, but it has no version yet.",
                    whyItMatters: "Metadata, screenshots, and builds all attach to a version — until one exists there is nothing to fill in or submit for review.",
                    evidence: "GET /v1/apps/\(app.id)/appStoreVersions returned no versions.",
                    suggestedFix: "Create the first version in App Store Connect and complete its metadata.",
                    estimatedFixMinutes: 10
                ))
                return AnalysisResult(category: category, findings: findings, checksPerformed: checks)
            }

            checks += 1
            let localizations = try await client.appStoreVersionLocalizations(forVersionID: version.id)
            findings.append(contentsOf: localizationFindings(for: localizations))

            checks += 4
            findings.append(contentsOf: await extendedFindings(
                client: client,
                appID: app.id,
                versionID: version.id,
                localizations: localizations
            ))

            // App Privacy nutrition label vs. source cross-check.
            checks += 1
            findings.append(contentsOf: await privacyLabelFindings(
                client: client,
                appID: app.id,
                context: context
            ))
        } catch {
            findings.append(Finding(
                category: category,
                severity: .warning,
                confidence: .fact,
                title: "Couldn't finish App Store Connect checks",
                detail: error.localizedDescription,
                suggestedFix: "Verify the API key in Settings and re-run the analysis."
            ))
        }

        return AnalysisResult(category: category, findings: findings, checksPerformed: checks)
    }

    // MARK: Extended checks

    /// The deeper checks behind common real-world rejections: screenshots,
    /// subscription metadata, Terms of Use, and reviewer information. Each
    /// endpoint is fetched with try? so a key with narrower permissions
    /// degrades to fewer checks instead of failing the whole category.
    private func extendedFindings(
        client: ASCClient,
        appID: String,
        versionID: String,
        localizations: [ASCResource<ASCClient.AppStoreVersionLocalizationAttributes>]
    ) async -> [Finding] {
        var findings: [Finding] = []

        // Screenshots per locale.
        var missingScreenshots: [String] = []
        for localization in localizations {
            if let sets = try? await client.screenshotSets(forLocalizationID: localization.id), sets.isEmpty {
                missingScreenshots.append(localization.attributes.locale ?? "unknown")
            }
        }
        if !missingScreenshots.isEmpty {
            findings.append(Finding(
                category: category,
                severity: .warning,
                confidence: .fact,
                rejectionLikelihood: .likely,
                title: "Screenshots are missing",
                detail: "One or more locales have no App Store screenshots.",
                whyItMatters: "A version can't be submitted without screenshots, and screenshots that don't reflect the app are a common metadata rejection.",
                evidence: "No screenshot sets for: \(missingScreenshots.joined(separator: ", ")).",
                guidelineReference: "2.3.3",
                suggestedFix: "Upload screenshots for each locale under the version in App Store Connect.",
                estimatedFixMinutes: 30
            ))
        }

        // Subscription metadata completeness.
        var hasSubscriptions = false
        if let groups = try? await client.subscriptionGroups(forAppID: appID) {
            var incomplete: [String] = []
            for group in groups {
                guard let subscriptions = try? await client.subscriptions(forGroupID: group.id) else { continue }
                if !subscriptions.isEmpty {
                    hasSubscriptions = true
                }
                incomplete.append(contentsOf: subscriptions
                    .filter { ($0.attributes.state ?? "").contains("MISSING_METADATA") }
                    .map { $0.attributes.name ?? $0.attributes.productId ?? "unnamed" })
            }
            if !incomplete.isEmpty {
                findings.append(Finding(
                    category: category,
                    severity: .warning,
                    confidence: .fact,
                    rejectionLikelihood: .likely,
                    title: "Subscription metadata is incomplete",
                    detail: "One or more subscriptions on App Store Connect are missing metadata.",
                    whyItMatters: "Apps with incomplete subscription metadata are frequently delayed or rejected during App Review — every subscription needs its localized name, description, and review screenshot before submission.",
                    evidence: "State is MISSING_METADATA for: \(incomplete.joined(separator: ", ")).",
                    guidelineReference: "3.1.2",
                    suggestedFix: "Open each subscription in App Store Connect and complete its metadata until the state reads Ready to Submit.",
                    estimatedFixMinutes: 20
                ))
            }
        }

        // Terms of Use for subscription apps: either a custom EULA or a
        // Terms link in the description is required.
        if hasSubscriptions {
            let customEULA = try? await client.endUserLicenseAgreement(forAppID: appID)
            let descriptionMentionsTerms = localizations.contains { localization in
                let description = (localization.attributes.description ?? "").lowercased()
                return description.contains("terms of use")
                    || description.contains("terms of service")
                    || description.contains("eula")
            }
            if customEULA == nil && !descriptionMentionsTerms {
                findings.append(Finding(
                    category: category,
                    severity: .warning,
                    confidence: .fact,
                    rejectionLikelihood: .likely,
                    title: "No Terms of Use (EULA) for a subscription app",
                    detail: "The app sells auto-renewable subscriptions, but there is no custom EULA and no Terms of Use link in the App Store description.",
                    whyItMatters: "Subscription apps must give users a Terms of Use link — either Apple's standard EULA referenced in the description or a custom EULA in App Store Connect. Reviewers turn back subscription submissions without it.",
                    evidence: "endUserLicenseAgreement is not set; no \"terms of use\", \"terms of service\", or \"EULA\" text found in any locale's description.",
                    guidelineReference: "3.1.2",
                    suggestedFix: "Add a Terms of Use (EULA) link to the App Description, or set a custom EULA in App Store Connect.",
                    estimatedFixMinutes: 10
                ))
            }
        }

        // Reviewer information. try? would flatten the "not set" nil into the
        // "request failed" nil, so catch explicitly to keep them distinct.
        do {
            let reviewDetail = try await client.appStoreReviewDetail(forVersionID: versionID)
            if let detail = reviewDetail {
                if detail.attributes.demoAccountRequired == true,
                   (detail.attributes.demoAccountName ?? "").isEmpty {
                    findings.append(Finding(
                        category: category,
                        severity: .warning,
                        confidence: .fact,
                        rejectionLikelihood: .likely,
                        title: "Demo account required but not provided",
                        detail: "The version says a demo account is required for review, but no credentials are filled in.",
                        whyItMatters: "If the reviewer can't sign in, the review stops immediately — missing demo credentials on a login-required app is one of the most common rejections.",
                        evidence: "appStoreReviewDetail has demoAccountRequired = true and an empty demoAccountName.",
                        suggestedFix: "Enter working demo account credentials under App Review Information for the version.",
                        estimatedFixMinutes: 10
                    ))
                }
            } else {
                findings.append(Finding(
                    category: category,
                    severity: .suggestion,
                    confidence: .fact,
                    rejectionLikelihood: .possible,
                    title: "No App Review information provided",
                    detail: "The version has no reviewer contact info, notes, or demo account.",
                    whyItMatters: "Review notes and a demo account are how you preempt reviewer confusion — apps that need context and don't provide it get rejected for things a sentence would have explained.",
                    evidence: "appStoreReviewDetail is not set for the latest version.",
                    suggestedFix: "Fill in App Review Information: contact details, notes about anything unusual, and demo credentials if the app has accounts.",
                    estimatedFixMinutes: 10
                ))
            }
        } catch {
            // Couldn't check reviewer info (narrow key permissions or a
            // network hiccup) — skip rather than guess.
        }

        return findings
    }

    // MARK: Privacy nutrition label cross-check

    /// Cross-references source-detected third-party SDKs against the app's
    /// declared App Privacy categories on App Store Connect. Uses try? on the
    /// ASC endpoint so a 404 or unexpected schema degrades gracefully.
    private func privacyLabelFindings(
        client: ASCClient,
        appID: String,
        context: AnalysisContext
    ) async -> [Finding] {
        let source = context.combinedSource()
        let detected = KnownDataCollector.all.filter { sdk in
            sdk.sourcePatterns.contains { source.contains($0) }
        }
        guard !detected.isEmpty else { return [] }

        guard let declarations = try? await client.appPrivacyDeclarations(forAppID: appID) else {
            return []
        }

        // No privacy categories declared on ASC at all while data-collecting
        // SDKs are present — the nutrition label is effectively empty.
        if declarations.isEmpty {
            let sdkNames = detected.map(\.name).joined(separator: ", ")
            return [Finding(
                category: category,
                severity: .warning,
                confidence: .observation,
                rejectionLikelihood: .likely,
                title: "App Privacy section not configured on App Store Connect",
                detail: "Data-collecting SDKs are detected in source, but the App Privacy section on App Store Connect has no declared data types.",
                whyItMatters: "Apple requires the App Privacy section to accurately reflect what your app and its SDKs collect. An empty nutrition label with data-collecting SDKs present is a documented App Review rejection cause.",
                evidence: "ASC App Privacy has no declared data types. Detected SDKs with known data collection: \(sdkNames).",
                guidelineReference: "5.1.1",
                suggestedFix: "Complete the App Privacy section in App Store Connect, declaring all data types your app and its third-party SDKs collect.",
                estimatedFixMinutes: 30
            )]
        }

        let declaredCategories = Set(declarations.compactMap { $0.attributes.category })
        // Non-empty declarations with all-nil categories means the schema
        // didn't match — skip to prevent false positives.
        guard !declaredCategories.isEmpty else { return [] }

        var findings: [Finding] = []
        for sdk in detected {
            let undeclared = sdk.ascCategories.filter { !declaredCategories.contains($0) }
            guard !undeclared.isEmpty else { continue }
            let detectedVia = sdk.sourcePatterns.first { source.contains($0) } ?? sdk.name
            let missingReadable = undeclared
                .map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
                .joined(separator: ", ")
            findings.append(Finding(
                category: category,
                severity: .warning,
                confidence: .observation,
                rejectionLikelihood: .likely,
                title: "\(sdk.name) data not declared in App Privacy",
                detail: "\(sdk.name) is detected in source and is known to collect user data, but the corresponding categories are missing from App Store Connect's App Privacy section.",
                whyItMatters: "A mismatch between what your app's SDKs actually collect and what you've declared in the privacy nutrition label is a documented App Review rejection cause — Apple specifically checks for this.",
                evidence: "Detected via \"\(detectedVia)\". Expected in ASC App Privacy but not declared: \(missingReadable).",
                guidelineReference: "5.1.1",
                suggestedFix: "In App Store Connect, open App Privacy and declare: \(missingReadable). Ensure purposes and data usage accurately reflect how \(sdk.name) uses this data in your app.",
                estimatedFixMinutes: 15
            ))
        }
        return findings
    }

    // MARK: Localization checks

    /// One aggregated finding per issue type, listing affected locales,
    /// instead of a flood of per-locale findings.
    private func localizationFindings(
        for localizations: [ASCResource<ASCClient.AppStoreVersionLocalizationAttributes>]
    ) -> [Finding] {
        var missingSupport: [String] = []
        var missingMarketing: [String] = []
        var shortDescriptions: [String] = []
        var missingKeywords: [String] = []
        var insecureURLs: [String] = []

        for localization in localizations {
            let attributes = localization.attributes
            let locale = attributes.locale ?? "unknown"

            if (attributes.supportUrl ?? "").isEmpty {
                missingSupport.append(locale)
            }
            if (attributes.marketingUrl ?? "").isEmpty {
                missingMarketing.append(locale)
            }
            let description = (attributes.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if description.count < 30 {
                shortDescriptions.append(locale)
            }
            if (attributes.keywords ?? "").isEmpty {
                missingKeywords.append(locale)
            }
            if [attributes.supportUrl, attributes.marketingUrl].contains(where: { $0?.hasPrefix("http://") == true }) {
                insecureURLs.append(locale)
            }
        }

        var findings: [Finding] = []

        if !missingSupport.isEmpty {
            findings.append(Finding(
                category: category,
                severity: .critical,
                confidence: .fact,
                rejectionLikelihood: .certain,
                title: "Support URL is missing",
                detail: "The version metadata has no support URL for one or more locales.",
                whyItMatters: "Apple requires a working way for users to reach you; submissions without a support URL are turned back before review completes.",
                evidence: "supportUrl is empty for: \(missingSupport.joined(separator: ", ")).",
                guidelineReference: "1.5",
                suggestedFix: "Add a support URL to the version metadata in App Store Connect.",
                estimatedFixMinutes: 5
            ))
        }
        if !shortDescriptions.isEmpty {
            findings.append(Finding(
                category: category,
                severity: .warning,
                confidence: .fact,
                rejectionLikelihood: .likely,
                title: "App description is empty or very short",
                detail: "The store description is under 30 characters for one or more locales.",
                whyItMatters: "Reviewers check that the description accurately explains what the app does; sparse descriptions are a common metadata rejection and hurt conversion.",
                evidence: "Description is under 30 characters for: \(shortDescriptions.joined(separator: ", ")).",
                guidelineReference: "2.3",
                suggestedFix: "Write a full description of what the app does in App Store Connect.",
                estimatedFixMinutes: 20
            ))
        }
        if !missingKeywords.isEmpty {
            findings.append(Finding(
                category: category,
                severity: .warning,
                confidence: .fact,
                rejectionLikelihood: .possible,
                title: "No keywords set",
                detail: "The keywords field is empty for one or more locales.",
                whyItMatters: "Keywords drive App Store search ranking; an empty field makes the app nearly impossible to find and leaves the metadata looking unfinished to a reviewer.",
                evidence: "keywords is empty for: \(missingKeywords.joined(separator: ", ")).",
                guidelineReference: "2.3",
                suggestedFix: "Add up to 100 characters of comma-separated keywords in App Store Connect.",
                estimatedFixMinutes: 10
            ))
        }
        if !missingMarketing.isEmpty {
            findings.append(Finding(
                category: category,
                severity: .suggestion,
                confidence: .fact,
                title: "No marketing URL",
                detail: "The marketing URL is empty for one or more locales.",
                whyItMatters: "It's optional, but a product page builds user trust and gives reviewers context about the app.",
                evidence: "marketingUrl is empty for: \(missingMarketing.joined(separator: ", ")).",
                suggestedFix: "Add a marketing URL in App Store Connect if you have a product page.",
                estimatedFixMinutes: 5
            ))
        }
        if !insecureURLs.isEmpty {
            findings.append(Finding(
                category: category,
                severity: .warning,
                confidence: .fact,
                rejectionLikelihood: .possible,
                title: "Metadata URLs use http://",
                detail: "Support or marketing URLs use plain HTTP for one or more locales.",
                whyItMatters: "Reviewers open these links; insecure or broken URLs are flagged during metadata review.",
                evidence: "Plain-HTTP URLs found for: \(insecureURLs.joined(separator: ", ")).",
                suggestedFix: "Use https:// versions of these URLs.",
                estimatedFixMinutes: 5
            ))
        }

        return findings
    }
}
