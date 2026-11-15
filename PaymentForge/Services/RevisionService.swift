// RevisionService.swift
// PaymentForge iOS - Spaced repetition for completed lessons.
// Stored locally with UserDefaults, namespaced per account through
// AccountScopedStorage.
// Intervals, in days: same day (0), next day (1), day 3, day 7, day 30.
// On a correct recall the concept advances to the next interval; on an
// incorrect recall it resets to the same day. Nothing here invents
// content: a concept is always a real completed lesson.
// No em dashes in any user-facing text.

import Foundation
import Combine

/// Spaced repetition for lessons the learner wants to revise.
final class RevisionService: ObservableObject {
    static let shared = RevisionService()

    struct RevisionConcept: Identifiable, Codable {
        let id: String
        let title: String
        let kind: String
        var nextDue: Date
        var intervalDays: Int
        var correctCount: Int
        var incorrectCount: Int

        /// True when this concept is due for revision today or earlier.
        var isDueToday: Bool {
            nextDue <= Calendar.current.startOfDay(for: Date()).addingTimeInterval(24 * 60 * 60 - 1)
        }
    }

    private enum Keys {
        static let concepts = "pf.revisionConcepts.v1"
    }

    /// The intervals, in days, in order. Index 0 is "same day".
    static let intervals: [Int] = [0, 1, 3, 7, 30]

    private var concepts: [RevisionConcept] = [] {
        didSet { save(); refreshDerived() }
    }

    /// Suppresses save() while loading, so a reload into an account
    /// with no stored concepts does not write an empty list into
    /// that namespace (which would block guest migration for it).
    private var suppressSave = false

    private func withoutSaving(_ work: () -> Void) {
        let previous = suppressSave
        suppressSave = true
        defer { suppressSave = previous }
        work()
    }

    /// Concepts due for revision today, earliest due first.
    @Published private(set) var dueToday: [RevisionConcept] = []

    /// Concepts where incorrect recalls outnumber correct ones.
    @Published private(set) var weakConcepts: [RevisionConcept] = []

    /// All scheduled concepts, by next due date.
    var allConcepts: [RevisionConcept] {
        concepts.sorted { $0.nextDue < $1.nextDue }
    }

    /// True when a lesson is already scheduled for revision.
    func isScheduled(lessonID: String) -> Bool {
        concepts.contains { $0.id == lessonID }
    }

    /// Schedule a lesson for revision, due today. A lesson already
    /// scheduled is left untouched, so its interval is never reset by
    /// re-adding it.
    func scheduleLessonForRevision(lessonID: String, title: String) {
        guard !isScheduled(lessonID: lessonID) else { return }
        let concept = RevisionConcept(
            id: lessonID,
            title: title,
            kind: "Lesson",
            nextDue: Calendar.current.startOfDay(for: Date()),
            intervalDays: 0,
            correctCount: 0,
            incorrectCount: 0
        )
        concepts.append(concept)
    }

    /// Record one recall review. Correct advances to the next interval
    /// (staying at the longest interval once reached); incorrect resets
    /// to the same day.
    func recordReview(conceptID: String, correct: Bool) {
        guard let index = concepts.firstIndex(where: { $0.id == conceptID }) else { return }
        var concept = concepts[index]
        if correct {
            concept.correctCount += 1
            let current = Self.intervals.firstIndex(of: concept.intervalDays) ?? 0
            let next = min(current + 1, Self.intervals.count - 1)
            concept.intervalDays = Self.intervals[next]
        } else {
            concept.incorrectCount += 1
            concept.intervalDays = 0
        }
        let days = concept.intervalDays
        concept.nextDue = Calendar.current.date(
            byAdding: .day, value: days,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        concepts[index] = concept
    }

    /// Remove a concept from revision.
    func removeConcept(id: String) {
        concepts.removeAll { $0.id == id }
    }

    init() {
        load()
        refreshDerived()
    }

    /// Reload for the current account namespace, clearing the
    /// previous account's revision concepts first.
    func reloadForCurrentAccount() {
        withoutSaving { concepts = [] }
        load()
        refreshDerived()
    }

    private func refreshDerived() {
        let todayEnd = Calendar.current.startOfDay(for: Date()).addingTimeInterval(24 * 60 * 60 - 1)
        dueToday = concepts
            .filter { $0.nextDue <= todayEnd }
            .sorted { $0.nextDue < $1.nextDue }
        weakConcepts = concepts
            .filter { $0.incorrectCount > $0.correctCount }
            .sorted { $0.nextDue < $1.nextDue }
    }

    private func load() {
        AccountScopedStorage.adoptLegacyKey(Keys.concepts)
        guard let data = UserDefaults.standard.data(forKey: AccountScopedStorage.currentKey(Keys.concepts)),
              let decoded = try? JSONDecoder().decode([RevisionConcept].self, from: data) else { return }
        withoutSaving { concepts = decoded }
    }

    private func save() {
        guard !suppressSave else { return }
        if let data = try? JSONEncoder().encode(concepts) {
            UserDefaults.standard.set(data, forKey: AccountScopedStorage.currentKey(Keys.concepts))
        }
    }
}
