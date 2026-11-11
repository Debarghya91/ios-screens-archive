// RecommendationService.swift
// PaymentForge iOS - Personalised recommendations (Phase 6).
//
// Recommendations are built only from real recorded data:
// CompetencyStore scores (from real assessments) and ProgressStore
// history (completed lessons and in-progress paths). Two sources,
// in this order:
// 1. Weakest dimension: the assessed dimension with the lowest
//    recorded score. Its chapters' not-yet-completed lessons are
//    suggested first, so the learner practises where they are
//    weakest.
// 2. Uncompleted path lessons: lessons of guided paths the learner
//    has started but not finished.
// When there is no recorded data at all (no assessment scores and no
// path progress), this returns an empty list and callers show
// nothing, rather than a generic list. No lesson is ever invented:
// every suggestion is a real catalogue entry the learner has not
// completed yet.
// No em dashes in any user-facing text.

import Foundation

/// One personalised recommendation: a real lesson and the real
/// reason it is suggested.
struct RecommendationItem: Identifiable {
    var id: String { lesson.id }
    let lesson: SearchEntry
    /// Why this lesson is suggested, from real recorded data.
    let reason: String
}

enum RecommendationService {
    /// Personalised recommendations, up to `limit` items. Empty when
    /// there is no recorded data to personalise from.
    static func recommendations(
        contentService: ContentService,
        progressStore: ProgressStore,
        competencyStore: CompetencyStore,
        limit: Int = 3
    ) -> [RecommendationItem] {
        var result: [RecommendationItem] = []
        var seen: Set<String> = []

        func append(_ lesson: SearchEntry, reason: String) {
            guard result.count < limit,
                  !progressStore.isLessonComplete(lesson.id),
                  seen.insert(lesson.id).inserted else { return }
            result.append(RecommendationItem(lesson: lesson, reason: reason))
        }

        // 1. Weakest assessed dimension first.
        if let weakest = weakestDimension(in: competencyStore) {
            let reason = "Weakest area: \(weakest.rawValue)"
            for number in weakest.chapterNumbers {
                for lesson in PFChapterHelper.lessons(forChapter: number, in: contentService) {
                    append(lesson, reason: reason)
                    if result.count >= limit { return result }
                }
            }
        }

        // 2. Uncompleted lessons of paths already started.
        for path in LearningPath.all {
            if result.count >= limit { break }
            let progress = path.progress(in: progressStore, service: contentService)
            guard progress.total > 0, progress.completed > 0, progress.completed < progress.total else { continue }
            for lesson in path.lessons(in: contentService) {
                append(lesson, reason: "Continue \(path.title)")
                if result.count >= limit { break }
            }
        }

        return result
    }

    /// The assessed dimension with the lowest recorded score, nil
    /// when no assessment has ever been recorded.
    static func weakestDimension(in competencyStore: CompetencyStore) -> CompetencyStore.CompetencyDimension? {
        guard competencyStore.hasAssessments else { return nil }
        return CompetencyStore.CompetencyDimension.allCases
            .compactMap { dimension -> (CompetencyStore.CompetencyDimension, Double)? in
                guard let score = competencyStore.score(for: dimension) else { return nil }
                return (dimension, score)
            }
            .min { $0.1 < $1.1 }?
            .0
    }
}
