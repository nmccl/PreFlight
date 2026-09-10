import Foundation
import FoundationModels

/// A compact, deterministically-derived description of what the application
/// actually is and does.
///
/// This exists so the verification pass never has to read the project. Every
/// value here comes from evidence the analyzers already collected, and the
/// behavioral flags are computed from application code with comments, string
/// literals, tests, and vendored dependencies excluded — so a keyword in prose
/// can't turn into a claim about behavior.
struct ApplicationFacts: Sendable {
    let platforms: String
    let hasAuthenticationFlow: Bool
    let capabilityAPIs: [String]
    let entitlementKeys: [String]
    let hasPrivacyManifest: Bool
    let usesInAppPurchase: Bool
    let dependencies: [String]

    /// Code-level signals for capabilities a reviewer cares about. Keys are the
    /// human name; values are API symbols that only appear when the app really
    /// calls the capability.
    private static let capabilitySignals: [String: [String]] = [
        "camera": ["AVCaptureDevice", "UIImagePickerController", "AVCaptureSession", "CameraCaptureMode"],
        "microphone": ["AVAudioRecorder", "AVAudioEngine", "AVCaptureAudio", "SFSpeechRecognizer"],
        "location": ["CLLocationManager", "CoreLocation", "requestWhenInUseAuthorization", "LocationButton"],
        "contacts": ["CNContactStore", "CNContact", "ContactAccessButton"],
        "photo library": ["PHPhotoLibrary", "PHPickerViewController", "PhotosPicker"],
        "health data": ["HKHealthStore", "HKQuery"],
        "Bluetooth": ["CBCentralManager", "CBPeripheralManager"],
        "calendar": ["EKEventStore"],
    ]

    private static let authenticationSignals = [
        "ASAuthorizationController", "ASAuthorizationAppleIDProvider", "SignInWithApple",
        "signIn(", "logIn(", "createUser", "createAccount", "Auth.auth", "signUp(",
    ]

    static func build(from context: AnalysisContext) -> ApplicationFacts {
        let code = context.applicationCode()

        let capabilities = capabilitySignals
            .filter { _, symbols in symbols.contains { code.contains($0) } }
            .keys
            .sorted()

        let entitlementKeys = context.evidenceBundle.entitlements.values
            .flatMap { Array($0.keys.keys) }
            .sorted()

        return ApplicationFacts(
            platforms: context.platforms.displayName,
            hasAuthenticationFlow: authenticationSignals.contains { code.contains($0) },
            capabilityAPIs: capabilities,
            entitlementKeys: Array(entitlementKeys.prefix(10)),
            hasPrivacyManifest: context.evidenceBundle.privacyManifest != nil,
            usesInAppPurchase: code.contains("StoreKit") || code.contains("Product.products")
                || !context.evidenceBundle.storeKitConfigs.isEmpty,
            dependencies: Array((context.evidenceBundle.dependencies?.packageNames ?? []).prefix(8))
        )
    }

    /// Roughly 150 tokens, which is the whole point.
    var promptDescription: String {
        """
        APPLICATION FACTS (established by static analysis of the app's own code, \
        excluding comments, string literals, tests, and third-party dependencies):
        - Target platforms: \(platforms)
        - Has an authentication/login flow: \(hasAuthenticationFlow ? "YES" : "NO")
        - Sensitive capability APIs actually called: \(capabilityAPIs.isEmpty ? "none" : capabilityAPIs.joined(separator: ", "))
        - Entitlements declared: \(entitlementKeys.isEmpty ? "none" : entitlementKeys.joined(separator: ", "))
        - Privacy manifest present: \(hasPrivacyManifest ? "YES" : "NO")
        - Uses In-App Purchase: \(usesInAppPurchase ? "YES" : "NO")
        - Dependencies: \(dependencies.isEmpty ? "none" : dependencies.joined(separator: ", "))
        """
    }
}

/// One verdict on one candidate finding.
@Generable
struct FindingVerdict: Sendable {
    @Guide(description: "The candidate's number, exactly as listed in the prompt")
    let index: Int

    @Guide(description: "Exactly one of: CONFIRM, REJECT, UNCERTAIN")
    let verdict: String

    @Guide(description: "One short sentence explaining the verdict")
    let reason: String
}

@Generable
struct FindingVerdictList: Sendable {
    @Guide(description: "One verdict per candidate, in the order listed", .maximumCount(6))
    let verdicts: [FindingVerdict]
}

/// Semantic verification layer between deterministic detection and the final
/// report.
///
/// Deterministic analyzers answer "does this pattern appear?" They can't answer
/// "does this actually apply to this application?" That second question is what
/// produces false positives, and it's the only thing this pass is for.
///
/// Scope is deliberately narrow:
/// - Only `.observation` findings are verified. A `.fact` was derived from a
///   verifiable configuration value, so it stays deterministic and never costs
///   a model round trip.
/// - At most `maxCandidates` are sent, in one batched call with no tools, so
///   the session stays far inside the context window.
/// - The model sees compact `ApplicationFacts`, never the project.
struct AIFindingVerifier: Sendable {

    /// Batched into a single request; more than this and the verdict list
    /// starts competing with the facts for context.
    static let maxCandidates = 6

    func verify(results: [AnalysisResult], facts: ApplicationFacts) async -> [AnalysisResult] {
        guard SystemLanguageModel.default.availability == .available else { return results }

        // Observations are heuristics over text; facts are verified config.
        let candidates = results
            .flatMap(\.findings)
            .filter { $0.confidence == .observation }
            .sorted { $0.severity < $1.severity }
            .prefix(Self.maxCandidates)

        guard !candidates.isEmpty else { return results }

        let verdicts = await requestVerdicts(for: Array(candidates), facts: facts)
        guard !verdicts.isEmpty else { return results }

        // Map verdicts back by finding ID so ordering mistakes can't misapply them.
        var decisions: [UUID: String] = [:]
        for verdict in verdicts {
            let position = verdict.index - 1
            guard candidates.indices.contains(position) else { continue }
            decisions[candidates[position].id] = verdict.verdict.uppercased()
        }

        return results.map { result in
            guard !result.wasSkipped else { return result }
            let kept = result.findings.compactMap { finding -> Finding? in
                switch decisions[finding.id] {
                case "REJECT":
                    print("[PreFlight AI] Rejected false positive: \(finding.title)")
                    return nil
                case "UNCERTAIN":
                    return downgraded(finding)
                default:
                    // CONFIRM, unverified, or an unrecognized verdict: keep as-is.
                    return finding
                }
            }
            return AnalysisResult(
                category: result.category,
                findings: kept,
                checksPerformed: result.checksPerformed
            )
        }
    }

    // MARK: - Private

    private func requestVerdicts(
        for candidates: [Finding],
        facts: ApplicationFacts
    ) async -> [FindingVerdict] {
        let session = LanguageModelSession(instructions: """
            You decide whether a static-analysis finding genuinely applies to an \
            application, using only the facts provided.

            The single rule: text describing a behavior is not evidence the \
            application performs it. A keyword in a comment, a string literal, a \
            documentation reference, a test fixture, or a dependency's source \
            does not mean the app does that thing.

            For each candidate answer exactly one verdict:
            - CONFIRM: the facts show the issue really applies to this app.
            - REJECT: the facts show it does not apply — wrong platform, the \
            capability is never actually used, or no such flow exists.
            - UNCERTAIN: the facts are insufficient to decide either way.

            Judge only against the facts given. Do not speculate about code you \
            cannot see. When a candidate depends on something the facts don't \
            cover, answer UNCERTAIN rather than guessing.
            """)
        session.prewarm()

        let list = candidates.enumerated().map { index, finding in
            "\(index + 1). [\(finding.category.displayName)] \(finding.title)\n   Evidence: \(finding.evidence ?? "none")"
        }.joined(separator: "\n")

        let prompt = """
            \(facts.promptDescription)

            CANDIDATE FINDINGS:
            \(list)

            Give one verdict for each of the \(candidates.count) candidates.
            """

        do {
            let response = try await session.respond(to: prompt, generating: FindingVerdictList.self)
            print("[PreFlight AI] Verification: \(response.content.verdicts.count) verdicts for \(candidates.count) candidates")
            return response.content.verdicts
        } catch LanguageModelError.contextSizeExceeded {
            print("[PreFlight AI] Verification exceeded context — keeping all candidates")
            return []
        } catch {
            print("[PreFlight AI] Verification failed: \(error) — keeping all candidates")
            return []
        }
    }

    /// An unverifiable candidate stays in the report but stops claiming
    /// confidence it hasn't earned: one severity step down, and flagged for
    /// manual confirmation.
    private func downgraded(_ finding: Finding) -> Finding {
        let softer: Severity
        switch finding.severity {
        case .critical, .warning: softer = .review
        case .review, .suggestion: softer = .suggestion
        }

        let note = "Not confirmed against the application's own code — verify manually."
        return Finding(
            id: finding.id,
            category: finding.category,
            severity: softer,
            confidence: .observation,
            rejectionLikelihood: .possible,
            title: finding.title,
            detail: finding.detail,
            whyItMatters: finding.whyItMatters,
            evidence: finding.evidence.map { "\($0)\n\(note)" } ?? note,
            guidelineReference: finding.guidelineReference,
            suggestedFix: finding.suggestedFix,
            estimatedFixMinutes: finding.estimatedFixMinutes,
            affectedPath: finding.affectedPath
        )
    }
}
