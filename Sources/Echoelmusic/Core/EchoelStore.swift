#if canImport(StoreKit)
import Foundation
import StoreKit
import Observation

/// StoreKit 2 manager for the ONE-TIME Echoel Pro unlock (non-consumable).
///
/// Product: `ProGate.productID` — "Einmal kaufen. Es ist ein Instrument, kein Abo."
/// What Pro unlocks is decided exclusively by `ProGate`; this class only owns
/// the purchase state (`isProUnlocked`) via `Transaction.currentEntitlements`.
@MainActor @Observable
final class EchoelStore {

    // MARK: - State

    var proProduct: Product?
    var isProUnlocked: Bool = false
    var isLoading: Bool = false

    // MARK: - Init

    private var updateTask: Task<Void, Never>?

    init() {
        // StoreKit stays dark until a real purchase surface exists
        // (FeatureFlags.storeKit, default OFF): no Transaction.updates listener,
        // no product load — the app has no purchasable product today, so launch
        // must not touch StoreKit. Release bit-identical when off.
        guard FeatureFlags.storeKit else { return }
        updateTask = Task { [weak self] in
            await self?.listenForTransactions()
        }
    }

    nonisolated deinit {
        // Task is self-cancelling when the store is deallocated
    }

    // MARK: - Load Product

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let products = try await Product.products(for: [ProGate.productID])
            proProduct = products.first { $0.id == ProGate.productID }
            log.log(.info, category: .system, "StoreKit: Loaded \(products.count) products")
        } catch {
            log.log(.error, category: .system, "StoreKit: Failed to load products — \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await updateEntitlements()
            log.log(.info, category: .system, "StoreKit: Purchased \(product.id)")
            return true

        case .userCancelled:
            return false

        case .pending:
            log.log(.info, category: .system, "StoreKit: Purchase pending approval")
            return false

        @unknown default:
            return false
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await updateEntitlements()
    }

    // MARK: - Entitlements

    func updateEntitlements() async {
        var unlocked = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == ProGate.productID,
               transaction.revocationDate == nil {
                unlocked = true
            }
        }

        isProUnlocked = unlocked
    }

    /// Whether `feature` is usable right now (policy from `ProGate`).
    func isUnlocked(_ feature: ProFeature) -> Bool {
        ProGate.isUnlocked(feature, proPurchased: isProUnlocked)
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await transaction.finish()
            await updateEntitlements()
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
#endif
