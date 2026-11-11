// PracticeStore.swift
// PaymentForge iOS - Practice Mode attempt storage.
// Attempts live in UserDefaults, so Practice Mode works fully for
// guests and offline. When a learner is signed in and Supabase is
// configured, each attempt is also mirrored to the practice_attempts
// table (see supabase/migrations/0004_practice_attempts.sql, which the
// project owner must run in the Supabase SQL editor before sync can
// succeed). A failed mirror never loses the attempt: it stays local
// with synced false and is retried by syncPendingAttempts.
// Why practice_attempts and not learning_activity: the existing
// learning_activity table is a per-day aggregate with only
// user_id, activity_date, lessons_completed and minutes, and a unique
// key on (user_id, activity_date). It has no event_type, situation_id
// or chosen-option column, so the per-attempt payload could not be
// stored there. practice_attempts holds exactly one row per attempt.
// No em dashes in any user-facing text.

import Foundation
import Combine

/// One row of the practice_attempts table.
private struct PracticeAttemptRow: Codable {
    let userID: String
    let situationID: String
    let chosenOptionIndex: Int
    let isCorrect: Bool
    let attemptedAt: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case situationID = "situation_id"
        case chosenOptionIndex = "chosen_option_index"
        case isCorrect = "is_correct"
        case attemptedAt = "attempted_at"
    }
}

/// Stores practice attempts locally and mirrors them to Supabase
/// for signed-in learners.
@MainActor
final class PracticeStore: ObservableObject {
    static let shared = PracticeStore()

    private enum Keys {
        static let attempts = "pf.practiceAttempts.v1"
    }

    private let client = SupabaseClient.shared

    /// All attempts on this device, newest last.
    @Published private(set) var attempts: [PracticeAttempt] = []

    var totalAttempts: Int { attempts.count }

    var correctCount: Int { attempts.filter { $0.isCorrect }.count }

    /// Recorded accuracy, 0 to 100. Nil when no attempt has been
    /// recorded yet; callers must not present 0 as a real score.
    var accuracy: Double? {
        guard !attempts.isEmpty else { return nil }
        return 100 * Double(correctCount) / Double(attempts.count)
    }

    /// True when at least one attempt is still waiting to be mirrored.
    var hasUnsyncedAttempts: Bool { attempts.contains { !$0.synced } }

    init() {
        load()
    }

    // MARK: - Recording

    /// Record one decision. The attempt is saved locally first, then
    /// mirrored in the background when the learner is signed in.
    /// Returns the recorded attempt.
    @discardableResult
    func recordAttempt(situationID: String, chosenOptionIndex: Int, isCorrect: Bool) -> PracticeAttempt {
        let attempt = PracticeAttempt(
            situationID: situationID,
            userID: AuthService.shared.currentUser?.id,
            chosenOptionIndex: chosenOptionIndex,
            isCorrect: isCorrect
        )
        attempts.append(attempt)
        save()
        Task { await mirror(attempt: attempt) }
        return attempt
    }

    /// Attempts for one situation, in the order they were made.
    func attempts(for situationID: String) -> [PracticeAttempt] {
        attempts.filter { $0.situationID == situationID }
    }

    /// The most recent attempt for one situation, if any.
    func lastAttempt(for situationID: String) -> PracticeAttempt? {
        attempts(for: situationID).last
    }

    // MARK: - Supabase mirror

    /// Mirror one attempt to the practice_attempts table. No-op for
    /// guests and when Supabase is not configured. A failure leaves
    /// synced false so the attempt is retried later.
    private func mirror(attempt: PracticeAttempt) async {
        guard let userID = attempt.userID,
              client.isConfigured,
              let token = await AuthService.shared.validAccessToken() else {
            return
        }
        let row = PracticeAttemptRow(
            userID: userID,
            situationID: attempt.situationID,
            chosenOptionIndex: attempt.chosenOptionIndex,
            isCorrect: attempt.isCorrect,
            attemptedAt: ISO8601DateFormatter().string(from: attempt.timestamp)
        )
        do {
            _ = try await client.restInsert(table: "practice_attempts", rows: [row], accessToken: token)
            markSynced(id: attempt.id)
        } catch {
            // Local attempt is kept with synced false. The next
            // syncPendingAttempts call retries it.
        }
    }

    /// Mirror every still-unsynced attempt for the signed-in user.
    /// Guest attempts (userID nil) are adopted into the signed-in
    /// account first, so practice done as a guest is not lost on
    /// sign-in. Already-synced attempts are never re-adopted.
    /// Safe to call any time; it is a no-op for guests and when
    /// Supabase is not configured.
    func syncPendingAttempts() async {
        guard client.isConfigured,
              AuthService.shared.isSignedIn,
              let userID = AuthService.shared.currentUser?.id,
              let token = await AuthService.shared.validAccessToken() else {
            return
        }
        for index in attempts.indices where !attempts[index].synced && attempts[index].userID == nil {
            let old = attempts[index]
            attempts[index] = PracticeAttempt(
                id: old.id,
                situationID: old.situationID,
                userID: userID,
                chosenOptionIndex: old.chosenOptionIndex,
                isCorrect: old.isCorrect,
                timestamp: old.timestamp,
                synced: false
            )
        }
        save()
        let pending = attempts.filter { !$0.synced && $0.userID == userID }
        guard !pending.isEmpty else { return }
        let rows = pending.map { attempt in
            PracticeAttemptRow(
                userID: userID,
                situationID: attempt.situationID,
                chosenOptionIndex: attempt.chosenOptionIndex,
                isCorrect: attempt.isCorrect,
                attemptedAt: ISO8601DateFormatter().string(from: attempt.timestamp)
            )
        }
        do {
            _ = try await client.restInsert(table: "practice_attempts", rows: rows, accessToken: token)
            for attempt in pending {
                markSynced(id: attempt.id)
            }
        } catch {
            // Attempts stay local with synced false for the next retry.
        }
    }

    private func markSynced(id: UUID) {
        guard let index = attempts.firstIndex(where: { $0.id == id }) else { return }
        attempts[index].synced = true
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Keys.attempts),
              let decoded = try? JSONDecoder().decode([PracticeAttempt].self, from: data) else {
            return
        }
        attempts = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(attempts) {
            UserDefaults.standard.set(data, forKey: Keys.attempts)
        }
    }
}
