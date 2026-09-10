import SwiftUI

/// Shown when the free trial has ended and the user needs to unlock PreFlight.
/// Also shown from the results summary card and copy-checklist button when
/// the user views a report without full access.
///
/// App Review checks that a purchase screen states exactly what is being sold,
/// its price, whether it renews, how to restore it, and links out to the terms
/// of use and privacy policy. All of those are required here — don't remove
/// them without checking Guidelines 3.1.1 and 3.1.2.
struct PaywallView: View {
    let purchases: PurchaseService
    let source: PaywallSource
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            featuresSection
            Divider()
            actionsSection
        }
        .frame(width: 380)
        .onChange(of: purchases.isPurchased) { _, isPurchased in
            if isPurchased { dismiss() }
        }
        .onAppear {
            AnalyticsService.shared.paywallShown(source: source)
        }
        .onDisappear {
            AnalyticsService.shared.paywallDismissed(source: source, converted: purchases.isPurchased)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .padding(.bottom, 4)

            Text("Your Free Trial Has Ended")
                .font(.title2.bold())

            Text("PreFlight Unlock — \(purchases.displayPrice)")
                .font(.headline)

            Text("One-time purchase · Not a subscription · Never auto-renews")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 32)
        .padding(.bottom, 24)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            featureRow(
                "All 7 Analyzers",
                detail: "Project, privacy, metadata, StoreKit, accessibility, device support, and review readiness in one report",
                image: "sparkle.magnifyingglass"
            )
            featureRow(
                "Apple Intelligence Insights",
                detail: "On-device AI cross-references your source code and configuration to surface hidden issues",
                image: "sparkles"
            )
            featureRow(
                "App Store Connect Integration",
                detail: "Live checks against your ASC record: screenshots, metadata, keywords, support URL",
                image: AnalysisCategory.metadata.systemImage
            )
            featureRow(
                "Export Fix Checklist",
                detail: "Copy your findings as a Markdown checklist to track and share outside the app",
                image: "list.clipboard.fill"
            )
        }
        .padding(24)
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await purchases.purchase() }
            } label: {
                Group {
                    if purchases.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Unlock for \(purchases.displayPrice)")
                            .bold()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 24)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(purchases.isLoading)

            // Required for non-consumables by Guideline 3.1.1.
            Button {
                Task { await purchases.restore() }
            } label: {
                Text("Restore Purchase")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(purchases.isLoading)

            if let error = purchases.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Text("Payment is charged to your Apple Account at confirmation of purchase. This unlock is permanent and applies to every Mac signed in to the same Apple Account.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Text("PreFlight surfaces issues to investigate — it does not guarantee App Review approval and cannot catch every possible rejection.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: 20) {
                Link("Terms of Use", destination: AppLinks.termsOfUse)
                Link("Privacy Policy", destination: AppLinks.privacyPolicy)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .padding(.bottom, 8)
    }

    private func featureRow(_ title: String, detail: String, image: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: image)
                .foregroundStyle(.tint)
                .frame(width: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
