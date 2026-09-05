import SwiftUI

/// Shown when a free-tier user taps a paid feature.
/// Presents what the unlock adds; does not re-list the free tier.
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

            Text("Unlock Full Analysis")
                .font(.title2.bold())

            Text("One-time purchase · No subscription")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 32)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            featureRow(
                "App Store Metadata",
                detail: "Live checks against your ASC record: screenshots, keywords, support URL",
                image: AnalysisCategory.metadata.systemImage
            )
            featureRow(
                "StoreKit Analysis",
                detail: "IAP configuration, restore path, paywall compliance checks",
                image: AnalysisCategory.storeKit.systemImage
            )
            featureRow(
                "AI Summary",
                detail: "On-device Apple Intelligence overview of your report's top priorities",
                image: "sparkles"
            )
            featureRow(
                "Export Fix Checklist",
                detail: "Copy your findings as a Markdown checklist to track outside the app",
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

            HStack(spacing: 20) {
                if let url = URL(string: "https://preflight.info/privacy") {
                    Link("Privacy Policy", destination: url)
                }
                if let url = URL(string: "https://preflight.info/terms") {
                    Link("Terms of Use", destination: url)
                }
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
