import Foundation
import OSLog
import StoreKit

/// The single non-consumable unlock (CLAUDE.md §8).
///
/// One product, no consumables, no subscriptions. Entitlement is re-checked at
/// launch and on foreground so a refund or a family-sharing change is honoured
/// without the app having to phone anything itself.
@Observable
final class PurchaseStore {

    static let productID = "com.wakuwaku.chizu.full"

    private static let log = Logger(subsystem: "com.wakuwaku.chizu", category: "Purchase")

    enum State: Equatable {
        case idle
        case loading
        case purchasing
        case failed(String)
    }

    private(set) var isUnlocked = false
    private(set) var product: Product?
    private(set) var state: State = .idle

    private var updatesTask: Task<Void, Never>?

    init() {
        // Transactions can arrive at any time (Ask to Buy approval, a purchase
        // made on another device), so the listener starts before anything else.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self.refreshEntitlements()
            }
        }
    }

    // No deinit teardown: this store is owned by AppState for the whole app
    // lifetime, and the updates listener must stay alive that long to catch an
    // Ask to Buy approval that lands minutes after the child asked.

    var displayPrice: String { product?.displayPrice ?? "" }

    // MARK: - Loading

    func load() async {
        state = .loading
        do {
            product = try await Product.products(for: [Self.productID]).first
            state = .idle
        } catch {
            // No network, or the product is not configured yet. The free stages
            // must keep working regardless, so this is not surfaced as an error
            // until the parent actually tries to buy.
            Self.log.error("product load failed: \(error.localizedDescription, privacy: .public)")
            state = .idle
        }
        await refreshEntitlements()
    }

    /// Source of truth for the unlock. Verified receipts only.
    func refreshEntitlements() async {
        var unlocked = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                unlocked = true
            }
        }
        isUnlocked = unlocked
    }

    // MARK: - Buying

    /// Called only from behind the parental gate.
    func purchase() async {
        guard let product else {
            state = .failed("いまは かえません")
            return
        }
        state = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                }
                await refreshEntitlements()
                state = .idle
            case .userCancelled, .pending:
                // Pending covers Ask to Buy: the listener above picks it up if
                // and when a parent approves.
                state = .idle
            @unknown default:
                state = .idle
            }
        } catch {
            Self.log.error("purchase failed: \(error.localizedDescription, privacy: .public)")
            state = .failed("かえませんでした")
        }
    }

    func restore() async {
        state = .purchasing
        do {
            try await AppStore.sync()
        } catch {
            Self.log.error("restore failed: \(error.localizedDescription, privacy: .public)")
        }
        await refreshEntitlements()
        state = .idle
    }
}
