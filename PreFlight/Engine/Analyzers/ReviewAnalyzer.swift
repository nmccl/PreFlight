import Foundation

/// Scans for patterns that commonly cause App Review rejections. Everything
/// here is a heuristic over source text, so every finding is an observation —
/// a reviewer may question it, but it is never a guaranteed failure.
struct ReviewAnalyzer: Analyzer {
    let category = AnalysisCategory.review

    private static let paymentSteeringPatterns = [
        "checkout." + "stripe.com", "pay" + "pal.me/", "buy on" + " our website", "purchase on" + " our site",
    ]

    private static let attributionProviders = [
        "open" + "weathermap", "weather" + "api.com", "Weather" + "Kit",
    ]

    private static let signUpPatterns = ["create" + "User", "create" + "Account", "sign" + "Up", "SignUp" + "View"]
    private static let deletionPatterns = ["delete" + "Account", "delete" + " account", "account" + " deletion", "delete" + "User"]

    func analyze(_ context: AnalysisContext) async -> AnalysisResult {
        let source = context.combinedSource()
        let lowercasedSource = source.lowercased()

        var findings: [Finding] = []
        var checks = 0

        checks += 1
        if source.contains("UI" + "WebView") {
            findings.append(Finding(
                category: category,
                severity: .warning,
                confidence: .observation,
                rejectionLikelihood: .likely,
                title: "UIWebView is no longer accepted",
                detail: "A reference to UIWebView appears in the project source.",
                whyItMatters: "Apple stopped accepting submissions that use UIWebView — if this reference ends up in the built app, it fails automated validation before a reviewer ever sees it.",
                evidence: "\"UIWebView\" found in project source.",
                suggestedFix: "Replace UIWebView with WKWebView.",
                estimatedFixMinutes: 60
            ))
        }

        checks += 1
        let steering = Self.paymentSteeringPatterns.filter { lowercasedSource.contains($0.lowercased()) }
        if !steering.isEmpty {
            findings.append(Finding(
                category: category,
                severity: .warning,
                confidence: .observation,
                rejectionLikelihood: .likely,
                title: "Possible external payment steering",
                detail: "The code appears to direct users toward purchasing outside the App Store.",
                whyItMatters: "Steering users to buy digital content outside the App Store is one of the most common rejection reasons. References that only cover physical goods and services are allowed.",
                evidence: "Found in source: \(steering.map { "\"\($0)\"" }.joined(separator: ", ")).",
                guidelineReference: "3.1.1",
                suggestedFix: "Sell digital content through in-app purchase, or confirm these references only cover physical goods and services.",
                estimatedFixMinutes: 30
            ))
        }

        checks += 1
        if lowercasedSource.contains("lorem" + " ipsum") {
            findings.append(Finding(
                category: category,
                severity: .warning,
                confidence: .observation,
                rejectionLikelihood: .possible,
                title: "Placeholder text in the app",
                detail: "\"Lorem ipsum\" appears in the project source.",
                whyItMatters: "Reviewers reject apps that visibly ship placeholder content — it signals the app isn't finished.",
                evidence: "\"lorem ipsum\" found in project source.",
                guidelineReference: "2.1",
                suggestedFix: "Replace placeholder text with final copy before submitting.",
                estimatedFixMinutes: 15
            ))
        }

        checks += 1
        let insecureURLs = insecureURLCount(in: source)
        if insecureURLs > 0 {
            findings.append(Finding(
                category: category,
                severity: .warning,
                confidence: .observation,
                rejectionLikelihood: .possible,
                title: "Insecure http:// URLs in code",
                detail: "The code contains plain-HTTP URLs.",
                whyItMatters: "App Transport Security blocks plain HTTP by default, so these requests fail at runtime — and a feature that breaks in front of a reviewer reads as an incomplete app.",
                evidence: "Found \(insecureURLs) http:// URL(s) in project source (excluding XML namespaces and DTDs).",
                suggestedFix: "Use https:// endpoints, or add a narrowly-scoped ATS exception with justification.",
                estimatedFixMinutes: 15
            ))
        }

        checks += 1
        let providers = Self.attributionProviders.filter { lowercasedSource.contains($0.lowercased()) }
        if !providers.isEmpty {
            findings.append(Finding(
                category: category,
                severity: .suggestion,
                confidence: .observation,
                rejectionLikelihood: .possible,
                title: "Data provider may require attribution",
                detail: "The app appears to use a third-party data provider.",
                whyItMatters: "Weather and similar data providers (including Apple's WeatherKit) require visible attribution in the UI; missing attribution violates their terms and can be flagged in review.",
                evidence: "Found in source: \(providers.joined(separator: ", ")).",
                suggestedFix: "Show the provider's required attribution and a link where the data appears.",
                estimatedFixMinutes: 15
            ))
        }

        checks += 1
        let matchedSignUp = Self.signUpPatterns.filter { source.contains($0) }
        let hasDeletion = Self.deletionPatterns.contains { lowercasedSource.contains($0.lowercased()) }
        if !matchedSignUp.isEmpty && !hasDeletion {
            findings.append(Finding(
                category: category,
                severity: .warning,
                confidence: .observation,
                rejectionLikelihood: .likely,
                title: "Account creation without account deletion",
                detail: "The app appears to let users create accounts, but no account-deletion path was found.",
                whyItMatters: "Apps that support account creation must also offer in-app account deletion — reviewers check for it, and its absence is a recurring rejection.",
                evidence: "Found account-creation patterns (\(matchedSignUp.joined(separator: ", "))); no deletion pattern (deleteAccount, account deletion, ...) found.",
                guidelineReference: "5.1.1(v)",
                suggestedFix: "Add an in-app way to initiate account deletion, typically in account settings.",
                estimatedFixMinutes: 60
            ))
        }

        // App with login requires demo credentials for review.
        checks += 1
        if !matchedSignUp.isEmpty {
            findings.append(Finding(
                category: category,
                severity: .warning,
                confidence: .observation,
                rejectionLikelihood: .likely,
                title: "App may need demo credentials for App Review",
                detail: "The app appears to require account creation or login. Reviewers who can't get past a login screen mark the app as not reviewable.",
                whyItMatters: "If a reviewer can't evaluate the app because they can't log in, it is rejected. Demo credentials must be provided in App Review Information in App Store Connect.",
                evidence: "Found sign-up/login patterns: \(matchedSignUp.joined(separator: ", ")).",
                guidelineReference: "2.1",
                suggestedFix: "Add a working demo username and password to App Review Information in App Store Connect, or implement a guest/demo mode reviewers can use without signing up.",
                estimatedFixMinutes: 10
            ))
        }

        // Purchases behind a sign-up wall.
        checks += 1
        let startsPurchases = source.contains("." + "purchase(")
        if !matchedSignUp.isEmpty && startsPurchases {
            findings.append(Finding(
                category: category,
                severity: .suggestion,
                confidence: .observation,
                rejectionLikelihood: .possible,
                title: "Verify purchases don't require an account",
                detail: "The app appears to have both account creation and in-app purchases.",
                whyItMatters: "If users must register before they can buy, reviewers reject the flow — purchases have to work as a guest unless the purchase is unusable without an account.",
                evidence: "Found account-creation patterns (\(matchedSignUp.joined(separator: ", "))) and \".purchase(\" in source.",
                guidelineReference: "5.1.1",
                suggestedFix: "Make the purchase flow reachable without signing up, and gate only truly account-bound features behind login.",
                estimatedFixMinutes: 30
            ))
        }

        // Personal data collected and sent over the network.
        checks += 1
        let usesNetwork = source.contains("URL" + "Session") || source.contains("Alamo" + "fire")
        if !matchedSignUp.isEmpty && usesNetwork {
            findings.append(Finding(
                category: category,
                severity: .suggestion,
                confidence: .observation,
                rejectionLikelihood: .possible,
                title: "Confirm users consent before personal data is uploaded",
                detail: "The app appears to collect account details and talk to a server.",
                whyItMatters: "Users must be told what personal data is collected and agree before it leaves the device — silent uploads of names, emails, or usage data are a privacy rejection.",
                evidence: "Found account-creation patterns (\(matchedSignUp.joined(separator: ", "))) and networking (URLSession) in source.",
                guidelineReference: "5.1.1",
                suggestedFix: "Show what's collected and get explicit agreement before the first upload, and cover it in the privacy policy.",
                estimatedFixMinutes: 20
            ))
        }

        return AnalysisResult(category: category, findings: findings, checksPerformed: checks)
    }

    /// Counts http:// occurrences, ignoring XML namespaces, DTD declarations,
    /// and bare scheme strings not followed by a real domain character.
    private func insecureURLCount(in source: String) -> Int {
        let needle = "http" + "://"
        let allowedPrefixes = ["http" + "://www.w3.org", "http" + "://apple.com/DTDs", "http" + "://www.apple.com/DTDs"]
        var count = 0
        var searchRange = source.startIndex..<source.endIndex
        while let range = source.range(of: needle, range: searchRange) {
            searchRange = range.upperBound..<source.endIndex
            // Real URLs start with a letter or digit after ://; skip bare scheme strings.
            guard range.upperBound < source.endIndex,
                  source[range.upperBound].isLetter || source[range.upperBound].isNumber else { continue }
            let remainder = source[range.lowerBound...]
            if !allowedPrefixes.contains(where: { remainder.hasPrefix($0) }) {
                count += 1
            }
        }
        return count
    }
}
