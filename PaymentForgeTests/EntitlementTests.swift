// EntitlementTests.swift
// PaymentForge iOS - Phase 1 (Release integrity) tests: the single
// entitlement model in ProductCatalogue and StoreManager.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the final app source before writing.
//
// What these tests prove, and what they cannot prove:
// - The catalogue shape (12 products, exact IDs, chapter coverage
//   with no overlaps or gaps, free samples) is asserted directly.
// - The unlock RULE logic (full course unlocks chapter products and
//   Situations; one bundle unlocks only its own chapters) is
//   asserted in DEBUG only, by seeding the DEBUG-only UserDefaults
//   cache that StoreManager init restores. That proves the rule in
//   isProductUnlocked and isChapterUnlocked. It does NOT prove the
//   Release verified-transaction path: purchasedProductIDs and
//   serverEntitledProductIDs have no test seam (the old test-purchase
//   API was removed in Phase 1), so a real purchase, restore, or
//   server entitlement can only be verified with the local .storekit
//   file, a StoreKit sandbox account, or live Supabase. Those are
//   manual test items; see the Phase 1 test report.
// - In Release builds the seeding tests assert the locked outcome
//   instead: polluted stored state must unlock nothing.
// - The fail-closed chapter rule (an unmapped chapter is locked) is
//   asserted here. The pending-revoke retry and the server-verified
//   entitlement cache live behind the same no-seam server paths and
//   are manual test items, like the record and revoke calls.

import XCTest
@testable import PaymentForge

@MainActor
final class EntitlementTests: XCTestCase {

    private let purchasedCacheKey = "pf.iap.purchasedProductIDs.v1"
    private let bypassKey = "pf.iap.buildPhaseUnlocked.v1"
    private let legacySituationsKey = "pf.iap.situationsPurchased.v1"

    private var cacheKeys: [String] {
        [purchasedCacheKey, bypassKey, legacySituationsKey]
    }

    override func setUp() {
        super.setUp()
        cleanCacheKeys()
    }

    override func tearDown() {
        cleanCacheKeys()
        super.tearDown()
    }

    private func cleanCacheKeys() {
        for key in cacheKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Seed owned product IDs through the DEBUG-only cache restore,
    /// then return a fresh store. In Release the seed is ignored by
    /// design and the store starts locked.
    private func storeOwning(_ productIDs: [String]) -> StoreManager {
        UserDefaults.standard.set(productIDs, forKey: purchasedCacheKey)
        return StoreManager()
    }

    // MARK: - Catalogue shape

    func testCatalogueHasTwelveProductsWithExactIDs() {
        XCTAssertEqual(ProductCatalogue.products.count, 12)
        XCTAssertEqual(ProductCatalogue.allProductIDs, [
            "com.paymentforge.app.full",
            "com.paymentforge.app.foundations",
            "com.paymentforge.app.messaging",
            "com.paymentforge.app.rails",
            "com.paymentforge.app.crossborder",
            "com.paymentforge.app.clearing",
            "com.paymentforge.app.cards",
            "com.paymentforge.app.compliance-ops",
            "com.paymentforge.app.architecture-apis",
            "com.paymentforge.app.ba-practice",
            "com.paymentforge.app.emerging",
            "com.paymentforge.app.situations"
        ])
        XCTAssertEqual(Set(ProductCatalogue.allProductIDs).count, 12, "Product IDs must be unique.")
        XCTAssertEqual(ProductCatalogue.fullCourseProductID, "com.paymentforge.app.full")
        XCTAssertEqual(ProductCatalogue.situationsProductID, "com.paymentforge.app.situations")
        XCTAssertEqual(StoreManager.fullCourseProductID, ProductCatalogue.fullCourseProductID)
        XCTAssertEqual(StoreManager.situationsProductID, ProductCatalogue.situationsProductID)
        XCTAssertEqual(StoreManager.allProductIDs, ProductCatalogue.allProductIDs)
    }

    func testCatalogueLookupsResolveEveryBundleID() {
        let bundleIDs = [
            "full", "foundations", "messaging", "rails", "crossborder",
            "clearing", "cards", "compliance-ops", "architecture-apis",
            "ba-practice", "emerging", "situations"
        ]
        for bundleID in bundleIDs {
            XCTAssertNotNil(ProductCatalogue.product(forBundleID: bundleID), "Bundle id \(bundleID) must resolve.")
        }
        XCTAssertNil(ProductCatalogue.product(forBundleID: "no-such-bundle"))
        XCTAssertNil(ProductCatalogue.product(for: "com.paymentforge.app.no-such-product"))
        XCTAssertNil(ProductCatalogue.product(for: ""))
    }

    func testSituationsAliasResolvesToSituationsProduct() {
        let aliased = ProductCatalogue.product(forBundleID: "situations-500")
        XCTAssertEqual(aliased?.productID, ProductCatalogue.situationsProductID)
        XCTAssertEqual(aliased?.situationCount, 564)
        XCTAssertEqual(ProductCatalogue.product(forBundleID: "situations")?.productID, ProductCatalogue.situationsProductID)
    }

    func testChapterCoverageIsExactlyCh1ToCh100WithNoOverlaps() {
        let bundles = ProductCatalogue.products.filter {
            $0.productID != ProductCatalogue.fullCourseProductID && $0.productID != ProductCatalogue.situationsProductID
        }
        XCTAssertEqual(bundles.count, 10, "There are 10 chapter bundles.")
        let allChapters = bundles.flatMap { $0.chapterIDs }
        XCTAssertEqual(allChapters.count, 100, "Bundle chapter lists must total 100: no overlaps.")
        XCTAssertEqual(Set(allChapters).count, 100, "No chapter may appear in two bundles.")
        XCTAssertEqual(Set(allChapters), Set((1...100).map { "ch\($0)" }), "Bundles must cover exactly ch1 to ch100: no gaps.")
    }

    func testPerBundleChapterCounts() {
        let expected: [String: Int] = [
            "foundations": 10,
            "messaging": 11,
            "rails": 14,
            "crossborder": 10,
            "clearing": 7,
            "cards": 7,
            "compliance-ops": 13,
            "architecture-apis": 10,
            "ba-practice": 13,
            "emerging": 5
        ]
        for (bundleID, count) in expected {
            XCTAssertEqual(
                ProductCatalogue.product(forBundleID: bundleID)?.chapterIDs.count,
                count,
                "Bundle \(bundleID) must contain \(count) chapters."
            )
        }
        XCTAssertEqual(ProductCatalogue.product(for: ProductCatalogue.fullCourseProductID)?.chapterIDs.count, 100)
        XCTAssertEqual(ProductCatalogue.product(for: ProductCatalogue.situationsProductID)?.chapterIDs.count, 0)
    }

    func testProductContainingNeverReturnsFullCourseOrSituations() {
        for number in 1...100 {
            let bundle = ProductCatalogue.productContaining(chapterID: "ch\(number)")
            XCTAssertNotNil(bundle, "ch\(number) must belong to a bundle.")
            XCTAssertNotEqual(bundle?.productID, ProductCatalogue.fullCourseProductID)
            XCTAssertNotEqual(bundle?.productID, ProductCatalogue.situationsProductID)
        }
        XCTAssertNil(ProductCatalogue.productContaining(chapterID: "ch0"))
        XCTAssertNil(ProductCatalogue.productContaining(chapterID: "ch101"))
        XCTAssertNil(ProductCatalogue.productContaining(chapterID: ""))
    }

    func testEveryManifestChapterBelongsToAProduct() {
        // M1: the manifest defines the chapters; every one of them
        // must map to exactly one chapter bundle. If a future
        // catalogue edit drops a mapping, this test fails loudly
        // instead of the chapter silently going free (chapters now
        // fail closed when unmapped).
        XCTAssertEqual(ContentManifest.chapterCount, 100)
        var mapped: [String] = []
        for number in 1...ContentManifest.chapterCount {
            let chapterID = "ch\(number)"
            let bundle = ProductCatalogue.productContaining(chapterID: chapterID)
            XCTAssertNotNil(bundle, "Manifest chapter \(chapterID) must belong to a product.")
            XCTAssertNotEqual(bundle?.productID, ProductCatalogue.fullCourseProductID)
            XCTAssertNotEqual(bundle?.productID, ProductCatalogue.situationsProductID)
            if let bundle {
                mapped.append(chapterID)
                XCTAssertTrue(bundle.chapterIDs.contains(chapterID))
            }
        }
        XCTAssertEqual(mapped.count, ContentManifest.chapterCount)
        XCTAssertEqual(Set(mapped), Set((1...ContentManifest.chapterCount).map { "ch\($0)" }))
    }

    func testUnmappedChapterIsLockedFailClosed() {
        // M1: a chapter no bundle contains is locked, never free.
        let fresh = StoreManager()
        for chapterID in ["ch0", "ch101", "ch999", ""] {
            XCTAssertFalse(fresh.isChapterUnlocked(chapterID), "An unmapped chapter must be locked, not free: \(chapterID).")
        }
        XCTAssertNil(fresh.unlockingProduct(for: "ch999"), "A chapter in no bundle has no unlocking product.")
        let bundleStore = storeOwning(["com.paymentforge.app.foundations"])
#if DEBUG
        XCTAssertFalse(bundleStore.isChapterUnlocked("ch999"), "Owning a bundle must not open an unmapped chapter.")
        // The full course is checked before the bundle mapping, so a
        // full-course owner passes every chapter check. Unmapped IDs
        // have no content behind them, so this opens nothing real.
        let fullStore = storeOwning([ProductCatalogue.fullCourseProductID])
        XCTAssertTrue(fullStore.isChapterUnlocked("ch999"))
#else
        XCTAssertFalse(bundleStore.isChapterUnlocked("ch999"), "Release must not unlock an unmapped chapter from stored state alone.")
#endif
    }

    func testFreeSampleSituationIDsAreExactlyTheSix() {
        XCTAssertEqual(ProductCatalogue.freeSampleSituationIDs, [
            "ABH-01", "JEB-C01", "ABH-03", "SCN-21", "RUN4-008", "INS-099"
        ])
        XCTAssertEqual(Set(ProductCatalogue.freeSampleSituationIDs).count, 6, "Free sample IDs must be unique.")
        // The catalogue list must stay in step with the runtime gate.
        XCTAssertEqual(ProductCatalogue.freeSampleSituationIDs, ContentService.freeSampleIDs)
    }

    // MARK: - Unlock rules

    func testUnknownProductIDsUnlockNothing() {
        let store = StoreManager()
        XCTAssertFalse(store.isProductOwned("com.paymentforge.app.no-such-product"))
        XCTAssertFalse(store.isProductUnlocked("com.paymentforge.app.no-such-product"))
        XCTAssertFalse(store.isProductOwned(""))
        XCTAssertFalse(store.isProductUnlocked(""))
    }

    func testFullCourseUnlocksEveryChapterProductAndSituations() {
        let store = storeOwning([ProductCatalogue.fullCourseProductID])
#if DEBUG
        XCTAssertTrue(store.isProductOwned(ProductCatalogue.fullCourseProductID))
        for productID in ProductCatalogue.allProductIDs {
            XCTAssertTrue(store.isProductUnlocked(productID), "The full course must unlock \(productID).")
        }
        XCTAssertTrue(store.isSituationsUnlocked)
        for number in 1...100 {
            XCTAssertTrue(store.isChapterUnlocked("ch\(number)"), "The full course must unlock ch\(number).")
        }
        XCTAssertEqual(store.unlockedProductCount, 12, "Full course unlocks all 12 products: every chapter product and Situations.")
#else
        XCTAssertFalse(store.isProductUnlocked(ProductCatalogue.fullCourseProductID), "Release must not unlock from stored state alone.")
        XCTAssertEqual(store.unlockedProductCount, 0)
#endif
    }

    func testSituationsOwnershipAloneUnlocksNoChapterProduct() {
        let store = storeOwning([ProductCatalogue.situationsProductID])
#if DEBUG
        XCTAssertTrue(store.isProductOwned(ProductCatalogue.situationsProductID))
        XCTAssertTrue(store.isProductUnlocked(ProductCatalogue.situationsProductID))
        XCTAssertTrue(store.isSituationsUnlocked)
        // Owning Situations alone unlocks no chapter product.
        for productID in ProductCatalogue.allProductIDs where productID != ProductCatalogue.situationsProductID {
            XCTAssertFalse(store.isProductUnlocked(productID), "Situations ownership must not unlock \(productID).")
        }
        XCTAssertFalse(store.isChapterUnlocked("ch1"))
        XCTAssertEqual(store.unlockedProductCount, 1)
#else
        XCTAssertFalse(store.isSituationsUnlocked, "Release must not unlock from stored state alone.")
        XCTAssertEqual(store.unlockedProductCount, 0)
#endif
    }

    func testOneBundleUnlocksOnlyItsOwnChapters() {
        let store = storeOwning(["com.paymentforge.app.foundations"])
#if DEBUG
        XCTAssertTrue(store.isProductUnlocked("com.paymentforge.app.foundations"))
        XCTAssertFalse(store.isProductUnlocked("com.paymentforge.app.messaging"))
        XCTAssertFalse(store.isSituationsUnlocked)
        XCTAssertTrue(store.isChapterUnlocked("ch1"), "ch1 is in Foundations.")
        XCTAssertTrue(store.isChapterUnlocked("ch64"), "ch64 is in Foundations.")
        XCTAssertFalse(store.isChapterUnlocked("ch5"), "ch5 is in Messaging, not Foundations.")
        XCTAssertFalse(store.isChapterUnlocked("ch95"), "ch95 is in Compliance, not Foundations.")
        XCTAssertEqual(store.unlockedProductCount, 1)
#else
        XCTAssertFalse(store.isChapterUnlocked("ch1"), "Release must not unlock from stored state alone.")
        XCTAssertEqual(store.unlockedProductCount, 0)
#endif
    }

    func testUnlockingProductPointsAtContainingBundleWhenLocked() {
        let store = StoreManager()
        XCTAssertEqual(store.unlockingProduct(for: "ch1")?.id, "foundations")
        XCTAssertEqual(store.unlockingProduct(for: "ch5")?.id, "messaging")
        XCTAssertNil(store.unlockingProduct(for: "ch999"), "A chapter in no bundle has no unlocking product.")
    }

    // MARK: - Price availability

    func testPriceTextIsUnavailableWhenNoStoreKitProductIsLoaded() {
        let store = StoreManager()
        XCTAssertFalse(store.allProductsLoaded)
        XCTAssertTrue(store.products.isEmpty, "A fresh store has loaded no StoreKit products.")
        for productID in ProductCatalogue.allProductIDs {
            XCTAssertFalse(store.isPriceAvailable(for: productID), "No price is available for \(productID) before StoreKit loads.")
            XCTAssertEqual(store.priceText(for: productID), "Price unavailable")
        }
        XCTAssertEqual(store.priceText, "Price unavailable")
        // The fallback must never be a hardcoded catalogue price.
        XCTAssertNotEqual(store.priceText(for: ProductCatalogue.fullCourseProductID), "Rs. 9,999")
        XCTAssertNotEqual(store.priceText(for: ProductCatalogue.situationsProductID), "Rs. 4,999")
        XCTAssertFalse(store.priceText(for: ProductCatalogue.fullCourseProductID).contains("9,999"))
    }
}
