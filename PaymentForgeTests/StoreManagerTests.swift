// StoreManagerTests.swift
// PaymentForge iOS - Phase 7 unit tests: entitlement logic, reconciled
// for Phase 1 (Release integrity).
// The security rule under test: nothing unlocks without a verified
// StoreKit transaction on this device or a server entitlement row
// (user_purchases). A fresh store is locked: no chapters, no
// situations, no products. Purchases are IAP only.
// No test performs a real purchase or a real network call.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the final app source before writing.
//
// Phase 1 reconciliation (12 Nov 2026): the catalogue moved from
// PaymentConfig (frozen, stale Situations count of 500) to
// ProductCatalogue. Every catalogue assertion below now reads
// ProductCatalogue. The ba-practice bundle name is "AI Product Owner
// and Product Manager for Payments" in both the catalogue and the
// frozen PaymentConfig; the old test name "BA and PO Professional
// Practice" matched neither and is corrected here. The Situations
// count is 564. ProductCatalogue.productContaining takes a labelled
// chapterID argument, unlike the old positional PaymentConfig call.
// The old PaymentConfig price assertions (priceAmountINR, priceText
// "Rs. 4,999") are removed: a hardcoded price must never be presented
// as a purchase price, and StoreManager.priceText now returns
// "Price unavailable" until a StoreKit product loads (see
// EntitlementTests for the price fallback tests).

import XCTest
@testable import PaymentForge

@MainActor
final class StoreManagerTests: XCTestCase {

    // The StoreManager UserDefaults cache keys, as string literals.
    // The keys are private in StoreManager, so tests cannot reference
    // them by symbol; these literals mirror them exactly and must be
    // kept in step. Cleaning them before each test is what makes a
    // fresh StoreManager deterministic in DEBUG, where init restores
    // the cached sets. In Release init starts locked and purges the
    // bypass key itself.
    private let cacheKeys = [
        "pf.iap.purchasedProductIDs.v1",
        "pf.iap.buildPhaseUnlocked.v1",
        "pf.iap.situationsPurchased.v1"
    ]

    override func setUp() {
        super.setUp()
        for key in cacheKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in cacheKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    func testFreshStoreIsLocked() {
        let store = StoreManager()
        XCTAssertFalse(store.isPurchased)
        XCTAssertFalse(store.isServerEntitlementVerified)
        XCTAssertFalse(store.isSituationsUnlocked)
        XCTAssertTrue(store.purchasedProductIDs.isEmpty)
        XCTAssertTrue(store.serverEntitledProductIDs.isEmpty)
    }

    // MARK: - Twelve products (11 Nov 2026, catalogue moved 12 Nov 2026)

    func testTwelveProductsWithCorrectIDsNamesAndPrices() {
        XCTAssertEqual(ProductCatalogue.products.count, 12)
        let expected: [(String, String, Int)] = [
            ("com.paymentforge.app.full", "The Integrated Course", 9999),
            ("com.paymentforge.app.foundations", "Payment Foundations", 1499),
            ("com.paymentforge.app.messaging", "ISO 20022 and SWIFT Messaging", 2999),
            ("com.paymentforge.app.rails", "Global Payment Rails", 2499),
            ("com.paymentforge.app.crossborder", "Cross-Border and Correspondent Banking", 1999),
            ("com.paymentforge.app.clearing", "Clearing, Settlement and Liquidity", 999),
            ("com.paymentforge.app.cards", "Cards and Domestic Payments", 1499),
            ("com.paymentforge.app.compliance-ops", "Compliance, Risk, Operations and Reconciliation", 1999),
            ("com.paymentforge.app.architecture-apis", "Payment Architecture and APIs", 2499),
            ("com.paymentforge.app.ba-practice", "AI Product Owner and Product Manager for Payments", 1999),
            ("com.paymentforge.app.emerging", "Emerging Technologies and the Future", 999),
            ("com.paymentforge.app.situations", "Payment Situations", 4999),
        ]
        for (id, name, price) in expected {
            let product = ProductCatalogue.product(for: id)
            XCTAssertNotNil(product, "Missing product \(id)")
            XCTAssertEqual(product?.name, name)
            XCTAssertEqual(product?.priceINR, price)
        }
        XCTAssertEqual(Set(ProductCatalogue.allProductIDs).count, 12, "Product IDs must be unique.")
        XCTAssertEqual(ProductCatalogue.allProductIDs.count, 12)
    }

    func testFullCourseCoversAll100Chapters() {
        let full = ProductCatalogue.product(for: ProductCatalogue.fullCourseProductID)
        XCTAssertEqual(full?.chapterIDs.count, 100)
        for number in 1...100 {
            XCTAssertTrue(full?.chapterIDs.contains("ch\(number)") ?? false, "The full course is missing ch\(number).")
        }
    }

    func testChapterBundleMappingMatchesBundlesJSON() {
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch1")?.id, "foundations")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch5")?.id, "messaging")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch9")?.id, "rails")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch13")?.id, "crossborder")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch17")?.id, "clearing")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch21")?.id, "cards")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch23")?.id, "compliance-ops")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch25")?.id, "architecture-apis")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch28")?.id, "ba-practice")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch27")?.id, "emerging")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch64")?.id, "foundations")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch95")?.id, "compliance-ops")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch96")?.id, "ba-practice")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch100")?.id, "ba-practice")
        XCTAssertNil(ProductCatalogue.productContaining(chapterID: "ch999"), "An unknown chapter maps to no bundle.")
        // The 10 chapter bundles together cover all 100 chapters.
        // The full course is excluded (it contains every chapter by
        // definition) and Situations contributes no chapters.
        let covered = Set(ProductCatalogue.products
            .filter { $0.productID != ProductCatalogue.fullCourseProductID && $0.productID != ProductCatalogue.situationsProductID }
            .flatMap { $0.chapterIDs })
        XCTAssertEqual(covered.count, 100)
        for number in 1...100 {
            XCTAssertTrue(covered.contains("ch\(number)"), "No bundle contains ch\(number).")
        }
    }

    func testSituationsProductUnchanged() {
        XCTAssertEqual(ProductCatalogue.situationsProductID, "com.paymentforge.app.situations")
        let situations = ProductCatalogue.product(for: ProductCatalogue.situationsProductID)
        XCTAssertEqual(situations?.situationCount, 564)
        XCTAssertTrue(situations?.chapterIDs.isEmpty ?? false)
        // The bundles.json id "situations-500" resolves to the same product.
        XCTAssertEqual(ProductCatalogue.product(forBundleID: "situations-500")?.productID, ProductCatalogue.situationsProductID)
    }

    func testFreshStoreLocksAllChaptersAndSituations() {
        let store = StoreManager()
        XCTAssertFalse(store.isChapterUnlocked("ch1"))
        XCTAssertFalse(store.isChapterUnlocked("ch5"))
        XCTAssertFalse(store.isChapterUnlocked("ch95"))
        XCTAssertFalse(store.isSituationsUnlocked)
        XCTAssertFalse(store.isProductUnlocked(ProductCatalogue.fullCourseProductID))
        XCTAssertFalse(store.isProductUnlocked(ProductCatalogue.situationsProductID))
        for productID in ProductCatalogue.allProductIDs {
            XCTAssertFalse(store.isProductOwned(productID), "Fresh store must not own \(productID).")
            XCTAssertFalse(store.isProductUnlocked(productID), "Fresh store must not unlock \(productID).")
        }
        XCTAssertEqual(store.unlockedProductCount, 0)
        // A chapter no bundle contains stays locked (fail closed).
        XCTAssertFalse(store.isChapterUnlocked("ch999"))
    }
}
