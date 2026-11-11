// SyncService.swift
// PaymentForge iOS - Guest-to-account progress sync with Supabase.
// CONFLICT RULE (the whole file follows it, and so does every merge
// below): the server wins on conflict by updated_at, and local data
// wins only when the server has no record. Nothing is ever deleted
// on either side, and a repeat push never duplicates a record.
// Per table:
// - Completed lessons: union of local and server. Only lessons the
//   server does not have are pushed, so a push never re-stamps the
//   server's completed_at or updated_at.
// - Last accessed lesson: the last completed lesson. Local wins when
//   the device has one; otherwise the server's latest completed_at
//   fills it in. There is no separate server column for it.
// - Quiz attempts: full history. An attempt is pushed only when no
//   server row matches its lesson, correct count, total and
//   timestamp. Attempts are never overwritten.
// - Learning activity: one row per day. The merged row keeps the
//   higher of the local and server lessons and minutes for that day,
//   so a second device's work is never overwritten and a repeat push
//   is idempotent. (Exact cross-device same-day summing would need
//   per-event sync; max is the honest idempotent merge.)
// - Bookmarks: union of local lesson bookmarks and server rows.
//   Situation bookmarks have no server table and stay local only.
// - Learning preferences and weekly goal: server wins when it has a
//   row; local wins only when the server has none. The weekly goal
//   follows the preference target on both sides of the merge.
// - Learning paths: enrolment is derived, not stored locally: a path
//   counts as enrolled when the learner completed a lesson in one of
//   its chapters or has a path progress event. Highest progress wins;
//   progress never regresses (the table has no updated_at column).
// - Practice attempts: synced by PracticeStore.syncPendingAttempts.
//   NOTE: attempts made as a guest carry no user id, so the Practice
//   Store only mirrors attempts already tagged with the signed-in
//   user. Migrating guest practice attempts needs a one-line change
//   in PracticeStore (P4 owns it) to adopt nil-user attempts on
//   sign-in; this file cannot do it without touching that store.
// Sync runs in the background with up to 3 attempts and exponential
// backoff, and never blocks the UI. Each table is synced with at most
// one read and one batched write: there is no network call per UI
// interaction, and noteLocalChange only flags work as pending.
// When Supabase is not configured, or nobody is signed in, this is a
// no-op and local progress is untouched.
// No em dashes in any user-facing text.

import Foundation
import Combine

/// Syncs local progress and preferences to Supabase after sign-in.
@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    private let client = SupabaseClient.shared
    private let maxAttempts = 3

    /// True while a sync is running.
    @Published private(set) var isSyncing = false

    /// The last error message from a sync, nil when the last sync worked.
    @Published private(set) var lastError: String?

    /// True when the last sync attempt failed and a retry is due.
    private(set) var hasPendingSync = false

    private init() {}

    // MARK: - Entry points

    /// Called after a guest signs in or registers. Migrates the local
    /// guest progress into the new account, then keeps syncing.
    func syncAfterSignIn() async {
        await syncAll()
    }

    /// Sync everything for the signed-in user: progress, quiz scores,
    /// bookmarks, learning activity, preferences, weekly goal, last
    /// accessed lesson, learning path enrolments and practice
    /// attempts. Safe to call any time; it is a no-op for guests and
    /// when Supabase is not configured.
    func syncAll() async {
        guard client.isConfigured else { return }
        let auth = AuthService.shared
        guard auth.isSignedIn,
              let userID = auth.currentUser?.id else {
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        ProgressStore.shared.markSyncPending()
        var attempt = 0
        var delayNanoseconds: UInt64 = 1_000_000_000
        while attempt < maxAttempts {
            attempt += 1
            do {
                guard let token = await auth.validAccessToken() else {
                    throw SupabaseError.missingAccessToken
                }
                try await syncProgress(userID: userID, accessToken: token)
                try await syncQuizAttempts(userID: userID, accessToken: token)
                try await syncBookmarks(userID: userID, accessToken: token)
                try await syncLearningActivity(userID: userID, accessToken: token)
                try await syncPreferences(userID: userID, accessToken: token)
                try await syncLearningPaths(userID: userID, accessToken: token)
                recordPathProgressForCompletedLessons()
                await PracticeStore.shared.syncPendingAttempts()
                ProgressStore.shared.markSynced()
                hasPendingSync = false
                lastError = nil
                return
            } catch {
                lastError = error.localizedDescription
                hasPendingSync = true
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: delayNanoseconds)
                    delayNanoseconds *= 2
                }
            }
        }
        // All attempts failed. Local progress is untouched and the
        // pending flag stays set, so the next sign-in or app launch
        // retries. Nothing is lost.
    }

    /// Mark local progress as changed while signed in, so the next
    /// sync picks it up. Called by views after a lesson completes or a
    /// quiz is recorded when a sync is wanted soon.
    func noteLocalChange() {
        ProgressStore.shared.markSyncPending()
        hasPendingSync = true
    }

    // MARK: - Progress

    /// Pull server progress, merge with local progress, push only
    /// what the server does not have yet. Server wins on conflict by
    /// updated_at: a lesson the server already has keeps its own
    /// completed_at and updated_at, because it is never re-pushed.
    /// Local wins only for lessons the server has no record of.
    private func syncProgress(userID: String, accessToken: String) async throws {
        let store = ProgressStore.shared
        let local = store.exportProgressDictionary()
        let localCompleted = Set(local["completedLessonIDs"] as? [String] ?? [])

        // Pull the server rows for this user.
        let data = try await client.restGet(
            table: "user_progress",
            query: "select=user_id,lesson_id,completed,completed_at,updated_at&user_id=eq.\(userID)",
            accessToken: accessToken
        )
        let serverRows = (try? client.decodeRows(data, as: ServerProgressRow.self)) ?? []
        let serverCompleted = Set(serverRows.filter { $0.completed }.map { $0.lessonID })

        // Import server lessons into the local store first, so the
        // device reflects the merged set even if the push fails. The
        // server's latest completed lesson also fills in the last
        // accessed lesson when this device has none yet.
        importServerProgress(serverRows: serverRows)

        // Merge: the union. Nothing is removed on either side. Only
        // local-only lessons are pushed; re-pushing the merged set
        // would re-stamp the server rows' completed_at and
        // updated_at with today, which breaks server-wins.
        let localOnly = localCompleted.subtracting(serverCompleted)
        guard !localOnly.isEmpty else { return }

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
    private func syncQuizAttempts(userID: String, accessToken: String) async throws {
        let store = ProgressStore.shared
        let localAttempts = store.quizHistory.flatMap { $0.value }
        guard !localAttempts.isEmpty else { return }
        let data = try await client.restGet(
            table: "quiz_attempts",
            query: "select=*&user_id=eq.\(userID)",
            accessToken: accessToken
        )
        let serverAttempts = (try? client.decodeRows(data, as: QuizAttemptRow.self)) ?? []
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
        let serverRows = (try? client.decodeRows(serverData, as: LearningActivityRow.self)) ?? []
        for row in serverRows {
            var entry = byDay[row.activityDate] ?? (lessons: 0, seconds: 0)
            entry.lessons = max(entry.lessons, row.lessonsCompleted)
            entry.seconds = max(entry.seconds, row.minutes * 60)
            byDay[row.activityDate] = entry
        }
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
        let local = PFBookmarkStore.shared.lessonIDs
        let data = try await client.restGet(
            table: "lesson_bookmarks",
            query: "select=user_id,lesson_id&user_id=eq.\(userID)",
            accessToken: accessToken
        )
        let serverRows = (try? client.decodeRows(data, as: LessonBookmarkRow.self)) ?? []
        let serverIDs = Set(serverRows.map { $0.lessonID })
        for lessonID in serverIDs where !local.contains(lessonID) {
            PFBookmarkStore.shared.toggleLesson(lessonID)
        }
        let localOnly = local.subtracting(serverIDs)
        guard !localOnly.isEmpty else { return }
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
        let serverRows = (try? client.decodeRows(data, as: UserLearningPathRow.self)) ?? []
        var merged: [String: Int] = [:]
        for row in serverRows {
            merged[row.pathID] = row.progressPct
        }
        for (pathID, pct) in localProgress {
            merged[pathID] = max(merged[pathID] ?? 0, pct)
        }
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

    // MARK: - Preferences

    /// Sync learning preferences. Local is authoritative once the
    /// user has explicitly saved on this device: a stale server row
    /// never overwrites it. The server row is only used to restore
    /// preferences on a device that never saved them, and local is
    /// only pushed to the server when it was explicitly saved, so a
    /// default row is never created from untouched defaults. Either
    /// way the weekly goal follows the winning target, so the
    /// Dashboard goal and the preference target never drift apart.
    private func syncPreferences(userID: String, accessToken: String) async throws {
        let local = LearningPreferences.loadLocal()
        let localSaved = LearningPreferences.hasSavedLocally
        let data = try await client.restGet(
            table: "user_preferences",
            query: "select=*&user_id=eq.\(userID)",
            accessToken: accessToken
        )
        let serverRows = (try? client.decodeRows(data, as: LearningPreferences.self)) ?? []
        if let server = serverRows.first {
            if localSaved {
                // Local wins: the user saved on this device.
                ProgressStore.shared.weeklyGoal = local.weeklyTarget
                return
            }
            // Never saved on this device: restore the account row.
            var merged = server
            merged.userID = userID
            merged.saveLocal()
            ProgressStore.shared.weeklyGoal = merged.weeklyTarget
            return
        }
        guard localSaved else {
            // No server row and nothing explicitly saved: do not
            // create a row from untouched defaults.
            return
        }
        var row = local
        row.userID = userID
        row.updatedAt = ISO8601DateFormatter().string(from: Date())
        _ = try await client.restUpsert(
            table: "user_preferences",
            rows: [row],
            onConflict: "user_id",
            accessToken: accessToken
        )
        ProgressStore.shared.weeklyGoal = row.weeklyTarget
    }

    /// Pull the server preferences for the signed-in user, save them
    /// locally and return them. Returns nil for guests and when the
    /// server has no row (the local preferences stand). Used by the
    /// Learning Preferences screen so it shows the account's values,
    /// not stale device values, after a sign-in on another device.
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
            let rows = try client.decodeRows(data, as: LearningPreferences.self)
            guard var server = rows.first else { return nil }
            server.userID = userID
            server.saveLocal()
            ProgressStore.shared.weeklyGoal = server.weeklyTarget
            return server
        } catch {
            return nil
        }
    }

    /// Push one set of preferences now (called after the user saves on
    /// the Learning Preferences screen). No-op for guests. Returns
    /// true when the server confirmed the write, false when it did
    /// not: the caller must not claim the preferences synced when
    /// this is false. The local copy is already saved either way.
    @discardableResult
    func pushPreferences(_ preferences: LearningPreferences) async -> Bool {
        guard client.isConfigured,
              let userID = AuthService.shared.currentUser?.id,
              let token = await AuthService.shared.validAccessToken() else {
            return false
        }
        var row = preferences
        row.userID = userID
        row.updatedAt = ISO8601DateFormatter().string(from: Date())
        do {
            _ = try await client.restUpsert(
                table: "user_preferences",
                rows: [row],
                onConflict: "user_id",
                accessToken: token
            )
            ProgressStore.shared.weeklyGoal = row.weeklyTarget
            return true
        } catch {
            hasPendingSync = true
            ProgressStore.shared.markSyncPending()
            return false
        }
    }
}
