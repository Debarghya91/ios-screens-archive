// StoreManager.swift
// Payments Training Hub iOS - Apple In-App Purchase (StoreKit 2) for the
// catalogue products: the chapter bundles plus Payment Situations.
// Every product is a non-consumable, one-time purchase. Product IDs
// and catalogue data live in ProductCatalogue (Models); StoreKit is
// the only source of a purchase price.
// There are no App Store Connect products yet. Until they exist,
// the products are served by the local StoreKit Configuration file
// PaymentForge.storekit (same product IDs, same prices) when it is
// selected in the Xcode scheme. Once the real products exist in App
// Store Connect with these EXACT product IDs and the same prices,
// the app will fetch them from the App Store instead of the local
// file. DEBUG simulated
// purchases use ONLY that .storekit configuration: there is no local
// test-purchase path that unlocks without a StoreKit transaction.
//
// Access rules (ProductCatalogue): a buyer of a bundle gets ONLY that
// bundle's chapters. The Integrated Course unlocks all chapter
// products AND all Payment Situations. Situations is also sold
// standalone: buyers of the situations product, or the signed-in
// user with an active server entitlement for it, can open the paid
// situations without the full course. The free sample situations
// stay free without purchase; that mechanism lives in SituationsView,
// not here.
//
// SECURITY: purchases are App Store In-App Purchase only. There is
// no manual payment path in this file. In Release builds a product
// unlocks ONLY when (a) a verified StoreKit transaction is active on
// this device, or (b) the signed-in user has an active row in
// Supabase user_purchases for this product, or (c) a failed server
// read falls back to the server-verified entitlement cache for that
// same account, which replays only rows the server itself confirmed,
// only for 7 days, and never for guests or for another account (see
// the cache helpers below). No other UserDefaults flag alone ever
// unlocks anything in Release: the store starts locked and only
// verified entitlements open it. A failed, cancelled,
// pending or unverified purchase NEVER unlocks content. Only verified
// transactions are finished. This file only READS the server row
// back through SupabaseClient; server writes go through the
// record-purchase Edge Function, which holds the service-role key
// server-side. No service-role key is ever in the app.
//
// Refunds and revocations (C3): a revoked transaction is NOT finished
// until its server revoke is confirmed, or a definitive server read
// shows no active row left for its product. The pending revoke is
// persisted before the revoke is attempted and retried on every
// launch and every sign-in until the server confirms, so a failed
// revoke can never silently leave cross-device access active. The
// on-device entitlement is removed immediately in every case, so
// holding the finish delays only a repurchase of that one product,
// never access control on this device. See handleRevokedTransaction
// for the full design choice.
//
// The build-phase bypass (buildPhaseBuyOpensContent) is retired:
// it is false in every build, and every build buys through real
// StoreKit transactions. In test builds those transactions come
// from the local PaymentForge.storekit configuration selected in
// the Xcode scheme; no test path unlocks without a verified
// StoreKit transaction. See STOREKIT-TEST-PROCEDURE.md.

import Foundation
import Combine
import StoreKit

// MARK: - Supabase rows (user_purchases)

/// One row of the user_purchases table.
private struct UserPurchaseRow: Codable {
    var userID: String
    var productID: String
    var store: String
    var transactionID: String?
    var purchasedAt: String?
    var status: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case productID = "product_id"
        case store
        case transactionID = "transaction_id"
        case purchasedAt = "purchased_at"
        case status
    }
}

/// One persisted pending server revoke (C3): a revoked StoreKit
/// transaction whose server row has not yet been confirmed revoked.
/// Written before the revoke is attempted, removed only when the
/// server confirms the revoke or a definitive server read shows no
/// active row for the product. userID is the account the row belongs
/// to, or nil when the refund arrived while nobody was signed in
/// (an orphan, filed under the guest namespace and attempted again
/// on sign-in; the server enforces row ownership, so an attempt
/// under the wrong account fails harmlessly).
private struct PendingRevoke: Codable {
    var transactionID: String
    var productID: String
    var userID: String?
}

/// One server-verified entitlement cache record (H2): the exact set
/// of product IDs a definitive server read returned for one account,
/// with the time the server confirmed it. Written only from decoded
/// server rows, never from any local purchase or bypass state. An
/// empty set is a real record: it means the server definitively
/// reported no active row, and it overwrites any older record so a
/// revoked entitlement cannot be resurrected offline.
private struct ServerEntitlementCache: Codable {
    var userID: String
    var productIDs: [String]
    var verifiedAt: TimeInterval
}

@MainActor
final class StoreManager: ObservableObject {

    /// Shared instance. PaymentForgeApp uses this same instance
    /// as its @StateObject and passes it through the environment,
    /// so AuthService calls to StoreManager.shared reach the very
    /// instance the UI observes. There is exactly one StoreManager.
    static let shared = StoreManager()

    /// The App Store Connect product ID for Payment Situations.
    /// Single source of truth is ProductCatalogue; kept here so
    /// existing call sites reading StoreManager.situationsProductID
    /// keep working.
    static let situationsProductID = ProductCatalogue.situationsProductID

    /// All catalogue product IDs, from ProductCatalogue.
    static let allProductIDs = ProductCatalogue.allProductIDs

    /// The Integrated Course product ID: it unlocks all chapter
    /// products and all Payment Situations.
    static let fullCourseProductID = ProductCatalogue.fullCourseProductID

    /// Retired 13 Nov 2026: always false. It used to let a DEBUG
    /// build open content on a Buy tap without a StoreKit purchase,
    /// which meant test builds never exercised StoreKit and never
    /// produced a verified transaction. Test builds now buy through
    /// real StoreKit transactions against PaymentForge.storekit.
    /// Other files read this symbol for purchase copy; keep it.
    static let buildPhaseBuyOpensContent = false

    /// Local record of the IAP purchases, so the unlocked state
    /// survives app restarts in DEBUG builds. The source of truth is
    /// the App Store entitlement, re-checked on launch and on
    /// restore; this flag is only a cache, and Release builds never
    /// read it to unlock anything. Kept for the Situations purchase,
    /// so older builds' cached state is not lost; the per-product set
    /// below is the cache for all products.
    private static let purchasedKey = "pf.iap.situationsPurchased.v1"

    /// Local record of all purchased product IDs, as an array in
    /// UserDefaults. Cache only; the App Store entitlement is the
    /// source of truth, re-checked on launch and on restore. Release
    /// builds write this cache but never read it to unlock anything.
    private static let purchasedProductIDsKey = "pf.iap.purchasedProductIDs.v1"

    /// Key for product IDs the retired build-phase Buy bypass once
    /// unlocked. Kept only so init() can purge it; nothing reads it
    /// to unlock anything any more.
    private static let buildPhaseUnlockedProductIDsKey = "pf.iap.buildPhaseUnlocked.v1"

    /// Base key for persisted pending server revokes (C3), stored as
    /// JSON under an account-scoped key (see AccountScopedStorage):
    /// the owning account's namespace when the owner is known, the
    /// guest namespace for orphans. Never read to unlock anything.
    private static let pendingRevokeBaseKey = "iap.pendingRevokes.v1"

    /// Base key for the server-verified entitlement cache (H2),
    /// stored as JSON under an account-scoped key for the account
    /// the server rows belong to. The namespace is always resolved
    /// from the explicit user ID, never from the cached current
    /// namespace, so the timing of AuthService namespace updates
    /// cannot misfile one account's cache under another identity.
    private static let serverEntitlementCacheBaseKey = "iap.serverEntitlements.v1"

    /// How long a server-verified cache record stays usable after a
    /// failed server read: 7 days. Past that, a failed read locks
    /// the server entitlements until a read succeeds.
    private static let serverEntitlementCacheValidity: TimeInterval = 7 * 24 * 60 * 60

    /// The fetched products, empty until the store loads them.
    @Published private(set) var products: [Product] = []

    /// The fetched product for Payment Situations, nil until the store
    /// loads it. Kept so existing call sites reading
    /// storeManager.product keep working.
    var product: Product? {
        products.first { $0.id == Self.situationsProductID }
    }

    /// The StoreKit product for one product ID, nil until loaded.
    func storeProduct(for productID: String) -> Product? {
        products.first { $0.id == productID }
    }

    /// True when every catalogue product has loaded from StoreKit.
    var allProductsLoaded: Bool {
        !products.isEmpty && Self.allProductIDs.allSatisfy { storeProduct(for: $0) != nil }
    }

    /// Product IDs with an active verified StoreKit transaction on
    /// this device. Set only from Transaction.currentEntitlements,
    /// through setPurchasedProductIDs. In Release this set starts
    /// empty and is populated only by verified transactions, never
    /// from a stored cache.
    @Published private(set) var purchasedProductIDs: Set<String> = []

    /// Product IDs with an active user_purchases row for the signed-in
    /// user on the server. This is the ONLY server path that unlocks
    /// a product. It is set by a definitive server read, or, when a
    /// server read fails, by replaying the server-verified cache for
    /// the same account (see the H2 helpers); it is never set from
    /// any other stored state. Guests (no account) never have
    /// one; their StoreKit purchase is what unlocks them.
    @Published private(set) var serverEntitledProductIDs: Set<String> = []

    /// Product IDs the retired build-phase Buy bypass unlocked.
    /// Always empty now: the bypass is retired, init() purges its
    /// stored key, and isProductOwned() never consults this set.
    /// Kept so existing call sites and tests keep compiling.
    @Published private(set) var buildPhaseUnlockedProductIDs: Set<String> = []

    /// True when the App Store entitlement for Situations is active
    /// on this device (bought, and verified from the transaction).
    var isPurchased: Bool {
        purchasedProductIDs.contains(Self.situationsProductID)
    }

    /// True when the signed-in user has an active user_purchases row
    /// for Situations on the server, or a fresh server-verified
    /// cache record for the same account after a failed server read.
    /// This is the ONLY server path that unlocks Situations. Guests
    /// (no account) never have one; their StoreKit purchase is what
    /// unlocks them.
    var isServerEntitlementVerified: Bool {
        serverEntitledProductIDs.contains(Self.situationsProductID)
    }

    /// The verified App Store transactions behind the current
    /// entitlements, latest purchase first. Empty when nothing is
    /// purchased, or when every purchase was refunded or revoked.
    /// Used for the Transaction History rows.
    @Published private(set) var ownedTransactions: [Transaction] = []

    /// The latest verified App Store transaction, when there is one.
    /// Nil when not purchased, or when the purchase was refunded or
    /// revoked. Used for the Purchased on date.
    var latestTransaction: Transaction? {
        ownedTransactions.first
    }

    /// True when a StoreKit purchase could not be recorded on the
    /// server (for example the record-purchase Edge Function call
    /// failed). The on-device StoreKit entitlement still works; this
    /// only means the purchase is not yet visible on other devices.
    /// Call retryPendingServerSync() to try again.
    @Published private(set) var serverEntitlementSyncPending = false

    /// True while products are being fetched or a purchase is running.
    @Published private(set) var isBusy = false

    /// True while the product list could not be loaded at all.
    @Published private(set) var productLoadFailed = false

    /// The last user-facing purchase status message, shown in Checkout.
    @Published private(set) var statusMessage: String?

    /// Clear the last purchase message, for example after the
    /// learner dismisses the alert that showed it.
    func clearStatusMessage() { statusMessage = nil }

    /// The display price for Payment Situations from StoreKit when the
    /// product is loaded, otherwise "Price unavailable". A hardcoded
    /// catalogue price is NEVER shown as a purchase price.
    var priceText: String {
        priceText(for: Self.situationsProductID)
    }

    /// The display price for one product from StoreKit when it is
    /// loaded, otherwise "Price unavailable". The StoreKit localised
    /// displayPrice is the only price ever presented as a purchase
    /// price; the catalogue priceINR is reference data only and is
    /// never shown here. Callers must check isPriceAvailable(for:)
    /// before offering a purchase.
    func priceText(for productID: String) -> String {
        if let product = storeProduct(for: productID) {
            return product.displayPrice
        }
        return "Price unavailable"
    }

    /// True when the StoreKit product has loaded and a real price is
    /// available for a purchase. False means the Buy button must stay
    /// disabled: a purchase must never be offered at a hardcoded
    /// price, or at no price.
    func isPriceAvailable(for productID: String) -> Bool {
        storeProduct(for: productID) != nil
    }

    /// How the current Situations entitlement was obtained, for the
    /// Purchases screen. App Store wins when both exist.
    var purchaseMethod: String? {
        if isPurchased { return "App Store" }
        if isServerEntitlementVerified { return "Verified purchase" }
        return nil
    }

    /// The date the latest entitlement was purchased, from the
    /// verified App Store transaction when there is one.
    var purchasedOnDate: Date? {
        latestTransaction?.purchaseDate
    }

    /// True when this product is owned outright: a verified StoreKit
    /// transaction on this device, or an active server entitlement
    /// for the signed-in user (a definitive server read, or a fresh
    /// server-verified cache record after a failed read). The full
    /// course is not counted here: see isProductUnlocked. ONLY those
    /// two sources count, in every build; no stored flag other than
    /// the server-verified cache is ever consulted.
    func isProductOwned(_ productID: String) -> Bool {
        purchasedProductIDs.contains(productID) || serverEntitledProductIDs.contains(productID)
    }

    /// True when this product is unlocked: owned outright, or the
    /// Integrated Course is owned. The Integrated Course unlocks
    /// all chapter products and all Payment Situations. Situations
    /// is also sold standalone: owning the situations product
    /// unlocks it without the full course.
    func isProductUnlocked(_ productID: String) -> Bool {
        if isProductOwned(productID) { return true }
        if productID == Self.fullCourseProductID { return false }
        return isProductOwned(Self.fullCourseProductID)
    }

    /// Situations are unlocked for paid access when the situations
    /// product is owned outright (an In-App Purchase active on
    /// this device, or an active server entitlement in Supabase
    /// user_purchases for the signed-in user), or when the
    /// Integrated Course is owned. The free sample situations are
    /// handled in SituationsView and stay free regardless of this
    /// value.
    var isSituationsUnlocked: Bool {
        isProductUnlocked(Self.situationsProductID)
    }

    /// True when a chapter is unlocked: the Integrated Course is
    /// owned, or the bundle containing this chapter is owned. A
    /// chapter no bundle contains is LOCKED (fail closed): an
    /// unmapped chapter is a catalogue error, and it must never be
    /// given away silently. All 100 manifest chapters are mapped
    /// (see the M1 test), so no real chapter is affected.
    func isChapterUnlocked(_ chapterID: String) -> Bool {
        if isProductOwned(Self.fullCourseProductID) { return true }
        guard let bundle = ProductCatalogue.productContaining(chapterID: chapterID) else { return false }
        return isProductOwned(bundle.productID)
    }

    /// The bundle that unlocks a chapter, for the lock screen copy.
    /// Nil when the chapter is in no bundle, or when it is already
    /// unlocked.
    func unlockingProduct(for chapterID: String) -> CourseProduct? {
        guard !isChapterUnlocked(chapterID) else { return nil }
        return ProductCatalogue.productContaining(chapterID: chapterID)
    }

    /// How many catalogue products are unlocked, for the Purchases
    /// screen summary.
    var unlockedProductCount: Int {
        Self.allProductIDs.filter { isProductUnlocked($0) }.count
    }

    private var updatesTask: Task<Void, Never>?

    /// True while a product fetch is in flight, so concurrent
    /// loadProducts() calls do not stack duplicate fetches. A failed
    /// or partial fetch can always be retried once it finishes.
    private var isLoadingProducts = false

    init() {
        // The retired bypass key is purged in every build, so a
        // bypass unlock left by an older DEBUG build can never
        // unlock anything again.
        UserDefaults.standard.removeObject(forKey: Self.buildPhaseUnlockedProductIDsKey)
#if DEBUG
        // DEBUG only: restore the verified-transaction cache so a
        // development build keeps its unlocked state across
        // restarts until refreshEntitlement() re-checks it. This
        // cache is written only from verified transactions.
        let cached = UserDefaults.standard.stringArray(forKey: Self.purchasedProductIDsKey) ?? []
        purchasedProductIDs = Set(cached.filter { Self.allProductIDs.contains($0) })
        // Older builds cached only the Situations purchase under the
        // single key; carry it into the per-product set once.
        if UserDefaults.standard.bool(forKey: Self.purchasedKey) {
            purchasedProductIDs.insert(Self.situationsProductID)
        }
#else
        // Release: start locked. Verified entitlements populate this
        // set through refreshEntitlement() in start().
#endif
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Load the products and re-check the entitlements. Call once at launch.
    /// Starts the listener for transaction updates (refunds,
    /// revocations, purchases made on another device, family sharing),
    /// then re-checks the App Store entitlements and the server
    /// entitlements for the signed-in user, retries recording any
    /// owned transaction the server has not confirmed yet (the
    /// best-effort queue for the record-purchase call), sweeps the
    /// transaction history for revokes the listener never saw, and
    /// retries any pending server revoke. Calling start() again
    /// restarts the listener instead of stacking a second one.
    func start() async {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handleTransactionUpdate(update)
            }
        }
        await loadProducts()
        await refreshEntitlement()
        await refreshEntitlementFromServer()
        await syncOwnedTransactionsToServer()
        await enqueueRevokesFromTransactionHistory()
        await retryPendingRevokes()
    }

    /// Fetch all catalogue products from the App Store (or the local
    /// .storekit file while there are no App Store Connect products
    /// yet). Always refetches, so a failed or partial load can be
    /// retried; concurrent calls share the in-flight fetch.
    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        isBusy = true
        defer {
            isBusy = false
            isLoadingProducts = false
        }
        do {
            let fetched = try await Product.products(for: Self.allProductIDs)
            products = fetched.sorted { $0.id < $1.id }
            productLoadFailed = fetched.isEmpty
            if fetched.isEmpty {
                statusMessage = "The products could not be loaded. Check your connection and try again."
            } else if fetched.count < Self.allProductIDs.count {
                statusMessage = "Some course prices could not be loaded. Check your connection and try again."
            }
        } catch {
            productLoadFailed = true
            statusMessage = "The products could not be loaded. Check your connection and try again."
        }
    }

    /// Fetch the products. Kept so existing call sites reading
    /// loadProduct keep working; it loads all catalogue products.
    func loadProduct() async {
        await loadProducts()
    }

    /// Buy Payment Situations. Kept so existing call sites keep
    /// working; it buys the situations product.
    func purchase() async {
        await purchase(productID: Self.situationsProductID)
    }

    /// Buy one product. Handles success, cancellation, pending and
    /// failure with a clear message for each. A failed, cancelled,
    /// pending or unverified purchase never unlocks anything. A
    /// purchase is only offered when the StoreKit product (and its
    /// real price) has loaded; otherwise the buyer is told the price
    /// is unavailable and nothing is charged.
    func purchase(productID: String) async {
        guard let catalogueProduct = ProductCatalogue.product(for: productID) else {
            statusMessage = "That product is not available. Please try again."
            return
        }
        if isProductUnlocked(productID) {
            statusMessage = "\(catalogueProduct.name) is already unlocked."
            return
        }
        // Every build buys through StoreKit: in test builds the
        // product comes from the local PaymentForge.storekit
        // configuration, and only a verified transaction unlocks.
        if storeProduct(for: productID) == nil {
            await loadProducts()
        }
        guard let product = storeProduct(for: productID) else {
            statusMessage = "The price is not available yet. Check your connection and try again."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handlePurchaseSuccess(verification)
            case .userCancelled:
                statusMessage = "Purchase cancelled. Nothing was charged."
            case .pending:
                statusMessage = "Purchase is pending approval. It will complete once it is approved."
            @unknown default:
                statusMessage = "Purchase did not complete. Please try again."
            }
        } catch {
            statusMessage = "Purchase failed. Please try again."
        }
    }

    /// Restore purchases made on this Apple ID (reinstall, new device).
    /// Asks the App Store to sync, then re-checks both entitlement
    /// sources, records any restored on-device purchases on the
    /// server for the signed-in user, so they sync across devices,
    /// and retries any pending server revoke.
    func restorePurchases() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await AppStore.sync()
        } catch {
            // Sync failing does not mean there is nothing to restore;
            // still re-check the local entitlements below.
        }
        await refreshEntitlement()
        await refreshEntitlementFromServer()
        await syncOwnedTransactionsToServer()
        await retryPendingRevokes()
        let unlocked = unlockedProductCount
        if unlocked > 0 {
            statusMessage = "Purchases restored. \(unlocked) of \(Self.allProductIDs.count) products unlocked."
        } else {
            statusMessage = "No purchase was found for this Apple ID."
        }
    }

    /// Re-check the current App Store entitlements for all catalogue
    /// products. A refunded or revoked transaction removes the
    /// entitlement and clears the stored transaction, so the UI goes
    /// back to Not purchased. This function deliberately never calls
    /// the server revoke: absence from currentEntitlements is not
    /// proof of a revocation (a transaction can be absent for other
    /// reasons), and revoking on absence could permanently revoke a
    /// live purchase. The authoritative revocation signal is the
    /// revocationDate on a delivered transaction update (see
    /// handleRevokedTransaction) or in the transaction history (see
    /// enqueueRevokesFromTransactionHistory, run at launch); both
    /// persist a pending revoke that retries until confirmed.
    /// Server entitlements are untouched by this function.
    func refreshEntitlement() async {
        var entitled: [Transaction] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard isEntitlingTransaction(transaction) else { continue }
            entitled.append(transaction)
        }
        entitled.sort { $0.purchaseDate > $1.purchaseDate }
        ownedTransactions = entitled
        setPurchasedProductIDs(Set(entitled.map { $0.productID }))
    }

    /// Re-read the server entitlements for the signed-in user from
    /// Supabase user_purchases. This is the only server unlock path.
    /// Guests have no server entitlement, and an unconfigured server
    /// means no server entitlement either: both clear the set.
    /// A definitive server answer (the read succeeded) REPLACES the
    /// set and the cache, even when it is empty: an empty answer
    /// means no active row, and it is the only response that clears
    /// a cached entitlement. A failed read (no network, a server
    /// error, an undecodable reply, or no usable token) never clears
    /// on its own: the fresh server-verified cache for this account
    /// is replayed instead, or the set is cleared when there is no
    /// fresh cache. The StoreKit entitlements are untouched.
    func refreshEntitlementFromServer() async {
        guard SupabaseConfig.isConfigured,
              let userID = AuthService.shared.currentUser?.id else {
            serverEntitledProductIDs = []
            return
        }
        guard let token = await AuthService.shared.validAccessToken() else {
            serverEntitledProductIDs = cachedServerEntitlements(for: userID) ?? []
            return
        }
        if let definitive = await fetchServerEntitledProductIDs(userID: userID, accessToken: token) {
            applyDefinitiveServerEntitlements(definitive, userID: userID)
        } else {
            serverEntitledProductIDs = cachedServerEntitlements(for: userID) ?? []
        }
    }

    /// Re-check both entitlement sources after authentication, and
    /// record any on-device StoreKit purchases on the server so they
    /// follow the account to other devices. Call this after sign-in
    /// completes. It also covers purchases bought as a guest before
    /// signing in: the verified on-device transactions are recorded
    /// against the account that just signed in. Pending server
    /// revokes for this account (including orphans filed while
    /// signed out) are retried last.
    func syncEntitlementsAfterSignIn() async {
        await refreshEntitlement()
        await refreshEntitlementFromServer()
        await syncOwnedTransactionsToServer()
        await retryPendingRevokes()
    }

    /// Drop every account-scoped entitlement. Call on sign-out so the
    /// next account (or a guest) never inherits the previous
    /// account's server entitlements. On-device StoreKit
    /// entitlements are untouched: they belong to the Apple ID, not
    /// to the app account. The server-verified cache and the pending
    /// revokes are deliberately NOT deleted here: both stay filed
    /// under the signed-out account's namespace, the in-memory set
    /// is what is cleared, and account deletion removes the whole
    /// namespace. A different account reads different keys and can
    /// never replay this account's cache.
    func clearAccountEntitlements() {
        serverEntitledProductIDs = []
        serverEntitlementSyncPending = false
    }

    /// Retry recording on-device purchases on the server after a
    /// failed sync. No-op when nothing is pending. There is no
    /// direct UI caller yet: retries happen on every launch
    /// (start()), on every sign-in (syncEntitlementsAfterSignIn),
    /// and through the restore and transaction-update paths, which
    /// all record owned transactions. A dedicated retry trigger
    /// (for example on foreground) is a follow-up.
    func retryPendingServerSync() async {
        guard serverEntitlementSyncPending else { return }
        await syncOwnedTransactionsToServer()
    }

    // MARK: - Server purchase entitlement

    /// Record a verified StoreKit purchase on the server so the
    /// entitlement syncs across devices. Best effort only: unlocking
    /// never waits for this call (callers run it detached, after the
    /// local entitlement refresh), and a failed record is queued by
    /// retry: the owned verified transactions are re-recorded on
    /// every launch, sign-in, and restore until the server confirms.
    /// Only verified, entitlement-granting transactions are ever
    /// recorded: guests keep only the on-device StoreKit purchase,
    /// and a failed server record sets
    /// serverEntitlementSyncPending instead of locking the user out
    /// here.
    /// The write goes through the record-purchase Edge Function,
    /// which holds the service-role key server-side, because
    /// user_purchases is SELECT-only for the app under RLS. The
    /// function upserts on transaction_id, so repeat calls never
    /// duplicate.
    private func syncPurchaseEntitlementToServer(_ transaction: Transaction) async {
        guard isEntitlingTransaction(transaction) else { return }
        guard SupabaseConfig.isConfigured,
              let userID = AuthService.shared.currentUser?.id,
              let token = await AuthService.shared.validAccessToken() else {
            // Guests keep only the on-device StoreKit purchase.
            return
        }
        let ok = await recordTransactionOnServer(transaction, userID: userID, accessToken: token)
        if ok {
            serverEntitlementSyncPending = false
            await refreshEntitlementFromServer()
        } else {
            serverEntitlementSyncPending = true
        }
    }

    /// Record every currently owned on-device transaction on the
    /// server, then refresh the server entitlements once. Used on
    /// every launch, after restore, after sign-in, and when retrying
    /// a pending sync. The owned verified transactions are the
    /// queue: a record that failed before is simply tried again,
    /// and the server upserts on transaction_id, so repeats never
    /// duplicate.
    private func syncOwnedTransactionsToServer() async {
        guard SupabaseConfig.isConfigured,
              let userID = AuthService.shared.currentUser?.id,
              let token = await AuthService.shared.validAccessToken() else {
            return
        }
        var allRecorded = true
        for transaction in ownedTransactions {
            guard isEntitlingTransaction(transaction) else { continue }
            let ok = await recordTransactionOnServer(transaction, userID: userID, accessToken: token)
            if !ok { allRecorded = false }
        }
        if allRecorded {
            serverEntitlementSyncPending = false
            await refreshEntitlementFromServer()
        } else if !ownedTransactions.isEmpty {
            serverEntitlementSyncPending = true
        }
    }

    /// One record-purchase Edge Function call for one verified
    /// transaction. Returns true only when the server confirmed the
    /// record (the function replies with ok true). The caller owns
    /// the signed-in user check; this helper only validates the
    /// transaction itself.
    private func recordTransactionOnServer(_ transaction: Transaction, userID: String, accessToken: String) async -> Bool {
        guard isEntitlingTransaction(transaction) else { return false }
        return await SupabaseClient.shared.recordPurchaseViaFunction(
            transactionID: String(transaction.id),
            productID: transaction.productID,
            userID: userID,
            purchasedAt: transaction.purchaseDate,
            accessToken: accessToken
        )
    }

    /// Ask the server to drop the entitlement for a refunded or
    /// revoked transaction. Goes through the record-purchase Edge
    /// Function (the app cannot update user_purchases under RLS).
    /// Returns true ONLY when the server confirmed the revoke. The
    /// caller must persist a pending revoke BEFORE calling this and
    /// must honour a false result: a failed call means the server
    /// row may still read active, so the pending record stays and
    /// the transaction stays unfinished until a retry confirms.
    /// StoreKit reports refunds and revocations through the same
    /// revocation date, so both are recorded with status "revoked".
    /// The revoke is idempotent server-side: revoking a row that is
    /// already revoked still answers ok, so a retried revoke after
    /// a lost reply is safe. A missing row answers 404, which this
    /// Bool API cannot distinguish from a transient failure; the
    /// callers therefore also accept a definitive server read
    /// showing no active row as proof that nothing is left to revoke.
    private func revokeServerEntitlement(transactionID: String) async -> Bool {
        guard SupabaseConfig.isConfigured,
              let userID = AuthService.shared.currentUser?.id,
              let token = await AuthService.shared.validAccessToken() else {
            return false
        }
        return await revokeServerEntitlement(transactionID: transactionID, userID: userID, accessToken: token)
    }

    /// One revoke call with credentials the caller already resolved,
    /// so a retry loop does not re-fetch a token per record. Returns
    /// true only when the server confirmed the revoke.
    private func revokeServerEntitlement(transactionID: String, userID: String, accessToken: String) async -> Bool {
        await SupabaseClient.shared.revokePurchaseViaFunction(
            transactionID: transactionID,
            userID: userID,
            status: "revoked",
            accessToken: accessToken
        )
    }

    // MARK: - Pending server revokes (C3)

    /// The stored pending revokes for one namespace (an account user
    /// ID, or the guest namespace for orphans). A corrupt or missing
    /// record list reads as empty; the launch history sweep
    /// re-enqueues revoked transactions, so a corrupt list cannot
    /// permanently lose a revoke.
    private func loadPendingRevokes(namespace: String) -> [PendingRevoke] {
        let key = AccountScopedStorage.key(Self.pendingRevokeBaseKey, namespace: namespace)
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([PendingRevoke].self, from: data) else {
            return []
        }
        return records
    }

    private func savePendingRevokes(_ records: [PendingRevoke], namespace: String) {
        let key = AccountScopedStorage.key(Self.pendingRevokeBaseKey, namespace: namespace)
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Persist a pending revoke before its revoke is attempted, so a
    /// crash or a kill between the attempt and its reply cannot lose
    /// it. One record per transaction ID: re-enqueueing the same
    /// transaction is a no-op. Records are filed under the owning
    /// account's namespace, or the guest namespace when the owner
    /// is unknown.
    private func enqueuePendingRevoke(_ record: PendingRevoke) {
        let namespace = record.userID ?? AccountScopedStorage.guestNamespace
        var records = loadPendingRevokes(namespace: namespace)
        guard !records.contains(where: { $0.transactionID == record.transactionID }) else { return }
        records.append(record)
        savePendingRevokes(records, namespace: namespace)
    }

    private func removePendingRevoke(transactionID: String, namespace: String) {
        let records = loadPendingRevokes(namespace: namespace)
            .filter { $0.transactionID != transactionID }
        savePendingRevokes(records, namespace: namespace)
    }

    /// Retry every pending server revoke for the signed-in user,
    /// plus every orphan filed while signed out. Called on every
    /// launch, every sign-in, and every restore. No-op when nothing
    /// is pending, when the server is unconfigured, or when nobody
    /// is signed in: pending records wait for their account. An
    /// orphan is attempted under the current account; the server
    /// enforces row ownership, so an attempt under the wrong account
    /// fails harmlessly and the orphan stays pending for the owning
    /// account. After the attempts, one definitive server read
    /// cleans up phantom records for this account: a pending record
    /// whose product has no active row needs no revoke (the row was
    /// never recorded, or is already revoked). Orphans are never
    /// cleaned this way, because the current account's read says
    /// nothing about another account's rows. This function never
    /// writes serverEntitledProductIDs or the cache: only
    /// applyDefinitiveServerEntitlements writes that state, and this
    /// function never calls it.
    private func retryPendingRevokes() async {
        guard SupabaseConfig.isConfigured,
              let userID = AuthService.shared.currentUser?.id else { return }
        let ownRecords = loadPendingRevokes(namespace: userID)
        let orphanRecords = loadPendingRevokes(namespace: AccountScopedStorage.guestNamespace)
        guard !ownRecords.isEmpty || !orphanRecords.isEmpty else { return }
        guard let token = await AuthService.shared.validAccessToken() else { return }
        for record in ownRecords {
            let confirmed = await revokeServerEntitlement(
                transactionID: record.transactionID, userID: userID, accessToken: token)
            if confirmed {
                removePendingRevoke(transactionID: record.transactionID, namespace: userID)
                removeDownloadsForRevokedProduct(record.productID)
            }
        }
        for record in orphanRecords {
            let confirmed = await revokeServerEntitlement(
                transactionID: record.transactionID, userID: userID, accessToken: token)
            if confirmed {
                removePendingRevoke(transactionID: record.transactionID, namespace: AccountScopedStorage.guestNamespace)
                removeDownloadsForRevokedProduct(record.productID)
            }
        }
        let remaining = loadPendingRevokes(namespace: userID)
        guard !remaining.isEmpty else { return }
        guard let definitive = await fetchServerEntitledProductIDs(userID: userID, accessToken: token) else { return }
        for record in remaining where !definitive.contains(record.productID) {
            removePendingRevoke(transactionID: record.transactionID, namespace: userID)
            removeDownloadsForRevokedProduct(record.productID)
        }
    }

    /// Launch-only sweep for revokes the updates listener never saw:
    /// a refund whose transaction was already finished (for example
    /// by a build that finished before revoking) is never
    /// redelivered, but the transaction history still carries its
    /// revocationDate. Only revocationDate-bearing entries enqueue a
    /// pending revoke; absence from currentEntitlements is never
    /// treated as a revocation. Enqueueing is idempotent, and the
    /// retry in start() attempts what this sweep files. While
    /// signed out, entries file as orphans for a later sign-in.
    private func enqueueRevokesFromTransactionHistory() async {
        let ownerID = AuthService.shared.currentUser?.id
        for await result in Transaction.all {
            guard case .verified(let transaction) = result else { continue }
            guard Self.allProductIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate != nil else { continue }
            enqueuePendingRevoke(PendingRevoke(
                transactionID: String(transaction.id),
                productID: transaction.productID,
                userID: ownerID
            ))
        }
    }

    // MARK: - Server entitlement cache (H2)

    /// One server read for the signed-in user's active rows. Returns
    /// the product IDs when the server answered definitively (the
    /// set may be empty: that means no active row), or nil on ANY
    /// failure (no network, a server error, an undecodable reply).
    /// Nil is never evidence about the rows; only a returned set is.
    /// Callers must not treat nil as empty. This helper writes no
    /// state: applying a definitive answer belongs to
    /// applyDefinitiveServerEntitlements.
    private func fetchServerEntitledProductIDs(userID: String, accessToken: String) async -> Set<String>? {
        do {
            let data = try await SupabaseClient.shared.restGet(
                table: "user_purchases",
                query: "select=user_id,product_id,store,status&user_id=eq.\(userID)&status=eq.active",
                accessToken: accessToken
            )
            let rows = try SupabaseClient.shared.decodeRows(data, as: UserPurchaseRow.self)
            return Set(rows.map { $0.productID }.filter { Self.allProductIDs.contains($0) })
        } catch {
            return nil
        }
    }

    /// Apply one definitive server answer: replace the in-memory set
    /// and overwrite the cache record for this account, even when
    /// the answer is empty. An empty definitive answer is what
    /// clears a cached entitlement; nothing else may clear it.
    private func applyDefinitiveServerEntitlements(_ productIDs: Set<String>, userID: String) {
        serverEntitledProductIDs = productIDs
        saveServerEntitlementCache(productIDs: productIDs, userID: userID)
    }

    /// The fresh server-verified cache for one account, or nil when
    /// there is no usable record: missing, corrupt, filed for a
    /// different account, or older than the validity window. A
    /// record dated in the future is also unusable (fail closed on
    /// clock or storage surprises). The returned set holds only
    /// known catalogue product IDs.
    ///
    /// Release safety and DEBUG separation: this cache holds ONLY
    /// records written by saveServerEntitlementCache from decoded
    /// server rows, and it is read ONLY here, only from
    /// refreshEntitlementFromServer after a server read was
    /// attempted and failed, or no usable token could be obtained.
    /// No purchase or ownership path can write to it or be read
    /// from it: the retired bypass used the separate
    /// buildPhaseUnlockedProductIDsKey and purchasedProductIDsKey,
    /// init() never loads this cache, and no purchase or ownership
    /// path references these keys.
    /// The cache is therefore server-verified in both DEBUG and
    /// Release, and a build can never unlock from a retired bypass
    /// record through it. The account check inside the record is a
    /// second line of defence behind the account-scoped key: even
    /// if a key were ever misfiled, a record for another account
    /// is refused.
    private func cachedServerEntitlements(for userID: String) -> Set<String>? {
        let key = AccountScopedStorage.key(Self.serverEntitlementCacheBaseKey, namespace: userID)
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode(ServerEntitlementCache.self, from: data),
              cache.userID == userID else {
            return nil
        }
        let age = Date().timeIntervalSince1970 - cache.verifiedAt
        guard age >= 0, age < Self.serverEntitlementCacheValidity else { return nil }
        return Set(cache.productIDs.filter { Self.allProductIDs.contains($0) })
    }

    /// Write one cache record from a definitive server answer. The
    /// ONLY writer is applyDefinitiveServerEntitlements, fed only by
    /// fetchServerEntitledProductIDs. Never call this from any
    /// purchase, bypass, or local-cache path.
    private func saveServerEntitlementCache(productIDs: Set<String>, userID: String) {
        let cache = ServerEntitlementCache(
            userID: userID,
            productIDs: Array(productIDs),
            verifiedAt: Date().timeIntervalSince1970
        )
        let key = AccountScopedStorage.key(Self.serverEntitlementCacheBaseKey, namespace: userID)
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Private

    /// True when a verified transaction grants an entitlement: a
    /// known catalogue product, not revoked, and owned outright or
    /// shared through Family Sharing (the products are family
    /// shareable). All products are non-consumable, so there is no
    /// expiry to check.
    private func isEntitlingTransaction(_ transaction: Transaction) -> Bool {
        guard Self.allProductIDs.contains(transaction.productID) else { return false }
        guard transaction.revocationDate == nil else { return false }
        return transaction.ownershipType == .purchased || transaction.ownershipType == .familyShared
    }

    /// Handle a completed purchase. Only a verified transaction for
    /// a known product, with no revocation, unlocks anything, and
    /// only verified transactions are finished. An unverified result
    /// is never finished and never unlocks. A revoked transaction
    /// unlocks nothing and is handled by handleRevokedTransaction:
    /// its server revoke is persisted and retried, and the
    /// transaction is finished only once the revoke is confirmed
    /// (or a definitive server read shows no active row). An
    /// unfinished transaction is redelivered through the updates
    /// listener, which is the retry mechanism.
    private func handlePurchaseSuccess(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else {
            statusMessage = "Purchase could not be verified. Please try again."
            return
        }
        guard Self.allProductIDs.contains(transaction.productID) else {
            statusMessage = "Purchase could not be verified. Please try again."
            return
        }
        guard transaction.revocationDate == nil else {
            await handleRevokedTransaction(transaction)
            statusMessage = "That purchase was refunded or revoked, so nothing was unlocked."
            return
        }
        await transaction.finish()
        await refreshEntitlement()
        // Unlocking is already done above, from the verified local
        // transaction. Recording it on the server is best effort
        // and runs detached, so an undeployed or slow
        // record-purchase function can never delay or block the
        // unlock or its confirmation; the launch, sign-in, and
        // restore retries re-record it until the server confirms.
        Task { await syncPurchaseEntitlementToServer(transaction) }
        let name = ProductCatalogue.product(for: transaction.productID)?.name ?? "The course"
        statusMessage = "Thank you. \(name) is unlocked on this device."
    }

    /// Handle one revoked or refunded transaction (C3). Design choice:
    /// the transaction is finished ONLY when the server state is
    /// confirmed, because finishing is irreversible: StoreKit never
    /// redelivers a finished transaction, so finishing before the
    /// revoke succeeds is what used to strand a live server row with
    /// no retry. An unfinished transaction IS redelivered, and that
    /// redelivery plus the persisted pending record (retried on
    /// every launch, sign-in, and restore) is the retry mechanism,
    /// so the queue is never stranded: every path either finishes
    /// on confirmation or leaves a durable record and an unfinished
    /// transaction that will be offered again.
    ///
    /// Order matters. The on-device entitlement is removed FIRST
    /// (refreshEntitlement), so access on this device ends at once
    /// whether or not the server call succeeds. The pending revoke
    /// is persisted BEFORE the revoke is attempted, so a crash
    /// cannot lose it. Confirmation is either (a) the revoke call
    /// answering ok, or (b) a definitive server read showing no
    /// active row for the product, which proves there is nothing
    /// left to revoke when the row was never recorded or is already
    /// revoked (the Bool revoke API cannot distinguish a missing
    /// row from a transient failure, so this second proof is what
    /// keeps a never-recorded purchase from holding its transaction
    /// forever). A failed revoke with a failed or still-active read
    /// finishes nothing: the record stays pending and the
    /// transaction stays unfinished.
    ///
    /// Tradeoff, stated plainly: while a revoked transaction stays
    /// unfinished, StoreKit blocks a repurchase of the same product.
    /// That block lasts only until the server confirms or a
    /// definitive read shows no active row, and every launch retries,
    /// so it is bounded by server reachability. The alternative
    /// (finishing first) lets a refunded buyer keep cross-device
    /// access indefinitely, which is the defect being fixed.
    ///
    /// While signed out, no server row can be addressed, but the
    /// purchase may have been recorded under an account that is
    /// currently signed out, so the revoke files as an orphan and
    /// the transaction stays unfinished. The sign-in retry attempts
    /// orphans, and redelivery re-offers the transaction.
    /// Remove downloaded audio for a revoked product, once the server
    /// revoke is confirmed. A full-course revoke clears all downloads;
    /// a bundle revoke clears only that bundle's chapters; a situations
    /// revoke clears nothing (situations have no audio downloads).
    /// Best-effort for files already on disk: a download still in
    /// flight is not stopped and re-creates its file on completion.
    /// Runs on the main actor (this class is @MainActor), which the
    /// download store's published-state updates require.
    private func removeDownloadsForRevokedProduct(_ productID: String) {
        if productID == Self.fullCourseProductID {
            LessonDownloadStore.shared.removeAllDownloads()
            return
        }
        guard productID != Self.situationsProductID,
              let chapters = ProductCatalogue.product(for: productID)?.chapterIDs,
              !chapters.isEmpty else { return }
        LessonDownloadStore.shared.removeDownloads(forChapterIDs: Set(chapters))
    }

    private func handleRevokedTransaction(_ transaction: Transaction) async {
        await refreshEntitlement()
        let transactionID = String(transaction.id)
        guard SupabaseConfig.isConfigured,
              let userID = AuthService.shared.currentUser?.id else {
            enqueuePendingRevoke(PendingRevoke(
                transactionID: transactionID,
                productID: transaction.productID,
                userID: nil
            ))
            return
        }
        enqueuePendingRevoke(PendingRevoke(
            transactionID: transactionID,
            productID: transaction.productID,
            userID: userID
        ))
        if await revokeServerEntitlement(transactionID: transactionID) {
            removePendingRevoke(transactionID: transactionID, namespace: userID)
            removeDownloadsForRevokedProduct(transaction.productID)
            await refreshEntitlementFromServer()
            await transaction.finish()
            return
        }
        guard let token = await AuthService.shared.validAccessToken(),
              let definitive = await fetchServerEntitledProductIDs(userID: userID, accessToken: token) else {
            await refreshEntitlementFromServer()
            return
        }
        applyDefinitiveServerEntitlements(definitive, userID: userID)
        guard !definitive.contains(transaction.productID) else { return }
        removePendingRevoke(transactionID: transactionID, namespace: userID)
        removeDownloadsForRevokedProduct(transaction.productID)
        await transaction.finish()
    }

    /// Handle a StoreKit transaction update: a purchase made on
    /// another device, a refund, a revocation, or a Family Sharing
    /// change. Only verified updates for known products are finished.
    /// Unverified updates are ignored and never finished. A refund or
    /// revocation is handled by handleRevokedTransaction, which
    /// finishes only once the server revoke is confirmed; a new
    /// purchase on another device is finished at once, adds the
    /// entitlement, and is recorded on the server for the signed-in
    /// user (a failed server record there is covered by the pending
    /// sync flag and its retry paths, not by holding the finish).
    private func handleTransactionUpdate(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else { return }
        guard Self.allProductIDs.contains(transaction.productID) else { return }
        guard transaction.revocationDate == nil else {
            await handleRevokedTransaction(transaction)
            return
        }
        await transaction.finish()
        await refreshEntitlement()
        if purchasedProductIDs.contains(transaction.productID) {
            // Best effort, detached: see handlePurchaseSuccess.
            Task { await syncPurchaseEntitlementToServer(transaction) }
        }
    }

    /// Cache the purchased product IDs locally. Cache only: the App
    /// Store entitlement is the source of truth, re-checked on launch
    /// and on restore, and Release builds never read this cache to
    /// unlock anything. The legacy single key is kept in step so
    /// older builds' cached Situations purchase is not lost.
    private func setPurchasedProductIDs(_ value: Set<String>) {
        purchasedProductIDs = value
        UserDefaults.standard.set(Array(value), forKey: Self.purchasedProductIDsKey)
        UserDefaults.standard.set(value.contains(Self.situationsProductID), forKey: Self.purchasedKey)
    }
}
