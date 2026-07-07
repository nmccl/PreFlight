import SwiftUI

/// First-launch walkthrough, shown as a non-dismissable sheet until completed.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var pageIndex = 0

    private let pages = OnboardingPage.all

    private var isLastPage: Bool {
        pageIndex == pages.count - 1
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            pageContent(for: pages[pageIndex])
                .id(pageIndex)
                .transition(.push(from: .trailing))

            Spacer()

            pageDots

            Button(isLastPage ? "Get Started" : "Continue") {
                if isLastPage {
                    appState.settings.hasCompletedOnboarding = true
                } else {
                    withAnimation(.smooth) {
                        pageIndex += 1
                    }
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .frame(width: 520, height: 560)
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

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
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
            title: "Welcome to Developer Companion",
            message: "Catch App Review issues before Apple does. Analyze your Xcode project and get a Release Readiness score with concrete fixes."
        ),
        OnboardingPage(
            systemImage: "sparkle.magnifyingglass",
            title: "Five Analyzers, One Report",
            message: "Project configuration, privacy, StoreKit, App Store metadata, and common review blockers — each check contributes to your score out of 100."
        ),
        OnboardingPage(
            systemImage: "lock.shield.fill",
            title: "Private by Design",
            message: "Analysis runs entirely on your Mac, and Apple Intelligence summarizes results on device. Nothing about your project leaves your machine."
        ),
    ]
}
