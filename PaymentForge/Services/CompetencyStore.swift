// CompetencyStore.swift
// Payments Training Hub iOS - Competency tracking from real assessments only.
// Stored locally with UserDefaults, namespaced per account through
// AccountScopedStorage.
// A dimension has no score until an assessment is taken for it: scores
// are never invented, seeded or estimated. Each assessment adds its
// correct/total to a running cumulative total per dimension, so the
// score is the learner's recorded accuracy across every assessment
// taken in that dimension.
// No em dashes in any user-facing text.

import Foundation
import Combine

/// Competency tracking, recorded from assessments only.
final class CompetencyStore: ObservableObject {
    static let shared = CompetencyStore()

    enum CompetencyDimension: String, CaseIterable, Codable {
        case architecture = "Payment architecture"
        case lifecycle = "Transaction lifecycle"
        case businessAnalysis = "Business analysis"
        case exceptionHandling = "Exception handling"
        case reconciliation = "Reconciliation and settlement"

        /// Short label for compact rows.
        var shortName: String {
            switch self {
            case .architecture: return "Architecture"
            case .lifecycle: return "Lifecycle"
            case .businessAnalysis: return "Business analysis"
            case .exceptionHandling: return "Exceptions"
            case .reconciliation: return "Reconciliation"
            }
        }

        /// SF Symbol for the dimension row.
        var systemImage: String {
            switch self {
            case .architecture: return "building.2.fill"
            case .lifecycle: return "arrow.left.arrow.right"
            case .businessAnalysis: return "doc.text.fill"
            case .exceptionHandling: return "exclamationmark.triangle.fill"
            case .reconciliation: return "checkmark.seal.fill"
            }
        }
    }

    private enum Keys {
        static let totals = "pf.competencyTotals.v1"
    }

    private struct Totals: Codable {
        var correct: Int = 0
        var total: Int = 0
    }

    /// Cumulative recorded totals per dimension, persisted.
    private var totals: [CompetencyDimension: Totals] = [:] {
        didSet { save(); refreshScores() }
    }

    /// Suppresses save() while loading, so a reload into an account
    /// with no stored totals does not write an empty set into that
    /// namespace (which would block guest migration for it).
    private var suppressSave = false

    private func withoutSaving(_ work: () -> Void) {
        let previous = suppressSave
        suppressSave = true
        defer { suppressSave = previous }
        work()
    }

    /// Recorded score per dimension, 0 to 100. A dimension is absent
    /// until an assessment has been taken for it.
    @Published private(set) var scores: [CompetencyDimension: Double] = [:]

    /// Mean of the assessed dimensions only. 0 when nothing has been
    /// assessed yet; callers must check `hasAssessments` before
    /// presenting this as a real score.
    var overallScore: Double {
        guard !scores.isEmpty else { return 0 }
        return scores.values.reduce(0, +) / Double(scores.count)
    }

    /// True when at least one assessment has been recorded.
    var hasAssessments: Bool { !scores.isEmpty }

    var overallLevel: String {
        guard hasAssessments else { return "Not assessed yet" }
        if overallScore < 50 { return "Beginner" }
        if overallScore <= 75 { return "Intermediate" }
        return "Advanced"
    }

    /// Score for one dimension, nil when it has never been assessed.
    func score(for dimension: CompetencyDimension) -> Double? {
        scores[dimension]
    }

    /// Record one assessment result for a dimension. Adds to the
    /// cumulative recorded total; nothing is averaged with invented data.
    func recordAssessment(dimension: CompetencyDimension, correct: Int, total: Int) {
        guard total > 0, correct >= 0, correct <= total else { return }
        var entry = totals[dimension] ?? Totals()
        entry.correct += correct
        entry.total += total
        totals[dimension] = entry
    }

    init() {
        load()
        refreshScores()
    }

    /// Reload for the current account namespace, clearing the
    /// previous account's scores first.
    func reloadForCurrentAccount() {
        withoutSaving { totals = [:] }
        load()
        refreshScores()
    }

    private func refreshScores() {
        var next: [CompetencyDimension: Double] = [:]
        for (dimension, entry) in totals where entry.total > 0 {
            next[dimension] = 100 * Double(entry.correct) / Double(entry.total)
        }
        scores = next
    }

    private func load() {
        AccountScopedStorage.adoptLegacyKey(Keys.totals)
        guard let data = UserDefaults.standard.data(forKey: AccountScopedStorage.currentKey(Keys.totals)),
              let decoded = try? JSONDecoder().decode([String: Totals].self, from: data) else { return }
        var restored: [CompetencyDimension: Totals] = [:]
        for (key, value) in decoded {
            if let dimension = CompetencyDimension(rawValue: key) {
                restored[dimension] = value
            }
        }
        withoutSaving { totals = restored }
    }

    private func save() {
        guard !suppressSave else { return }
        var raw: [String: Totals] = [:]
        for (dimension, value) in totals {
            raw[dimension.rawValue] = value
        }
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: AccountScopedStorage.currentKey(Keys.totals))
        }
    }
}
