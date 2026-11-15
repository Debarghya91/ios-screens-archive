// SyncService.swift
// Payments Training Hub iOS - Signed-in progress sync with Supabase.
//
// WHAT SYNCS (signed-in users only; nothing syncs while signed out,
// and every entry point is a no-op when Supabase is not configured):
// - Lesson completions to user_progress (union merge; completion is
//   monotonic, a completed lesson stays completed).
// - Quiz attempts to quiz_attempts (full history; attempts are never
//   overwritten or dropped).
// - Lesson bookmarks to lesson_bookmarks (union). Situation bookmarks
//   have no server table and stay on the device.
// - Learning activity to learning_activity (one row per day).
// - Learning preferences to user_preferences (see the rule below).
// - Learning path enrolments to user_learning_paths.
// - Practice attempts to practice_attempts, through
//   PracticeStore.syncPendingAttempts (owned by PracticeStore, which
//   adopts guest attempts into the signed-in account there).
// - Path certificates: best-effort backfill so the website
//   verification page can check them; it never fails a sync.
// WHAT DOES NOT SYNC through this file: notes (device-only), the
// weekly goal (ProgressStore only; no server column is written for
// it), streaks and other derived statistics (computed from events),
// purchases (written only by the record-purchase edge function),
// and profile rows (owned by AuthService). Anything not listed above
// does not sync through this file.
//
// CONFLICT RULES (per table; nothing is ever deleted on either side):
// - Completed lessons: union of local and server. No updated_at
//   comparison is performed: a lesson the server already has is never
//   re-pushed, so the server keeps its own completed_at and
//   updated_at, and a lesson completed on any device stays completed.
// - Quiz attempts: keyed by lesson, correct count, total and
//   timestamp. Every attempt is kept; a local attempt is never
//   dropped because a server read failed (a decode failure fails the
//   sync instead, and the attempt stays local and pending).
// - Learning activity: one row per day keeps the higher of the local
//   and server lessons and minutes, so a second device's work is
//   never overwritten. The table has no updated_at column.
// - Bookmarks: union. There is no delete path: removing a bookmark on
//   one device does not delete the server row.
// - Learning preferences: local wins once the user has explicitly
//   saved on this device; the server row only restores preferences
//   on a device that never saved. This is deliberately NOT
//   last-write-wins by updated_at: the server updated_at is decoded
//   but never compared, and the local store keeps no updated_at, so
//   comparing timestamps would need a local timestamp that does not
//   exist. The rule protects an explicit on-device save from a stale
//   server row. A sync run never overwrites a server preference row;
//   only an explicit save pushes, through pushPreferences().
// - Learning paths: highest progress wins; progress never regresses.
//   The table has no updated_at column.
// - Last accessed lesson: the last completed lesson. Local wins when
//   the device has one; otherwise the server's latest completed_at
//   fills it in. There is no separate server column for it.
//
// IDEMPOTENT WRITES: user_progress, lesson_bookmarks,
// learning_activity, user_learning_paths and user_preferences are
// written with restUpsert on their natural keys (user_id plus
// lesson_id, activity_date, path_id, or user_id alone), so a repeat
// push updates the same row instead of duplicating it. Those keys
// match supabase/migrations/0001_init.sql in this working copy; the
// live schema was not verified from this machine. quiz_attempts and
// practice_attempts have no unique key by design (history tables
// with server-generated ids, and the local attempt UUID is never
// sent because the server row has no client id column), so they are
// written with restInsert and duplicates on retry are prevented by
// reading the server first: quiz attempts push only rows with no
// matching dedupe key, and practice attempts carry a synced flag in
// PracticeStore. Limitation: two quiz attempts with identical
// lesson, correct count, total and timestamp (same second) are
// indistinguishable to the dedupe key and collapse to one server
// row. A retry after a lost response re-reads first, so it does not
// duplicate.
//
// ERROR HANDLING: a server decoding failure is a sync failure, never
// an empty dataset. No local data is overwritten or wiped on any
// failure. Network errors are retryable (bounded attempts per
// trigger, then retry on foreground or on the next local change).
// Auth errors stop the run after the fresh-token attempt:
// validAccessToken() already refreshes an expiring token, so looping
// would not help. Decode and other server errors stop the run, keep
// the pending state, and surface in lastError for a later trigger.
// If the signed-in user changes mid-sync, the run is abandoned and
// nothing is written for the wrong account.
//
// TRIGGERS: noteLocalChange() records durable pending work and starts
// a debounced sync (about 2 seconds of quiet, coalescing bursts).
// The app returning to the foreground syncs when work is pending or
// the last successful sync is stale. syncAfterSignIn() runs a full
// refresh (each table pulls server state first, then pushes local
// changes) for the newly signed-in user. Pending work survives app
// restarts through SyncPendingQueue; the local stores remain the
// durable record of progress itself.
// No em dashes in any user-facing text.

import Foundation
import Combine
import UIKit

/// Syncs local progress and preferences to Supabase after sign-in.
@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    private let client = SupabaseClient.shared
    private let maxAttempts = 3

    /// Quiet period after the last local change before a debounced
    /// sync fires, coalescing bursts of changes into one sync run.
    private let debounceNanoseconds: UInt64 = 2_000_000_000

    /// A foreground return syncs when the last successful sync is
    /// older than this, even with no pending work recorded.
    private let staleThresholdSeconds: TimeInterval = 15 * 60

    /// Base key for the persisted last-successful-sync date. The
    /// stored key is account-scoped through AccountScopedStorage.
    private let lastSyncBaseKey = "pf.lastSuccessfulSync.v1"

    /// True while a sync is running.
    @Published private(set) var isSyncing = false

    /// The last error message from a sync, nil when the last sync worked.
    @Published private(set) var lastError: String?

    /// When the last sync run fully succeeded for the current account,
    /// nil when it has never succeeded. Persisted per account.
    @Published private(set) var lastSuccessfulSyncAt: Date?

    /// True when local changes are recorded as still needing a sync.
    /// Mirrors hasPendingSync; both are updated together.
    @Published private(set) var hasPendingChanges = false

    /// True when the last sync attempt failed and a retry is due.
    /// Kept for existing readers (ProfileView); mirrors
    /// hasPendingChanges and is updated together with it.
    @Published private(set) var hasPendingSync = false

    /// The pending debounced sync, if one is waiting out its quiet
    /// period. Cancelled and replaced by every new local change.
    private var debounceTask: Task<Void, Never>? = nil

    /// Foreground observer token. The singleton lives for the life of
    /// the app, so the observer is never removed.
    private var foregroundObserver: NSObjectProtocol? = nil

    /// True when a sync was requested while another run was in
    /// flight. The in-flight run schedules one follow-up debounced
    /// sync when it finishes, so the request is not lost.
    private var syncRequestedWhileRunning = false

    private init() {
        reloadPersistedSyncState()
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.syncIfNeededOnForeground()
            }
        }
    }

    // MARK: - Entry points

    /// Called after a guest signs in or registers. Runs a full
    /// refresh for the newly signed-in user: each table pulls server
    /// state first, then pushes local changes, so guest progress made
    /// on this device migrates into the new account and server state
    /// from other devices lands here. Any debounced sync left over
    /// from before sign-in is cancelled; this run replaces it.
    func syncAfterSignIn() async {
        debounceTask?.cancel()
        debounceTask = nil
        reloadPersistedSyncState()
        await syncAll()
    }

    /// Sync everything for the signed-in user: progress, quiz scores,
    /// lesson bookmarks, learning activity, preferences, learning
    /// path enrolments, practice attempts and path certificates. Safe
    /// to call any time; it is a no-op for guests and when Supabase is
    /// not configured. If a run is already in flight, the request is
    /// remembered and one follow-up sync is scheduled when the run
    /// finishes, instead of running two syncs at once.
    func syncAll() async {
        guard client.isConfigured else { return }
        let auth = AuthService.shared
        guard auth.isSignedIn,
              let userID = auth.currentUser?.id else {
            return
        }
        guard !isSyncing else {
            syncRequestedWhileRunning = true
            setPending(true)
            ProgressStore.shared.markSyncPending()
            return
        }
        debounceTask = nil
        isSyncing = true
        let runStartedAt = Date()
        defer {
            isSyncing = false
            if syncRequestedWhileRunning {
                syncRequestedWhileRunning = false
                if hasPendingChanges {
                    scheduleDebouncedSync()
                }
            }
        }
        refreshPendingFlags()
        ProgressStore.shared.markSyncPending()
        var attempt = 0
        var delayNanoseconds: UInt64 = 1_000_000_000
        while attempt < maxAttempts {
            attempt += 1
            do {
                try ensureSameUser(userID)
                guard let token = await auth.validAccessToken() else {
                    throw SupabaseError.missingAccessToken
                }
                try ensureSameUser(userID)
                try await syncProgress(userID: userID, accessToken: token)
                try ensureSameUser(userID)
                SyncPendingQueue.shared.remove(kind: .progress, onlyIfLastRecordedOnOrBefore: runStartedAt)
                try await syncQuizAttempts(userID: userID, accessToken: token)
                try ensureSameUser(userID)
                SyncPendingQueue.shared.remove(kind: .quizAttempts, onlyIfLastRecordedOnOrBefore: runStartedAt)
                try await syncBookmarks(userID: userID, accessToken: token)
                try ensureSameUser(userID)
                SyncPendingQueue.shared.remove(kind: .bookmarks, onlyIfLastRecordedOnOrBefore: runStartedAt)
                try await syncLearningActivity(userID: userID, accessToken: token)
                try ensureSameUser(userID)
                SyncPendingQueue.shared.remove(kind: .learningActivity, onlyIfLastRecordedOnOrBefore: runStartedAt)
                try await syncPreferences(userID: userID, accessToken: token)
                try ensureSameUser(userID)
                SyncPendingQueue.shared.remove(kind: .preferences, onlyIfLastRecordedOnOrBefore: runStartedAt)
                try await syncLearningPaths(userID: userID, accessToken: token)
                try ensureSameUser(userID)
                SyncPendingQueue.shared.remove(kind: .learningPaths, onlyIfLastRecordedOnOrBefore: runStartedAt)
                recordPathProgressForCompletedLessons()
                await PracticeStore.shared.syncPendingAttempts()
                try ensureSameUser(userID)
                await syncPathCertificates(userID: userID)
                try ensureSameUser(userID)
                // Full success. Entries recorded before this run
                // started are cleared; anything recorded mid-run
                // stays pending, and its debounced sync (scheduled
                // by noteLocalChange) runs as the follow-up.
                SyncPendingQueue.shared.removeAll(onlyIfLastRecordedOnOrBefore: runStartedAt)
                ProgressStore.shared.markSynced()
                lastSuccessfulSyncAt = Date()
                persistLastSuccessfulSync()
                refreshPendingFlags()
                lastError = nil
                return
            } catch SyncAbort.userChanged {
                // The signed-in user changed mid-sync. Abandon the
                // run quietly: pending state is kept, local data is
                // untouched, and nothing is written for the wrong
                // account. No error is surfaced; this is not a
                // failure of the new account's sync.
                NSLog("%@", "[SyncService] Sync abandoned: the signed-in user changed mid-sync. Pending state is kept.")
                return
            } catch {
                let category = syncFailureCategory(for: error)
                NSLog("%@", "[SyncService] Sync attempt \(attempt) of \(maxAttempts) failed (category: \(category)): \(error.localizedDescription)")
                // The failure itself is durable pending work: record
                // it so a restart still knows a sync is owed, even
                // when this run was triggered without queue entries.
                SyncPendingQueue.shared.record(kind: .general)
                setPending(true)
                lastError = error.localizedDescription
                switch category {
                case .auth, .terminal:
                    // Auth: the token was already fresh (see
                    // validAccessToken), so retrying now would loop
                    // without helping. Decode/server: the payload
                    // will not change by retrying immediately.
                    // Both keep pending state and retry on a later
                    // trigger (foreground, next local change).
                    return
                case .retryable:
                    guard attempt < maxAttempts else { return }
                    try? await Task.sleep(nanoseconds: delayNanoseconds)
                    delayNanoseconds *= 2
                    if !auth.isSignedIn || auth.currentUser?.id != userID {
                        return
                    }
                }
            }
        }
        // All attempts failed. Local progress is untouched and the
        // pending flag stays set, so the next trigger retries.
        // Nothing is lost.
    }

    /// Mark local progress as changed, so a sync picks it up soon.
    /// Records durable pending work and starts a debounced sync
    /// (about 2 seconds of quiet), coalescing bursts of changes into
    /// one run instead of firing one request per change. Safe to call
    /// from any thread and from views or stores with no async
    /// context: the durable record is written synchronously here,
    /// and the main-actor work hops through a task.
    nonisolated func noteLocalChange() {
        SyncPendingQueue.shared.record(kind: .general)
        Task { @MainActor in
            SyncService.shared.handleNotedLocalChange()
        }
    }

    /// Mark a specific kind of local change, with the identifiers
    /// involved when known (for example lesson IDs completed, or quiz
    /// attempt identities). Behaves like noteLocalChange(), and lets
    /// the durable queue record which tables have pending work.
    nonisolated func noteLocalChange(kind: SyncChangeKind, identifiers: [String] = []) {
        SyncPendingQueue.shared.record(kind: kind, identifiers: identifiers)
        Task { @MainActor in
            SyncService.shared.handleNotedLocalChange()
        }
    }

    /// Record that one lesson was completed locally.
    nonisolated func noteLessonCompleted(_ lessonID: String) {
        noteLocalChange(kind: .progress, identifiers: [lessonID])
    }

    /// Record that one quiz attempt was recorded locally. The
    /// identifier combines the lesson and the local attempt UUID so
    /// the queue entry names the attempt; the sync itself re-reads
    /// the local quiz history, it does not replay identifiers.
    nonisolated func noteQuizAttemptRecorded(lessonID: String, attemptID: UUID) {
        noteLocalChange(kind: .quizAttempts, identifiers: ["\(lessonID)|\(attemptID.uuidString)"])
    }

    /// Drop all pending sync work for the current account: the durable
    /// queue, the pending flags, the persisted last-sync date and any
    /// waiting debounced sync. Needed by account deletion, so a
    /// deleted account leaves no sync work behind. This drops only
    /// the "sync needed" record; it never touches local progress,
    /// which the deletion flow clears separately.
    func clearPendingOperations() {
        debounceTask?.cancel()
        debounceTask = nil
        SyncPendingQueue.shared.removeAll()
        lastSuccessfulSyncAt = nil
        persistLastSuccessfulSync()
        setPending(false)
        lastError = nil
    }

    // MARK: - Triggers and pending state

    /// Main-actor half of noteLocalChange(): flag the store pending
    /// and (re)start the debounced sync.
    private func handleNotedLocalChange() {
        ProgressStore.shared.markSyncPending()
        refreshPendingFlags()
        scheduleDebouncedSync()
    }

    /// Start (or restart) the debounced sync: wait for the quiet
    /// period, then run one sync. Every new local change cancels the
    /// waiting task and restarts the wait, so a burst of changes
    /// produces one run, not one run per change.
    private func scheduleDebouncedSync() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self.syncAll()
        }
    }

    /// Foreground trigger: sync when work is pending, when no sync
    /// has ever succeeded, or when the last successful sync is stale.
    /// A foreground return with a recent successful sync and no
    /// pending work does nothing, so returning to the app does not
    /// spam the server.
    private func syncIfNeededOnForeground() async {
        guard client.isConfigured, AuthService.shared.isSignedIn else { return }
        refreshPendingFlags()
        let isStale: Bool
        if let lastSync = lastSuccessfulSyncAt {
            isStale = Date().timeIntervalSince(lastSync) > staleThresholdSeconds
        } else {
            isStale = true
        }
        guard hasPendingChanges || isStale else { return }
        guard !isSyncing else {
            syncRequestedWhileRunning = true
            return
        }
        debounceTask?.cancel()
        debounceTask = nil
        await syncAll()
    }

    /// Set both pending flags together. They always agree.
    private func setPending(_ pending: Bool) {
        hasPendingSync = pending
        hasPendingChanges = pending
    }

    /// Re-read the pending flags from the durable queue.
    private func refreshPendingFlags() {
        setPending(SyncPendingQueue.shared.hasPending)
    }

    /// Re-read the persisted per-account sync state (last successful
    /// sync date and pending flags) for whoever is signed in now.
    /// Called on init and on sign-in, so a new account never inherits
    /// the previous account's displayed sync state.
    private func reloadPersistedSyncState() {
        lastSuccessfulSyncAt = persistedLastSuccessfulSync()
        refreshPendingFlags()
    }

    private var lastSyncDefaultsKey: String {
        AccountScopedStorage.currentKey(lastSyncBaseKey)
    }

    private func persistedLastSuccessfulSync() -> Date? {
        UserDefaults.standard.object(forKey: lastSyncDefaultsKey) as? Date
    }

    private func persistLastSuccessfulSync() {
        if let date = lastSuccessfulSyncAt {
            UserDefaults.standard.set(date, forKey: lastSyncDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastSyncDefaultsKey)
        }
    }

    // MARK: - Account guard and failure classification

    /// Thrown when the signed-in user changed mid-sync. The run is
    /// abandoned, never completed for the wrong account.
    private enum SyncAbort: Error {
        case userChanged
    }

    /// Throw SyncAbort.userChanged unless the given user is still the
    /// signed-in user. Checked before every table step and after
    /// every await that could span a sign-out or account switch, so a
    /// sync never mixes data between accounts.
    private func ensureSameUser(_ userID: String) throws {
        guard AuthService.shared.isSignedIn,
              AuthService.shared.currentUser?.id == userID else {
            throw SyncAbort.userChanged
        }
    }

    /// How a sync failure is handled: retry within this trigger,
    /// stop for auth, or stop for a decode/server problem.
    private enum SyncFailureCategory: CustomStringConvertible {
        case retryable
        case auth
        case terminal

        var description: String {
            switch self {
            case .retryable: return "retryable"
            case .auth: return "auth"
            case .terminal: return "terminal"
            }
        }
    }

    private func syncFailureCategory(for error: Error) -> SyncFailureCategory {
        if let supabaseError = error as? SupabaseError {
            switch supabaseError {
            case .network:
                return .retryable
            case .missingAccessToken:
                return .auth
            case .decoding, .notConfigured, .invalidURL:
                return .terminal
            case .http(let status, _):
                if status == 401 || status == 403 {
                    return .auth
                }
                if status == 429 || (500..<600).contains(status) {
                    return .retryable
                }
                return .terminal
            }
        }
        if error is URLError {
            return .retryable
        }
        return .terminal
    }

    /// Decode one table's server rows. A decoding failure is thrown
    /// with the table named in the log: it must NEVER be treated as
    /// an empty dataset, because an empty dataset would make the
    /// merge push local state over server state it never saw, and
    /// would hide the failure from every later retry.
    private func decodeServerRows<T: Decodable>(_ data: Data, as type: T.Type, table: String) throws -> [T] {
        do {
            return try client.decodeRows(data, as: type)
        } catch {
            NSLog("%@", "[SyncService] Could not decode server rows for table \(table) (\(data.count) bytes). Treating this as a sync failure, not as an empty dataset. Error: \(String(describing: error))")
            throw error
        }
    }

    // MARK: - Progress

    /// Pull server progress, merge with local progress, push only
    /// what the server does not have yet. Completion is monotonic:
    /// the merged set is the union, a lesson the server already has
    /// keeps its own completed_at and updated_at because it is never
    /// re-pushed, and local wins only for lessons the server has no
    /// record of.
    private func syncProgress(userID: String, accessToken: String) async throws {
        try ensureSameUser(userID)
        let store = ProgressStore.shared
        let local = store.exportProgressDictionary()
        let localCompleted = Set(local["completedLessonIDs"] as? [String] ?? [])

        // Pull the server rows for this user.
        let data = try await client.restGet(
            table: "user_progress",
            query: "select=user_id,lesson_id,completed,completed_at,updated_at&user_id=eq.\(userID)",
            accessToken: accessToken
        )
        let serverRows = try decodeServerRows(data, as: ServerProgressRow.self, table: "user_progress")
        let serverCompleted = Set(serverRows.filter { $0.completed }.map { $0.lessonID })

        // Import server lessons into the local store first, so the
        // device reflects the merged set even if the push fails. The
        // server's latest completed lesson also fills in the last
        // accessed lesson when this device has none yet.
        importServerProgress(serverRows: serverRows)

        // Merge: the union. Nothing is removed on either side. Only
        // local-only lessons are pushed; re-pushing the merged set
        // would re-stamp the server rows' completed_at and
        // updated_at with today.
        let localOnly = localCompleted.subtracting(serverCompleted)
        guard !localOnly.isEmpty else { return }
        try ensureSameUser(userID)

        // Push the new lessons as upserts. on_conflict makes a repeat
        // push update the same row instead of duplicating it.
        let now = ISO8601DateFormatter().string(from: Date())
        let rows = localOnly.map { lessonID in
            ServerProgressRow(
                userID: userID,
                lessonID: lessonID,
                completed: true,
                completedAt: now,
                updatedAt: now
            )
        }
        _ = try await client.restUpsert(
            table: "user_progress",
            rows: rows,
            onConflict: "user_id,lesson_id",
            accessToken: accessToken
        )
    }

    /// Fold server-completed lessons into the local store. Uses the
    /// import hook on ProgressStore, which unions and never deletes.
    /// The last accessed lesson is the server row with the latest
    /// completed_at; it is only used when this device has no last
    /// lesson yet (ProgressStore keeps its own when it has one).
    private func importServerProgress(serverRows: [ServerProgressRow]) {
        let completedIDs = serverRows.filter { $0.completed }.map { $0.lessonID }
        guard !completedIDs.isEmpty else { return }
        var dict: [String: Any] = [
            "completedLessonIDs": completedIDs,
            "quizScores": [:] as [String: Int]
        ]
        let formatter = ISO8601DateFormatter()
        let latest = serverRows
            .filter { $0.completed }
            .compactMap { row -> (lessonID: String, date: Date)? in
                guard let at = row.completedAt, let date = formatter.date(from: at) else { return nil }
                return (row.lessonID, date)
            }
            .max { $0.date < $1.date }
        if let latest {
            dict["lastLessonID"] = latest.lessonID
        }
        ProgressStore.shared.importProgress(from: dict)
    }

    // MARK: - Quiz attempts

    /// Push the FULL local quiz history the server does not have yet.
    /// Attempts are history and are never overwritten: a local attempt
    /// is pushed when no server row matches its lesson, correct count,
    /// total and timestamp. Best-score-only comparison is gone.
    /// Idempotency: quiz_attempts has no unique key (history table,
    /// server-generated id), so the write is a plain insert and the
    /// read-first dedupe above is what stops a retry from
    /// duplicating. A decode failure throws before any push, so a
    /// local attempt is never dropped because the server reply could
    /// not be read.
    private func syncQuizAttempts(userID: String, accessToken: String) async throws {
        try ensureSameUser(userID)
        let store = ProgressStore.shared
        let localAttempts = store.quizHistory.flatMap { $0.value }
        guard !localAttempts.isEmpty else { return }
        let data = try await client.restGet(
            table: "quiz_attempts",
            query: "select=*&user_id=eq.\(userID)",
            accessToken: accessToken
        )
        let serverAttempts = try decodeServerRows(data, as: QuizAttemptRow.self, table: "quiz_attempts")
        let formatter = ISO8601DateFormatter()
        let serverKeys = Set(serverAttempts.map { attempt in
            "\(attempt.lessonID)|\(attempt.correct)|\(attempt.total)|\(attempt.attemptedAt ?? "")"
        })
        let newRows = localAttempts.compactMap { attempt -> QuizAttemptRow? in
            let key = "\(attempt.lessonID)|\(attempt.correct)|\(attempt.total)|\(formatter.string(from: attempt.attemptedAt))"
            guard !serverKeys.contains(key) else { return nil }
            return QuizAttemptRow(
                userID: userID,
                lessonID: attempt.lessonID,
                correct: attempt.correct,
                total: attempt.total,
                score: attempt.correct,
                attemptedAt: formatter.string(from: attempt.attemptedAt)
            )
        }
        guard !newRows.isEmpty else { return }
        try ensureSameUser(userID)
        _ = try await client.restInsert(table: "quiz_attempts", rows: newRows, accessToken: accessToken)
    }

    /// Mirror local learning events to the learning_activity table as
    /// one row per day: lessons completed that day (from
    /// lessonCompleted events) and minutes (from recorded lesson and
    /// audio durations only, never estimated). The server rows are
    /// pulled first and each day keeps the higher of the local and
    /// server lessons and minutes, so another device's work is never
    /// overwritten and a repeat push changes nothing. The unique
    /// (user_id, activity_date) key makes a repeat push update the
    /// same row. Guests never reach this: syncAll is a no-op for them.
    private func syncLearningActivity(userID: String, accessToken: String) async throws {
        try ensureSameUser(userID)
        let store = ProgressStore.shared
        guard !store.events.isEmpty else { return }
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        var byDay: [String: (lessons: Int, seconds: Int)] = [:]
        for event in store.events {
            let day = dayFormatter.string(from: event.timestamp)
            var entry = byDay[day] ?? (lessons: 0, seconds: 0)
            if event.type == .lessonCompleted {
                entry.lessons += 1
            }
            if event.type == .lessonDuration || event.type == .audioListened {
                entry.seconds += event.durationSeconds ?? 0
            }
            byDay[day] = entry
        }
        let serverData = try await client.restGet(
            table: "learning_activity",
            query: "select=user_id,activity_date,lessons_completed,minutes&user_id=eq.\(userID)",
            accessToken: accessToken
        )
        let serverRows = try decodeServerRows(serverData, as: LearningActivityRow.self, table: "learning_activity")
        for row in serverRows {
            var entry = byDay[row.activityDate] ?? (lessons: 0, seconds: 0)
            entry.lessons = max(entry.lessons, row.lessonsCompleted)
            entry.seconds = max(entry.seconds, row.minutes * 60)
            byDay[row.activityDate] = entry
        }
        try ensureSameUser(userID)
        let rows = byDay.map { day, entry in
            LearningActivityRow(
                userID: userID,
                activityDate: day,
                lessonsCompleted: entry.lessons,
                minutes: entry.seconds / 60
            )
        }
        _ = try await client.restUpsert(
            table: "learning_activity",
            rows: rows,
            onConflict: "user_id,activity_date",
            accessToken: accessToken
        )
    }

    // MARK: - Bookmarks

    /// Sync lesson bookmarks: union of the device set and the server
    /// rows. Server-only bookmarks are added on this device, and
    /// local-only bookmarks are pushed. The upsert key
    /// (user_id, lesson_id) stops duplicates. Situation bookmarks
    /// have no server table and stay on the device only.
    private func syncBookmarks(userID: String, accessToken: String) async throws {
        try ensureSameUser(userID)
        let local = PFBookmarkStore.shared.lessonIDs
        let data = try await client.restGet(
            table: "lesson_bookmarks",
            query: "select=user_id,lesson_id&user_id=eq.\(userID)",
            accessToken: accessToken
        )
        let serverRows = try decodeServerRows(data, as: LessonBookmarkRow.self, table: "lesson_bookmarks")
        let serverIDs = Set(serverRows.map { $0.lessonID })
        try ensureSameUser(userID)
        for lessonID in serverIDs where !local.contains(lessonID) {
            PFBookmarkStore.shared.toggleLesson(lessonID)
        }
        let localOnly = local.subtracting(serverIDs)
        guard !localOnly.isEmpty else { return }
        try ensureSameUser(userID)
        let rows = localOnly.map { LessonBookmarkRow(userID: userID, lessonID: $0) }
        _ = try await client.restUpsert(
            table: "lesson_bookmarks",
            rows: rows,
            onConflict: "user_id,lesson_id",
            accessToken: accessToken
        )
    }

    // MARK: - Learning paths

    /// Sync learning path enrolments. Enrolment is derived, not
    /// stored locally: a path counts as enrolled when the learner
    /// completed at least one of its required lessons (resolved
    /// through LearningPath's chapter mapping against the loaded
    /// catalogue) or has a recorded path progress event. Progress is
    /// the completed share of the path's required lessons. Highest
    /// progress wins between this device and the server; progress
    /// never regresses. While the catalogue is still loading, the
    /// required lessons are empty and no path is pushed.
    private func syncLearningPaths(userID: String, accessToken: String) async throws {
        try ensureSameUser(userID)
        let store = ProgressStore.shared
        let service = ContentService.shared
        var localProgress: [String: Int] = [:]
        for path in LearningPath.all {
            let result = path.progress(in: store, service: service)
            guard result.total > 0, result.completed > 0 else { continue }
            localProgress[path.id] = Int((Double(result.completed) / Double(result.total) * 100).rounded())
        }
        // A path with a progress event but no completed required
        // lesson in the loaded catalogue still counts as enrolled.
        for path in LearningPath.all where localProgress[path.id] == nil {
            if let pct = store.pathCompletion(pathID: path.id) {
                localProgress[path.id] = pct
            }
        }
        guard !localProgress.isEmpty else { return }
        let data = try await client.restGet(
            table: "user_learning_paths",
            query: "select=user_id,path_id,enrolled_at,progress_pct&user_id=eq.\(userID)",
            accessToken: accessToken
        )
        let serverRows = try decodeServerRows(data, as: UserLearningPathRow.self, table: "user_learning_paths")
        var merged: [String: Int] = [:]
        for row in serverRows {
            merged[row.pathID] = row.progressPct
        }
        for (pathID, pct) in localProgress {
            merged[pathID] = max(merged[pathID] ?? 0, pct)
        }
        try ensureSameUser(userID)
        let rows = merged.map { pathID, pct in
            UserLearningPathRow(userID: userID, pathID: pathID, enrolledAt: nil, progressPct: pct)
        }
        _ = try await client.restUpsert(
            table: "user_learning_paths",
            rows: rows,
            onConflict: "user_id,path_id",
            accessToken: accessToken
        )
    }

    /// Record path progress for lessons completed inside a guided
    /// path. This is the P1 gap 6 call site: ProgressStore's
    /// markLessonComplete lives in LessonView, which this file does
    /// not own, so the hook runs here, batched into syncAll after
    /// the progress merge. It records only when the computed
    /// completion changed since the last recorded pathProgress event,
    /// so a sync never spams an event per view appearance or per run.
    /// While the catalogue is still loading, required lessons are
    /// empty and nothing is recorded.
    private func recordPathProgressForCompletedLessons() {
        let store = ProgressStore.shared
        let service = ContentService.shared
        for path in LearningPath.all {
            let result = path.progress(in: store, service: service)
            guard result.total > 0, result.completed > 0 else { continue }
            let pct = Int((Double(result.completed) / Double(result.total) * 100).rounded())
            guard store.pathCompletion(pathID: path.id) != pct else { continue }
            store.recordPathProgress(pathID: path.id, progressPct: pct)
        }
    }

    /// Backfill path certificates to the server so the website
    /// verification page can check them. Best effort only: it never
    /// throws and never fails syncAll. Each issued path certificate
    /// is derived exactly as CertificateView derives it, with the
    /// same learner-name order (signed-in name, then profile name);
    /// with no real name there is nothing to write, because
    /// learner_name must never be the "Guest Learner" fallback.
    /// While the catalogue is still loading, no path is complete and
    /// nothing is written. Each write is already silent inside
    /// PFCertificateStore, so a failed write here changes nothing
    /// about the rest of the sync. Nothing is written when the
    /// signed-in user no longer matches the sync run's user.
    private func syncPathCertificates(userID: String) async {
        guard AuthService.shared.isSignedIn,
              AuthService.shared.currentUser?.id == userID else {
            return
        }
        let auth = AuthService.shared
        let learnerName: String
        if let name = auth.currentUser?.displayName,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            learnerName = name
        } else if let name = auth.profile?.displayName,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            learnerName = name
        } else {
            return
        }
        let store = ProgressStore.shared
        let service = ContentService.shared
        let competency = CompetencyStore.shared
        for path in LearningPath.certificatePaths {
            guard let certificate = PFCertificateStore.certificate(
                for: path,
                progress: store,
                service: service,
                competency: competency,
                learnerName: learnerName
            ) else { continue }
            await PFCertificateStore.syncCertificateToServer(certificate)
        }
    }

    // MARK: - Preferences

    /// Sync learning preferences. Local is authoritative once the
    /// user has explicitly saved on this device: a stale server row
    /// never overwrites it. The server row is only used to restore
    /// preferences on a device that never saved them, and local is
    /// only pushed to the server when it was explicitly saved, so a
    /// default row is never created from untouched defaults. A sync
    /// run never overwrites an existing server row: only an explicit
    /// save pushes, through pushPreferences(). The weekly goal is not
    /// merged here: it lives only in ProgressStore.weeklyGoal, which
    /// is already loaded, and no server column is written for it.
    /// This rule is deliberately not last-write-wins by updated_at
    /// (see the file header): the local store keeps no updated_at to
    /// compare against the server row's.
    private func syncPreferences(userID: String, accessToken: String) async throws {
        try ensureSameUser(userID)
        let local = LearningPreferences.loadLocal()
        let localSaved = LearningPreferences.hasSavedLocally
        let data = try await client.restGet(
            table: "user_preferences",
            query: "select=*&user_id=eq.\(userID)",
            accessToken: accessToken
        )
        let serverRows = try decodeServerRows(data, as: LearningPreferences.self, table: "user_preferences")
        if let server = serverRows.first {
            if localSaved {
                // Local wins: the user saved on this device. The
                // server row is left alone; an explicit save pushes
                // through pushPreferences(), not through syncAll.
                return
            }
            // Never saved on this device: restore the account row.
            var merged = server
            merged.userID = userID
            merged.saveLocal()
            return
        }
        guard localSaved else {
            // No server row and nothing explicitly saved: do not
            // create a row from untouched defaults.
            return
        }
        try ensureSameUser(userID)
        var row = local
        row.userID = userID
        row.updatedAt = ISO8601DateFormatter().string(from: Date())
        _ = try await client.restUpsert(
            table: "user_preferences",
            rows: [row],
            onConflict: "user_id",
            accessToken: accessToken
        )
    }

    /// Pull the server preferences for the signed-in user, save them
    /// locally and return them. Returns nil for guests and when the
    /// server has no row (the local preferences stand). Used by the
    /// Learning Preferences screen so it shows the account's values,
    /// not stale device values, after a sign-in on another device.
    /// A decoding failure is surfaced in lastError and recorded as
    /// pending work instead of being silently treated as "no row":
    /// the local preferences still stand either way.
    func fetchPreferences() async -> LearningPreferences? {
        // Local is authoritative once explicitly saved; a server
        // fetch must never overwrite it. Callers fall back to local.
        guard !LearningPreferences.hasSavedLocally,
              client.isConfigured,
              let userID = AuthService.shared.currentUser?.id,
              let token = await AuthService.shared.validAccessToken() else {
            return nil
        }
        do {
            let data = try await client.restGet(
                table: "user_preferences",
                query: "select=*&user_id=eq.\(userID)",
                accessToken: token
            )
            let rows = try decodeServerRows(data, as: LearningPreferences.self, table: "user_preferences")
            guard var server = rows.first else { return nil }
            server.userID = userID
            server.saveLocal()
            return server
        } catch {
            if case SupabaseError.decoding(_) = error {
                NSLog("%@", "[SyncService] Could not decode server preferences; keeping local preferences and keeping the sync pending. Error: \(String(describing: error))")
                SyncPendingQueue.shared.record(kind: .preferences)
                setPending(true)
                lastError = error.localizedDescription
            }
            return nil
        }
    }

    /// Push one set of preferences now (called after the user saves on
    /// the Learning Preferences screen). No-op for guests. Returns
    /// true when the server confirmed the write, false when it did
    /// not: the caller must not claim the preferences synced when
    /// this is false. The local copy is already saved either way. A
    /// failed push records durable pending work so a later sync
    /// retries it.
    @discardableResult
    func pushPreferences(_ preferences: LearningPreferences) async -> Bool {
        let pushStartedAt = Date()
        guard client.isConfigured,
              let userID = AuthService.shared.currentUser?.id,
              let token = await AuthService.shared.validAccessToken() else {
            if AuthService.shared.isSignedIn {
                SyncPendingQueue.shared.record(kind: .preferences)
                setPending(true)
            }
            return false
        }
        var row = preferences
        row.userID = userID
        row.updatedAt = ISO8601DateFormatter().string(from: Date())
        do {
            try ensureSameUser(userID)
            _ = try await client.restUpsert(
                table: "user_preferences",
                rows: [row],
                onConflict: "user_id",
                accessToken: token
            )
            SyncPendingQueue.shared.remove(kind: .preferences, onlyIfLastRecordedOnOrBefore: pushStartedAt)
            return true
        } catch {
            SyncPendingQueue.shared.record(kind: .preferences)
            setPending(true)
            ProgressStore.shared.markSyncPending()
            lastError = error.localizedDescription
            return false
        }
    }
}
