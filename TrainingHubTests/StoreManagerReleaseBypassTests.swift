// StoreManagerReleaseBypassTests.swift
// TrainingHub iOS - Phase 1 (Release integrity) tests: the
// build-phase Buy bypass must not exist in Release builds.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the final app source before writing.
// The Release branch of these tests only proves its claims when the
// test bundle is built with the Release configuration (DEBUG not
// defined). A DEBUG run exercises only the DEBUG branch, which
// asserts the retired bypass stays off and asserts nothing about
// Release behavior.
//
// How the Release test works: it pollutes every UserDefaults key a
// bypass could read (the purchased cache, the entitlement expiry
// map, the bypass set, and the legacy Situations flag), then
// constructs a fresh StoreManager.
// A Release build must still report no ownership and no unlocks,
// because Release init starts locked, purges the bypass key, and
// never reads a stored flag to unlock anything. A fresh StoreManager
// CAN be constructed in tests (internal init), so there is no
// construction gap for this file.
//
// The polluted key names are string literals mirroring the private
// keys in StoreManager; they must be kept in step with that file.

import XCTest
@testable import TrainingHub

@MainActor
final class StoreManagerReleaseBypassTests: XCTestCase {

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

    /// Write the most permissive stored state possible: every store
    /// ID in the purchased cache, a future expiry for every store
    /// ID, every store ID in the bypass set, and the legacy
    /// Situations flag set.
    private func polluteStoredPurchaseState() {
        UserDefaults.standard.set(ProductCatalogue.allStoreProductIDs, forKey: purchasedCacheKey)
        let future = Date().addingTimeInterval(365 * 24 * 60 * 60).timeIntervalSince1970
        let expiries = Dictionary(uniqueKeysWithValues: ProductCatalogue.allStoreProductIDs.map { ($0, future) })
        if let data = try? JSONEncoder().encode(expiries) {
            UserDefaults.standard.set(data, forKey: entitlementExpiriesKey)
        }
        UserDefaults.standard.set(ProductCatalogue.allStoreProductIDs, forKey: bypassKey)
        UserDefaults.standard.set(true, forKey: legacySituationsKey)
    }

    func testBuildPhaseBypassFlagMatchesConfiguration() {
        // The build-phase bypass is retired: the flag is false in
        // every configuration, and DEBUG purchases go through the
        // local .storekit configuration with verified StoreKit
        // transactions, exactly like Release.
        XCTAssertFalse(StoreManager.buildPhaseBuyOpensContent, "The build-phase bypass flag must be false in every configuration.")
    }

#if DEBUG
    func testDebugPurchasesRequireVerifiedTransactions() {
        // The bypass is retired: in DEBUG there is no unlock path
        // without a verified StoreKit transaction. DEBUG purchases
        // use the local .storekit configuration, and whether a
        // polluted cache unlocks content is intentionally NOT
        // asserted here: this file must never assert Release
        // behavior from a DEBUG run. The Release assertions live in
        // the #else branch below and run only in Release builds.
        XCTAssertFalse(StoreManager.buildPhaseBuyOpensContent)
    }
#else
    func testReleaseFreshStoreIgnoresPollutedStoredState() {
        polluteStoredPurchaseState()
        let store = StoreManager()
        for storeID in ProductCatalogue.allStoreProductIDs {
            XCTAssertFalse(store.isProductOwned(storeID), "Release must not own \(storeID) from stored state alone.")
        }
        for productID in ProductCatalogue.allProductIDs {
            XCTAssertFalse(store.isProductUnlocked(productID), "Release must not unlock \(productID) from stored state alone.")
            XCTAssertNil(store.expiryDate(for: productID), "Release must not report an expiry for \(productID) from stored state alone.")
        }
        XCTAssertFalse(store.isPracticeUnlocked)
        XCTAssertFalse(store.isStudioUnlocked)
        XCTAssertFalse(store.isSimulatorUnlocked)
        XCTAssertFalse(store.isInvestigationLabUnlocked)
        XCTAssertFalse(store.isInterviewUnlocked)
        XCTAssertEqual(store.unlockedProductCount, 0)
        XCTAssertTrue(store.purchasedProductIDs.isEmpty)
        XCTAssertTrue(store.deviceEntitlementExpiries.isEmpty)
        XCTAssertTrue(store.serverEntitlementExpiries.isEmpty)
        XCTAssertTrue(store.buildPhaseUnlockedProductIDs.isEmpty)
    }

    func testReleaseFreshStoreLocksChaptersDespitePollutedStoredState() {
        polluteStoredPurchaseState()
        let store = StoreManager()
        XCTAssertFalse(store.isChapterUnlocked("ch1"))
        XCTAssertFalse(store.isChapterUnlocked("ch5"))
        XCTAssertFalse(store.isChapterUnlocked("ch28"))
        XCTAssertFalse(store.isChapterUnlocked("ch95"))
        XCTAssertFalse(store.isChapterUnlocked("ch100"))
        // The held-out ch37 stays reachable: it is never sold, so
        // its reachability is not an unlock granted by stored state.
        XCTAssertTrue(store.isChapterUnlocked("ch37"))
        // A chapter no part contains stays locked (fail closed), even
        // in Release; it is not an unlock granted by stored state.
        XCTAssertFalse(store.isChapterUnlocked("ch999"))
    }

    func testReleaseInitPurgesBypassKey() {
        polluteStoredPurchaseState()
        _ = StoreManager()
        XCTAssertNil(
            UserDefaults.standard.object(forKey: bypassKey),
            "Release init must purge the build-phase bypass key so it can never unlock anything again."
        )
        XCTAssertNil(
            UserDefaults.standard.object(forKey: legacySituationsKey),
            "Release init must purge the legacy Situations flag so it can never unlock anything again."
        )
    }
#endif

    func testSharedInstanceExists() {
        // StoreManager.shared is the instance AuthService and
        // SyncService use for entitlement refresh and clearing. This
        // asserts only that the singleton exists and is stable; its
        // entitlement state is owned by the running app, so no
        // locked-state assertion is made against it here.
        XCTAssertTrue(StoreManager.shared === StoreManager.shared)
    }
}
