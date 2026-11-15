// AccountDeletionTests.swift
// PaymentForge iOS - Phase 1 (Release integrity) tests: account
// deletion clearing. AuthService.deleteAccount clears local state
// ONLY after the delete-account Edge Function confirms with ok true:
// pending sync operations are dropped, every UserDefaults key in the
// deleted account's namespace is removed, account-scoped server
// entitlements are dropped, and the session is cleared.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the final app source before writing.
//
// What is tested here: the clearing helpers themselves
// (SyncService.clearPendingOperations plus
// AccountScopedStorage.removeAllKeys leave no residue in the deleted
// namespace and touch no other namespace), the failure path that
// keeps the session (deleteAccount with no session returns false and
// stays a guest, with no network call), and the sign-out contract
// (sign-out does not wipe stored account data). A successful
// server-side deletion needs a live Edge Function, a real signed-in
// account, and Supabase RLS verification, so it is a MANUAL test
// item and is deliberately not faked here; see the Phase 1 report.
// Keychain clearing on deletion is likewise manual-only: the
// Keychain wrapper is private to AuthService and no test seam
// exposes it.

import XCTest
@testable import PaymentForge

@MainActor
final class AccountDeletionTests: XCTestCase {

    private let deletedNamespace = "test-deleted-account"
    private let otherNamespace = "test-other-account"

    override func setUp() {
        super.setUp()
        AccountScopedStorage.setCurrentNamespace(nil)
        AccountScopedStorage.removeAllKeys(in: deletedNamespace)
        AccountScopedStorage.removeAllKeys(in: otherNamespace)
        SyncPendingQueue.shared.removeAll()
    }

    override func tearDown() {
        AccountScopedStorage.removeAllKeys(in: deletedNamespace)
        AccountScopedStorage.removeAllKeys(in: otherNamespace)
        AccountScopedStorage.setCurrentNamespace(nil)
        SyncPendingQueue.shared.removeAll()
        super.tearDown()
    }

    func testClearingHelpersLeaveNoResidueInDeletedNamespace() {
        // Seed the deleted namespace the way the deletion flow sees
        // it: stored values plus pending sync work recorded under
        // the same namespace.
        AccountScopedStorage.setCurrentNamespace(deletedNamespace)
        UserDefaults.standard.set("progress", forKey: AccountScopedStorage.currentKey("pf.completedLessons.v1"))
        UserDefaults.standard.set("notes", forKey: AccountScopedStorage.currentKey("pf.notes.v1"))
        SyncPendingQueue.shared.record(kind: .progress, identifiers: ["ch1s1"])
        SyncPendingQueue.shared.record(kind: .quizAttempts, identifiers: ["ch1s1"])
        XCTAssertTrue(SyncPendingQueue.shared.hasPending)

        // The two clearing helpers deleteAccount runs before
        // clearSession (in the same order as the app code).
        SyncService.shared.clearPendingOperations()
        AccountScopedStorage.removeAllKeys(in: deletedNamespace)

        XCTAssertFalse(SyncPendingQueue.shared.hasPending)
        XCTAssertFalse(SyncService.shared.hasPendingChanges)
        XCTAssertFalse(SyncService.shared.hasPendingSync)
        XCTAssertNil(SyncService.shared.lastSuccessfulSyncAt)
        XCTAssertNil(UserDefaults.standard.object(forKey: AccountScopedStorage.key("pf.completedLessons.v1", namespace: deletedNamespace)))
        XCTAssertNil(UserDefaults.standard.object(forKey: AccountScopedStorage.key("pf.notes.v1", namespace: deletedNamespace)))
        let remainingKeys = UserDefaults.standard.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(AccountScopedStorage.prefix(for: deletedNamespace))
        }
        XCTAssertTrue(remainingKeys.isEmpty, "No key may remain in the deleted namespace, found: \(remainingKeys).")
    }

    func testClearingHelpersTouchNoOtherNamespace() {
        AccountScopedStorage.setCurrentNamespace(otherNamespace)
        UserDefaults.standard.set("kept", forKey: AccountScopedStorage.currentKey("pf.completedLessons.v1"))
        AccountScopedStorage.setCurrentNamespace(deletedNamespace)
        UserDefaults.standard.set("doomed", forKey: AccountScopedStorage.currentKey("pf.completedLessons.v1"))
        SyncPendingQueue.shared.record(kind: .general)

        SyncService.shared.clearPendingOperations()
        AccountScopedStorage.removeAllKeys(in: deletedNamespace)

        XCTAssertEqual(
            UserDefaults.standard.string(forKey: AccountScopedStorage.key("pf.completedLessons.v1", namespace: otherNamespace)),
            "kept",
            "Another account's stored data must survive a deletion."
        )
    }

    func testDeleteAccountWithoutSessionReturnsFalseAndStaysGuest() async {
        // No stored session: deleteAccount returns false before any
        // network call (either the not-configured guard or the
        // missing-token guard), the session stays absent, and no
        // local state is cleared. The authError wording differs by
        // configuration, so only the outcome is asserted.
        let auth = AuthService()
        let deleted = await auth.deleteAccount()
        XCTAssertFalse(deleted)
        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNil(auth.currentUser)
        XCTAssertNil(auth.profile)
    }

    func testSignOutDoesNotWipeStoredAccountData() async {
        // Sign-out switches the visible namespace to guest; stored
        // data under the account namespace stays, so the next
        // sign-in restores it. Only deletion removes stored data.
        AccountScopedStorage.setCurrentNamespace(deletedNamespace)
        UserDefaults.standard.set("stored-progress", forKey: AccountScopedStorage.currentKey("pf.completedLessons.v1"))
        AccountScopedStorage.setCurrentNamespace(nil)

        let auth = AuthService()
        await auth.signOut()

        XCTAssertFalse(auth.isSignedIn)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: AccountScopedStorage.key("pf.completedLessons.v1", namespace: deletedNamespace)),
            "stored-progress",
            "Sign-out must not wipe stored account data."
        )
        XCTAssertEqual(AccountScopedStorage.currentNamespace, AccountScopedStorage.guestNamespace)
    }

    func testClearAccountEntitlementsKeepsFreshStoreLocked() {
        // Smoke test only: server entitlements cannot be seeded from
        // tests (private(set), set only by reading Supabase), so the
        // positive case, clearing a populated server set, is a
        // manual test item. This asserts the call is safe on a fresh
        // store and leaves it locked with no pending sync flag.
        let store = StoreManager()
        store.clearAccountEntitlements()
        XCTAssertFalse(store.isPracticeUnlocked)
        XCTAssertTrue(store.serverEntitledProductIDs.isEmpty)
        XCTAssertFalse(store.serverEntitlementSyncPending)
        XCTAssertEqual(store.unlockedProductCount, 0)
    }
}
