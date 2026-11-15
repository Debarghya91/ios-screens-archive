// CommunityChallenge.swift
// PaymentForge iOS - Weekly community challenge.
//
// One real case per week, picked deterministically from the existing
// exception investigation catalogue (ExceptionCaseCatalogue), so
// every learner sees the same case in the same week and the case
// changes every Monday. No case is invented here: every weekly case
// is one of the 12 grounded lab cases, and the selection only
// indexes into that catalogue. The challenge reuses the lab's own
// scoring (ExceptionLabScoring), so a challenge score means exactly
// what a lab score means.
//
// The week is the ISO 8601 week (Monday to Sunday) in UTC, so the
// week boundary is the same on every device whatever the local time
// zone. The week key ("2026-W46") is the storage key and the display
// label; the week ordinal (year times 53 plus week number) is the
// selection index, so 12 consecutive weeks visit all 12 cases.
//
// Gating: this file changes no gating. The view applies the lab's
// existing rule to the same content (a case grounded in a
// non-free situation needs StoreManager.isSituationsUnlocked; a case
// grounded in a free-sample situation is open to all), read-only.
// D101 decided (hard-gate, v69): SituationsView gates locked
// situation detail, consistent with the lab hard-gating the same
// grounded content. The challenge follows the same rule because
// it reuses lab cases.
//
// Local-first, honestly labelled: there is no server backend for
// shared challenge results in this version. No Supabase table and
// no Edge Function exists for challenge scores (checked 12 Nov
// 2026: no leaderboard or challenge table in supabase/migrations,
// and no leaderboard code anywhere in the app). The leaderboard
// therefore shows only the learner's own progress, with an honest
// empty state, and never invents community rows, totals,
// participation counts, or testimonials. CommunityLeaderboardEntry
// and CommunityChallengeLeaderboard exist so a future shared board
// has a typed shape to fill; until a backend exists, the store
// always returns zero community entries. A shared board needs, at
// minimum: a server table for anonymous weekly aggregates, an Edge
// Function that accepts only a week key and a score (no name, no
// identifier, no device id), and a read endpoint returning
// anonymous rows only. Nothing in this file calls the network.
//
// Privacy: no name, no identifier, and no data leaves the device in
// this implementation. Attempts are stored on this device only,
// namespaced per account through AccountScopedStorage, mirroring
// ExceptionLabStore. The UI copy states this plainly.
// No em dashes in any user-facing text.

import Foundation
import Combine

// MARK: - Weekly selection

/// Deterministic weekly case selection from the existing lab
/// catalogue. Pure logic with no UI and no storage, so it can be
/// covered by unit tests.
enum CommunityChallenge {

    /// The ISO 8601 calendar in UTC, so week boundaries match on
    /// every device whatever the local time zone.
    private static var isoCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }

    /// The ISO week components for a date: the week-numbering year
    /// and the week number (1 to 53).
    static func weekComponents(for date: Date) -> (yearForWeekOfYear: Int, weekOfYear: Int) {
        let components = isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return (components.yearForWeekOfYear ?? 1970, components.weekOfYear ?? 1)
    }

    /// The storage and display key for the week containing a date,
    /// for example "2026-W46". The week number is zero padded.
    static func weekKey(for date: Date) -> String {
        let parts = weekComponents(for: date)
        let week = parts.weekOfYear < 10 ? "0\(parts.weekOfYear)" : "\(parts.weekOfYear)"
        return "\(parts.yearForWeekOfYear)-W\(week)"
    }

    /// A monotonic ordinal for the week containing a date: the
    /// week-numbering year times 53 plus the week number. Consecutive
    /// weeks have consecutive ordinals, so indexing the catalogue by
    /// ordinal modulo the catalogue size cycles through every case.
    static func weekOrdinal(for date: Date) -> Int {
        let parts = weekComponents(for: date)
        return parts.yearForWeekOfYear * 53 + parts.weekOfYear
    }

    /// The Monday starting the week containing a date, in UTC.
    static func weekStart(for date: Date) -> Date? {
        let parts = weekComponents(for: date)
        return isoCalendar.date(from: DateComponents(
            weekday: 2,
            weekOfYear: parts.weekOfYear,
            yearForWeekOfYear: parts.yearForWeekOfYear
        ))
    }

    /// The Sunday ending the week containing a date, in UTC.
    static func weekEnd(for date: Date) -> Date? {
        guard let start = weekStart(for: date) else { return nil }
        return isoCalendar.date(byAdding: .day, value: 6, to: start)
    }

    /// The weekly case for a week ordinal: the catalogue case at
    /// ordinal modulo the catalogue size. Nil only when the
    /// catalogue is empty, which it never is in a shipped build.
    static func caseForWeek(ordinal: Int) -> ExceptionCase? {
        let cases = ExceptionCaseCatalogue.allCases
        guard !cases.isEmpty else { return nil }
        let index = ((ordinal % cases.count) + cases.count) % cases.count
        return cases[index]
    }

    /// The weekly case for the week containing a date.
    static func caseFor(date: Date) -> ExceptionCase? {
        caseForWeek(ordinal: weekOrdinal(for: date))
    }

    /// The catalogue case with this id, for history rows that store
    /// only the case id. Nil when the catalogue no longer holds it.
    static func exceptionCase(forID caseID: String) -> ExceptionCase? {
        ExceptionCaseCatalogue.allCases.first { $0.id == caseID }
    }

    /// Shareable result text for one completed challenge. It names
    /// only the week, the case title, and the score: no answers, no
    /// takeaway, no name, and no identifier. The learner shares it
    /// through the standard share sheet; nothing is sent by the app.
    static func shareText(weekKey: String, caseTitle: String, total: Int, maximum: Int) -> String {
        "I completed the Payments Training Hub community challenge for week \(weekKey): \"\(caseTitle)\". I scored \(total) out of \(maximum)."
    }
}

// MARK: - Stored attempt

/// The stored result for one challenge week: the best score the
/// learner has earned on that week's case, how many times the week
/// has been completed, and the breakdown from the most recent
/// completion. Keyed by week key, so a retake of the same week
/// updates the same record and never lowers the best score.
struct CommunityChallengeAttempt: Codable, Hashable, Identifiable {
    let weekKey: String
    let caseID: String
    let bestTotal: Int
    let bestMaximum: Int
    let completions: Int
    let lastCompletedAt: Date
    let lastBreakdown: ExceptionLabScoreBreakdown

    var id: String { weekKey }
}

// MARK: - Leaderboard (local-first, honest)

/// One anonymous row for a future shared leaderboard. The label is
/// an anonymous placeholder assigned by the server (for example
/// "Learner 1"), never a name, handle, or identifier. No code in
/// this version creates one: there is no shared-results backend,
/// so the leaderboard always carries zero community entries. This
/// type exists so the future backend work has a typed shape and so
/// the anonymity rule is stated in code, not just in copy.
struct CommunityLeaderboardEntry: Codable, Hashable {
    let anonymousLabel: String
    let weekKey: String
    let total: Int
    let maximum: Int
}

/// What the leaderboard screen shows for one week: the community
/// rows, which are empty until a shared-results backend exists, and
/// the learner's own best attempt, which is the only real result
/// this version can show. The view must never render community rows
/// beyond this array, and must label the empty state honestly.
struct CommunityChallengeLeaderboard: Hashable {
    let weekKey: String
    let communityEntries: [CommunityLeaderboardEntry]
    let personalBest: CommunityChallengeAttempt?

    /// True only when real community rows exist. False in this
    /// version, always: no shared results have been collected.
    var hasCommunityData: Bool { !communityEntries.isEmpty }
}

// MARK: - Store

/// Stores community challenge attempts locally, per account. Device
/// only: nothing here leaves the device, and nothing is mirrored to
/// any server table, because no server table exists for challenge
/// scores. Mirrors ExceptionLabStore: the same key namespacing, the
/// same legacy adoption, and the same reload pattern on account
/// change, so one account's challenge results are never served to
/// another.
@MainActor
final class CommunityChallengeStore: ObservableObject {
    static let shared = CommunityChallengeStore()

    private enum Keys {
        static let attempts = "pf.communityChallengeAttempts.v1"
    }

    /// All attempts on this device, in the order the weeks were
    /// first completed.
    @Published private(set) var attempts: [CommunityChallengeAttempt] = []

    /// The learner's best attempt across all weeks: the highest best
    /// total, with the most recent completion winning a tie. Nil
    /// when no week has been completed yet.
    var personalBest: CommunityChallengeAttempt? {
        attempts.max(by: { ($0.bestTotal, $0.lastCompletedAt) < ($1.bestTotal, $1.lastCompletedAt) })
    }

    /// Week keys completed at least once.
    var completedWeekKeys: Set<String> {
        Set(attempts.map { $0.weekKey })
    }

    init() {
        load()
    }

    /// Reload for the current account namespace, clearing the
    /// previous account's attempts first. The coordinator calls this
    /// on account change; guest attempts reach an account only
    /// through the guest-to-account migration offer, which copies
    /// the namespaced key before this reload runs.
    func reloadForCurrentAccount() {
        attempts = []
        load()
    }

    // MARK: - Recording

    /// Record one completed weekly challenge. The best total for the
    /// week is kept; a lower retry never lowers it. The breakdown
    /// from this completion is kept as the most recent one. The
    /// case id is updated to the completed case, which only differs
    /// from a stored one when the catalogue changed between app
    /// updates mid-week.
    func recordCompletion(weekKey: String, caseID: String, breakdown: ExceptionLabScoreBreakdown) {
        if let index = attempts.firstIndex(where: { $0.weekKey == weekKey }) {
            let existing = attempts[index]
            attempts[index] = CommunityChallengeAttempt(
                weekKey: weekKey,
                caseID: caseID,
                bestTotal: max(existing.bestTotal, breakdown.total),
                bestMaximum: breakdown.maximum,
                completions: existing.completions + 1,
                lastCompletedAt: Date(),
                lastBreakdown: breakdown
            )
        } else {
            attempts.append(CommunityChallengeAttempt(
                weekKey: weekKey,
                caseID: caseID,
                bestTotal: breakdown.total,
                bestMaximum: breakdown.maximum,
                completions: 1,
                lastCompletedAt: Date(),
                lastBreakdown: breakdown
            ))
        }
        save()
    }

    /// The stored attempt for one week, if it has been completed.
    func attempt(forWeekKey weekKey: String) -> CommunityChallengeAttempt? {
        attempts.first { $0.weekKey == weekKey }
    }

    /// True when the week has been completed at least once.
    func isCompleted(weekKey: String) -> Bool {
        attempt(forWeekKey: weekKey) != nil
    }

    /// The leaderboard for one week: zero community entries (no
    /// shared-results backend exists) plus the learner's personal
    /// best. When a backend is built, this is the one place that
    /// gains community entries, from the server read endpoint only,
    /// never from invented data.
    func leaderboard(forWeekKey weekKey: String) -> CommunityChallengeLeaderboard {
        CommunityChallengeLeaderboard(
            weekKey: weekKey,
            communityEntries: [],
            personalBest: personalBest
        )
    }

    // MARK: - Persistence

    private func load() {
        AccountScopedStorage.adoptLegacyKey(Keys.attempts)
        guard let data = UserDefaults.standard.data(forKey: AccountScopedStorage.currentKey(Keys.attempts)),
              let decoded = try? JSONDecoder().decode([CommunityChallengeAttempt].self, from: data) else {
            return
        }
        attempts = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(attempts) {
            UserDefaults.standard.set(data, forKey: AccountScopedStorage.currentKey(Keys.attempts))
        }
    }
}
