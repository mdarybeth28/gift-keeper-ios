import Foundation
import StoreKit

/// StoreKit 2, and only StoreKit 2 — no third-party purchase SDK.
///
/// What this store owns: loading the one subscription product,
/// running a purchase, restoring purchases, and reporting the
/// device's current Apple entitlements.
///
/// What it deliberately does NOT own: ACCESS. A verified StoreKit
/// entitlement is shown on the paywall as information, but the
/// door into the app is the backend approval (ApprovalStore),
/// exactly as on the web. Purchase completion therefore ends in a
/// "finishing setup" state whose only job is to re-ask the backend
/// until Apple's server notification (via the IAP bridge) lands
/// the approved_emails row. If that row never lands, this store
/// cannot and will not let anyone in locally.
///
/// APP-ACCOUNT TOKEN: every purchase passes the signed-in Supabase
/// user id as StoreKit's appAccountToken. Supabase Auth user ids
/// ARE UUIDs (auth.users.id is a uuid), so the mapping is the
/// identity mapping — UUID(uuidString: user.id) — with no derived
/// or hashed substitute. The bridge reads appAccountToken back out
/// of Apple's signed transaction and resolves it to the account's
/// email through the Supabase Auth admin API. If a session ever
/// presents a non-UUID id, purchase is refused with an honest
/// message rather than buying under an unlinkable token.
@MainActor
final class SubscriptionStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loadingProducts
        case purchasing(productID: String)
        case restoring
        /// Purchase paid; waiting on the backend approval row.
        case finishingSetup
        case failed(message: String)
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var entitledProductIDs: Set<String> = []
    @Published private(set) var phase: Phase = .idle

    private var updatesTask: Task<Void, Never>?

    var hasAppleEntitlement: Bool { !entitledProductIDs.isEmpty }
    var isBusy: Bool {
        switch phase {
        case .loadingProducts, .purchasing, .restoring, .finishingSetup: return true
        case .idle, .failed: return false
        }
    }

    // MARK: - Lifecycle

    /// Start listening for transactions that arrive outside a
    /// purchase tap (renewals, Ask to Buy approvals, purchases on
    /// another device). Safe to call repeatedly.
    func start() {
        if updatesTask == nil {
            updatesTask = Task { [weak self] in
                for await update in Transaction.updates {
                    guard let self else { return }
                    if case .verified(let transaction) = update {
                        await transaction.finish()
                        await self.refreshEntitlements()
                    }
                }
            }
        }
        Task { await loadProducts() }
        Task { await refreshEntitlements() }
    }

    // MARK: - Products

    func loadProducts() async {
        phase = .loadingProducts
        do {
            let loaded = try await Product.products(for: StoreConfig.allProductIDs)
            products = StoreConfig.allProductIDs.compactMap { id in
                loaded.first { $0.id == id }
            }
            phase = .idle
        } catch {
            phase = .failed(message: "Could not load the subscription options from Apple. Check your connection and try again.")
        }
    }

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    // MARK: - Entitlements

    /// The device's current verified entitlements for our one
    /// product. INFORMATION ONLY — see the header: this never
    /// opens the app's door by itself.
    func refreshEntitlements() async {
        var entitled: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard StoreConfig.allProductIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            entitled.insert(transaction.productID)
        }
        entitledProductIDs = entitled
    }

    // MARK: - Purchase

    /// Runs one purchase under the signed-in account's token.
    /// `onPaid` is called after the transaction is verified and
    /// finished, while this store sits in .finishingSetup — the
    /// caller (the paywall) uses it to poll the backend approval.
    /// This function returns when that polling is over, whatever
    /// the gate then says.
    func purchase(productID: String, session: SessionStore,
                  onPaid: @escaping () async -> Void) async {
        guard let product = product(for: productID) else {
            phase = .failed(message: "That subscription option is not available right now.")
            return
        }
        guard let token = session.appAccountToken else {
            phase = .failed(message: "Your account id could not be linked to an Apple purchase, so nothing was charged. Please sign out and sign in again, and tell Mary if it keeps happening.")
            return
        }
        phase = .purchasing(productID: productID)
        do {
            let result = try await product.purchase(options: [.appAccountToken(token)])
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    phase = .failed(message: "Apple could not verify that purchase, so it has not been counted. If you were charged, tap Restore purchases.")
                    return
                }
                await transaction.finish()
                await refreshEntitlements()
                phase = .finishingSetup
                await onPaid()
                if phase == .finishingSetup { phase = .idle }
            case .userCancelled:
                phase = .idle
            case .pending:
                phase = .failed(message: "Apple is still approving that purchase (for example, Ask to Buy). When it goes through, tap \"Check again\" below.")
            @unknown default:
                phase = .failed(message: "Apple returned something unexpected. Nothing has been counted here; tap Restore purchases to check.")
            }
        } catch {
            phase = .failed(message: "The purchase did not finish: \(error.localizedDescription)")
        }
    }

    // MARK: - Restore

    /// AppStore.sync() re-presents the account's purchases to this
    /// device; entitlements refresh right after. The caller then
    /// re-asks the backend — restore, like purchase, never grants
    /// access locally.
    func restore() async {
        phase = .restoring
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            phase = .idle
        } catch {
            phase = .failed(message: "Restore did not finish: \(error.localizedDescription)")
        }
    }
}
