// InvestigationStore.swift
// Investigation Experience result storage.
//
// Results live in UserDefaults, namespaced per account through
// AccountScopedStorage, mirroring ExceptionLabStore: the same key
// namespacing, the same legacy adoption, and the same reload pattern
// on account change, so one account's results are never served to
// another. Results are device-only and are never mirrored to any
// server table: no server table exists for investigation results,
// and no sync is flagged and no Supabase call is made from this
// file. No em dashes in any user-facing text.

import Foundation
import Combine

/// Stores investigation results locally, per account. Device only:
/// nothing here leaves the device.
@MainActor
final class InvestigationStore: ObservableObject {
    static let shared = InvestigationStore()

    private enum Keys {
        static let results = "pf.investigationResults.v1"
    }

    /// All results on this device, in the order the cases were
    /// first completed.
    @Published private(set) var results: [InvestigationResult] = []

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

    /// Record one completed investigation. The best overall score
    /// for the case is kept; a lower retry never lowers it. The
    /// stored difficulty follows the run that set the best score.
    /// The report from this completion is kept as the most recent
    /// one.
    func recordCompletion(result report: InvestigationReport) {
        let overall = report.dimensionScores.overall
        if let index = results.firstIndex(where: { $0.caseID == report.caseID }) {
            let existing = results[index]
            let isNewBest = overall >= existing.bestOverall
            results[index] = InvestigationResult(
                caseID: report.caseID,
                situationID: report.situationID,
                difficulty: isNewBest ? report.difficulty : existing.difficulty,
                bestOverall: max(existing.bestOverall, overall),
                completions: existing.completions + 1,
                lastCompletedAt: report.completedAt,
                lastReport: report
            )
        } else {
            results.append(InvestigationResult(
                caseID: report.caseID,
                situationID: report.situationID,
                difficulty: report.difficulty,
                bestOverall: overall,
                completions: 1,
                lastCompletedAt: report.completedAt,
                lastReport: report
            ))
        }
        save()
    }

    /// The stored result for one case, if it has been completed.
    func result(for caseID: String) -> InvestigationResult? {
        results.first { $0.caseID == caseID }
    }

    /// True when the case has been completed at least once.
    func isCompleted(_ caseID: String) -> Bool {
        result(for: caseID) != nil
    }

    /// The best overall score for one case, or nil when it has never
    /// been completed.
    func bestOverall(for caseID: String) -> Int? {
        result(for: caseID)?.bestOverall
    }

    // MARK: - Persistence

    private func load() {
        AccountScopedStorage.adoptLegacyKey(Keys.results)
        guard let data = UserDefaults.standard.data(forKey: AccountScopedStorage.currentKey(Keys.results)),
              let decoded = try? JSONDecoder().decode([InvestigationResult].self, from: data) else {
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
