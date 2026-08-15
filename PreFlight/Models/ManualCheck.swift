import Foundation

/// A pre-submission item Apple evaluates that PreFlight cannot verify
/// automatically. Shown at the end of every report so unknowns become
/// visible checklist items instead of silent gaps — a clean automated
/// score must never read as "guaranteed to pass review".
struct ManualCheck: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let detail: String
}

extension ManualCheck {
    /// The checklist for a report. Commerce items only appear when the app
    /// actually uses StoreKit.
    static func checklist(for report: Report) -> [ManualCheck] {
        let usesStoreKit = report.results.contains { $0.category == .storeKit && !$0.wasSkipped }

        var checks = [
            ManualCheck(
                title: "First launch on a clean device",
                detail: "Run the app on a fresh simulator or device. Reviewers always see the first-launch experience: onboarding, permission prompts, and empty states."
            ),
            ManualCheck(
                title: "Consent before personal data leaves the device",
                detail: "If the app uploads names, emails, health data, or other personal information, users must be told what is collected and agree before it's sent."
            ),
            ManualCheck(
                title: "Every link works",
                detail: "Open each URL in the app and its metadata — privacy policy, terms, support. Reviewers click them, and broken links are flagged."
            ),
            ManualCheck(
                title: "Screenshots match the app",
                detail: "Store screenshots must show the app as it actually behaves; outdated or misleading screenshots are a metadata rejection."
            ),
        ]

        if usesStoreKit {
            checks.append(contentsOf: [
                ManualCheck(
                    title: "Paid Apps Agreement is active",
                    detail: "Check Business in App Store Connect. Purchases fail during review if the agreement has lapsed — agreement status isn't visible to PreFlight."
                ),
                ManualCheck(
                    title: "Purchases work in the StoreKit sandbox",
                    detail: "Products must load, purchase, and restore with a Sandbox Apple Account. A purchase screen that loads forever in sandbox is a common rejection."
                ),
                ManualCheck(
                    title: "Paywall shows the full offer",
                    detail: "Title, duration, price, Privacy Policy link, and Terms of Use link must be visible on the subscription screen itself."
                ),
                ManualCheck(
                    title: "Purchases work without an account",
                    detail: "Users must be able to buy without registering first, unless the purchase is unusable without an account."
                ),
            ])
        }

        return checks
    }
}
