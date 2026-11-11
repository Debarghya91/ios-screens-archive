// StoreManager.swift
// PaymentForge iOS - Apple In-App Purchase (StoreKit 2) for the 12
// course products: the 11 chapter bundles plus Payment Situations.
// Every product is a non-consumable, one-time purchase:
//   com.paymentforge.app.full            ("The Integrated Course", Rs. 9,999)
//   com.paymentforge.app.foundations     ("Payment Foundations", Rs. 1,499)
//   com.paymentforge.app.messaging       ("ISO 20022 and SWIFT Messaging", Rs. 2,999)
//   com.paymentforge.app.rails          ("Global Payment Rails", Rs. 2,499)
//   com.paymentforge.app.crossborder     ("Cross-Border and Correspondent Banking", Rs. 1,999)
//   com.paymentforge.app.clearing        ("Clearing, Settlement and Liquidity", Rs. 999)
//   com.paymentforge.app.cards           ("Cards and Domestic Payments", Rs. 1,499)
//   com.paymentforge.app.compliance-ops  ("Compliance, Risk, Operations and Reconciliation", Rs. 1,999)
//   com.paymentforge.app.architecture-apis ("Payment Architecture and APIs", Rs. 2,499)
//   com.paymentforge.app.ba-practice     ("AI Product Owner and Product Manager for Payments", Rs. 1,999)
//   com.paymentforge.app.emerging        ("Emerging Technologies and the Future", Rs. 999)
//   com.paymentforge.app.situations      ("Payment Situations", Rs. 4,999)
// There are no App Store Connect products yet: the owner has no paid
// Developer Program account. Until then the products are served by the
// local StoreKit Configuration file PaymentForge.storekit (same product
// IDs, same prices). Once he enrols, create the real products in App
// Store Connect with these EXACT product IDs and the same prices, and
// the app will fetch them from the App Store instead of the local file.
//
// Access rules (PaymentConfig, from bundles.json): a buyer of a bundle
// gets ONLY that bundle's chapters. The Integrated Course unlocks
// everything: all 100 chapters and the 564 situations. Situations is
// separate: only buyers of the situations product OR the full course
// can open them.
//
// SECURITY (Phase 1): there is NO device-local UPI unlock in this file.
// A submitted UTR is only ever a PENDING claim row in Supabase
// payment_claims. It never grants access on this device, and no claim
// status is ever stored in UserDefaults. A product unlocks only when
// (a) a verified StoreKit transaction is active on this device, or
// (b) the signed-in user has an active row in Supabase user_purchases
// for this product. Path (b) is how an admin-verified UPI payment
// unlocks: the verify-upi-claim edge function writes the
// user_purchases row, and this file only READS it back.
// Product IDs, prices and UPI ID live in PaymentConfig (SupabaseConfig.swift).
// No service-role key is ever in the app.

import Foundation
import Combine
import StoreKit

/// Status of a UPI payment claim, as stored on the server. A claim
/// starts Pending and only an admin moves it to Verified or Rejected
/// through the verify-upi-claim edge function. Pending and Rejected
/// never grant access.
enum UPIClaimStatus: String, Codable, CaseIterable {
    case pending = "Pending"
    case verified = "Verified"
    case rejected = "Rejected"
}

/// A UPI claim: a UTR submitted by the user for manual verification.
/// This is an in-memory view of a Supabase payment_claims row only.
/// It is never written to UserDefaults and never unlocks anything.
/// Legacy claims written to UserDefaults by older builds are migrated
/// once to Supabase (see migrateLegacyLocalClaim) and the local copy
/// is deleted; the migrated claim still grants nothing until verified.
/// `productID` is the App Store product the payment was for; claims
/// written before products carried it decode as Situations, which was
/// the only product then.
struct UPIClaim: Codable, Equatable {
    let id: String?
    let productID: String
    let product: String
    let amount: Int
    let payerName: String
    let utr: String
    let submittedAt: String
    var status: UPIClaimStatus

    init(id: String? = nil, productID: String = PaymentConfig.situationsProductID, product: String, amount: Int, payerName: String, utr: String, submittedAt: String, status: UPIClaimStatus = .pending) {
        self.id = id
        self.productID = productID
        self.product = product
        self.amount = amount
        self.payerName = payerName
        self.utr = utr
        self.submittedAt = submittedAt
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        productID = try container.decodeIfPresent(String.self, forKey: .productID) ?? PaymentConfig.situationsProductID
        product = try container.decode(String.self, forKey: .product)
        amount = try container.decode(Int.self, forKey: .amount)
        payerName = try container.decode(String.self, forKey: .payerName)
        utr = try container.decode(String.self, forKey: .utr)
        submittedAt = try container.decode(String.self, forKey: .submittedAt)
        status = try container.decodeIfPresent(UPIClaimStatus.self, forKey: .status) ?? .pending
    }
}

// MARK: - Supabase rows (payment_claims, user_purchases)

/// One row of the payment_claims table.
private struct PaymentClaimRow: Codable {
    var id: String?
    var userID: String?
    var productID: String
    var amount: Double
    var payerName: String?
    var utr: String
    var status: String
    var submittedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case productID = "product_id"
        case amount
        case payerName = "payer_name"
        case utr
        case status
        case submittedAt = "submitted_at"
    }
}

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

@MainActor
final class StoreManager: ObservableObject {

    /// The App Store Connect product ID for Payment Situations.
    /// Single source of truth is PaymentConfig; kept here so existing
    /// call sites reading StoreManager.situationsProductID keep working.
    static let situationsProductID = PaymentConfig.situationsProductID

    /// All 12 product IDs, from PaymentConfig.
    static let allProductIDs = PaymentConfig.allProductIDs

    /// The Integrated Course product ID: it unlocks everything.
    static let fullCourseProductID = PaymentConfig.fullCourseProductID

    /// Local record of the IAP purchases, so the unlocked state survives
    /// app restarts. The source of truth is the App Store entitlement,
    /// re-checked on launch and on restore; this flag is only a cache.
    /// Kept for the Situations purchase, so older builds' cached state
    /// is not lost; the per-product set below is the cache for all 12.
    private static let purchasedKey = "pf.iap.situationsPurchased.v1"

    /// Local record of all purchased product IDs, as an array in
    /// UserDefaults. Cache only; the App Store entitlement is the
    /// source of truth, re-checked on launch and on restore.
    private static let purchasedProductIDsKey = "pf.iap.purchasedProductIDs.v1"

#if DEBUG
    /// UserDefaults key for debug-only test purchases. Debug builds
    /// only: when StoreKit products cannot be loaded (no .storekit
    /// config, no App Store Connect products yet), Buy records a
    /// local test purchase here so the owner can test the app.
    /// Release builds never read or write this key, so real
    /// purchases are unaffected.
    private static let testPurchasedProductIDsKey = "pf.iap.testPurchasedProductIDs.v1"
#endif

    /// Legacy UserDefaults key an older build used for a local UPI
    /// claim. Read ONCE for migration and deleted immediately; never
    /// written again, never used as an unlock source.
    private static let legacyUPIClaimKey = "pf.upiClaim.v1"

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

    /// Product IDs with an active verified StoreKit transaction on
    /// this device. Set only from Transaction.currentEntitlements.
    @Published private(set) var purchasedProductIDs: Set<String> = []

#if DEBUG
    /// Product IDs unlocked by a debug test purchase on this device.
    /// Debug builds only; never synced to the server.
    @Published private(set) var testPurchasedProductIDs: Set<String> = []
#endif

    /// Product IDs with an active user_purchases row for the signed-in
    /// user on the server. This is the ONLY server path that unlocks
    /// a product, and it is set only by reading Supabase, never by
    /// anything stored on this device. Guests (no account) never have
    /// one; their StoreKit purchase is what unlocks them.
    @Published private(set) var serverEntitledProductIDs: Set<String> = []

    /// True when the App Store entitlement for Situations is active
    /// on this device (bought, and verified from the transaction).
    var isPurchased: Bool {
        purchasedProductIDs.contains(Self.situationsProductID)
    }

    /// True when the signed-in user has an active user_purchases row
    /// for Situations on the server. This is the ONLY server path
    /// that unlocks Situations, and it is set only by reading
    /// Supabase, never by anything stored on this device. Guests
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

    /// The latest UPI claim for the signed-in user, as read from the
    /// server. In-memory only, never persisted locally. Nil when no
    /// UTR has ever been submitted. A claim that exists is Pending
    /// until an admin verifies it; it does not unlock on its own.
    /// Only one claim is held at a time: the latest claim for the
    /// product the Purchases screen is currently showing.
    @Published private(set) var upiClaim: UPIClaim?

    /// True when a claim exists that has not been sent to the server
    /// yet (submitted while signed out, or the insert failed). It is
    /// retried on the next refresh; it never unlocks anything.
    @Published private(set) var hasPendingClaimUpload = false

    /// True when a StoreKit purchase could not be recorded on the
    /// server (the user_purchases table is read-only for the app
    /// under current RLS; see syncPurchaseEntitlementToServer). The
    /// on-device StoreKit entitlement still works; this only means
    /// the purchase is not yet visible on other devices.
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
    /// product is loaded, otherwise the fixed Rs. 4,999. Never changes
    /// the price itself.
    var priceText: String {
        priceText(for: Self.situationsProductID)
    }

    /// The display price for one product from StoreKit when it is
    /// loaded, otherwise the fixed price from PaymentConfig. Never
    /// changes the price itself.
    func priceText(for productID: String) -> String {
        if let product = storeProduct(for: productID) {
            return product.displayPrice
        }
        return PaymentConfig.product(for: productID)?.priceText ?? PaymentConfig.priceText
    }

    /// How the current Situations entitlement was obtained, for the
    /// Purchases screen. App Store wins when both exist.
    var purchaseMethod: String? {
        if isPurchased { return "App Store" }
        if isUPIClaimVerified { return "UPI" }
        if isServerEntitlementVerified { return "Verified purchase" }
        return nil
    }

    /// The date the latest entitlement was purchased, from the
    /// verified App Store transaction when there is one. UPI claims
    /// have no transaction date; they show their submitted date
    /// in the claims tab instead.
    var purchasedOnDate: Date? {
        latestTransaction?.purchaseDate
    }

    /// True when this product is owned outright: a verified StoreKit
    /// transaction on this device, or an active server entitlement
    /// for the signed-in user. The full course is not counted here:
    /// see isProductUnlocked.
    func isProductOwned(_ productID: String) -> Bool {
        if purchasedProductIDs.contains(productID) || serverEntitledProductIDs.contains(productID) { return true }
#if DEBUG
        return testPurchasedProductIDs.contains(productID)
#else
        return false
#endif
    }

    /// True when this product is unlocked: owned outright, or the
    /// Integrated Course is owned (it unlocks everything, including
    /// Situations). A submitted UTR never unlocks: it only creates a
    /// pending server claim, and only an admin-verified claim (which
    /// writes the user_purchases row) unlocks through the server path.
    func isProductUnlocked(_ productID: String) -> Bool {
        if isProductOwned(productID) { return true }
        if productID == Self.fullCourseProductID { return false }
        return isProductOwned(Self.fullCourseProductID)
    }

    /// Situations are unlocked when EITHER the In-App Purchase is
    /// active on this device OR the signed-in user has an active
    /// server entitlement in Supabase user_purchases, OR the
    /// Integrated Course is owned. A submitted UTR never unlocks: it
    /// only creates a pending server claim, and only an admin-verified
    /// claim (which writes the user_purchases row) unlocks through
    /// the server path.
    var isSituationsUnlocked: Bool {
        isProductUnlocked(Self.situationsProductID)
    }

    /// True when a chapter is unlocked: the Integrated Course is
    /// owned, or the bundle containing this chapter is owned. A
    /// chapter no bundle contains is never locked: it stays open
    /// rather than locking content the catalogue cannot map.
    func isChapterUnlocked(_ chapterID: String) -> Bool {
        if isProductOwned(Self.fullCourseProductID) { return true }
        guard let bundle = PaymentConfig.productContaining(chapterID) else { return true }
        return isProductOwned(bundle.productID)
    }

    /// The bundle that unlocks a chapter, for the lock screen copy.
    /// Nil when the chapter is in no bundle, or when it is already
    /// unlocked.
    func unlockingProduct(for chapterID: String) -> CourseProduct? {
        guard !isChapterUnlocked(chapterID) else { return nil }
        return PaymentConfig.productContaining(chapterID)
    }

    /// How many of the 12 products are unlocked, for the Purchases
    /// screen summary.
    var unlockedProductCount: Int {
        Self.allProductIDs.filter { isProductUnlocked($0) }.count
    }

    /// True when a UPI claim is known for this user, whatever its
    /// status. Display only; do not use it as an unlock check.
    var hasUPIClaim: Bool {
        upiClaim != nil
    }

    /// True only when the server says the latest UPI claim is
    /// Verified. Display only: the unlock itself comes from the
    /// user_purchases row that verification creates, read by
    /// refreshEntitlementFromServer, not from this flag.
    var isUPIClaimVerified: Bool {
        upiClaim?.status == .verified
    }

    private var updatesTask: Task<Void, Never>?

    init() {
        let cached = UserDefaults.standard.stringArray(forKey: Self.purchasedProductIDsKey) ?? []
        purchasedProductIDs = Set(cached.filter { Self.allProductIDs.contains($0) })
#if DEBUG
        let testCached = UserDefaults.standard.stringArray(forKey: Self.testPurchasedProductIDsKey) ?? []
        testPurchasedProductIDs = Set(testCached.filter { Self.allProductIDs.contains($0) })
#endif
        // Older builds cached only the Situations purchase under the
        // single key; carry it into the per-product set once.
        if UserDefaults.standard.bool(forKey: Self.purchasedKey) {
            purchasedProductIDs.insert(Self.situationsProductID)
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Load the products and re-check the entitlements. Call once at launch.
    /// Starts the listener for transaction updates (refunds, purchases
    /// made on another device, family sharing). Migrates any legacy
    /// local UPI claim to the server first, then re-checks both the
    /// App Store entitlements and the server entitlements.
    func start() async {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handleTransactionUpdate(update)
            }
        }
        await loadProduct()
        await migrateLegacyLocalClaim()
        await refreshEntitlement()
        await refreshUPIClaimStatus()
    }

    /// Fetch all 12 products from the App Store (or the local .storekit
    /// file while there are no App Store Connect products yet).
    func loadProducts() async {
        guard products.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let fetched = try await Product.products(for: Self.allProductIDs)
            products = fetched.sorted { $0.id < $1.id }
            productLoadFailed = fetched.isEmpty
            if fetched.isEmpty {
                statusMessage = "The products could not be loaded. Check your connection and try again."
            }
        } catch {
            productLoadFailed = true
            statusMessage = "The products could not be loaded. Check your connection and try again."
        }
    }

    /// Fetch the products. Kept so existing call sites reading
    /// loadProduct keep working; it loads all 12 products.
    func loadProduct() async {
        await loadProducts()
    }

    /// Buy Payment Situations. Kept so existing call sites keep
    /// working; it buys the situations product.
    func purchase() async {
        await purchase(productID: Self.situationsProductID)
    }

#if DEBUG
    /// Record a debug test purchase: unlocks the product on this
    /// device only, for testing. Debug builds only; never touches
    /// StoreKit or the server.
    private func recordTestPurchase(productID: String) {
        testPurchasedProductIDs.insert(productID)
        UserDefaults.standard.set(Array(testPurchasedProductIDs), forKey: Self.testPurchasedProductIDsKey)
        let name = PaymentConfig.product(for: productID)?.name ?? "The course"
        statusMessage = "Test purchase: \(name) unlocked on this device."
    }
#endif

    /// Buy one product. Handles success, cancellation, pending and
    /// failure with a clear message for each.
    func purchase(productID: String) async {
        guard PaymentConfig.product(for: productID) != nil else {
            statusMessage = "That product is not available. Please try again."
            return
        }
        if storeProduct(for: productID) == nil {
            await loadProducts()
        }
        guard let product = storeProduct(for: productID) else {
#if DEBUG
            // Debug builds only: the store has no products (no
            // .storekit config or no App Store Connect products yet),
            // so Buy records a local test purchase and unlocks now.
            // Release builds keep the error below.
            recordTestPurchase(productID: productID)
            return
#else
            statusMessage = "The product could not be loaded. Check your connection and try again."
            return
#endif
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
    /// Asks the App Store to sync, then re-checks the entitlements.
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
        let unlocked = unlockedProductCount
        if unlocked > 0 {
            statusMessage = "Purchases restored. \(unlocked) of 12 products unlocked."
        } else {
            statusMessage = "No purchase was found for this Apple ID."
        }
    }

    /// Re-check the current App Store entitlements for all 12 products.
    /// A refunded or revoked transaction removes the entitlement and
    /// clears the stored transaction, so the UI goes back to
    /// Not purchased. Server entitlements are untouched by this:
    /// refunds only apply to App Store purchases.
    func refreshEntitlement() async {
        var entitled: [Transaction] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if Self.allProductIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                entitled.append(transaction)
            }
        }
        entitled.sort { $0.purchaseDate > $1.purchaseDate }
        ownedTransactions = entitled
        setPurchasedProductIDs(Set(entitled.map { $0.productID }))
    }

    /// Re-read the server entitlements for the signed-in user from
    /// Supabase user_purchases. This is the only server unlock path.
    /// Guests have no server entitlement. A revoked or refunded
    /// server row (status not active) grants nothing.
    func refreshEntitlementFromServer() async {
        guard SupabaseConfig.isConfigured,
              let userID = AuthService.shared.currentUser?.id,
              let token = await AuthService.shared.validAccessToken() else {
            serverEntitledProductIDs = []
            return
        }
        do {
            let data = try await SupabaseClient.shared.restGet(
                table: "user_purchases",
                query: "select=user_id,product_id,store,status&user_id=eq.\(userID)&status=eq.active",
                accessToken: token
            )
            let rows = try SupabaseClient.shared.decodeRows(data, as: UserPurchaseRow.self)
            serverEntitledProductIDs = Set(rows.map { $0.productID }.filter { Self.allProductIDs.contains($0) })
        } catch {
            // A failed read never unlocks and never locks out a
            // StoreKit purchase: it only leaves the server set empty
            // when it was already empty, and keeps the StoreKit
            // entitlements untouched.
            serverEntitledProductIDs = []
        }
    }

    // MARK: - UPI claims (server only, never local)

    /// Submit a UTR for manual verification for Payment Situations.
    /// Kept so existing call sites keep working.
    @discardableResult
    func submitUPIClaim(payerName: String, utr: String) async -> UPIClaim {
        await submitUPIClaim(productID: Self.situationsProductID, payerName: payerName, utr: utr)
    }

    /// Submit a UTR for manual verification for one product. This
    /// writes a PENDING row to Supabase payment_claims and returns the
    /// claim; it does NOT unlock the product. Only an admin-verified
    /// claim unlocks, through the user_purchases row the edge function
    /// creates. A guest (not signed in) cannot write a server row under
    /// RLS, so the claim is held in memory only and flagged for upload;
    /// it is sent on the next refresh once the user signs in.
    @discardableResult
    func submitUPIClaim(productID: String, payerName: String, utr: String) async -> UPIClaim {
        let product = PaymentConfig.product(for: productID)
        let claim = UPIClaim(
            productID: productID,
            product: product.map { "\($0.name), \($0.contentsText)" } ?? productID,
            amount: product?.priceINR ?? PaymentConfig.priceAmountINR,
            payerName: payerName,
            utr: utr,
            submittedAt: ISO8601DateFormatter().string(from: Date()),
            status: .pending
        )
        upiClaim = claim
        hasPendingClaimUpload = true
        await uploadClaimToServer(claim)
        return upiClaim ?? claim
    }

    /// Retry sending a claim that is held locally because the user
    /// was signed out (or the insert failed) when it was submitted.
    /// Called from refreshUPIClaimStatus and from start().
    func uploadPendingClaim() async {
        guard let claim = upiClaim, hasPendingClaimUpload else { return }
        await uploadClaimToServer(claim)
    }

    /// Send one claim row to Supabase payment_claims. Never grants
    /// access; the row is always status pending.
    private func uploadClaimToServer(_ claim: UPIClaim) async {
        guard SupabaseConfig.isConfigured,
              let userID = AuthService.shared.currentUser?.id,
              let token = await AuthService.shared.validAccessToken() else {
            // Not signed in (or not configured): keep the claim in
            // memory only and retry after sign-in. Never unlock.
            statusMessage = "Your UTR is recorded as Pending. Sign in so it can be sent for verification."
            return
        }
        let row = PaymentClaimRow(
            id: nil,
            userID: userID,
            productID: claim.productID,
            amount: Double(claim.amount),
            payerName: claim.payerName,
            utr: claim.utr,
            status: UPIClaimStatus.pending.rawValue.lowercased(),
            submittedAt: claim.submittedAt
        )
        do {
            let data = try await SupabaseClient.shared.restInsert(
                table: "payment_claims",
                rows: [row],
                accessToken: token,
                returning: true
            )
            let inserted = try? SupabaseClient.shared.decodeRows(data, as: PaymentClaimRow.self)
            var saved = claim
            if let serverID = inserted?.first?.id {
                saved = UPIClaim(
                    id: serverID,
                    productID: claim.productID,
                    product: claim.product,
                    amount: claim.amount,
                    payerName: claim.payerName,
                    utr: claim.utr,
                    submittedAt: claim.submittedAt,
                    status: claim.status
                )
            }
            upiClaim = saved
            hasPendingClaimUpload = false
            statusMessage = nil
        } catch {
            // The insert failed: the claim stays pending-upload in
            // memory and is retried later. It never unlocks.
            hasPendingClaimUpload = true
            statusMessage = "Your UTR could not be sent yet. Check your connection and refresh the claim status."
        }
    }

    /// Re-fetch the latest claim status for Payment Situations from
    /// Supabase. Kept so existing call sites keep working.
    func refreshUPIClaimStatus() async {
        await refreshUPIClaimStatus(for: Self.situationsProductID)
    }

    /// Re-fetch the latest claim status for one product from Supabase
    /// and update the UI. This is the ONLY way a claim status changes
    /// in the app: no local method can mark a claim verified or
    /// rejected. After reading the claim, the server entitlements are
    /// re-read too, so an admin-verified payment unlocks through
    /// user_purchases.
    func refreshUPIClaimStatus(for productID: String) async {
        await uploadPendingClaim()
        guard SupabaseConfig.isConfigured,
              let userID = AuthService.shared.currentUser?.id,
              let token = await AuthService.shared.validAccessToken() else {
            return
        }
        do {
            let data = try await SupabaseClient.shared.restGet(
                table: "payment_claims",
                query: "select=id,user_id,product_id,amount,payer_name,utr,status,submitted_at&user_id=eq.\(userID)&product_id=eq.\(productID)&order=submitted_at.desc&limit=1",
                accessToken: token
            )
            let rows = try SupabaseClient.shared.decodeRows(data, as: PaymentClaimRow.self)
            if let row = rows.first {
                let status = UPIClaimStatus(rawValue: row.status.capitalized) ?? .pending
                let product = PaymentConfig.product(for: productID)
                // Keep the payer name from the claim already on screen
                // when it is for the same product; the server row does
                // not always carry it back.
                let payerName = (upiClaim?.productID == productID) ? (upiClaim?.payerName ?? "") : (row.payerName ?? "")
                upiClaim = UPIClaim(
                    id: row.id,
                    productID: productID,
                    product: product.map { "\($0.name), \($0.contentsText)" } ?? productID,
                    amount: Int(row.amount),
                    payerName: payerName,
                    utr: row.utr,
                    submittedAt: row.submittedAt ?? upiClaim?.submittedAt ?? ISO8601DateFormatter().string(from: Date()),
                    status: status
                )
                hasPendingClaimUpload = false
            } else if upiClaim?.productID == productID {
                // No server claim for this product: clear a stale
                // on-screen claim for it rather than showing another
                // product's claim under this product's name.
                upiClaim = nil
            }
        } catch {
            // A failed refresh leaves the last known claim on screen
            // and changes nothing about access.
        }
        await refreshEntitlementFromServer()
    }

    /// Remove the in-memory claim from this device. This deletes
    /// nothing on the server: a submitted claim can only be decided
    /// by an admin. Kept so the UI can clear a claim that was never
    /// sent (for example a guest claim held only in memory).
    func clearUPIClaim() {
        upiClaim = nil
        hasPendingClaimUpload = false
    }

    /// One-time migration for claims an older build stored locally
    /// under pf.upiClaim.v1. The local copy is deleted immediately,
    /// before any network call, so it can never be read as an unlock
    /// again. The claim is then submitted ONCE to Supabase as status
    /// pending (never granting access). When the user is signed out
    /// the claim is held in memory only and uploaded on the next
    /// refresh after sign-in.
    private func migrateLegacyLocalClaim() async {
        guard let json = UserDefaults.standard.string(forKey: Self.legacyUPIClaimKey),
              let data = json.data(using: .utf8),
              let legacy = try? JSONDecoder().decode(UPIClaim.self, from: data) else {
            return
        }
        UserDefaults.standard.removeObject(forKey: Self.legacyUPIClaimKey)
        // Never let a legacy verified-looking local status through:
        // the migrated claim is always pending until the server says
        // otherwise.
        let pending = UPIClaim(
            id: legacy.id,
            productID: legacy.productID,
            product: legacy.product,
            amount: legacy.amount,
            payerName: legacy.payerName,
            utr: legacy.utr,
            submittedAt: legacy.submittedAt,
            status: .pending
        )
        upiClaim = pending
        hasPendingClaimUpload = true
        await uploadClaimToServer(pending)
    }

    // MARK: - Server purchase entitlement

    /// Record a verified StoreKit purchase on the server so the
    /// entitlement syncs across devices. Called on purchase, on
    /// restore and on transaction updates.
    /// NOTE: under the current RLS (0002_rls.sql) user_purchases is
    /// SELECT-only for the app, so a direct upsert is rejected and
    /// this sets serverEntitlementSyncPending instead. The on-device
    /// StoreKit entitlement is unaffected. A server-side
    /// record-purchase edge function (service-role key, same pattern
    /// as verify-upi-claim) is needed before cross-device StoreKit
    /// sync works; until then the flag records that the write is due.
    private func syncPurchaseEntitlementToServer(_ transaction: Transaction) async {
        guard SupabaseConfig.isConfigured,
              let userID = AuthService.shared.currentUser?.id,
              let token = await AuthService.shared.validAccessToken() else {
            // Guests keep only the on-device StoreKit purchase.
            return
        }
        // user_purchases is SELECT-only for the app under RLS, so the
        // write goes through the record-purchase edge function, which
        // holds the service-role key server-side. The function upserts
        // on transaction_id, so repeat calls never duplicate.
        let ok = await SupabaseClient.shared.recordPurchaseViaFunction(
            transactionID: String(transaction.id),
            productID: transaction.productID,
            userID: userID,
            purchasedAt: transaction.purchaseDate,
            accessToken: token
        )
        if ok {
            serverEntitlementSyncPending = false
            await refreshEntitlementFromServer()
        } else {
            serverEntitlementSyncPending = true
        }
    }

    /// Ask the server to drop the entitlement for a refunded or
    /// revoked transaction. Goes through the record-purchase edge
    /// function (the app cannot update user_purchases under RLS).
    /// Best effort only: a failed call only sets the sync-pending
    /// flag. The on-device entitlement is already cleared by
    /// refreshEntitlement, so access is lost on this device regardless.
    private func revokeServerEntitlement(transactionID: String) async {
        guard SupabaseConfig.isConfigured,
              let userID = AuthService.shared.currentUser?.id,
              let token = await AuthService.shared.validAccessToken() else {
            return
        }
        _ = await SupabaseClient.shared.revokePurchaseViaFunction(
            transactionID: transactionID,
            userID: userID,
            status: "revoked",
            accessToken: token
        )
    }

    // MARK: - Private

    private func handlePurchaseSuccess(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else {
            statusMessage = "Purchase could not be verified. Please try again."
            return
        }
        guard Self.allProductIDs.contains(transaction.productID) else {
            statusMessage = "Purchase could not be verified. Please try again."
            return
        }
        await transaction.finish()
        await refreshEntitlement()
        await syncPurchaseEntitlementToServer(transaction)
        let name = PaymentConfig.product(for: transaction.productID)?.name ?? "The course"
        statusMessage = "Thank you. \(name) is unlocked on this device."
    }

    private func handleTransactionUpdate(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else { return }
        guard Self.allProductIDs.contains(transaction.productID) else { return }
        await transaction.finish()
        // A refund or revocation removes the entitlement; a new purchase
        // on another device adds it. refreshEntitlement re-checks the
        // live entitlement, so a revoked transaction clears the UI,
        // and the server entitlement is dropped too.
        let wasRevoked = transaction.revocationDate != nil
        await refreshEntitlement()
        if wasRevoked {
            await revokeServerEntitlement(transactionID: String(transaction.id))
            await refreshEntitlementFromServer()
        } else if purchasedProductIDs.contains(transaction.productID) {
            await syncPurchaseEntitlementToServer(transaction)
        }
    }

    /// Cache the purchased product IDs locally. Cache only: the App
    /// Store entitlement is the source of truth, re-checked on launch
    /// and on restore. The legacy single key is kept in step so older
    /// builds' cached Situations purchase is not lost.
    private func setPurchasedProductIDs(_ value: Set<String>) {
        purchasedProductIDs = value
        UserDefaults.standard.set(Array(value), forKey: Self.purchasedProductIDsKey)
        UserDefaults.standard.set(value.contains(Self.situationsProductID), forKey: Self.purchasedKey)
    }
}
