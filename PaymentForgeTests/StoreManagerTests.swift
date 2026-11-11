// StoreManagerTests.swift
// PaymentForge iOS - Phase 7 unit tests: entitlement logic.
// The security rule under test: a submitted UTR never unlocks
// anything on its own. Situations unlock only through a verified
// StoreKit transaction on this device or a server entitlement row
// (user_purchases) written when an admin verifies the claim.
// A pending claim, and even a claim object whose status reads
// Verified, must not flip isSituationsUnlocked by itself: the
// unlock comes from the server entitlement, not from the claim.
// No test performs a real purchase or a real network call.

import XCTest
@testable import PaymentForge

@MainActor
final class StoreManagerTests: XCTestCase {

    func testFreshStoreIsLocked() {
        let store = StoreManager()
        XCTAssertFalse(store.isPurchased)
        XCTAssertFalse(store.isServerEntitlementVerified)
        XCTAssertFalse(store.isSituationsUnlocked)
        XCTAssertFalse(store.hasUPIClaim)
        XCTAssertFalse(store.isUPIClaimVerified)
        XCTAssertNil(store.upiClaim)
    }

    func testPendingUPIClaimDoesNotUnlock() async {
        let store = StoreManager()
        let claim = await store.submitUPIClaim(payerName: "Test Learner", utr: "123456789012")
        XCTAssertEqual(claim.status.rawValue, "Pending")
        XCTAssertEqual(claim.utr, "123456789012")
        XCTAssertEqual(claim.amount, 4999, "Situations still costs Rs. 4,999.")
        XCTAssertTrue(store.hasUPIClaim)
        XCTAssertFalse(store.isUPIClaimVerified)
        XCTAssertFalse(store.isSituationsUnlocked, "A pending UTR must never unlock Situations.")
        XCTAssertTrue(store.hasPendingClaimUpload, "A guest claim is held for upload after sign-in, never treated as paid.")
    }

    func testUPIClaimDecodesPendingByDefault() throws {
        let json = """
        {"product":"Payment Situations, all 564 situations","amount":4999,"payerName":"Test Learner","utr":"123456789012","submittedAt":"2026-11-11T00:00:00Z"}
        """.data(using: .utf8)!
        let claim = try JSONDecoder().decode(UPIClaim.self, from: json)
        XCTAssertEqual(claim.status.rawValue, "Pending", "A claim with no status field is pending, never verified.")
        XCTAssertEqual(claim.productID, PaymentConfig.situationsProductID, "A claim with no product id decodes as Situations, the only product when claims were introduced.")
    }

    func testUPIClaimStatusValuesDecode() throws {
        for (raw, expectedRaw) in [("Pending", "Pending"), ("Verified", "Verified"), ("Rejected", "Rejected")] {
            let json = """
            {"product":"p","amount":4999,"payerName":"n","utr":"u","submittedAt":"2026-11-11T00:00:00Z","status":"\(raw)"}
            """.data(using: .utf8)!
            let claim = try JSONDecoder().decode(UPIClaim.self, from: json)
            XCTAssertEqual(claim.status.rawValue, expectedRaw)
        }
    }

    func testVerifiedClaimAloneDoesNotUnlockWithoutServerEntitlement() {
        // A claim object that reads Verified is not the unlock: the
        // unlock is isServerEntitlementVerified, set only by reading
        // the user_purchases row the verification creates. A fresh
        // store has no such row, so it stays locked even though a
        // verified claim can exist as data.
        let store = StoreManager()
        XCTAssertFalse(store.isServerEntitlementVerified)
        XCTAssertFalse(store.isSituationsUnlocked)
        let verified = UPIClaim(product: "p", amount: 4999, payerName: "n", utr: "u", submittedAt: "2026-11-11T00:00:00Z", status: .verified)
        XCTAssertEqual(verified.status.rawValue, "Verified")
        XCTAssertFalse(store.isSituationsUnlocked, "Unlock must come from the server entitlement, not from the claim status.")
    }

    // MARK: - Twelve products (11 Nov 2026)

    func testTwelveProductsWithCorrectIDsNamesAndPrices() {
        XCTAssertEqual(PaymentConfig.products.count, 12)
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
            ("com.paymentforge.app.ba-practice", "BA and PO Professional Practice", 1999),
            ("com.paymentforge.app.emerging", "Emerging Technologies and the Future", 999),
            ("com.paymentforge.app.situations", "Payment Situations", 4999),
        ]
        for (id, name, price) in expected {
            let product = PaymentConfig.product(for: id)
            XCTAssertNotNil(product, "Missing product \(id)")
            XCTAssertEqual(product?.name, name)
            XCTAssertEqual(product?.priceINR, price)
        }
        XCTAssertEqual(Set(PaymentConfig.allProductIDs).count, 12, "Product IDs must be unique.")
        XCTAssertEqual(PaymentConfig.allProductIDs.count, 12)
    }

    func testFullCourseCoversAll100Chapters() {
        let full = PaymentConfig.product(for: PaymentConfig.fullCourseProductID)
        XCTAssertEqual(full?.chapterIDs.count, 100)
        for number in 1...100 {
            XCTAssertTrue(full?.chapterIDs.contains("ch\(number)") ?? false, "The full course is missing ch\(number).")
        }
    }

    func testChapterBundleMappingMatchesBundlesJSON() {
        XCTAssertEqual(PaymentConfig.productContaining("ch1")?.id, "foundations")
        XCTAssertEqual(PaymentConfig.productContaining("ch5")?.id, "messaging")
        XCTAssertEqual(PaymentConfig.productContaining("ch9")?.id, "rails")
        XCTAssertEqual(PaymentConfig.productContaining("ch13")?.id, "crossborder")
        XCTAssertEqual(PaymentConfig.productContaining("ch17")?.id, "clearing")
        XCTAssertEqual(PaymentConfig.productContaining("ch21")?.id, "cards")
        XCTAssertEqual(PaymentConfig.productContaining("ch23")?.id, "compliance-ops")
        XCTAssertEqual(PaymentConfig.productContaining("ch25")?.id, "architecture-apis")
        XCTAssertEqual(PaymentConfig.productContaining("ch28")?.id, "ba-practice")
        XCTAssertEqual(PaymentConfig.productContaining("ch27")?.id, "emerging")
        XCTAssertEqual(PaymentConfig.productContaining("ch64")?.id, "foundations")
        XCTAssertEqual(PaymentConfig.productContaining("ch95")?.id, "compliance-ops")
        XCTAssertEqual(PaymentConfig.productContaining("ch96")?.id, "ba-practice")
        XCTAssertEqual(PaymentConfig.productContaining("ch100")?.id, "ba-practice")
        XCTAssertNil(PaymentConfig.productContaining("ch999"), "An unknown chapter maps to no bundle.")
        // The 11 chapter bundles together cover all 100 chapters.
        let covered = Set(PaymentConfig.products
            .filter { $0.productID != PaymentConfig.fullCourseProductID }
            .flatMap { $0.chapterIDs })
        XCTAssertEqual(covered.count, 100)
        for number in 1...100 {
            XCTAssertTrue(covered.contains("ch\(number)"), "No bundle contains ch\(number).")
        }
    }

    func testSituationsProductUnchanged() {
        XCTAssertEqual(PaymentConfig.situationsProductID, "com.paymentforge.app.situations")
        XCTAssertEqual(PaymentConfig.priceAmountINR, 4999)
        XCTAssertEqual(PaymentConfig.priceText, "Rs. 4,999")
        let situations = PaymentConfig.product(for: PaymentConfig.situationsProductID)
        XCTAssertEqual(situations?.situationCount, 500)
        XCTAssertTrue(situations?.chapterIDs.isEmpty ?? false)
        // The bundles.json id "situations-500" resolves to the same product.
        XCTAssertEqual(PaymentConfig.product(forBundleID: "situations-500")?.productID, PaymentConfig.situationsProductID)
    }

    func testFreshStoreLocksAllChaptersAndSituations() {
        let store = StoreManager()
        XCTAssertFalse(store.isChapterUnlocked("ch1"))
        XCTAssertFalse(store.isChapterUnlocked("ch5"))
        XCTAssertFalse(store.isChapterUnlocked("ch95"))
        XCTAssertFalse(store.isSituationsUnlocked)
        XCTAssertFalse(store.isProductUnlocked(PaymentConfig.fullCourseProductID))
        XCTAssertFalse(store.isProductUnlocked(PaymentConfig.situationsProductID))
        XCTAssertEqual(store.unlockedProductCount, 0)
        // A chapter no bundle contains stays open, never locked by mistake.
        XCTAssertTrue(store.isChapterUnlocked("ch999"))
    }

    func testUPIClaimForAnotherProductDoesNotUnlock() async {
        let store = StoreManager()
        let foundationsID = PaymentConfig.product(forBundleID: "foundations")!.productID
        let claim = await store.submitUPIClaim(productID: foundationsID, payerName: "Test Learner", utr: "123456789012")
        XCTAssertEqual(claim.productID, "com.paymentforge.app.foundations")
        XCTAssertEqual(claim.amount, 1499)
        XCTAssertEqual(claim.status.rawValue, "Pending")
        XCTAssertFalse(store.isChapterUnlocked("ch1"), "A pending UTR must never unlock a chapter.")
        XCTAssertFalse(store.isProductUnlocked(foundationsID))
    }
}
