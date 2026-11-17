// StoreManager.swift
// Payments Training Hub iOS - Apple In-App Purchase (StoreKit 2) for the
// catalogue products: the 10 courses, BA/PO Studio, Payment
// Simulator, Investigation Lab, Practice Experiences, Interview
// Ready, and The Integrated Course. Every purchase product is a
// non-consumable that gives 1 year of access from the verified
// purchase timestamp. Every product also has a renewal product: a
// 1-year auto-renewable subscription at half the sale price, with
// the same product ID plus ".renewal". Product IDs and catalogue
// data live in ProductCatalogue (Models); StoreKit is the only
// source of a purchase price.
// There are no App Store Connect products yet. Until they exist,
// the products are served by the local StoreKit Configuration file
// TrainingHub.storekit (same product IDs, same sale prices) when it
// is selected in the Xcode scheme. Once the real products exist in
// App Store Connect with these EXACT product IDs and the same prices,
// the app will fetch them from the App Store instead of the local
// file. DEBUG simulated
// purchases use ONLY that .storekit configuration: there is no local
// test-purchase path that unlocks without a StoreKit transaction.
//
// Access rules (ProductCatalogue): a buyer of a part gets ONLY that
// part's chapters. The Integrated Course unlocks every product.
// Each standalone product unlocks only its own content. A product
// is unlocked while the buyer holds an ACTIVE purchase of it, an
// ACTIVE renewal subscription for it, or an ACTIVE Integrated
// purchase or renewal. Expired entitlements lock again: a
// non-consumable purchase expires 1 year after its verified
// purchase date, and a renewal subscription expires at the
// subscription expiry StoreKit reports. The held-out ch37 is in no
// product and is never sold, so it is never locked. The free sample
// situations stay free without purchase; that mechanism lives in
// SituationsView, not here.
//
// SECURITY: purchases are App Store In-App Purchase only. There is
// no manual payment path in this file. In Release builds a product
// unlocks ONLY when (a) a verified, unexpired StoreKit transaction
// is active on this device, or (b) the signed-in user has an active,
// unexpired row in Supabase user_purchases for this product, or (c)
// a failed server read falls back to the server-verified entitlement
// cache for that same account, which replays only rows the server
// itself confirmed, only for 7 days, only while their recorded
// expiry is still in the future, and never for guests or for
// another account (see the cache helpers below). No other
// UserDefaults flag alone ever unlocks anything in Release: the
// store starts locked and only verified entitlements open it. A
// failed, cancelled, pending, unverified or expired purchase NEVER
// unlocks content. Only verified transactions are finished. This
// file only READS the server row back through SupabaseClient;
// server writes go through the record-purchase Edge Function, which
// holds the service-role key server-side. No service-role key is
// ever in the app.
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
// from the local TrainingHub.storekit configuration selected in
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
    var expiresAt: String?
    var status: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case productID = "product_id"
        case store
        case transactionID = "transaction_id"
        case purchasedAt = "purchased_at"
        case expiresAt = "expires_at"
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
/// with the time the server confirmed it and the expiry recorded
/// for each product ID (Unix time). Written only from decoded
/// server rows, never from any local purchase or bypass state. An
/// empty set is a real record: it means the server definitively
/// reported no active row, and it overwrites any older record so a
/// revoked entitlement cannot be resurrected offline. Records
/// written before expiries were stored decode with expiries nil
/// and unlock nothing on replay (fail closed).
private struct ServerEntitlementCache: Codable {
    var userID: String
    var productIDs: [String]
    var verifiedAt: TimeInterval
    var expiries: [String: TimeInterval]?
}

@MainActor
final class StoreManager: ObservableObject {

    /// Shared instance. TrainingHubApp uses this same instance
    /// as its @StateObject and passes it through the environment,
    /// so AuthService calls to StoreManager.shared reach the very
    /// instance the UI observes. There is exactly one StoreManager.
    static let shared = StoreManager()

    /// The Integrated Course product ID: it unlocks every product.
    static let integratedProductID = ProductCatalogue.integratedProductID

    /// Alias kept for existing call sites: the full course is The
    /// Integrated Course.
    static let fullCourseProductID = ProductCatalogue.fullCourseProductID

    /// The Practice Experiences product ID.
    static let practiceProductID = ProductCatalogue.practiceProductID

    /// The BA/PO Studio product ID.
    static let studioProductID = ProductCatalogue.studioProductID

    /// The Payment Simulator product ID.
    static let simulatorProductID = ProductCatalogue.simulatorProductID

    /// The Investigation Lab product ID.
    static let investigationLabProductID = ProductCatalogue.investigationLabProductID

    /// The Interview Ready product ID.
    static let interviewProductID = ProductCatalogue.interviewProductID

    /// All catalogue purchase product IDs, from ProductCatalogue.
    static let allProductIDs = ProductCatalogue.allProductIDs

    /// All renewal subscription product IDs, from ProductCatalogue.
    static let allRenewalProductIDs = ProductCatalogue.allRenewalProductIDs

    /// All store product IDs (purchases plus renewals), from
    /// ProductCatalogue. StoreKit fetches this full set.
    static let allStoreProductIDs = ProductCatalogue.allStoreProductIDs

    /// Retired 13 Nov 2026: always false. It used to let a DEBUG
    /// build open content on a Buy tap without a StoreKit purchase,
    /// which meant test builds never exercised StoreKit and never
    /// produced a verified transaction. Test builds now buy through
    /// real StoreKit transactions against TrainingHub.storekit.
    /// Other files read this symbol for purchase copy; keep it.
    static let buildPhaseBuyOpensContent = false

    /// Retired legacy key for the abolished standalone Situations
    /// purchase. Kept only so init() can purge it; nothing reads it
    /// to unlock anything any more, and nothing writes it.
    private static let purchasedKey = "pf.iap.situationsPurchased.v1"

    /// Local record of all purchased product IDs, as an array in
    /// UserDefaults. Cache only; the App Store entitlement is the
    /// source of truth, re-checked on launch and on restore. Release
    /// builds write this cache but never read it to unlock anything.
    private static let purchasedProductIDsKey = "pf.iap.purchasedProductIDs.v1"

    /// Local record of entitlement expiry timestamps (product ID
    /// to Unix time), written alongside the purchased cache from
    /// verified transactions only. DEBUG restore only; Release
    /// builds never read it to unlock anything.
    private static let entitlementExpiriesKey = "pf.iap.entitlementExpiries.v1"

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

    /// Medium date style for access-until messages, for example
    /// "15 Nov 2027".
    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// The fetched products, empty until the store loads them.
    @Published private(set) var products: [Product] = []

    /// The StoreKit product for one store ID (a purchase ID or a
    /// renewal ID), nil until loaded.
    func storeProduct(for productID: String) -> Product? {
        products.first { $0.id == productID }
    }

    /// True when every catalogue purchase product has loaded from
    /// StoreKit. Renewal products load with the same fetch; a
    /// renewal price is checked on its own ID when renewing.
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

    /// Expiry per store product ID from verified on-device
    /// transactions: the purchase date plus 1 year for a purchase,
    /// the subscription expiry for a renewal. Set only by
    /// refreshEntitlement, from verified transactions.
    @Published private(set) var deviceEntitlementExpiries: [String: Date] = [:]

    /// Expiry per store product ID from definitive server reads:
    /// the row's expires_at when present, else purchased_at plus
    /// 1 year. Set only by applyDefinitiveServerEntitlements and
    /// by replaying the server-verified cache.
    @Published private(set) var serverEntitlementExpiries: [String: Date] = [:]

    /// Product IDs the retired build-phase Buy bypass unlocked.
    /// Always empty now: the bypass is retired, init() purges its
    /// stored key, and isProductOwned() never consults this set.
    /// Kept so existing call sites and tests keep compiling.
    @Published private(set) var buildPhaseUnlockedProductIDs: Set<String> = []

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

    /// True when fewer products loaded than the catalogue holds:
    /// some prices are missing even though the fetch succeeded.
    /// The Checkout Retry row shows for either flag.
    @Published private(set) var productLoadIncomplete = false

    /// The last user-facing purchase status message, shown in Checkout.
    @Published private(set) var statusMessage: String?

    /// The product id a signed-out learner tried to buy, set when
    /// a Buy action finds no session. Views present the sign-in
    /// sheet while this is set and the learner is signed out;
    /// after sign-in the learner returns to the Buy button and
    /// taps it again: the purchase is never auto-executed.
    /// Cleared on sign-in sync and on sign-out, so a stale flag
    /// never pops an unsolicited sign-in prompt.
    @Published private(set) var signInRequiredForPurchase: String?

    /// Clear the pending sign-in-for-purchase flag, for example
    /// when the sign-in sheet is dismissed without signing in.
    func clearSignInRequiredForPurchase() {
        signInRequiredForPurchase = nil
    }

    /// Clear the last purchase message, for example after the
    /// learner dismisses the alert that showed it.
    func clearStatusMessage() { statusMessage = nil }

    /// The display price for one store ID (a purchase ID or a
    /// renewal ID) from StoreKit when it is loaded, otherwise
    /// "Price unavailable". The StoreKit localised displayPrice is
    /// the only price ever presented as a purchase price; the
    /// catalogue priceINR is reference data only and is never shown
    /// here. Callers must check isPriceAvailable(for:) before
    /// offering a purchase.
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

    /// The date the latest entitlement was purchased, from the
    /// verified App Store transaction when there is one.
    var purchasedOnDate: Date? {
        latestTransaction?.purchaseDate
    }

    /// True when this product is owned outright with an ACTIVE
    /// entitlement: a verified, unexpired StoreKit transaction on
    /// this device, or an active, unexpired server entitlement for
    /// the signed-in user (a definitive server read, or a fresh
    /// server-verified cache record after a failed read), for the
    /// purchase product or for its renewal subscription. The
    /// Integrated Course is not counted here: see
    /// isProductUnlocked. A renewal product ID passed directly
    /// answers for that renewal alone. An unknown ID owns nothing.
    /// ONLY those two sources count, in every build; no stored flag
    /// other than the server-verified cache is ever consulted.
    func isProductOwned(_ productID: String) -> Bool {
        if ProductCatalogue.isRenewalProductID(productID) {
            guard ProductCatalogue.productForStoreID(productID) != nil else { return false }
            return isStoreIDActive(productID)
        }
        guard let base = ProductCatalogue.product(for: productID) else { return false }
        return isStoreIDActive(base.productID) || isStoreIDActive(base.renewalProductID)
    }

    /// True when one store ID (a purchase ID or a renewal ID) holds
    /// an active entitlement from either source, with an unexpired
    /// expiry. An ID with no recorded expiry counts as active: that
    /// happens only for DEBUG-seeded cache state in tests, because
    /// every Release path records an expiry.
    private func isStoreIDActive(_ storeID: String, at now: Date = Date()) -> Bool {
        guard purchasedProductIDs.contains(storeID) || serverEntitledProductIDs.contains(storeID) else { return false }
        return EntitlementValidity.isActive(expiry: latestExpiry(for: storeID), at: now)
    }

    /// The latest recorded expiry for one store ID across both
    /// entitlement sources, or nil when none was recorded.
    private func latestExpiry(for storeID: String) -> Date? {
        [deviceEntitlementExpiries[storeID], serverEntitlementExpiries[storeID]].compactMap { $0 }.max()
    }

    /// True when this product is unlocked: owned outright with an
    /// active entitlement, or the Integrated Course is owned with
    /// an active entitlement. The Integrated Course unlocks every
    /// product. Owning one product does NOT unlock another: the
    /// parts and the standalone products are independent unless
    /// the Integrated Course is owned. An admin (app_metadata
    /// is_admin) sees every product unlocked, always.
    func isProductUnlocked(_ productID: String) -> Bool {
        if AuthService.shared.isAdmin { return true }
        if isProductOwned(productID) { return true }
        if productID == Self.fullCourseProductID { return false }
        return isProductOwned(Self.fullCourseProductID)
    }

    /// The date this product's access runs until, for the Purchases
    /// screen: the latest active expiry among the product's own
    /// purchase and renewal entitlements, or the Integrated
    /// Course's expiry when the product is unlocked through it.
    /// Nil when the product is not unlocked, or when no expiry was
    /// recorded (DEBUG-seeded state).
    func expiryDate(for productID: String) -> Date? {
        guard let base = ProductCatalogue.productForStoreID(productID),
              isProductUnlocked(productID) else { return nil }
        var candidates: [Date] = []
        for storeID in [base.productID, base.renewalProductID] {
            if let expiry = latestExpiry(for: storeID) { candidates.append(expiry) }
        }
        if base.productID != Self.fullCourseProductID, isProductOwned(Self.fullCourseProductID) {
            for storeID in [Self.fullCourseProductID, ProductCatalogue.renewalProductID(for: Self.fullCourseProductID)] {
                if let expiry = latestExpiry(for: storeID) { candidates.append(expiry) }
            }
        }
        return candidates.max()
    }

    /// Practice Experiences is unlocked when the Practice product
    /// is owned outright with an active entitlement (an In-App
    /// Purchase active on this device, or an active server
    /// entitlement in Supabase user_purchases for the signed-in
    /// user), or when the Integrated Course is owned. The free
    /// sample situations are handled in SituationsView and stay
    /// free regardless of this value.
    var isPracticeUnlocked: Bool { isProductUnlocked(Self.practiceProductID) }

    /// BA/PO Studio is unlocked when the Studio product is owned
    /// with an active entitlement, or when the Integrated Course
    /// is owned.
    var isStudioUnlocked: Bool { isProductUnlocked(Self.studioProductID) }

    /// The Payment Simulator is unlocked when the Simulator product
    /// is owned with an active entitlement, or when the Integrated
    /// Course is owned.
    var isSimulatorUnlocked: Bool { isProductUnlocked(Self.simulatorProductID) }

    /// The Investigation Lab is unlocked when the Lab product is
    /// owned with an active entitlement, or when the Integrated
    /// Course is owned.
    var isInvestigationLabUnlocked: Bool { isProductUnlocked(Self.investigationLabProductID) }

    /// Interview Ready is unlocked when the Interview product is
    /// owned with an active entitlement, or when the Integrated
    /// Course is owned.
    var isInterviewUnlocked: Bool { isProductUnlocked(Self.interviewProductID) }

    /// True when a chapter is unlocked. The held-out ch37 is always
    /// reachable: it is in no product and is never sold, so it is
    /// never locked behind a product that does not exist. An admin
    /// (app_metadata is_admin) sees every chapter unlocked. For
    /// every other chapter, the Integrated Course being owned
    /// unlocks it, or the part containing this chapter being owned
    /// unlocks it. A chapter that is in no part (unknown) is
    /// LOCKED: fail closed, so unmapped content is never free by
    /// accident.
    func isChapterUnlocked(_ chapterID: String) -> Bool {
        if AuthService.shared.isAdmin { return true }
        if ProductCatalogue.isHeldOutChapter(chapterID) { return true }
        if isProductOwned(Self.fullCourseProductID) { return true }
        guard let part = ProductCatalogue.productContaining(chapterID: chapterID) else { return false }
        return isProductOwned(part.productID)
    }

    /// The part that unlocks a chapter, for the lock screen copy.
    /// Nil when the chapter is in no part, or when it is already
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

    /// The in-flight product fetch, so concurrent loadProducts()
    /// calls join the same fetch instead of stacking duplicates or
    /// proceeding with no products. A failed or partial fetch can
    /// always be retried once it finishes.
    private var productsLoadTask: Task<Void, Never>?

    /// True while a purchase or a restore is running. Two Buy
    /// surfaces share this manager (the lesson card and the
    /// checkout sheet), so the flag, not the disabled button,
    /// is the guard against overlapping purchases.
    private var purchaseInFlight = false

    init() {
        // The retired bypass key and the retired legacy Situations
        // key are purged in every build, so a bypass unlock left by
        // an older DEBUG build, or a cached standalone Situations
        // purchase from the abolished 12-product division, can never
        // unlock anything again.
        UserDefaults.standard.removeObject(forKey: Self.buildPhaseUnlockedProductIDsKey)
        UserDefaults.standard.removeObject(forKey: Self.purchasedKey)
#if DEBUG
        // DEBUG only: restore the verified-transaction cache and
        // the cached expiry map so a development build keeps its
        // unlocked state across restarts until
        // refreshEntitlement() re-checks it. This cache is written
        // only from verified transactions. Cached IDs are filtered
        // to the current store IDs, so stale IDs from an older
        // catalogue unlock nothing. IDs with no cached expiry stay
        // active, matching how tests seed ownership.
        let cached = UserDefaults.standard.stringArray(forKey: Self.purchasedProductIDsKey) ?? []
        let restored = Set(cached.filter { Self.allStoreProductIDs.contains($0) })
        purchasedProductIDs = restored
        if let data = UserDefaults.standard.data(forKey: Self.entitlementExpiriesKey),
           let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data) {
            deviceEntitlementExpiries = decoded
                .filter { restored.contains($0.key) }
                .mapValues { Date(timeIntervalSince1970: $0) }
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
    /// retried; concurrent calls join the in-flight fetch and wait
    /// for it, so no caller proceeds with an empty product list.
    func loadProducts() async {
        if let task = productsLoadTask {
            await task.value
            return
        }
        let task = Task { await fetchProducts() }
        productsLoadTask = task
        await task.value
        productsLoadTask = nil
    }

    /// The fetch body. Load failures set the published flags only:
    /// the Checkout Retry row is their surface, and writing a
    /// status message here used to pop a Purchase alert over the
    /// first lesson opened, unprompted.
    private func fetchProducts() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let fetched = try await Product.products(for: Self.allStoreProductIDs)
            products = fetched.sorted { $0.id < $1.id }
            productLoadFailed = fetched.isEmpty
            productLoadIncomplete = fetched.count < Self.allStoreProductIDs.count
        } catch {
            productLoadFailed = true
            productLoadIncomplete = true
        }
    }

    /// Buy one product. A renewal product ID is routed to
    /// purchaseRenewal(for:), which enforces the direct-ownership
    /// rule. Handles success, cancellation, pending and failure
    /// with a clear message for each. A failed, cancelled, pending
    /// or unverified purchase never unlocks anything. A purchase is
    /// only offered when the StoreKit product (and its real price)
    /// has loaded; otherwise the buyer is told the price is
    /// unavailable and nothing is charged. Buying again while the
    /// product is already unlocked through the Integrated Course
    /// is refused: the buyer already has access.
    func purchase(productID: String) async {
        if ProductCatalogue.isRenewalProductID(productID) {
            guard let base = ProductCatalogue.productForStoreID(productID) else {
                statusMessage = "That product is not available. Please try again."
                return
            }
            await purchaseRenewal(for: base.productID)
            return
        }
        guard let catalogueProduct = ProductCatalogue.product(for: productID) else {
            statusMessage = "That product is not available. Please try again."
            return
        }
        if !AuthService.shared.isSignedIn {
            signInRequiredForPurchase = productID
            return
        }
        if isProductUnlocked(productID) {
            statusMessage = "\(catalogueProduct.name) is already unlocked."
            return
        }
        guard let product = await loadedStoreProduct(for: productID) else {
            statusMessage = "The price is not available yet. Check your connection and try again."
            return
        }
        await buyStoreProduct(product)
    }

    /// Renew one product for 1 more year at half the sale price, by
    /// buying its renewal subscription. The buyer must DIRECTLY own
    /// the product (an active purchase or an active renewal of that
    /// product itself): access through the Integrated Course does
    /// not qualify, because the renewal price must never be a cheap
    /// first buy. A renewal bought while the current access is
    /// still active extends from the subscription expiry StoreKit
    /// reports.
    func purchaseRenewal(for baseProductID: String) async {
        guard let catalogueProduct = ProductCatalogue.product(for: baseProductID) else {
            statusMessage = "That product is not available. Please try again."
            return
        }
        if !AuthService.shared.isSignedIn {
            signInRequiredForPurchase = catalogueProduct.renewalProductID
            return
        }
        guard isProductOwned(baseProductID) else {
            statusMessage = "Renewal is only available once you own \(catalogueProduct.name). Buy it first, then renew."
            return
        }
        guard let product = await loadedStoreProduct(for: catalogueProduct.renewalProductID) else {
            statusMessage = "The renewal price is not available yet. Check your connection and try again."
            return
        }
        await buyStoreProduct(product)
    }

    /// The loaded StoreKit product for one store ID, refetching once
    /// when it has not loaded yet. Nil when the product is still
    /// not loaded: the caller must not offer a purchase then.
    private func loadedStoreProduct(for storeID: String) async -> Product? {
        // Every build buys through StoreKit: in test builds the
        // product comes from the local TrainingHub.storekit
        // configuration, and only a verified transaction unlocks.
        if storeProduct(for: storeID) == nil {
            await loadProducts()
        }
        return storeProduct(for: storeID)
    }

    /// Run the StoreKit purchase sheet for one loaded product and
    /// handle every outcome. Shared by purchase(productID:) and
    /// purchaseRenewal(for:).
    private func buyStoreProduct(_ product: Product) async {
        // Atomic on the main actor: no suspension sits between the
        // guard and the set, so a second Buy tap cannot slip in.
        guard !purchaseInFlight else { return }
        purchaseInFlight = true
        isBusy = true
        defer {
            isBusy = false
            purchaseInFlight = false
        }
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
        // Same guard as a purchase: a restore must not overlap a
        // purchase, or two restores overlap each other.
        guard !purchaseInFlight else { return }
        purchaseInFlight = true
        isBusy = true
        defer {
            isBusy = false
            purchaseInFlight = false
        }
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
    /// products. A refunded, revoked, or EXPIRED transaction removes
    /// the entitlement and clears the stored transaction, so the UI
    /// goes back to Not purchased: a purchase expires 1 year after
    /// its verified purchase date, and a renewal subscription
    /// expires at the subscription expiry StoreKit reports. This
    /// function deliberately never calls the server revoke: absence
    /// from currentEntitlements is not proof of a revocation (a
    /// transaction can be absent for other reasons), and revoking
    /// on absence could permanently revoke a live purchase. The
    /// authoritative revocation signal is the revocationDate on a
    /// delivered transaction update (see handleRevokedTransaction)
    /// or in the transaction history (see
    /// enqueueRevokesFromTransactionHistory, run at launch); both
    /// persist a pending revoke that retries until confirmed.
    /// Server entitlements are untouched by this function.
    func refreshEntitlement() async {
        var entitled: [Transaction] = []
        var expiries: [String: Date] = [:]
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard isEntitlingTransaction(transaction) else { continue }
            entitled.append(transaction)
            let expiry = transactionExpiryDate(transaction)
            if let existing = expiries[transaction.productID] {
                expiries[transaction.productID] = max(existing, expiry)
            } else {
                expiries[transaction.productID] = expiry
            }
        }
        entitled.sort { $0.purchaseDate > $1.purchaseDate }
        ownedTransactions = entitled
        setPurchasedProductIDs(Set(entitled.map { $0.productID }), expiries: expiries)
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
            serverEntitlementExpiries = [:]
            return
        }
        guard let token = await AuthService.shared.validAccessToken() else {
            applyCachedServerEntitlementsOrClear(userID: userID)
            return
        }
        if let definitive = await fetchServerEntitlements(userID: userID, accessToken: token) {
            applyDefinitiveServerEntitlements(definitive, userID: userID)
        } else {
            applyCachedServerEntitlementsOrClear(userID: userID)
        }
    }

    /// Replay the fresh server-verified cache for one account after
    /// a failed server read, or clear the server entitlements when
    /// there is no usable record. The replayed map holds only
    /// unexpired rows for known store IDs.
    private func applyCachedServerEntitlementsOrClear(userID: String) {
        if let cached = cachedServerEntitlements(for: userID) {
            serverEntitledProductIDs = Set(cached.keys)
            serverEntitlementExpiries = cached
        } else {
            serverEntitledProductIDs = []
            serverEntitlementExpiries = [:]
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
        signInRequiredForPurchase = nil
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
        signInRequiredForPurchase = nil
        serverEntitledProductIDs = []
        serverEntitlementExpiries = [:]
        serverEntitlementSyncPending = false
        // Sign-out and account deletion both route through here:
        // every live audio service must stop, including players
        // owned by views that are not on screen.
        NotificationCenter.default.post(name: .pfStopAudioForAccessChange, object: nil)
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
        guard let definitive = await fetchServerEntitlements(userID: userID, accessToken: token) else { return }
        for record in remaining where definitive[record.productID] == nil {
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
            guard Self.allStoreProductIDs.contains(transaction.productID) else { continue }
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
    /// the expiry per store ID when the server answered definitively
    /// (the map may be empty: that means no active row), or nil on
    /// ANY failure (no network, a server error, an undecodable
    /// reply). Nil is never evidence about the rows; only a
    /// returned map is. Callers must not treat nil as empty. Only
    /// known store IDs with a parseable, still-future expiry are
    /// returned; rows with unparseable or missing dates and expired
    /// rows unlock nothing. When several rows cover one product,
    /// the latest expiry wins. This helper writes no state:
    /// applying a definitive answer belongs to
    /// applyDefinitiveServerEntitlements.
    private func fetchServerEntitlements(userID: String, accessToken: String) async -> [String: Date]? {
        do {
            let data = try await SupabaseClient.shared.restGet(
                table: "user_purchases",
                query: "select=user_id,product_id,store,status,purchased_at,expires_at&user_id=eq.\(userID)&status=eq.active",
                accessToken: accessToken
            )
            let rows = try SupabaseClient.shared.decodeRows(data, as: UserPurchaseRow.self)
            var expiries: [String: Date] = [:]
            let now = Date()
            for row in rows {
                guard Self.allStoreProductIDs.contains(row.productID) else { continue }
                guard let expiry = Self.serverRowExpiry(row), expiry > now else { continue }
                if let existing = expiries[row.productID] {
                    expiries[row.productID] = max(existing, expiry)
                } else {
                    expiries[row.productID] = expiry
                }
            }
            return expiries
        } catch {
            return nil
        }
    }

    /// The expiry of one server row: the server's expires_at when
    /// present and parseable, else purchased_at plus 1 year. Nil
    /// when neither timestamp parses: such a row unlocks nothing
    /// (fail closed).
    private static func serverRowExpiry(_ row: UserPurchaseRow) -> Date? {
        if let raw = row.expiresAt, let date = Self.parseServerTimestamp(raw) { return date }
        guard let raw = row.purchasedAt, let purchased = Self.parseServerTimestamp(raw) else { return nil }
        return EntitlementValidity.expiryDate(forPurchaseAt: purchased)
    }

    /// Parse a Supabase timestamptz string, with or without
    /// fractional seconds.
    private static func parseServerTimestamp(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }

    /// Apply one definitive server answer: replace the in-memory set
    /// and expiry map, and overwrite the cache record for this
    /// account, even when the answer is empty. An empty definitive
    /// answer is what clears a cached entitlement; nothing else may
    /// clear it.
    private func applyDefinitiveServerEntitlements(_ expiries: [String: Date], userID: String) {
        serverEntitledProductIDs = Set(expiries.keys)
        serverEntitlementExpiries = expiries
        saveServerEntitlementCache(expiries: expiries, userID: userID)
    }

    /// The fresh server-verified cache for one account, or nil when
    /// there is no usable record: missing, corrupt, filed for a
    /// different account, or older than the validity window. A
    /// record dated in the future is also unusable (fail closed on
    /// clock or storage surprises). The returned map holds only
    /// known store IDs with a still-future recorded expiry. A
    /// record written before expiries were stored (no expiry data)
    /// replays as an empty map: it unlocks nothing.
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
    private func cachedServerEntitlements(for userID: String) -> [String: Date]? {
        let key = AccountScopedStorage.key(Self.serverEntitlementCacheBaseKey, namespace: userID)
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode(ServerEntitlementCache.self, from: data),
              cache.userID == userID else {
            return nil
        }
        let age = Date().timeIntervalSince1970 - cache.verifiedAt
        guard age >= 0, age < Self.serverEntitlementCacheValidity else { return nil }
        guard let expiries = cache.expiries else { return [:] }
        let now = Date()
        var active: [String: Date] = [:]
        for (productID, timestamp) in expiries {
            guard Self.allStoreProductIDs.contains(productID) else { continue }
            let expiry = Date(timeIntervalSince1970: timestamp)
            guard expiry > now else { continue }
            active[productID] = expiry
        }
        return active
    }

    /// Write one cache record from a definitive server answer. The
    /// ONLY writer is applyDefinitiveServerEntitlements, fed only by
    /// fetchServerEntitlements. Never call this from any
    /// purchase, bypass, or local-cache path.
    private func saveServerEntitlementCache(expiries: [String: Date], userID: String) {
        let cache = ServerEntitlementCache(
            userID: userID,
            productIDs: Array(expiries.keys),
            verifiedAt: Date().timeIntervalSince1970,
            expiries: expiries.mapValues { $0.timeIntervalSince1970 }
        )
        let key = AccountScopedStorage.key(Self.serverEntitlementCacheBaseKey, namespace: userID)
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Private

    /// True when a verified transaction grants an entitlement: a
    /// known store product (a purchase or a renewal), not revoked,
    /// owned outright or shared through Family Sharing (the
    /// products are family shareable), and unexpired. A purchase
    /// expires 1 year after its verified purchase date; a renewal
    /// subscription expires at the subscription expiry StoreKit
    /// reports.
    private func isEntitlingTransaction(_ transaction: Transaction) -> Bool {
        guard Self.allStoreProductIDs.contains(transaction.productID) else { return false }
        guard transaction.revocationDate == nil else { return false }
        guard transaction.ownershipType == .purchased || transaction.ownershipType == .familyShared else { return false }
        return transactionExpiryDate(transaction) > Date()
    }

    /// The expiry of a verified transaction: the subscription
    /// expiry for a renewal subscription, else the purchase date
    /// plus 1 year. Every product gives 1 year of access.
    private func transactionExpiryDate(_ transaction: Transaction) -> Date {
        if let expiration = transaction.expirationDate { return expiration }
        return EntitlementValidity.expiryDate(forPurchaseAt: transaction.purchaseDate)
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
        guard Self.allStoreProductIDs.contains(transaction.productID) else {
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
        let name = ProductCatalogue.productForStoreID(transaction.productID)?.name ?? "The course"
        if let expiry = expiryDate(for: transaction.productID) {
            statusMessage = "Thank you. \(name) is unlocked until \(Self.displayDateFormatter.string(from: expiry))."
        } else {
            statusMessage = "Thank you. \(name) is unlocked on this device."
        }
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
    /// revoke is confirmed. An Integrated Course revoke (purchase or
    /// renewal) clears all downloads; a part revoke clears only that
    /// part's chapters; a standalone product revoke clears nothing
    /// (those products have no lesson audio downloads).
    /// Best-effort for files already on disk: a download still in
    /// flight is not stopped and re-creates its file on completion.
    /// Runs on the main actor (this class is @MainActor), which the
    /// download store's published-state updates require.
    private func removeDownloadsForRevokedProduct(_ productID: String) {
        guard let base = ProductCatalogue.productForStoreID(productID) else { return }
        if base.productID == Self.fullCourseProductID {
            LessonDownloadStore.shared.removeAllDownloads()
            return
        }
        guard !base.chapterIDs.isEmpty else { return }
        LessonDownloadStore.shared.removeDownloads(forChapterIDs: Set(base.chapterIDs))
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
              let definitive = await fetchServerEntitlements(userID: userID, accessToken: token) else {
            await refreshEntitlementFromServer()
            return
        }
        applyDefinitiveServerEntitlements(definitive, userID: userID)
        guard definitive[transaction.productID] == nil else { return }
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
        guard Self.allStoreProductIDs.contains(transaction.productID) else { return }
        guard transaction.revocationDate == nil else {
            await handleRevokedTransaction(transaction)
            // A refund or revocation on another device must not be
            // silent: the learner sees why the content locked.
            if let name = ProductCatalogue.productForStoreID(transaction.productID)?.name {
                statusMessage = "That purchase was refunded or revoked, so \(name) is no longer unlocked."
            }
            return
        }
        let wasOwned = purchasedProductIDs.contains(transaction.productID)
        await transaction.finish()
        await refreshEntitlement()
        if purchasedProductIDs.contains(transaction.productID) {
            // A purchase made on another device unlocks here too:
            // say so, once, only when it newly unlocked.
            if !wasOwned, let name = ProductCatalogue.productForStoreID(transaction.productID)?.name {
                if let expiry = expiryDate(for: transaction.productID) {
                    statusMessage = "Thank you. \(name) is unlocked until \(Self.displayDateFormatter.string(from: expiry))."
                } else {
                    statusMessage = "Thank you. \(name) is unlocked on this device."
                }
            }
            // Best effort, detached: see handlePurchaseSuccess.
            Task { await syncPurchaseEntitlementToServer(transaction) }
        }
    }

    /// Cache the purchased product IDs and their expiry timestamps
    /// locally. Cache only: the App Store entitlement is the source
    /// of truth, re-checked on launch and on restore, and Release
    /// builds never read this cache to unlock anything. Written
    /// only from verified transactions.
    private func setPurchasedProductIDs(_ value: Set<String>, expiries: [String: Date]) {
        purchasedProductIDs = value
        deviceEntitlementExpiries = expiries
        UserDefaults.standard.set(Array(value), forKey: Self.purchasedProductIDsKey)
        if let data = try? JSONEncoder().encode(expiries.mapValues { $0.timeIntervalSince1970 }) {
            UserDefaults.standard.set(data, forKey: Self.entitlementExpiriesKey)
        }
    }
}
