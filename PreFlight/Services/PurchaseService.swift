import StoreKit
import Observation

/// Manages the one-time $12.99 PreFlight Pro unlock.
/// Purchase state is always verified against Transaction.currentEntitlements — never stored in UserDefaults.
@MainActor
@Observable
final class PurchaseService {
    static let productID = "com.noahmcclung.PreFlight.unlock"

    private(set) var isPurchased = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var product: Product?

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
        guard let product, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handleTransaction(verification)
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Processes one entry from Transaction.updates.
    /// The caller (PreFlightApp .task) owns the loop so the stream lives for the app's lifetime.
    func handleTransaction(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let tx) = result else { return }
        if tx.productID == Self.productID {
            isPurchased = tx.revocationDate == nil
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
        isPurchased = found
    }
}
