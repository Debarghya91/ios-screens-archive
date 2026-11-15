// ExceptionLabStore.swift
// PaymentForge iOS - Investigation Lab score storage.
//
// Lab results live in UserDefaults, namespaced per account through
// AccountScopedStorage, mirroring PracticeStore: the same key
// namespacing, the same legacy adoption, and the same reload pattern
// on account change, so one account's lab scores are never served to
// another. Unlike PracticeStore, results are never mirrored to any
// server table: no server table exists for lab scores, and the UI
// says so plainly ("Your lab scores stay on this device."). No sync
// is flagged and no Supabase call is made from this file.
// No em dashes in any user-facing text.

import Foundation
import Combine

/// The stored result for one investigation case: the best score the
/// learner has earned on it, how many times it has been completed,
/// and the breakdown from the most recent completion.
struct ExceptionLabResult: Codable, Hashable, Identifiable {
    let caseID: String
    let bestTotal: Int
    let bestMaximum: Int
    let completions: Int
    let lastCompletedAt: Date
    let lastBreakdown: ExceptionLabScoreBreakdown

    var id: String { caseID }
}

/// Stores investigation lab results locally, per account. Device
/// only: nothing here leaves the device.
@MainActor
final class ExceptionLabStore: ObservableObject {
    static let shared = ExceptionLabStore()

    private enum Keys {
        static let results = "pf.exceptionLabResults.v1"
    }

    /// All results on this device, in the order the cases were
    /// first completed.
    @Published private(set) var results: [ExceptionLabResult] = []

    /// Ids of the cases completed at least once.
    var completedCaseIDs: Set<String> {
        Set(results.map { $0.caseID })
    }

    /// How many cases have been completed at least once.
    var completedCount: Int { results.count }

    init() {
        load()
    }

    /// Reload for the current account namespace, clearing the
    /// previous account's results first. The coordinator calls this
    /// on account change; guest results reach an account only
    /// through the guest-to-account migration offer, which copies
    /// the namespaced key before this reload runs.
    func reloadForCurrentAccount() {
        results = []
        load()
    }

    // MARK: - Recording

    /// Record one completed investigation. The best total for the
    /// case is kept; a lower retry never lowers it. The breakdown
    /// from this completion is kept as the most recent one.
    func recordCompletion(caseID: String, breakdown: ExceptionLabScoreBreakdown) {
        if let index = results.firstIndex(where: { $0.caseID == caseID }) {
            let existing = results[index]
            results[index] = ExceptionLabResult(
                caseID: caseID,
                bestTotal: max(existing.bestTotal, breakdown.total),
                bestMaximum: breakdown.maximum,
                completions: existing.completions + 1,
                lastCompletedAt: Date(),
                lastBreakdown: breakdown
            )
        } else {
            results.append(ExceptionLabResult(
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

    /// The stored result for one case, if it has been completed.
    func result(for caseID: String) -> ExceptionLabResult? {
        results.first { $0.caseID == caseID }
    }

    /// True when the case has been completed at least once.
    func isCompleted(_ caseID: String) -> Bool {
        result(for: caseID) != nil
    }

    // MARK: - Persistence

    private func load() {
        AccountScopedStorage.adoptLegacyKey(Keys.results)
        guard let data = UserDefaults.standard.data(forKey: AccountScopedStorage.currentKey(Keys.results)),
              let decoded = try? JSONDecoder().decode([ExceptionLabResult].self, from: data) else {
            return
        }
        results = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(results) {
            UserDefaults.standard.set(data, forKey: AccountScopedStorage.currentKey(Keys.results))
        }
    }
}
