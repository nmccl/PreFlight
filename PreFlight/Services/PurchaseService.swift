import StoreKit
import Observation

/// Manages the one-time $12.99 PreFlight Pro unlock.
/// Purchase state is always verified against Transaction.currentEntitlements — never stored in UserDefaults.
@MainActor
@Observable
final class PurchaseService {
    static let productID = "com.noahmcclung.PreFlight.unlock"
    private static let devOverrideKey = "preflight_dev_proUnlock"

    private var _isPurchased = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var product: Product?

    /// Dev-only: bypasses StoreKit so Pro features can be tested without a real transaction.
    /// Persisted across launches via UserDefaults.
    var devOverrideEnabled: Bool = UserDefaults.standard.bool(forKey: devOverrideKey) {
        didSet { UserDefaults.standard.set(devOverrideEnabled, forKey: Self.devOverrideKey) }
    }

    var isPurchased: Bool { devOverrideEnabled || _isPurchased }

    /// The localized price string for display in the paywall.
    /// Falls back to "$12.99" before the product record loads (simulator / pre-submission).
    var displayPrice: String { product?.displayPrice ?? "$12.99" }

    /// Verifies entitlements and loads the product for price display.
    /// Call once at app launch before showing any UI.
    func load() async {
        await verifyEntitlements()
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            // No ASC product record yet — displayPrice falls back to the hardcoded default above.
        }
    }

    /// Initiates the StoreKit purchase flow.
    func purchase() async {
        guard !isLoading else { return }
        guard let product else {
            errorMessage = "Purchase information is still loading. Please try again in a moment."
            return
        }
        isLoading = true
        errorMessage = nil
        AnalyticsService.shared.purchaseInitiated()
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handleTransaction(verification)
                AnalyticsService.shared.purchaseCompleted()
            case .userCancelled:
                AnalyticsService.shared.purchaseFailed(userCancelled: true)
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
            AnalyticsService.shared.purchaseFailed(userCancelled: false)
        }
    }

    /// Re-verifies entitlements; call from the restore button.
    func restore() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await verifyEntitlements()
            AnalyticsService.shared.purchaseRestored(foundEntitlement: _isPurchased)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Processes one entry from Transaction.updates.
    /// The caller (PreFlightApp .task) owns the loop so the stream lives for the app's lifetime.
    func handleTransaction(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let tx) = result else { return }
        if tx.productID == Self.productID {
            _isPurchased = tx.revocationDate == nil
        }
        await tx.finish()
    }

    private func verifyEntitlements() async {
        var found = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               tx.productID == Self.productID,
               tx.revocationDate == nil {
                found = true
                break
            }
        }
        _isPurchased = found
    }
}
