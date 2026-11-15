// RecommendationEngine.swift
// Payments Training Hub iOS - Adaptive lesson recommendations from recorded
// evidence only: the learner's role route, completed lessons, quiz
// history, competency scores, revision schedule, and diagnostic
// score. No statistics are fabricated: every reason names its real
// evidence (a path name, a dimension name, or a recorded score).
//
// Ordering: the route head first (continue, next, or fresh start),
// then weak areas, then revision due today, then a diagnostic gap,
// then the rest of the route in order. When the route is exhausted,
// the guided sessions in order, then the catalogue in order, fill
// the list, so the engine returns a recommendation whenever any
// uncompleted lesson exists.
//
// Mastered exclusion: a completed lesson is never recommended as
// continue, next, or fresh start. A completed lesson counts as
// mastered when its best recorded quiz score reaches 80 percent, or
// when no quiz score was ever recorded for it (no quiz evidence).
// Mastered lessons surface only through revision, and only when
// RevisionService lists them as due today.
//
// The diagnostic score is a fraction from 0 to 1, as stored by
// OnboardingProfile: a score below 0.8 points at foundations.
// Knowledge level, objective, intensity and weekly target do not
// reorder recommendations: the role route is the ordering
// authority, and recorded evidence adapts within it.
// No em dashes in any user-facing text.

import Foundation

// MARK: - Recommendation kinds and values

enum RecommendationKind: String, Hashable {
    case continuePath
    case nextInPath
    case weakArea
    case revision
    case diagnosticGap
    case freshStart
}

struct LessonRecommendation: Identifiable, Hashable {
    let id: String
    let lesson: SearchEntry
    let reason: String
    let kind: RecommendationKind
}

// MARK: - Engine

enum RecommendationEngine {
    /// The quiz percentage that counts as mastered: 80 percent.
    /// Stored as a fraction to match ProgressStore quiz fractions.
    static let masteryThreshold: Double = 0.8

    /// The pure mastery rule, exposed for tests. A lesson counts as
    /// mastered when it is complete and either no quiz score was
    /// ever recorded for it, or its best recorded quiz score
    /// reaches the mastery threshold. Whether the lesson's page
    /// carries a quiz cannot be known from the search index, so a
    /// complete lesson with no recorded attempt is treated as
    /// having no quiz evidence, and therefore as mastered.
    static func isMastered(isComplete: Bool, bestQuizFraction: Double?) -> Bool {
        guard isComplete else { return false }
        guard let best = bestQuizFraction else { return true }
        return best >= masteryThreshold
    }

    /// Mastery for one lesson from the recorded progress store.
    /// The percentage check uses ProgressStore.bestQuizScore(for:),
    /// which returns a fraction: ProgressStore.quizScores holds
    /// best correct counts, not percentages, so it cannot express
    /// an 80 percent threshold.
    static func isMastered(lessonID: String, progress: ProgressStore) -> Bool {
        isMastered(
            isComplete: progress.isLessonComplete(lessonID),
            bestQuizFraction: progress.bestQuizScore(for: lessonID)
        )
    }

    /// The single best next lesson: the first recommendation.
    /// Returns nil when no recommendation can be made, for example
    /// while the catalogue is still loading.
    static func nextLesson(
        for profile: OnboardingProfile?,
        progress: ProgressStore,
        competency: CompetencyStore,
        service: ContentService
    ) -> LessonRecommendation? {
        recommendations(for: profile, progress: progress, competency: competency, service: service, limit: 1).first
    }

    /// Up to `limit` recommendations, in priority order. A nil
    /// profile (guest, or skipped onboarding) falls back to the
    /// guided-session order: the first incomplete lesson of the
    /// first incomplete session, then the rest in session order.
    /// A skipped profile is treated as no profile: its role was
    /// never chosen, so it must not steer the route.
    static func recommendations(
        for profile: OnboardingProfile?,
        progress: ProgressStore,
        competency: CompetencyStore,
        service: ContentService,
        limit: Int
    ) -> [LessonRecommendation] {
        guard limit > 0 else { return [] }
        let effectiveProfile: OnboardingProfile?
        if let profile, !profile.wasSkipped {
            effectiveProfile = profile
        } else {
            effectiveProfile = nil
        }
        let route = effectiveProfile.map { RoleRouteCatalogue.route(for: $0.role) }
        let routeLessons = route?.lessons(in: service) ?? guidedOrderLessons(in: service)
        let routeLabel = routeLabel(for: route)

        var results: [LessonRecommendation] = []
        var usedIDs: Set<String> = []
        func append(_ lesson: SearchEntry, kind: RecommendationKind, reason: String) {
            guard results.count < limit, usedIDs.insert(lesson.id).inserted else { return }
            results.append(LessonRecommendation(
                id: "\(kind.rawValue):\(lesson.id)",
                lesson: lesson,
                reason: reason,
                kind: kind
            ))
        }

        // 1. The route head: the first uncompleted lesson in route
        // order. Fresh start when nothing is complete yet, continue
        // when the route is already started, next when the learner
        // has completed lessons elsewhere but not on this route.
        let nothingCompleted = progress.completedLessonIDs.isEmpty
        let routeStarted = routeLessons.contains { progress.isLessonComplete($0.id) }
        if let head = routeLessons.first(where: { !progress.isLessonComplete($0.id) }) {
            if nothingCompleted {
                append(head, kind: .freshStart, reason: "Start here: the first lesson of \(routeLabel).")
            } else if routeStarted {
                append(head, kind: .continuePath, reason: "Continue \(routeLabel): the next lesson you have not completed yet.")
            } else {
                append(head, kind: .nextInPath, reason: "The first lesson of \(routeLabel).")
            }
        }

        // 2. Weak area from competency evidence: the lowest recorded
        // dimension score, when it is below 80 percent. The pick is
        // the first uncompleted lesson in that dimension's chapters.
        // A dimension with no recorded score is never called weak.
        if let (dimension, score) = weakestDimension(in: competency),
           score < masteryThreshold * 100 {
            let dimensionLessons = lessons(for: dimension, in: service)
            if let weak = dimensionLessons.first(where: { !progress.isLessonComplete($0.id) }) {
                append(
                    weak,
                    kind: .weakArea,
                    reason: "Your lowest recorded competency score is \(Int(score.rounded()))% in \(dimension.rawValue). This lesson is in that area."
                )
            }
        }

        // 3. Weak area from quiz evidence: completed lessons that
        // are not mastered and whose average quiz score is below 80
        // percent, lowest average first, at most two. Mastered
        // lessons never appear here: they surface only via revision.
        let weakQuizLessons = service.allLessons.compactMap { lesson -> (SearchEntry, Double)? in
            guard progress.isLessonComplete(lesson.id),
                  !isMastered(lessonID: lesson.id, progress: progress),
                  let average = progress.averageQuizScore(for: lesson.id),
                  average < masteryThreshold else { return nil }
            return (lesson, average)
        }.sorted { $0.1 < $1.1 }
        for (lesson, average) in weakQuizLessons.prefix(2) {
            append(
                lesson,
                kind: .weakArea,
                reason: "Your average quiz score for this lesson is \(Int((average * 100).rounded()))%. Worth another look."
            )
        }

        // 4. Revision: lessons RevisionService lists as due today,
        // in due order. This is the only way a mastered lesson
        // surfaces. Concepts that do not resolve to a catalogue
        // lesson are skipped, never invented.
        var lessonsByID: [String: SearchEntry] = [:]
        for lesson in service.allLessons {
            lessonsByID[lesson.id] = lesson
        }
        for concept in RevisionService.shared.dueToday {
            guard let lesson = lessonsByID[concept.id] else { continue }
            append(
                lesson,
                kind: .revision,
                reason: "Due for revision today, from your revision schedule."
            )
        }

        // 5. Diagnostic gap: a recorded diagnostic score below 80
        // percent points at foundations, so the first uncompleted
        // lesson of the Payments Fundamentals path is suggested.
        // The score is a fraction from 0 to 1, clamped into range
        // for profiles constructed directly instead of saved
        // through OnboardingStore.
        if let score = effectiveProfile?.diagnosticScore {
            let fraction = min(1, max(0, score))
            if fraction < masteryThreshold,
               let fundamentals = LearningPath.all.first(where: { $0.id == "fundamentals" }),
               let gap = fundamentals.firstIncompleteLesson(in: progress, service: service) {
                append(
                    gap,
                    kind: .diagnosticGap,
                    reason: "Your diagnostic score was \(Int((fraction * 100).rounded()))%. This foundations lesson is the suggested starting point."
                )
            }
        }

        // 6. The rest of the route, in route order.
        for lesson in routeLessons where !progress.isLessonComplete(lesson.id) {
            guard results.count < limit else { break }
            append(lesson, kind: .nextInPath, reason: "The next lesson in \(routeLabel), in order.")
        }

        // 7. Fallbacks when the route is exhausted: the guided
        // sessions in order, then the catalogue in order.
        if results.count < limit {
            for lesson in guidedOrderLessons(in: service) where !progress.isLessonComplete(lesson.id) {
                guard results.count < limit else { break }
                append(lesson, kind: .nextInPath, reason: "Next in the guided sessions, in order.")
            }
        }
        if results.count < limit {
            for lesson in service.allLessons where !progress.isLessonComplete(lesson.id) {
                guard results.count < limit else { break }
                append(lesson, kind: .nextInPath, reason: "Next uncompleted lesson in the catalogue, in catalogue order.")
            }
        }

        return results
    }

    // MARK: - Helpers

    /// The label used in reasons: the route's guided path when it
    /// names one that exists, otherwise the role route, otherwise
    /// the guided path for a nil profile.
    private static func routeLabel(for route: RoleRoute?) -> String {
        if let route, let path = route.learningPath() {
            return "the \(path.title) journey"
        }
        if let route {
            return "your \(route.title) route"
        }
        return "the guided sessions"
    }

    /// Every guided-session lesson in session order, deduped. Used
    /// for the nil-profile fallback and when a route is exhausted.
    private static func guidedOrderLessons(in service: ContentService) -> [SearchEntry] {
        var seen: Set<String> = []
        var result: [SearchEntry] = []
        for session in ContentService.guidedSessions {
            for lesson in PFChapterHelper.lessons(forSession: session, in: service) {
                if seen.insert(lesson.id).inserted {
                    result.append(lesson)
                }
            }
        }
        return result
    }

    /// The recorded dimension with the lowest score, or nil when
    /// nothing has been assessed yet.
    private static func weakestDimension(in competency: CompetencyStore) -> (CompetencyStore.CompetencyDimension, Double)? {
        competency.scores.min(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
    }

    /// Lessons in a dimension's chapters, in chapter order, deduped.
    /// Dimension chapters come from the CompetencyDimension
    /// extension in LearningPath.swift, resolved live.
    private static func lessons(for dimension: CompetencyStore.CompetencyDimension, in service: ContentService) -> [SearchEntry] {
        var seen: Set<String> = []
        var result: [SearchEntry] = []
        for number in dimension.chapterNumbers {
            for lesson in PFChapterHelper.lessons(forChapter: number, in: service) {
                if seen.insert(lesson.id).inserted {
                    result.append(lesson)
                }
            }
        }
        return result
    }
}
