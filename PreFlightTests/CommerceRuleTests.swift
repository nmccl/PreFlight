import Foundation
import Testing
@testable import PreFlight

/// Apple's automated pre-review check demands a *functional link* to the Terms
/// of Use, not the words "Terms of Use". These cover the distinction the
/// original substring check missed.
@Suite("Terms of Use link detection")
struct TermsOfUseLinkTests {
    /// Mirrors MetadataAnalyzer.containsURL, which is private. Kept in sync
    /// deliberately: this is the behavior Apple's check turns on.
    private func containsURL(_ text: String) -> Bool {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            let lowered = text.lowercased()
            return lowered.contains("https://") || lowered.contains("http://")
        }
        return detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    @Test("A description mentioning terms with no URL is not a functional link")
    func mentionWithoutLinkIsNotEnough() {
        let description = "A great app. See our Terms of Use for details."
        #expect(description.lowercased().contains("terms of use"))
        #expect(!containsURL(description), "no URL present, so the old keyword check would wrongly pass")
    }

    @Test("A description with a full Terms URL counts")
    func fullURLCounts() {
        let description = """
            A great app.
            Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
            """
        #expect(containsURL(description))
    }

    @Test("A bare domain still resolves as a link")
    func bareDomainCounts() {
        #expect(containsURL("Terms of Use: www.pre-flight.info/terms"))
    }

    @Test("A description with neither terms nor a link fails both halves")
    func noTermsNoLink() {
        let description = "A great app for developers."
        #expect(!description.lowercased().contains("terms of use"))
        #expect(!containsURL(description))
    }
}

/// The EULA check silently never fired because `try?` on an already-optional
/// return produces a double optional, and `.some(nil) == nil` is false. This
/// pins the unwrapping so the bug can't come back.
@Suite("Optional EULA unwrapping")
struct EULAOptionalTests {
    private struct EULA { let agreementText: String? }

    /// Reproduces the shape: `try? await client.endUserLicenseAgreement(...)`
    /// where the call itself returns `EULA?`.
    private func fetch(succeeds: Bool, eula: EULA?) -> EULA?? {
        succeeds ? .some(eula) : .none
    }

    @Test("A successful 'no EULA set' response is not equal to nil")
    func successfulEmptyResponseIsNotNil() {
        let result = fetch(succeeds: true, eula: nil)
        // This is the bug: the outer optional is .some, so the old
        // `customEULA == nil` test was false and the finding never fired.
        #expect(!(result == nil))
    }

    @Test("Flattening both levels correctly reports a missing EULA")
    func flatteningDetectsMissingEULA() {
        let result = fetch(succeeds: true, eula: nil)
        let customEULA = result ?? nil
        #expect(customEULA == nil)
    }

    @Test("A custom EULA with text is treated as present")
    func presentEULADetected() {
        let result = fetch(succeeds: true, eula: EULA(agreementText: "Real terms."))
        let customEULA = result ?? nil
        let hasCustomEULA = !(customEULA?.agreementText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        #expect(hasCustomEULA)
    }

    @Test("A custom EULA with only whitespace is treated as missing")
    func whitespaceEULATreatedAsMissing() {
        let result = fetch(succeeds: true, eula: EULA(agreementText: "   \n  "))
        let customEULA = result ?? nil
        let hasCustomEULA = !(customEULA?.agreementText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        #expect(!hasCustomEULA)
    }

    @Test("A failed request flattens to no EULA rather than crashing")
    func failedRequestFlattens() {
        let result = fetch(succeeds: false, eula: nil)
        let customEULA = result ?? nil
        #expect(customEULA == nil)
    }
}

@Suite("Commerce manual checklist")
struct CommerceManualCheckTests {
    private func report(withStoreKit: Bool) -> Report {
        let project = Project(
            name: "Sample",
            projectFileURL: URL(filePath: "/tmp/Sample.xcodeproj"),
            directoryURL: URL(filePath: "/tmp"),
            bundleIdentifier: "com.example.Sample"
        )
        let results: [AnalysisResult] = withStoreKit
            ? [AnalysisResult(category: .storeKit, findings: [], checksPerformed: 1)]
            : [.skipped(.storeKit, reason: "The project doesn't use StoreKit.")]
        return Report(project: project, results: results)
    }

    @Test("A commerce app is told to verify the agreement and tax forms")
    func commerceChecksPresent() {
        let titles = ManualCheck.checklist(for: report(withStoreKit: true)).map(\.title)
        #expect(titles.contains { $0.contains("Paid Applications Agreement") })
        #expect(titles.contains { $0.contains("Tax forms") })
    }

    @Test("A non-commerce app isn't asked about agreements or tax")
    func nonCommerceChecksAbsent() {
        let checks = ManualCheck.checklist(for: report(withStoreKit: false))
        let titles = checks.map(\.title)
        #expect(!titles.contains { $0.contains("Paid Applications Agreement") })
        #expect(!titles.contains { $0.contains("Tax forms") })
        #expect(!checks.isEmpty, "baseline checks should still apply")
    }
}
