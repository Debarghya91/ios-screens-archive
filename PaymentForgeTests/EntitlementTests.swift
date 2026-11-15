// EntitlementTests.swift
// PaymentForge iOS - Phase 1 (Release integrity) tests: the single
// entitlement model in ProductCatalogue and StoreManager.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the final app source before writing.
//
// What these tests prove, and what they cannot prove:
// - The catalogue shape (16 products, exact IDs, 32 store IDs,
//   chapter coverage with no overlaps or gaps, lesson counts,
//   prices, validity, free samples) is asserted directly.
// - The unlock RULE logic (the Integrated Course unlocks every
//   product; one part unlocks only its own chapters; a renewal
//   subscription unlocks its product; expired entitlements lock
//   again) is asserted in DEBUG only, by seeding the DEBUG-only
//   UserDefaults cache that StoreManager init restores. That
//   proves the rule in isProductUnlocked and isChapterUnlocked.
//   It does NOT prove the Release verified-transaction path:
//   purchasedProductIDs and serverEntitledProductIDs have no test
//   seam (the old test-purchase API was removed in Phase 1), so a
//   real purchase, restore, or server entitlement can only be
//   verified with the local .storekit file, a StoreKit sandbox
//   account, or live Supabase. Those are manual test items; see
//   the Phase 1 test report.
// - In Release builds the seeding tests assert the locked outcome
//   instead: polluted stored state must unlock nothing.
// - The fail-closed chapter rule (an unmapped chapter is locked)
//   is asserted here. The held-out ch37 is the one exception: it
//   is in no product and never sold, so it is reachable without
//   purchase. The pending-revoke retry and the server-verified
//   entitlement cache live behind the same no-seam server paths
//   and are manual test items, like the record and revoke calls.

import XCTest
@testable import PaymentForge

@MainActor
final class EntitlementTests: XCTestCase {

    private let purchasedCacheKey = "pf.iap.purchasedProductIDs.v1"
    private let entitlementExpiriesKey = "pf.iap.entitlementExpiries.v1"
    private let bypassKey = "pf.iap.buildPhaseUnlocked.v1"
    private let legacySituationsKey = "pf.iap.situationsPurchased.v1"

    private var cacheKeys: [String] {
        [purchasedCacheKey, entitlementExpiriesKey, bypassKey, legacySituationsKey]
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
    /// with optional expiry timestamps, then return a fresh store.
    /// In Release the seed is ignored by design and the store
    /// starts locked. IDs seeded without an expiry stay active,
    /// matching how tests seed ownership.
    private func storeOwning(_ productIDs: [String], expiries: [String: Date] = [:]) -> StoreManager {
        UserDefaults.standard.set(productIDs, forKey: purchasedCacheKey)
        if !expiries.isEmpty {
            let timestamps = expiries.mapValues { $0.timeIntervalSince1970 }
            if let data = try? JSONEncoder().encode(timestamps) {
                UserDefaults.standard.set(data, forKey: entitlementExpiriesKey)
            }
        }
        return StoreManager()
    }

    // MARK: - Catalogue shape

    func testCatalogueHasSixteenProductsWithExactIDs() {
        XCTAssertEqual(ProductCatalogue.products.count, 16)
        XCTAssertEqual(ProductCatalogue.allProductIDs, [
            "com.paymentforge.app.integrated",
            "com.paymentforge.app.part-1",
            "com.paymentforge.app.part-2",
            "com.paymentforge.app.part-3",
            "com.paymentforge.app.part-4",
            "com.paymentforge.app.part-5",
            "com.paymentforge.app.part-6",
            "com.paymentforge.app.part-7",
            "com.paymentforge.app.part-8",
            "com.paymentforge.app.part-9",
            "com.paymentforge.app.part-10",
            "com.paymentforge.app.studio",
            "com.paymentforge.app.simulator",
            "com.paymentforge.app.investigation-lab",
            "com.paymentforge.app.practice",
            "com.paymentforge.app.interview"
        ])
        XCTAssertEqual(Set(ProductCatalogue.allProductIDs).count, 16, "Product IDs must be unique.")
        XCTAssertEqual(ProductCatalogue.integratedProductID, "com.paymentforge.app.integrated")
        XCTAssertEqual(ProductCatalogue.fullCourseProductID, "com.paymentforge.app.integrated")
        XCTAssertEqual(ProductCatalogue.practiceProductID, "com.paymentforge.app.practice")
        XCTAssertEqual(ProductCatalogue.studioProductID, "com.paymentforge.app.studio")
        XCTAssertEqual(ProductCatalogue.simulatorProductID, "com.paymentforge.app.simulator")
        XCTAssertEqual(ProductCatalogue.investigationLabProductID, "com.paymentforge.app.investigation-lab")
        XCTAssertEqual(ProductCatalogue.interviewProductID, "com.paymentforge.app.interview")
        XCTAssertEqual(StoreManager.fullCourseProductID, ProductCatalogue.fullCourseProductID)
        XCTAssertEqual(StoreManager.integratedProductID, ProductCatalogue.integratedProductID)
        XCTAssertEqual(StoreManager.practiceProductID, ProductCatalogue.practiceProductID)
        XCTAssertEqual(StoreManager.studioProductID, ProductCatalogue.studioProductID)
        XCTAssertEqual(StoreManager.simulatorProductID, ProductCatalogue.simulatorProductID)
        XCTAssertEqual(StoreManager.investigationLabProductID, ProductCatalogue.investigationLabProductID)
        XCTAssertEqual(StoreManager.interviewProductID, ProductCatalogue.interviewProductID)
        XCTAssertEqual(StoreManager.allProductIDs, ProductCatalogue.allProductIDs)
        XCTAssertEqual(StoreManager.allRenewalProductIDs, ProductCatalogue.allRenewalProductIDs)
        XCTAssertEqual(StoreManager.allStoreProductIDs, ProductCatalogue.allStoreProductIDs)
    }

    func testRenewalAndStoreIDsAreThirtyTwo() {
        XCTAssertEqual(ProductCatalogue.allRenewalProductIDs.count, 16)
        XCTAssertEqual(ProductCatalogue.allStoreProductIDs.count, 32)
        for productID in ProductCatalogue.allProductIDs {
            let renewalID = ProductCatalogue.renewalProductID(for: productID)
            XCTAssertEqual(renewalID, productID + ".renewal")
            XCTAssertTrue(ProductCatalogue.allRenewalProductIDs.contains(renewalID))
            XCTAssertTrue(ProductCatalogue.isRenewalProductID(renewalID))
            XCTAssertFalse(ProductCatalogue.isRenewalProductID(productID))
        }
        XCTAssertEqual(Set(ProductCatalogue.allStoreProductIDs).count, 32, "Store IDs must be unique.")
    }

    func testRenewalIDResolution() {
        for product in ProductCatalogue.products {
            XCTAssertEqual(product.renewalProductID, product.productID + ".renewal")
            XCTAssertNil(ProductCatalogue.product(for: product.renewalProductID), "Renewal IDs do not resolve through product(for:).")
            XCTAssertEqual(ProductCatalogue.productForStoreID(product.renewalProductID)?.productID, product.productID)
            XCTAssertEqual(ProductCatalogue.productForStoreID(product.productID)?.productID, product.productID)
            XCTAssertEqual(ProductCatalogue.baseProductID(forStoreID: product.renewalProductID), product.productID)
            XCTAssertEqual(ProductCatalogue.baseProductID(forStoreID: product.productID), product.productID)
        }
        XCTAssertNil(ProductCatalogue.productForStoreID("com.paymentforge.app.no-such-product"))
        XCTAssertNil(ProductCatalogue.productForStoreID("com.paymentforge.app.no-such-product.renewal"))
        XCTAssertNil(ProductCatalogue.baseProductID(forStoreID: "com.paymentforge.app.no-such-product"))
    }

    func testCatalogueLookupsResolveEveryProductID() {
        let catalogueIDs = [
            "integrated",
            "part-1", "part-2", "part-3", "part-4", "part-5",
            "part-6", "part-7", "part-8", "part-9", "part-10",
            "studio", "simulator", "investigation-lab", "practice", "interview"
        ]
        for catalogueID in catalogueIDs {
            XCTAssertNotNil(ProductCatalogue.product(forBundleID: catalogueID), "Catalogue id \(catalogueID) must resolve.")
        }
        XCTAssertNil(ProductCatalogue.product(forBundleID: "no-such-product"))
        XCTAssertNil(ProductCatalogue.product(for: "com.paymentforge.app.no-such-product"))
        XCTAssertNil(ProductCatalogue.product(for: ""))
    }

    func testNoLegacyAliasesResolve() {
        // The abolished 12-product division must never silently
        // map to a product through a legacy alias.
        for legacyID in ["situations-500", "situations", "full", "foundations", "messaging", "rails", "crossborder", "clearing", "cards", "compliance-ops", "architecture-apis", "ba-practice", "emerging"] {
            XCTAssertNil(ProductCatalogue.product(forBundleID: legacyID), "Legacy id \(legacyID) must resolve to nothing.")
        }
        for legacyProductID in ["com.paymentforge.app.full", "com.paymentforge.app.situations", "com.paymentforge.app.foundations", "com.paymentforge.app.messaging", "com.paymentforge.app.rails", "com.paymentforge.app.ba-practice", "com.paymentforge.app.emerging"] {
            XCTAssertNil(ProductCatalogue.product(for: legacyProductID), "Legacy product ID \(legacyProductID) must resolve to nothing.")
        }
    }

    func testChapterCoverageIsExactlyNinetyNineChaptersWithNoOverlaps() {
        let parts = ProductCatalogue.partProducts
        XCTAssertEqual(parts.count, 10, "There are 10 book parts.")
        let allChapters = parts.flatMap { $0.chapterIDs }
        XCTAssertEqual(allChapters.count, 99, "Part chapter lists must total 99: no overlaps.")
        XCTAssertEqual(Set(allChapters).count, 99, "No chapter may appear in two parts.")
        let expected = Set((1...100).map { "ch\($0)" }).subtracting(["ch37"])
        XCTAssertEqual(Set(allChapters), expected, "Parts must cover exactly ch1 to ch100 except the held-out ch37: no gaps.")
        XCTAssertFalse(allChapters.contains("ch37"), "ch37 is in no product and must never be sold.")
        XCTAssertEqual(ProductCatalogue.product(for: ProductCatalogue.integratedProductID)?.chapterIDs.count, 99)
        XCTAssertEqual(Set(ProductCatalogue.product(for: ProductCatalogue.integratedProductID)?.chapterIDs ?? []), expected)
        for standaloneID in ["studio", "simulator", "investigation-lab", "practice", "interview"] {
            XCTAssertEqual(ProductCatalogue.product(forBundleID: standaloneID)?.chapterIDs.count, 0, "\(standaloneID) has no chapters.")
        }
    }

    func testPerPartChapterCounts() {
        let expected: [String: Int] = [
            "part-1": 7,
            "part-2": 14,
            "part-3": 14,
            "part-4": 8,
            "part-5": 13,
            "part-6": 11,
            "part-7": 5,
            "part-8": 14,
            "part-9": 10,
            "part-10": 3
        ]
        for (partID, count) in expected {
            XCTAssertEqual(
                ProductCatalogue.product(forBundleID: partID)?.chapterIDs.count,
                count,
                "Part \(partID) must contain \(count) chapters."
            )
        }
    }

    func testPerPartLessonCountsSumTo874() {
        let expected: [String: Int] = [
            "part-1": 49,
            "part-2": 137,
            "part-3": 149,
            "part-4": 71,
            "part-5": 110,
            "part-6": 98,
            "part-7": 37,
            "part-8": 118,
            "part-9": 79,
            "part-10": 26
        ]
        var total = 0
        for (partID, count) in expected {
            XCTAssertEqual(
                ProductCatalogue.product(forBundleID: partID)?.lessonCount,
                count,
                "Part \(partID) must contain \(count) lessons."
            )
            total += count
        }
        XCTAssertEqual(total, 874)
        XCTAssertEqual(ProductCatalogue.product(for: ProductCatalogue.integratedProductID)?.lessonCount, 874)
        XCTAssertEqual(ContentManifest.lessonCount, 881, "881 total lessons: 874 in parts plus 7 held-out ch37 lessons.")
    }

    func testLessonCountsMatchReadingOrderMapWhenLoaded() {
        // Conditional: the hardcoded fallback carries chapters but
        // no lesson lists, so orderedLessons is empty there and
        // only the metadata checks above apply. When the bundled
        // map loads, its lesson lists must agree with the catalogue
        // metadata exactly.
        let ordered = PFBookModeReadingOrder.orderedLessons
        guard !ordered.isEmpty else { return }
        XCTAssertEqual(ordered.count, 874, "The map must list 874 in-book lessons.")
        for part in ProductCatalogue.partProducts {
            guard let partNumber = Int(part.id.dropFirst("part-".count)) else {
                XCTFail("Part id \(part.id) must parse to a number.")
                continue
            }
            let count = ordered.filter { lessonID in
                guard let number = PFChapterHelper.chapterNumber(from: lessonID) else { return false }
                return PFBookModeReadingOrder.part(forInternalNumber: number)?.number == partNumber
            }.count
            XCTAssertEqual(count, part.lessonCount, "Map lessons for \(part.id) must match its catalogue lesson count.")
        }
    }

    func testChapterMembershipMatchesReadingOrderMapWhenLoaded() {
        let ordered = PFBookModeReadingOrder.orderedLessons
        guard !ordered.isEmpty else { return }
        for number in 1...100 {
            let chapterID = "ch\(number)"
            let mapPart = PFBookModeReadingOrder.part(forInternalNumber: number)
            let cataloguePart = ProductCatalogue.productContaining(chapterID: chapterID)
            if chapterID == "ch37" {
                XCTAssertNil(mapPart, "ch37 is held out of the map parts.")
                XCTAssertNil(cataloguePart, "ch37 is in no catalogue part.")
            } else {
                XCTAssertEqual(cataloguePart?.id, "part-\(mapPart?.number ?? -1)", "\(chapterID) must sit in the same part in the catalogue as in the map.")
            }
        }
    }

    func testProductContainingNeverReturnsIntegrated() {
        for number in 1...100 {
            let chapterID = "ch\(number)"
            let part = ProductCatalogue.productContaining(chapterID: chapterID)
            if chapterID == "ch37" {
                XCTAssertNil(part, "ch37 belongs to no part.")
            } else {
                XCTAssertNotNil(part, "\(chapterID) must belong to a part.")
                XCTAssertNotEqual(part?.productID, ProductCatalogue.integratedProductID)
            }
        }
        XCTAssertNil(ProductCatalogue.productContaining(chapterID: "ch0"))
        XCTAssertNil(ProductCatalogue.productContaining(chapterID: "ch101"))
        XCTAssertNil(ProductCatalogue.productContaining(chapterID: ""))
    }

    func testEveryManifestChapterBelongsToAProductExceptHeldOut() {
        // M1: the manifest defines the chapters; every in-book one
        // must map to exactly one part. If a future catalogue edit
        // drops a mapping, this test fails loudly instead of the
        // chapter silently going free (chapters fail closed when
        // unmapped). ch37 is the deliberate exception: held out,
        // never sold, reachable without purchase.
        XCTAssertEqual(ContentManifest.chapterCount, 100)
        var mapped: [String] = []
        for number in 1...ContentManifest.chapterCount {
            let chapterID = "ch\(number)"
            let part = ProductCatalogue.productContaining(chapterID: chapterID)
            if chapterID == "ch37" {
                XCTAssertNil(part, "ch37 must belong to no product.")
                continue
            }
            XCTAssertNotNil(part, "Manifest chapter \(chapterID) must belong to a product.")
            XCTAssertNotEqual(part?.productID, ProductCatalogue.integratedProductID)
            if let part {
                mapped.append(chapterID)
                XCTAssertTrue(part.chapterIDs.contains(chapterID))
            }
        }
        XCTAssertEqual(mapped.count, 99)
        XCTAssertEqual(Set(mapped), Set((1...ContentManifest.chapterCount).map { "ch\($0)" }).subtracting(["ch37"]))
        XCTAssertTrue(ProductCatalogue.isHeldOutChapter("ch37"))
        XCTAssertEqual(ProductCatalogue.heldOutChapterIDs, ["ch37"])
        XCTAssertFalse(ProductCatalogue.isHeldOutChapter("ch1"))
    }

    func testHeldOutChapterIsReachableWithoutPurchase() {
        let fresh = StoreManager()
        XCTAssertTrue(fresh.isChapterUnlocked("ch37"), "ch37 is never sold, so it is never locked behind a product.")
        XCTAssertNil(fresh.unlockingProduct(for: "ch37"), "ch37 is already reachable, so it has no unlocking product.")
    }

    func testUnmappedChapterIsLockedFailClosed() {
        // M1: a chapter no part contains is locked, never free.
        let fresh = StoreManager()
        for chapterID in ["ch0", "ch101", "ch999", ""] {
            XCTAssertFalse(fresh.isChapterUnlocked(chapterID), "An unmapped chapter must be locked, not free: \(chapterID).")
        }
        XCTAssertNil(fresh.unlockingProduct(for: "ch999"), "A chapter in no part has no unlocking product.")
        let partStore = storeOwning(["com.paymentforge.app.part-1"])
#if DEBUG
        XCTAssertFalse(partStore.isChapterUnlocked("ch999"), "Owning a part must not open an unmapped chapter.")
        // The Integrated Course is checked before the part mapping,
        // so an Integrated owner passes every chapter check.
        // Unmapped IDs have no content behind them, so this opens
        // nothing real.
        let fullStore = storeOwning([ProductCatalogue.integratedProductID])
        XCTAssertTrue(fullStore.isChapterUnlocked("ch999"))
#else
        XCTAssertFalse(partStore.isChapterUnlocked("ch999"), "Release must not unlock an unmapped chapter from stored state alone.")
#endif
    }

    func testFreeSampleSituationIDsAreExactlyTheTwo() {
        XCTAssertEqual(ProductCatalogue.freeSampleSituationIDs, ["ABH-01", "JEB-C01"])
        XCTAssertEqual(Set(ProductCatalogue.freeSampleSituationIDs).count, 2, "Free sample IDs must be unique.")
        // The catalogue list must stay in step with the runtime gate.
        XCTAssertEqual(ProductCatalogue.freeSampleSituationIDs, ContentService.freeSampleIDs)
    }

    func testPricesValidityAndRenewals() {
        let expected: [String: (sale: Int, list: Int, renewal: Int)] = [
            "part-1": (399, 599, 200),
            "part-2": (399, 599, 200),
            "part-3": (399, 599, 200),
            "part-4": (399, 599, 200),
            "part-5": (399, 599, 200),
            "part-6": (399, 599, 200),
            "part-7": (399, 599, 200),
            "part-8": (399, 599, 200),
            "part-9": (399, 599, 200),
            "part-10": (399, 599, 200),
            "studio": (799, 1199, 400),
            "simulator": (499, 749, 250),
            "investigation-lab": (499, 749, 250),
            "practice": (999, 1499, 500),
            "interview": (1599, 2399, 800),
            "integrated": (2999, 4499, 1500)
        ]
        for (catalogueID, prices) in expected {
            guard let product = ProductCatalogue.product(forBundleID: catalogueID) else {
                XCTFail("Product \(catalogueID) must exist.")
                continue
            }
            XCTAssertEqual(product.priceINR, prices.sale, "\(catalogueID) sale price.")
            XCTAssertEqual(product.listPriceINR, prices.list, "\(catalogueID) list price.")
            XCTAssertEqual(product.renewalPriceINR, prices.renewal, "\(catalogueID) renewal price.")
            XCTAssertEqual(product.validityDays, 365, "\(catalogueID) gives 1 year of access.")
            // List prices are at most 50 percent above the sale
            // price: the inflated list prices are dead.
            XCTAssertLessThanOrEqual(product.listPriceINR, (product.priceINR * 3 + 1) / 2, "\(catalogueID) list price must be at most 50 percent above sale.")
            XCTAssertEqual(product.priceDetailText, "\(product.priceText), 1 year of access")
        }
        // The inflated list prices are dead: every list price
        // above is pinned exactly, and each is at most 50 percent
        // above its sale price, as asserted per product.
        XCTAssertEqual(ProductCatalogue.product(forBundleID: "practice")?.situationCount, 564)
        XCTAssertFalse(ProductCatalogue.product(forBundleID: "practice")?.contentsSummary.isEmpty ?? true)
    }

    // MARK: - Validity

    func testEntitlementValidityIsOneYear() {
        XCTAssertEqual(EntitlementValidity.validityDays, 365)
        let purchase = Date(timeIntervalSince1970: 1_700_000_000)
        let expiry = EntitlementValidity.expiryDate(forPurchaseAt: purchase)
        XCTAssertEqual(expiry.timeIntervalSince(purchase), 365 * 24 * 60 * 60, accuracy: 2 * 24 * 60 * 60, "Expiry is 365 calendar days after purchase (a DST shift may move it by hours).")
        XCTAssertTrue(EntitlementValidity.isActive(expiry: nil, at: purchase), "No recorded expiry counts as active: DEBUG-seeded state only.")
        XCTAssertTrue(EntitlementValidity.isActive(expiry: expiry, at: purchase))
        XCTAssertFalse(EntitlementValidity.isActive(expiry: expiry, at: expiry), "The expiry instant itself is no longer active.")
        XCTAssertFalse(EntitlementValidity.isActive(expiry: expiry, at: expiry.addingTimeInterval(1)))
    }

    // MARK: - Free sample rules

    func testFreeSampleCounts() {
        XCTAssertEqual(FreeSampleRules.sequentialSamplesPerPart, 2)
        XCTAssertEqual(FreeSampleRules.interviewFreeQuestionCount, 5)
        XCTAssertEqual(FreeSampleRules.studioFreeLessonCount, 2)
        XCTAssertEqual(FreeSampleRules.studioFreeGuideCount, 2)
        XCTAssertEqual(FreeSampleRules.simulatorFreeRuns, 2)
        XCTAssertEqual(FreeSampleRules.faqFreeCount, 5)
        XCTAssertEqual(FreeSampleRules.labFreeCount, 2)
    }

    func testSequentialSamplesBelongToTheirParts() {
        for partNumber in 1...10 {
            let samples = FreeSampleRules.sequentialSampleLessonIDs(forPartNumber: partNumber)
            XCTAssertLessThanOrEqual(samples.count, 2)
            // Under the hardcoded fallback there are no lesson
            // lists, so every part has zero sequential samples and
            // only D77 applies. When the map loads, each part has
            // exactly 2, and each belongs to that part.
            if PFBookModeReadingOrder.orderedLessons.isEmpty {
                XCTAssertTrue(samples.isEmpty)
            } else {
                XCTAssertEqual(samples.count, 2)
            }
            for lessonID in samples {
                XCTAssertTrue(FreeSampleRules.isSequentialSampleLesson(lessonID))
                XCTAssertNotNil(FreeSampleRules.sequentialSampleIndex(forLessonID: lessonID))
                guard let number = PFChapterHelper.chapterNumber(from: lessonID) else {
                    XCTFail("Sample lesson \(lessonID) must parse to a chapter.")
                    continue
                }
                XCTAssertEqual(
                    ProductCatalogue.productContaining(chapterID: "ch\(number)")?.id,
                    "part-\(partNumber)",
                    "Sequential sample \(lessonID) must belong to part \(partNumber)."
                )
            }
        }
        XCTAssertNil(FreeSampleRules.sequentialSampleIndex(forLessonID: "no-such-lesson"))
        XCTAssertFalse(FreeSampleRules.isSequentialSampleLesson("no-such-lesson"))
    }

    // MARK: - Unlock rules

    func testUnknownProductIDsUnlockNothing() {
        let store = StoreManager()
        XCTAssertFalse(store.isProductOwned("com.paymentforge.app.no-such-product"))
        XCTAssertFalse(store.isProductUnlocked("com.paymentforge.app.no-such-product"))
        XCTAssertFalse(store.isProductOwned(""))
        XCTAssertFalse(store.isProductUnlocked(""))
        XCTAssertFalse(store.isProductOwned("com.paymentforge.app.no-such-product.renewal"))
        XCTAssertNil(store.expiryDate(for: "com.paymentforge.app.no-such-product"))
    }

    func testIntegratedUnlocksEveryProductAndChapter() {
        let store = storeOwning([ProductCatalogue.integratedProductID])
#if DEBUG
        XCTAssertTrue(store.isProductOwned(ProductCatalogue.integratedProductID))
        for productID in ProductCatalogue.allProductIDs {
            XCTAssertTrue(store.isProductUnlocked(productID), "The Integrated Course must unlock \(productID).")
        }
        XCTAssertTrue(store.isPracticeUnlocked)
        XCTAssertTrue(store.isStudioUnlocked)
        XCTAssertTrue(store.isSimulatorUnlocked)
        XCTAssertTrue(store.isInvestigationLabUnlocked)
        XCTAssertTrue(store.isInterviewUnlocked)
        for number in 1...100 {
            XCTAssertTrue(store.isChapterUnlocked("ch\(number)"), "The Integrated Course must unlock ch\(number).")
        }
        XCTAssertEqual(store.unlockedProductCount, 16, "The Integrated Course unlocks all 16 products.")
#else
        XCTAssertFalse(store.isProductUnlocked(ProductCatalogue.integratedProductID), "Release must not unlock from stored state alone.")
        XCTAssertEqual(store.unlockedProductCount, 0)
#endif
    }

    func testPracticeOwnershipAloneUnlocksNoPart() {
        let store = storeOwning([ProductCatalogue.practiceProductID])
#if DEBUG
        XCTAssertTrue(store.isProductOwned(ProductCatalogue.practiceProductID))
        XCTAssertTrue(store.isProductUnlocked(ProductCatalogue.practiceProductID))
        XCTAssertTrue(store.isPracticeUnlocked)
        XCTAssertFalse(store.isStudioUnlocked)
        XCTAssertFalse(store.isSimulatorUnlocked)
        XCTAssertFalse(store.isInvestigationLabUnlocked)
        XCTAssertFalse(store.isInterviewUnlocked)
        // Owning Practice alone unlocks no part.
        for productID in ProductCatalogue.allProductIDs where productID != ProductCatalogue.practiceProductID {
            XCTAssertFalse(store.isProductUnlocked(productID), "Practice ownership must not unlock \(productID).")
        }
        XCTAssertFalse(store.isChapterUnlocked("ch1"))
        XCTAssertEqual(store.unlockedProductCount, 1)
#else
        XCTAssertFalse(store.isPracticeUnlocked, "Release must not unlock from stored state alone.")
        XCTAssertEqual(store.unlockedProductCount, 0)
#endif
    }

    func testOnePartUnlocksOnlyItsOwnChapters() {
        let store = storeOwning(["com.paymentforge.app.part-1"])
#if DEBUG
        XCTAssertTrue(store.isProductUnlocked("com.paymentforge.app.part-1"))
        XCTAssertFalse(store.isProductUnlocked("com.paymentforge.app.part-3"))
        XCTAssertFalse(store.isPracticeUnlocked)
        XCTAssertTrue(store.isChapterUnlocked("ch1"), "ch1 is in Part 1.")
        XCTAssertTrue(store.isChapterUnlocked("ch64"), "ch64 is in Part 1.")
        XCTAssertFalse(store.isChapterUnlocked("ch5"), "ch5 is in Part 3, not Part 1.")
        XCTAssertFalse(store.isChapterUnlocked("ch95"), "ch95 is in Part 6, not Part 1.")
        XCTAssertEqual(store.unlockedProductCount, 1)
#else
        XCTAssertFalse(store.isChapterUnlocked("ch1"), "Release must not unlock from stored state alone.")
        XCTAssertEqual(store.unlockedProductCount, 0)
#endif
    }

    func testRenewalSubscriptionUnlocksItsProduct() {
        let renewalID = ProductCatalogue.renewalProductID(for: "com.paymentforge.app.part-1")
        let store = storeOwning([renewalID])
#if DEBUG
        XCTAssertTrue(store.isProductOwned(renewalID))
        XCTAssertTrue(store.isProductOwned("com.paymentforge.app.part-1"), "An active renewal counts as owning the product.")
        XCTAssertTrue(store.isProductUnlocked("com.paymentforge.app.part-1"))
        XCTAssertTrue(store.isChapterUnlocked("ch1"))
        XCTAssertFalse(store.isProductUnlocked("com.paymentforge.app.part-2"))
        XCTAssertEqual(store.unlockedProductCount, 1)
#else
        XCTAssertFalse(store.isProductUnlocked("com.paymentforge.app.part-1"), "Release must not unlock from stored state alone.")
#endif
    }

    func testExpiredEntitlementLocksAgain() {
        let past = Date().addingTimeInterval(-24 * 60 * 60)
        let store = storeOwning(
            ["com.paymentforge.app.part-1"],
            expiries: ["com.paymentforge.app.part-1": past]
        )
#if DEBUG
        XCTAssertFalse(store.isProductOwned("com.paymentforge.app.part-1"), "An expired purchase must not count as owned.")
        XCTAssertFalse(store.isProductUnlocked("com.paymentforge.app.part-1"))
        XCTAssertFalse(store.isChapterUnlocked("ch1"))
        XCTAssertNil(store.expiryDate(for: "com.paymentforge.app.part-1"))
        XCTAssertEqual(store.unlockedProductCount, 0)
#else
        XCTAssertFalse(store.isProductUnlocked("com.paymentforge.app.part-1"))
#endif
    }

    func testExpiredRenewalLocksAgainWhilePurchaseStaysActive() {
        let past = Date().addingTimeInterval(-24 * 60 * 60)
        let future = Date().addingTimeInterval(30 * 24 * 60 * 60)
        let renewalID = ProductCatalogue.renewalProductID(for: "com.paymentforge.app.part-1")
        // Expired renewal alone: locked.
        let renewalOnly = storeOwning([renewalID], expiries: [renewalID: past])
#if DEBUG
        XCTAssertFalse(renewalOnly.isProductUnlocked("com.paymentforge.app.part-1"))
        // Active purchase plus expired renewal: still unlocked, and
        // the expiry reported is the purchase expiry.
        let both = storeOwning(
            ["com.paymentforge.app.part-1", renewalID],
            expiries: ["com.paymentforge.app.part-1": future, renewalID: past]
        )
        XCTAssertTrue(both.isProductUnlocked("com.paymentforge.app.part-1"))
        XCTAssertEqual(both.expiryDate(for: "com.paymentforge.app.part-1"), future)
#else
        XCTAssertFalse(renewalOnly.isProductUnlocked("com.paymentforge.app.part-1"))
#endif
    }

    func testExpiryDateReportsLatestActiveExpiry() {
        let near = Date().addingTimeInterval(10 * 24 * 60 * 60)
        let far = Date().addingTimeInterval(300 * 24 * 60 * 60)
        let renewalID = ProductCatalogue.renewalProductID(for: "com.paymentforge.app.part-1")
        let store = storeOwning(
            ["com.paymentforge.app.part-1", renewalID],
            expiries: ["com.paymentforge.app.part-1": near, renewalID: far]
        )
#if DEBUG
        XCTAssertEqual(store.expiryDate(for: "com.paymentforge.app.part-1"), far, "The latest active expiry wins.")
        XCTAssertNil(store.expiryDate(for: "com.paymentforge.app.part-2"), "A locked product reports no expiry.")
        // Seeded without an expiry: active, but no expiry recorded.
        let unexpiring = storeOwning(["com.paymentforge.app.part-2"])
        XCTAssertTrue(unexpiring.isProductUnlocked("com.paymentforge.app.part-2"))
        XCTAssertNil(unexpiring.expiryDate(for: "com.paymentforge.app.part-2"))
#else
        XCTAssertNil(store.expiryDate(for: "com.paymentforge.app.part-1"))
#endif
    }

    func testUnlockingProductPointsAtContainingPartWhenLocked() {
        let store = StoreManager()
        XCTAssertEqual(store.unlockingProduct(for: "ch1")?.id, "part-1")
        XCTAssertEqual(store.unlockingProduct(for: "ch5")?.id, "part-3")
        XCTAssertEqual(store.unlockingProduct(for: "ch95")?.id, "part-6")
        XCTAssertNil(store.unlockingProduct(for: "ch999"), "A chapter in no part has no unlocking product.")
    }

    // MARK: - Price availability

    func testPriceTextIsUnavailableWhenNoStoreKitProductIsLoaded() {
        let store = StoreManager()
        XCTAssertFalse(store.allProductsLoaded)
        XCTAssertTrue(store.products.isEmpty, "A fresh store has loaded no StoreKit products.")
        for storeID in ProductCatalogue.allStoreProductIDs {
            XCTAssertFalse(store.isPriceAvailable(for: storeID), "No price is available for \(storeID) before StoreKit loads.")
            XCTAssertEqual(store.priceText(for: storeID), "Price unavailable")
        }
        // The fallback must never be a hardcoded catalogue price.
        XCTAssertNotEqual(store.priceText(for: ProductCatalogue.integratedProductID), "Rs. 2,999")
        XCTAssertNotEqual(store.priceText(for: ProductCatalogue.practiceProductID), "Rs. 999")
        XCTAssertFalse(store.priceText(for: ProductCatalogue.integratedProductID).contains("2,999"))
    }
}
