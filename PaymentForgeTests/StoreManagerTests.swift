// StoreManagerTests.swift
// PaymentForge iOS - Phase 7 unit tests: entitlement logic, reconciled
// for Phase 1 (Release integrity) and the v90 16-product catalogue.
// The security rule under test: nothing unlocks without a verified,
// unexpired StoreKit transaction on this device or a server
// entitlement row (user_purchases). A fresh store is locked: no
// chapters (except the held-out ch37, which is never sold), no
// standalone products, no parts. Purchases are IAP only.
// No test performs a real purchase or a real network call.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the final app source before writing.
//
// v90 reconciliation (15 Nov 2026): the catalogue is the decided
// 16-product lineup in ProductCatalogue (10 book parts, BA/PO
// Studio, Payment Simulator, Investigation Lab, Practice
// Experiences, Interview Ready, The Integrated Course), each with
// 1 year of access and a renewal subscription at half the sale
// price. The old 12-product division is shelved: no old product ID
// appears below. Every catalogue assertion reads ProductCatalogue.
// The old PaymentConfig price assertions (priceAmountINR, priceText
// "Rs. 4,999") are removed: a hardcoded price must never be presented
// as a purchase price, and StoreManager.priceText(for:) returns
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
    // bypass and legacy keys itself.
    private let cacheKeys = [
        "pf.iap.purchasedProductIDs.v1",
        "pf.iap.entitlementExpiries.v1",
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
        XCTAssertFalse(store.isPracticeUnlocked)
        XCTAssertFalse(store.isStudioUnlocked)
        XCTAssertFalse(store.isSimulatorUnlocked)
        XCTAssertFalse(store.isInvestigationLabUnlocked)
        XCTAssertFalse(store.isInterviewUnlocked)
        XCTAssertTrue(store.purchasedProductIDs.isEmpty)
        XCTAssertTrue(store.serverEntitledProductIDs.isEmpty)
        XCTAssertTrue(store.deviceEntitlementExpiries.isEmpty)
        XCTAssertTrue(store.serverEntitlementExpiries.isEmpty)
    }

    // MARK: - Sixteen products (v90, 15 Nov 2026)

    func testSixteenProductsWithCorrectIDsNamesAndPrices() {
        XCTAssertEqual(ProductCatalogue.products.count, 16)
        let expected: [(String, String, Int, Int, Int)] = [
            ("com.paymentforge.app.integrated", "The Integrated Course", 2999, 4499, 1500),
            ("com.paymentforge.app.part-1", "Part 1: Foundations of Money and Payments", 399, 599, 200),
            ("com.paymentforge.app.part-2", "Part 2: How Payments Move: Rails, Schemes and Systems", 399, 599, 200),
            ("com.paymentforge.app.part-3", "Part 3: Messages: SWIFT MT, ISO 20022 and Standards", 399, 599, 200),
            ("com.paymentforge.app.part-4", "Part 4: Cross-Border Payments and Correspondent Banking", 399, 599, 200),
            ("com.paymentforge.app.part-5", "Part 5: Clearing, Settlement, Liquidity and Reconciliation", 399, 599, 200),
            ("com.paymentforge.app.part-6", "Part 6: Exceptions, Investigations, Returns and Claims", 399, 599, 200),
            ("com.paymentforge.app.part-7", "Part 7: Cards and Customer Payments", 399, 599, 200),
            ("com.paymentforge.app.part-8", "Part 8: Architecture, APIs, Hubs and Engineering", 399, 599, 200),
            ("com.paymentforge.app.part-9", "Part 9: The Business Analyst at Work", 399, 599, 200),
            ("com.paymentforge.app.part-10", "Part 10: Emerging Payments and the Future", 399, 599, 200),
            ("com.paymentforge.app.studio", "BA/PO Studio", 799, 1199, 400),
            ("com.paymentforge.app.simulator", "Payment Simulator", 499, 749, 250),
            ("com.paymentforge.app.investigation-lab", "Investigation Lab", 499, 749, 250),
            ("com.paymentforge.app.practice", "Practice Experiences", 999, 1499, 500),
            ("com.paymentforge.app.interview", "Interview Ready", 1599, 2399, 800),
        ]
        for (id, name, sale, list, renewal) in expected {
            let product = ProductCatalogue.product(for: id)
            XCTAssertNotNil(product, "Missing product \(id)")
            XCTAssertEqual(product?.name, name)
            XCTAssertEqual(product?.priceINR, sale, "Sale price for \(id).")
            XCTAssertEqual(product?.listPriceINR, list, "List price for \(id).")
            XCTAssertEqual(product?.renewalPriceINR, renewal, "Renewal price for \(id).")
            XCTAssertEqual(product?.validityDays, 365, "Every product gives 1 year of access.")
        }
        XCTAssertEqual(Set(ProductCatalogue.allProductIDs).count, 16, "Product IDs must be unique.")
        XCTAssertEqual(ProductCatalogue.allProductIDs.count, 16)
        XCTAssertEqual(ProductCatalogue.allStoreProductIDs.count, 32, "16 purchases plus 16 renewals.")
    }

    func testIntegratedCoversAll99InBookChapters() {
        let integrated = ProductCatalogue.product(for: ProductCatalogue.integratedProductID)
        XCTAssertEqual(integrated?.chapterIDs.count, 99)
        for number in 1...100 {
            if number == 37 {
                XCTAssertFalse(integrated?.chapterIDs.contains("ch37") ?? true, "The Integrated Course must not contain the held-out ch37.")
            } else {
                XCTAssertTrue(integrated?.chapterIDs.contains("ch\(number)") ?? false, "The Integrated Course is missing ch\(number).")
            }
        }
    }

    func testChapterPartMappingMatchesProposalSection3() {
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch1")?.id, "part-1")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch5")?.id, "part-3")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch9")?.id, "part-2")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch13")?.id, "part-4")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch17")?.id, "part-5")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch21")?.id, "part-5")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch23")?.id, "part-6")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch25")?.id, "part-8")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch28")?.id, "part-9")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch27")?.id, "part-10")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch64")?.id, "part-1")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch95")?.id, "part-6")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch96")?.id, "part-9")
        XCTAssertEqual(ProductCatalogue.productContaining(chapterID: "ch100")?.id, "part-9")
        XCTAssertNil(ProductCatalogue.productContaining(chapterID: "ch37"), "The held-out ch37 maps to no part.")
        XCTAssertNil(ProductCatalogue.productContaining(chapterID: "ch999"), "An unknown chapter maps to no part.")
        // The 10 parts together cover the 99 in-book chapters.
        // The Integrated Course is excluded (it contains every
        // chapter by definition) and the standalone products
        // contribute no chapters.
        let covered = Set(ProductCatalogue.products
            .filter { $0.productID != ProductCatalogue.integratedProductID }
            .flatMap { $0.chapterIDs })
        XCTAssertEqual(covered.count, 99)
        for number in 1...100 where number != 37 {
            XCTAssertTrue(covered.contains("ch\(number)"), "No part contains ch\(number).")
        }
        XCTAssertFalse(covered.contains("ch37"))
    }

    func testPracticeProductScope() {
        XCTAssertEqual(ProductCatalogue.practiceProductID, "com.paymentforge.app.practice")
        let practice = ProductCatalogue.product(for: ProductCatalogue.practiceProductID)
        XCTAssertEqual(practice?.situationCount, 564)
        XCTAssertTrue(practice?.chapterIDs.isEmpty ?? false)
        XCTAssertFalse(practice?.contentsSummary.isEmpty ?? true)
        // The abolished bundles.json id resolves to nothing: there
        // are no legacy aliases.
        XCTAssertNil(ProductCatalogue.product(forBundleID: "situations-500"))
    }

    func testFreshStoreLocksAllChaptersAndProductsExceptHeldOut() {
        let store = StoreManager()
        XCTAssertFalse(store.isChapterUnlocked("ch1"))
        XCTAssertFalse(store.isChapterUnlocked("ch5"))
        XCTAssertFalse(store.isChapterUnlocked("ch95"))
        XCTAssertTrue(store.isChapterUnlocked("ch37"), "The held-out ch37 is reachable without purchase.")
        XCTAssertFalse(store.isPracticeUnlocked)
        XCTAssertFalse(store.isProductUnlocked(ProductCatalogue.integratedProductID))
        XCTAssertFalse(store.isProductUnlocked(ProductCatalogue.practiceProductID))
        for productID in ProductCatalogue.allProductIDs {
            XCTAssertFalse(store.isProductOwned(productID), "Fresh store must not own \(productID).")
            XCTAssertFalse(store.isProductUnlocked(productID), "Fresh store must not unlock \(productID).")
        }
        for renewalID in ProductCatalogue.allRenewalProductIDs {
            XCTAssertFalse(store.isProductOwned(renewalID), "Fresh store must not own \(renewalID).")
        }
        XCTAssertEqual(store.unlockedProductCount, 0)
        // A chapter no part contains stays locked (fail closed).
        XCTAssertFalse(store.isChapterUnlocked("ch999"))
    }
}
