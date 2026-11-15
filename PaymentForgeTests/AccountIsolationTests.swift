// AccountIsolationTests.swift
// PaymentForge iOS - Phase 1 (Release integrity) tests: account
// scoped storage. Every account or personal value lives under
// pf.account.<namespace>.<baseKey>, where the namespace is the
// signed-in user's id or "guest". Two accounts must never see each
// other's data, guest data must never leak into an account except
// through the explicit migration offer, and removal must clear only
// the target namespace.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the final app source before writing.
//
// Test namespaces ("test-isolation-a" and friends) are removed in
// tearDown, and the current namespace is reset to guest, so no test
// leaks state into another test file sharing the process. The base
// keys used here are test-only keys that no store reads.

import XCTest
@testable import PaymentForge

final class AccountIsolationTests: XCTestCase {

    private let namespaceA = "test-isolation-a"
    private let namespaceB = "test-isolation-b"
    private let guestNamespace = AccountScopedStorage.guestNamespace

    override func setUp() {
        super.setUp()
        AccountScopedStorage.setCurrentNamespace(nil)
        AccountScopedStorage.removeAllKeys(in: namespaceA)
        AccountScopedStorage.removeAllKeys(in: namespaceB)
    }

    override func tearDown() {
        AccountScopedStorage.removeAllKeys(in: namespaceA)
        AccountScopedStorage.removeAllKeys(in: namespaceB)
        AccountScopedStorage.setCurrentNamespace(nil)
        super.tearDown()
    }

    // MARK: - Key scheme

    func testKeySchemeIsNamespaced() {
        XCTAssertEqual(AccountScopedStorage.guestNamespace, "guest")
        XCTAssertEqual(
            AccountScopedStorage.key("pf.completedLessons.v1", namespace: "user-123"),
            "pf.account.user-123.pf.completedLessons.v1"
        )
        XCTAssertEqual(AccountScopedStorage.prefix(for: "user-123"), "pf.account.user-123.")
        XCTAssertTrue(AccountScopedStorage.prefix(for: "user-123").hasSuffix("."), "The prefix ends with a dot so a scan never matches a longer namespace sharing the same start.")
    }

    func testKeysDifferPerNamespace() {
        let baseKey = "pf.test.value.v1"
        let keyA = AccountScopedStorage.key(baseKey, namespace: namespaceA)
        let keyB = AccountScopedStorage.key(baseKey, namespace: namespaceB)
        let guestKey = AccountScopedStorage.key(baseKey, namespace: guestNamespace)
        XCTAssertNotEqual(keyA, keyB)
        XCTAssertNotEqual(keyA, guestKey)
        XCTAssertNotEqual(keyB, guestKey)
    }

    func testGuestAndAccountNamespacesNeverCollide() {
        let baseKey = "pf.test.collision.v1"
        UserDefaults.standard.set("guest-value", forKey: AccountScopedStorage.key(baseKey, namespace: guestNamespace))
        UserDefaults.standard.set("account-value", forKey: AccountScopedStorage.key(baseKey, namespace: namespaceA))
        XCTAssertEqual(UserDefaults.standard.string(forKey: AccountScopedStorage.key(baseKey, namespace: guestNamespace)), "guest-value")
        XCTAssertEqual(UserDefaults.standard.string(forKey: AccountScopedStorage.key(baseKey, namespace: namespaceA)), "account-value")
        UserDefaults.standard.removeObject(forKey: AccountScopedStorage.key(baseKey, namespace: guestNamespace))
    }

    func testCurrentNamespaceDefaultsToGuest() {
        AccountScopedStorage.setCurrentNamespace(nil)
        XCTAssertEqual(AccountScopedStorage.currentNamespace, "guest")
        XCTAssertEqual(AccountScopedStorage.currentKey("pf.test.value.v1"), "pf.account.guest.pf.test.value.v1")
    }

    func testSetCurrentNamespaceTrimsAndTreatsBlankAsGuest() {
        AccountScopedStorage.setCurrentNamespace("  user-abc  ")
        XCTAssertEqual(AccountScopedStorage.currentNamespace, "user-abc")
        AccountScopedStorage.setCurrentNamespace("")
        XCTAssertEqual(AccountScopedStorage.currentNamespace, "guest")
        AccountScopedStorage.setCurrentNamespace("   ")
        XCTAssertEqual(AccountScopedStorage.currentNamespace, "guest")
    }

    func testCurrentKeyFollowsCurrentNamespace() {
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        XCTAssertEqual(AccountScopedStorage.currentKey("pf.test.value.v1"), AccountScopedStorage.key("pf.test.value.v1", namespace: namespaceA))
        AccountScopedStorage.setCurrentNamespace(namespaceB)
        XCTAssertEqual(AccountScopedStorage.currentKey("pf.test.value.v1"), AccountScopedStorage.key("pf.test.value.v1", namespace: namespaceB))
    }

    func testNamespaceSanitisationReplacesUnsafeCharacters() {
        // Supabase ids (UUIDs) pass through unchanged; anything else
        // is replaced with a hyphen so the key stays well formed.
        XCTAssertEqual(AccountScopedStorage.key("k", namespace: "550e8400-e29b-41d4-a716-446655440000"), "pf.account.550e8400-e29b-41d4-a716-446655440000.k")
        XCTAssertEqual(AccountScopedStorage.key("k", namespace: "a.b@c"), "pf.account.a-b-c.k")
        XCTAssertEqual(AccountScopedStorage.key("k", namespace: ""), "pf.account.guest.k")
    }

    // MARK: - Migration

    func testMigrateGuestKeysCopiesMissingKeysAndKeepsGuestCopy() {
        let baseKey = "pf.test.migrate.v1"
        UserDefaults.standard.set("guest-data", forKey: AccountScopedStorage.key(baseKey, namespace: guestNamespace))
        let migrated = AccountScopedStorage.migrateGuestKeys([baseKey], to: namespaceA)
        XCTAssertEqual(migrated, [baseKey])
        XCTAssertEqual(UserDefaults.standard.string(forKey: AccountScopedStorage.key(baseKey, namespace: namespaceA)), "guest-data")
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: AccountScopedStorage.key(baseKey, namespace: guestNamespace)),
            "guest-data",
            "Migration copies, it does not move: the guest copy stays."
        )
        UserDefaults.standard.removeObject(forKey: AccountScopedStorage.key(baseKey, namespace: guestNamespace))
    }

    func testMigrateGuestKeysNeverOverwritesExistingAccountValues() {
        let baseKey = "pf.test.migrateKeep.v1"
        UserDefaults.standard.set("guest-data", forKey: AccountScopedStorage.key(baseKey, namespace: guestNamespace))
        UserDefaults.standard.set("account-data", forKey: AccountScopedStorage.key(baseKey, namespace: namespaceA))
        let migrated = AccountScopedStorage.migrateGuestKeys([baseKey], to: namespaceA)
        XCTAssertTrue(migrated.isEmpty, "An existing account value is never reported as migrated.")
        XCTAssertEqual(UserDefaults.standard.string(forKey: AccountScopedStorage.key(baseKey, namespace: namespaceA)), "account-data")
        UserDefaults.standard.removeObject(forKey: AccountScopedStorage.key(baseKey, namespace: guestNamespace))
    }

    func testMigrateGuestKeysSkipsKeysWithNoGuestValue() {
        let migrated = AccountScopedStorage.migrateGuestKeys(["pf.test.noGuestValue.v1"], to: namespaceA)
        XCTAssertTrue(migrated.isEmpty)
        XCTAssertNil(UserDefaults.standard.object(forKey: AccountScopedStorage.key("pf.test.noGuestValue.v1", namespace: namespaceA)))
    }

    func testMigrateGuestKeysToGuestIsNoOp() {
        let baseKey = "pf.test.migrateToGuest.v1"
        UserDefaults.standard.set("guest-data", forKey: AccountScopedStorage.key(baseKey, namespace: guestNamespace))
        let migrated = AccountScopedStorage.migrateGuestKeys([baseKey], to: guestNamespace)
        XCTAssertTrue(migrated.isEmpty, "Migrating to the guest namespace is a no-op.")
        UserDefaults.standard.removeObject(forKey: AccountScopedStorage.key(baseKey, namespace: guestNamespace))
    }

    func testMigrateGuestKeysWithPrefixCopiesOnlyMissingPrefixedKeys() {
        let prefix = "pf.test.prefix."
        UserDefaults.standard.set("one", forKey: AccountScopedStorage.key("\(prefix)one", namespace: guestNamespace))
        UserDefaults.standard.set("two", forKey: AccountScopedStorage.key("\(prefix)two", namespace: guestNamespace))
        UserDefaults.standard.set("kept", forKey: AccountScopedStorage.key("\(prefix)two", namespace: namespaceA))
        UserDefaults.standard.set("other", forKey: AccountScopedStorage.key("pf.test.unrelated.v1", namespace: guestNamespace))
        let migrated = AccountScopedStorage.migrateGuestKeys(withPrefix: prefix, to: namespaceA)
        XCTAssertEqual(migrated, ["\(prefix)one"])
        XCTAssertEqual(UserDefaults.standard.string(forKey: AccountScopedStorage.key("\(prefix)one", namespace: namespaceA)), "one")
        XCTAssertEqual(UserDefaults.standard.string(forKey: AccountScopedStorage.key("\(prefix)two", namespace: namespaceA)), "kept")
        XCTAssertNil(UserDefaults.standard.object(forKey: AccountScopedStorage.key("pf.test.unrelated.v1", namespace: namespaceA)))
        UserDefaults.standard.removeObject(forKey: AccountScopedStorage.key("\(prefix)one", namespace: guestNamespace))
        UserDefaults.standard.removeObject(forKey: AccountScopedStorage.key("\(prefix)two", namespace: guestNamespace))
        UserDefaults.standard.removeObject(forKey: AccountScopedStorage.key("pf.test.unrelated.v1", namespace: guestNamespace))
    }

    func testHasKeysWithBasePrefix() {
        XCTAssertFalse(AccountScopedStorage.hasKeys(in: namespaceA, withBasePrefix: "pf.test.prefix."))
        UserDefaults.standard.set("one", forKey: AccountScopedStorage.key("pf.test.prefix.one", namespace: namespaceA))
        XCTAssertTrue(AccountScopedStorage.hasKeys(in: namespaceA, withBasePrefix: "pf.test.prefix."))
        XCTAssertFalse(AccountScopedStorage.hasKeys(in: namespaceB, withBasePrefix: "pf.test.prefix."))
    }

    // MARK: - Removal

    func testRemoveAllKeysClearsOnlyTargetNamespace() {
        UserDefaults.standard.set("a", forKey: AccountScopedStorage.key("pf.test.value.v1", namespace: namespaceA))
        UserDefaults.standard.set("b", forKey: AccountScopedStorage.key("pf.test.value.v1", namespace: namespaceB))
        UserDefaults.standard.set("guest", forKey: AccountScopedStorage.key("pf.test.value.v1", namespace: guestNamespace))
        UserDefaults.standard.set("legacy", forKey: "pf.test.legacyUnnamespaced.v1")
        AccountScopedStorage.removeAllKeys(in: namespaceA)
        XCTAssertNil(UserDefaults.standard.object(forKey: AccountScopedStorage.key("pf.test.value.v1", namespace: namespaceA)))
        XCTAssertEqual(UserDefaults.standard.string(forKey: AccountScopedStorage.key("pf.test.value.v1", namespace: namespaceB)), "b")
        XCTAssertEqual(UserDefaults.standard.string(forKey: AccountScopedStorage.key("pf.test.value.v1", namespace: guestNamespace)), "guest")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "pf.test.legacyUnnamespaced.v1"), "legacy")
        UserDefaults.standard.removeObject(forKey: AccountScopedStorage.key("pf.test.value.v1", namespace: guestNamespace))
        UserDefaults.standard.removeObject(forKey: "pf.test.legacyUnnamespaced.v1")
    }

    func testRemoveAllKeysDoesNotMatchLongerNamespacePrefix() {
        // The trailing dot in the prefix means removing "test-ns"
        // must not remove keys in "test-ns2".
        let shortNamespace = "test-ns"
        let longNamespace = "test-ns2"
        AccountScopedStorage.removeAllKeys(in: shortNamespace)
        AccountScopedStorage.removeAllKeys(in: longNamespace)
        defer {
            AccountScopedStorage.removeAllKeys(in: shortNamespace)
            AccountScopedStorage.removeAllKeys(in: longNamespace)
        }
        UserDefaults.standard.set("short", forKey: AccountScopedStorage.key("pf.test.value.v1", namespace: shortNamespace))
        UserDefaults.standard.set("long", forKey: AccountScopedStorage.key("pf.test.value.v1", namespace: longNamespace))
        AccountScopedStorage.removeAllKeys(in: shortNamespace)
        XCTAssertNil(UserDefaults.standard.object(forKey: AccountScopedStorage.key("pf.test.value.v1", namespace: shortNamespace)))
        XCTAssertEqual(UserDefaults.standard.string(forKey: AccountScopedStorage.key("pf.test.value.v1", namespace: longNamespace)), "long")
    }

    // MARK: - Legacy adoption

    func testAdoptLegacyKeyCopiesOnceAndRemovesLegacyKey() {
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let legacyKey = "pf.test.legacyAdopt.v1"
        UserDefaults.standard.set("legacy-data", forKey: legacyKey)
        AccountScopedStorage.adoptLegacyKey(legacyKey)
        XCTAssertEqual(UserDefaults.standard.string(forKey: AccountScopedStorage.currentKey(legacyKey)), "legacy-data")
        XCTAssertNil(UserDefaults.standard.object(forKey: legacyKey), "The legacy key is removed so it can never be adopted twice.")
        // Adopting again is a no-op: there is no legacy key left.
        AccountScopedStorage.adoptLegacyKey(legacyKey)
        XCTAssertEqual(UserDefaults.standard.string(forKey: AccountScopedStorage.currentKey(legacyKey)), "legacy-data")
    }

    func testAdoptLegacyKeyNeverOverwritesNamespacedValue() {
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let legacyKey = "pf.test.legacyKeep.v1"
        UserDefaults.standard.set("namespaced-data", forKey: AccountScopedStorage.currentKey(legacyKey))
        UserDefaults.standard.set("legacy-data", forKey: legacyKey)
        AccountScopedStorage.adoptLegacyKey(legacyKey)
        XCTAssertEqual(UserDefaults.standard.string(forKey: AccountScopedStorage.currentKey(legacyKey)), "namespaced-data")
        XCTAssertNil(UserDefaults.standard.object(forKey: legacyKey), "The legacy key is removed even when its value is not adopted.")
    }

    func testAdoptLegacyKeysWithPrefixAdoptsOnlyLegacyKeys() {
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let prefix = "pf.test.legacyPrefix."
        UserDefaults.standard.set("one", forKey: "\(prefix)one")
        UserDefaults.standard.set("two", forKey: "\(prefix)two")
        UserDefaults.standard.set("unrelated", forKey: "pf.test.otherLegacy.v1")
        AccountScopedStorage.adoptLegacyKeys(withPrefix: prefix)
        XCTAssertEqual(UserDefaults.standard.string(forKey: AccountScopedStorage.currentKey("\(prefix)one")), "one")
        XCTAssertEqual(UserDefaults.standard.string(forKey: AccountScopedStorage.currentKey("\(prefix)two")), "two")
        XCTAssertNil(UserDefaults.standard.object(forKey: "\(prefix)one"))
        XCTAssertNil(UserDefaults.standard.object(forKey: "\(prefix)two"))
        XCTAssertEqual(UserDefaults.standard.string(forKey: "pf.test.otherLegacy.v1"), "unrelated", "Keys outside the prefix are untouched.")
        UserDefaults.standard.removeObject(forKey: "pf.test.otherLegacy.v1")
    }

    // MARK: - Store-level isolation through public APIs

    @MainActor
    func testPracticeStoreDoesNotLeakAcrossNamespaces() {
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let firstStore = PracticeStore()
        firstStore.recordAttempt(situationID: "ABH-01", chosenOptionIndex: 0, isCorrect: true)
        XCTAssertEqual(firstStore.totalAttempts, 1)

        AccountScopedStorage.setCurrentNamespace(namespaceB)
        let secondStore = PracticeStore()
        XCTAssertEqual(secondStore.totalAttempts, 0, "The second namespace must not see the first namespace's attempts.")

        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let firstStoreAgain = PracticeStore()
        XCTAssertEqual(firstStoreAgain.totalAttempts, 1, "Returning to the first namespace restores its attempts.")
    }
}
