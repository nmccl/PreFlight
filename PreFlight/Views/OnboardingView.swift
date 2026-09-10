import SwiftUI

/// First-launch walkthrough, shown as a non-dismissable sheet until completed.
/// The final step starts the 7-day free trial.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var pageIndex = 0

    private let pages = OnboardingPage.all

    /// The trial step sits one past the informational pages.
    private var trialPageIndex: Int { pages.count }
    private var isTrialPage: Bool { pageIndex == trialPageIndex }
    private var stepCount: Int { pages.count + 1 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Group {
                if isTrialPage {
                    trialPageContent
                } else {
                    pageContent(for: pages[pageIndex])
                }
            }
            .id(pageIndex)
            .transition(.push(from: .trailing))

            Spacer()

            pageDots

            Button(isTrialPage ? "Start Free Trial" : "Continue") {
                if isTrialPage {
                    appState.trial.beginTrial()
                    appState.settings.hasCompletedOnboarding = true
                    AnalyticsService.shared.onboardingCompleted()
                    AnalyticsService.shared.trialStarted()
                } else {
                    withAnimation(.smooth) {
                        pageIndex += 1
                    }
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .padding(.top, 24)
            .padding(.bottom, isTrialPage ? 16 : 40)

            if isTrialPage {
                legalLinks
                    .padding(.bottom, 24)
            }
        }
        .frame(width: 520, height: 600)
    }

    private func pageContent(for page: OnboardingPage) -> some View {
        VStack(spacing: 24) {
            Image(systemName: page.systemImage)
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .frame(width: 120, height: 120)
                .glassEffect(in: .circle)

            Text(page.title)
                .font(.largeTitle.bold())

            Text(page.message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(.horizontal, 32)
    }

    /// The trial step. App Review expects the trial length, what happens when
    /// it ends, and the exact price to all be stated before the user commits.
    private var trialPageContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "clock.badge.checkmark.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .frame(width: 120, height: 120)
                .glassEffect(in: .circle)

            Text("7 Days, Fully Unlocked")
                .font(.largeTitle.bold())

            Text("Every analyzer, Apple Intelligence insights, App Store Connect checks, and checklist export — free for 7 days. No payment method required.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            VStack(spacing: 4) {
                Text("After the trial, unlock PreFlight for \(appState.purchases.displayPrice)")
                    .font(.callout.weight(.medium))
                Text("One-time purchase · Not a subscription · Never auto-renews")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .frame(maxWidth: 400)
            .glassEffect(in: .rect(cornerRadius: 12))
        }
        .padding(.horizontal, 32)
    }

    private var legalLinks: some View {
        HStack(spacing: 20) {
            Link("Terms of Use", destination: AppLinks.termsOfUse)
            Link("Privacy Policy", destination: AppLinks.privacyPolicy)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<stepCount, id: \.self) { index in
                Circle()
                    .fill(index == pageIndex ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

private struct OnboardingPage {
    let systemImage: String
    let title: String
    let message: String

    static let all = [
        OnboardingPage(
            systemImage: "checkmark.seal.fill",
            title: "Know Before You Submit",
            message: "PreFlight analyzes your Xcode project and surfaces the configuration errors, privacy gaps, and guideline violations that trigger App Store rejections."
        ),
        OnboardingPage(
            systemImage: "doc.text.magnifyingglass",
            title: "Findings, Not Guesses",
            message: "Every finding comes from your actual project files — build settings, entitlements, privacy manifests, StoreKit config, and live App Store Connect data. Each one includes the exact issue, why it matters, and how to fix it."
        ),
        OnboardingPage(
            systemImage: "lock.shield.fill",
            title: "Runs on Your Mac",
            message: "Analysis is entirely local. No project files or source code leave your machine. App Store Connect credentials are optional and stored in your Keychain."
        ),
    ]
}
