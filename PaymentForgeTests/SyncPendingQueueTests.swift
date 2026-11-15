// SyncPendingQueueTests.swift
// PaymentForge iOS - Phase 1 (Release integrity) tests: the durable
// pending-sync queue and the noteLocalChange recording paths.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the final app source before writing.
//
// No test requires network: recording, removal, and degradation are
// all local UserDefaults behavior. A full syncAll run against live
// Supabase is a manual test item. The queue is a singleton with a
// private init, so persistence "across instances" cannot be tested
// with a second instance; instead these tests assert the durable
// payload itself in UserDefaults under the namespaced key, which is
// the storage a fresh process re-reads. All tests run in a test-only
// namespace that tearDown removes, and the namespace is reset to
// guest afterwards.
//
// Note: noteLocalChange also schedules a debounced sync through a
// Task hop. For a guest that sync is a no-op (syncAll returns early
// when nobody is signed in), so these tests make no network call in
// the guest test environment.

import XCTest
@testable import PaymentForge

final class SyncPendingQueueTests: XCTestCase {

    private let testNamespace = "test-sync-queue"
    private let queueBaseKey = "pf.syncPendingQueue.v1"

    private var queueKey: String {
        AccountScopedStorage.currentKey(queueBaseKey)
    }

    override func setUp() {
        super.setUp()
        AccountScopedStorage.setCurrentNamespace(testNamespace)
        SyncPendingQueue.shared.removeAll()
    }

    override func tearDown() {
        SyncPendingQueue.shared.removeAll()
        AccountScopedStorage.removeAllKeys(in: testNamespace)
        AccountScopedStorage.setCurrentNamespace(nil)
        super.tearDown()
    }

    // MARK: - Recording

    func testRecordMakesQueuePending() {
        XCTAssertFalse(SyncPendingQueue.shared.hasPending)
        SyncPendingQueue.shared.record(kind: .progress, identifiers: ["ch1s1"])
        XCTAssertTrue(SyncPendingQueue.shared.hasPending)
        XCTAssertEqual(SyncPendingQueue.shared.pendingKinds, [.progress])
        let snapshot = SyncPendingQueue.shared.snapshot
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(snapshot.first?.kind, .progress)
        XCTAssertEqual(snapshot.first?.identifiers, ["ch1s1"])
    }

    func testRecordMergesIdentifiersIntoOneEntryPerKind() {
        SyncPendingQueue.shared.record(kind: .progress, identifiers: ["ch1s1"])
        SyncPendingQueue.shared.record(kind: .progress, identifiers: ["ch1s2", "ch1s1"])
        let snapshot = SyncPendingQueue.shared.snapshot
        XCTAssertEqual(snapshot.count, 1, "One kind has one entry; identifiers merge into it.")
        XCTAssertEqual(snapshot.first?.identifiers, ["ch1s1", "ch1s2"], "Identifiers merge, deduplicate, and sort.")
        XCTAssertNotNil(snapshot.first?.firstRecordedAt)
        XCTAssertNotNil(snapshot.first?.lastRecordedAt)
        XCTAssertTrue(snapshot.first!.lastRecordedAt >= snapshot.first!.firstRecordedAt)
    }

    func testRecordPersistsDurablePayloadUnderNamespacedKey() {
        SyncPendingQueue.shared.record(kind: .bookmarks, identifiers: ["ch2s1"])
        guard let data = UserDefaults.standard.data(forKey: queueKey) else {
            XCTFail("The queue must persist a payload under the namespaced key.")
            return
        }
        let decoded = try? JSONDecoder().decode([SyncPendingChange].self, from: data)
        XCTAssertEqual(decoded?.count, 1)
        XCTAssertEqual(decoded?.first?.kind, .bookmarks)
        XCTAssertEqual(decoded?.first?.identifiers, ["ch2s1"])
        XCTAssertTrue(queueKey.hasPrefix("pf.account.\(testNamespace)."), "The queue key is account-scoped.")
    }

    func testDifferentKindsAreSeparateEntries() {
        SyncPendingQueue.shared.record(kind: .progress)
        SyncPendingQueue.shared.record(kind: .preferences)
        SyncPendingQueue.shared.record(kind: .general)
        XCTAssertEqual(SyncPendingQueue.shared.snapshot.count, 3)
        XCTAssertEqual(SyncPendingQueue.shared.pendingKinds, [.progress, .preferences, .general])
    }

    // MARK: - Removal

    func testRemoveKindDropsOnlyThatKind() {
        SyncPendingQueue.shared.record(kind: .progress)
        SyncPendingQueue.shared.record(kind: .preferences)
        SyncPendingQueue.shared.remove(kind: .progress)
        XCTAssertEqual(SyncPendingQueue.shared.pendingKinds, [.preferences])
        XCTAssertTrue(SyncPendingQueue.shared.hasPending)
    }

    func testDateBoundedRemovalRemovesOnlyEntriesRecordedBeforeTheDate() {
        SyncPendingQueue.shared.record(kind: .progress)
        let past = Date().addingTimeInterval(-60)
        SyncPendingQueue.shared.remove(kind: .progress, onlyIfLastRecordedOnOrBefore: past)
        XCTAssertTrue(
            SyncPendingQueue.shared.pendingKinds.contains(.progress),
            "An entry recorded after the run start date must survive: it is newer work."
        )
        let future = Date().addingTimeInterval(60)
        SyncPendingQueue.shared.remove(kind: .progress, onlyIfLastRecordedOnOrBefore: future)
        XCTAssertFalse(SyncPendingQueue.shared.pendingKinds.contains(.progress))
    }

    func testDateBoundedRemovalNeverDropsNewerEntry() {
        // Record an old entry, then record again so its last-recorded
        // date moves past the simulated run start. The newer entry
        // must survive a removal bounded at the run start.
        SyncPendingQueue.shared.record(kind: .quizAttempts, identifiers: ["old"])
        let runStartedAt = Date()
        Thread.sleep(forTimeInterval: 0.01)
        SyncPendingQueue.shared.record(kind: .quizAttempts, identifiers: ["new"])
        SyncPendingQueue.shared.remove(kind: .quizAttempts, onlyIfLastRecordedOnOrBefore: runStartedAt)
        let snapshot = SyncPendingQueue.shared.snapshot
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(snapshot.first?.identifiers, ["new", "old"])
    }

    func testRemoveAllDateBoundedKeepsNewerEntries() {
        SyncPendingQueue.shared.record(kind: .progress)
        let past = Date().addingTimeInterval(-60)
        SyncPendingQueue.shared.removeAll(onlyIfLastRecordedOnOrBefore: past)
        XCTAssertTrue(SyncPendingQueue.shared.hasPending)
        let future = Date().addingTimeInterval(60)
        SyncPendingQueue.shared.removeAll(onlyIfLastRecordedOnOrBefore: future)
        XCTAssertFalse(SyncPendingQueue.shared.hasPending)
    }

    func testRemoveIdentifiersPartialAndFull() {
        SyncPendingQueue.shared.record(kind: .progress, identifiers: ["ch1s1", "ch1s2", "ch1s3"])
        SyncPendingQueue.shared.remove(kind: .progress, identifiers: ["ch1s1"])
        XCTAssertEqual(SyncPendingQueue.shared.snapshot.first?.identifiers, ["ch1s2", "ch1s3"])
        SyncPendingQueue.shared.remove(kind: .progress, identifiers: ["ch1s2", "ch1s3"])
        XCTAssertFalse(SyncPendingQueue.shared.hasPending, "Removing every identifier drops the entry.")
    }

    func testRemoveIdentifiersLeavesKindOnlyEntryAlone() {
        SyncPendingQueue.shared.record(kind: .general)
        SyncPendingQueue.shared.remove(kind: .general, identifiers: ["anything"])
        XCTAssertTrue(SyncPendingQueue.shared.pendingKinds.contains(.general), "A kind-only entry still means this kind needs a sync.")
    }

    func testRemoveAllDropsWholeQueue() {
        SyncPendingQueue.shared.record(kind: .progress)
        SyncPendingQueue.shared.record(kind: .preferences)
        SyncPendingQueue.shared.removeAll()
        XCTAssertFalse(SyncPendingQueue.shared.hasPending)
        XCTAssertTrue(SyncPendingQueue.shared.snapshot.isEmpty)
        XCTAssertNil(UserDefaults.standard.object(forKey: queueKey), "removeAll removes the stored payload itself.")
    }

    // MARK: - Corrupt payload

    func testCorruptPayloadDegradesToGeneralEntryWithoutCrashing() {
        UserDefaults.standard.set(Data("not json".utf8), forKey: queueKey)
        XCTAssertTrue(SyncPendingQueue.shared.hasPending, "A corrupt payload must still report pending work.")
        let snapshot = SyncPendingQueue.shared.snapshot
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(snapshot.first?.kind, .general)
        XCTAssertTrue(snapshot.first?.identifiers.isEmpty ?? false)
    }

    func testRecordingAfterCorruptionReplacesPayloadWithValidQueue() {
        UserDefaults.standard.set(Data("not json".utf8), forKey: queueKey)
        SyncPendingQueue.shared.record(kind: .progress, identifiers: ["ch1s1"])
        let kinds = SyncPendingQueue.shared.pendingKinds
        XCTAssertTrue(kinds.contains(.general), "The degraded general entry is kept.")
        XCTAssertTrue(kinds.contains(.progress), "The new entry is recorded alongside it.")
        let data = UserDefaults.standard.data(forKey: queueKey)
        XCTAssertNotNil(data)
        XCTAssertNotNil(try? JSONDecoder().decode([SyncPendingChange].self, from: data!), "The stored payload must be valid JSON again after a record.")
    }

    // MARK: - Change kinds

    func testSyncChangeKindRawValuesAreStable() {
        // Raw values are persisted; renaming one would orphan stored
        // queue entries. All nine kinds are asserted.
        XCTAssertEqual(SyncChangeKind.allCases.count, 9)
        XCTAssertEqual(SyncChangeKind.general.rawValue, "general")
        XCTAssertEqual(SyncChangeKind.progress.rawValue, "progress")
        XCTAssertEqual(SyncChangeKind.quizAttempts.rawValue, "quizAttempts")
        XCTAssertEqual(SyncChangeKind.bookmarks.rawValue, "bookmarks")
        XCTAssertEqual(SyncChangeKind.learningActivity.rawValue, "learningActivity")
        XCTAssertEqual(SyncChangeKind.preferences.rawValue, "preferences")
        XCTAssertEqual(SyncChangeKind.learningPaths.rawValue, "learningPaths")
        XCTAssertEqual(SyncChangeKind.practiceAttempts.rawValue, "practiceAttempts")
        XCTAssertEqual(SyncChangeKind.certificates.rawValue, "certificates")
    }

    // MARK: - noteLocalChange recording

    @MainActor
    func testNoteLocalChangeRecordsPendingState() {
        SyncService.shared.noteLocalChange()
        XCTAssertTrue(SyncPendingQueue.shared.hasPending, "noteLocalChange must synchronously record durable pending work.")
        XCTAssertTrue(SyncPendingQueue.shared.pendingKinds.contains(.general))
    }

    @MainActor
    func testNoteLocalChangeKindOverloadRecordsKindAndIdentifiers() {
        SyncService.shared.noteLocalChange(kind: .progress, identifiers: ["ch3s2"])
        XCTAssertEqual(SyncPendingQueue.shared.snapshot.first?.kind, .progress)
        XCTAssertEqual(SyncPendingQueue.shared.snapshot.first?.identifiers, ["ch3s2"])
    }

    @MainActor
    func testNoteLessonCompletedRecordsProgressKind() {
        SyncService.shared.noteLessonCompleted("ch4s1")
        XCTAssertEqual(SyncPendingQueue.shared.snapshot.first?.kind, .progress)
        XCTAssertEqual(SyncPendingQueue.shared.snapshot.first?.identifiers, ["ch4s1"])
    }

    @MainActor
    func testNoteQuizAttemptRecordedRecordsQuizAttemptsKind() {
        let attemptID = UUID()
        SyncService.shared.noteQuizAttemptRecorded(lessonID: "ch1s1", attemptID: attemptID)
        XCTAssertEqual(SyncPendingQueue.shared.snapshot.first?.kind, .quizAttempts)
        XCTAssertEqual(SyncPendingQueue.shared.snapshot.first?.identifiers, ["ch1s1|\(attemptID.uuidString)"])
    }
}
