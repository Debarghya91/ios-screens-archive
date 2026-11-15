// ProgressInsights.swift
// PaymentForge iOS - Pure progress computations for My Progress.
//
// Every function here is pure: it takes recorded values in and
// returns a summary, with no store access, no persistence, no
// network and no side effect. DashboardView supplies the recorded
// values from the existing stores and presents the results. Tests
// construct the inputs directly, so no test touches UserDefaults.
//
// Activity and demonstrated competence are kept apart on purpose.
// Completing or opening a lesson is activity. Demonstrated
// competence is only quiz, assessment and lab evidence: a quiz
// fraction, a competency score, a Final Assessment result, or a
// lab score. A completed lesson with no quiz attempt is reported
// as having no quiz evidence; it is never called demonstrated.
// This differs deliberately from RecommendationEngine.isMastered,
// which treats a completed lesson with no recorded attempt as
// mastered for recommendation ordering only (D82). That ordering
// rule must never be reused as a competence claim.
//
// Quiz fractions: ProgressStore.quizScores holds best correct
// COUNTS, not percents (D82), so no function here reads it. Every
// quiz computation uses QuizAttempt fractions (correct over total)
// from quizHistory. Attempts with no recorded total (total 0, from
// the old best-score-only store) count as attempts but contribute
// no fraction, and are reported separately, never averaged in.
// Fractions are clamped to 0 through 1, so a stored attempt with
// correct above total cannot push an average above 100 percent.
//
// Thresholds: the quiz demonstration bar is
// RecommendationEngine.masteryThreshold (0.8), reused, not copied.
// The competency bar is 80 on the 0 to 100 competency scale, chosen
// to match that same 80 percent bar. It is not the
// CompetencyStore.overallLevel bands (50 and 75), which describe
// levels, not evidence strength. Lab scores have no pass mark in
// the code, so none is invented here: lab results are reported as
// fractions and counts only.
//
// Competency dimensions are not the catalogue domains
// (ContentManifest.domainCount). The app has no domain grouping
// for lessons (Chapter and Domain exist in ContentModels but no
// catalogue builds them), so grouped knowledge is reported per
// competency dimension, using each dimension's chapter list, and
// labelled as such. See the discrepancy report.
//
// No em dashes in any user-facing text.

import Foundation

// MARK: - Quiz summaries

/// Quiz evidence across all lessons, from quizHistory only.
/// Averages are means of attempt fractions, matching
/// ProgressStore.averageQuizScore semantics: each attempt counts
/// once, and only attempts with a recorded total contribute.
struct ProgressQuizSummary: Equatable {
    /// Every recorded attempt, including attempts with no total.
    let totalAttempts: Int
    /// Attempts that recorded a total and contribute a fraction.
    let attemptsWithTotal: Int
    /// Attempts with no recorded total. Counted, never averaged.
    let attemptsWithoutTotal: Int
    /// Lessons with at least one recorded attempt.
    let lessonsAttempted: Int
    /// Mean fraction correct across attempts with a total.
    /// Nil when no attempt recorded a total.
    let averageFraction: Double?
    /// Best fraction correct across attempts with a total.
    /// Nil when no attempt recorded a total.
    let bestFraction: Double?
    /// Lessons whose best fraction reaches the demonstration bar.
    let demonstratedLessonCount: Int
    /// Lessons with an attempt whose best fraction is below the
    /// bar, or has no fraction because no total was recorded.
    let attemptedNotDemonstratedLessonCount: Int
}

/// Quiz evidence for one lesson, from its recorded attempts.
struct ProgressLessonQuizEvidence: Equatable {
    let lessonID: String
    /// Every recorded attempt for the lesson.
    let attemptCount: Int
    /// Attempts that recorded a total.
    let attemptsWithTotal: Int
    /// Mean fraction correct, nil when no attempt has a total.
    let averageFraction: Double?
    /// Best fraction correct, nil when no attempt has a total.
    let bestFraction: Double?

    /// True when the best recorded fraction reaches the
    /// demonstration bar. False when no fraction was recorded:
    /// no evidence is never treated as demonstrated here.
    var isDemonstrated: Bool {
        guard let bestFraction else { return false }
        return bestFraction >= RecommendationEngine.masteryThreshold
    }

    /// True when at least one attempt was recorded, with or
    /// without a total.
    var hasAttempt: Bool { attemptCount > 0 }
}

/// Completed lessons split by quiz evidence: demonstrated,
/// attempted but below the bar, and no quiz attempt recorded.
/// The three counts sum to the number of completed lessons passed
/// in. Lessons that were never completed are not counted here.
struct ProgressDemonstratedSummary: Equatable {
    let completedLessonCount: Int
    let demonstratedLessonCount: Int
    let attemptedNotDemonstratedCount: Int
    let noQuizEvidenceCount: Int
}

// MARK: - Grouped knowledge

/// Knowledge in one competency dimension, from two independent
/// evidence sources: the recorded competency score for the
/// dimension (assessment correct over total, 0 to 100), and the
/// quiz fractions of lessons in the dimension's chapters.
/// Lesson completion in the dimension is activity, shown
/// separately, and never feeds the evidence judgement.
struct ProgressDimensionInsight: Equatable, Identifiable {
    let dimension: CompetencyStore.CompetencyDimension
    var id: CompetencyStore.CompetencyDimension { dimension }

    /// Recorded competency score, 0 to 100. Nil when the
    /// dimension has never been assessed.
    let competencyScorePercent: Double?
    /// Mean quiz fraction across attempts with a total, for
    /// lessons in the dimension's chapters. Nil when no such
    /// attempt recorded a total.
    let quizAverageFraction: Double?
    /// Every quiz attempt for lessons in the dimension's chapters.
    let quizAttemptCount: Int
    /// Attempts that recorded a total and feed the average.
    let quizAttemptsWithTotal: Int
    /// Attempts with no recorded total.
    let quizAttemptsWithoutTotal: Int
    /// Lessons in the dimension's chapters with a best fraction
    /// at or above the demonstration bar.
    let demonstratedLessonCount: Int
    /// Lessons completed in the dimension's chapters (activity).
    let lessonsCompleted: Int
    /// Lessons in the dimension's chapters in the catalogue
    /// passed in. Zero while the catalogue is loading.
    let lessonsTotal: Int

    /// True when either evidence source has a value.
    var hasAnyEvidence: Bool {
        competencyScorePercent != nil || quizAverageFraction != nil
    }

    /// Completed share, nil when the dimension has no lessons in
    /// the catalogue passed in (loading), so a loading state is
    /// never shown as 0 percent.
    var fractionCompleted: Double? {
        guard lessonsTotal > 0 else { return nil }
        return Double(lessonsCompleted) / Double(lessonsTotal)
    }
}

/// Whether the evidence for one dimension is stronger or needs
/// attention. Wording is about evidence, never about the learner:
/// no dimension is called weak, and no learner is called
/// proficient. A dimension with no evidence is in neither list.
enum ProgressAreaKind: Equatable {
    case strongerEvidence
    case needsAttention
}

/// One dimension placed by its evidence, with the evidence stated
/// in words. The evidence text names every source that exists and
/// says plainly when a source is missing, so the placement can
/// always be checked against the numbers.
struct ProgressEvidenceArea: Equatable, Identifiable {
    let dimension: CompetencyStore.CompetencyDimension
    var id: CompetencyStore.CompetencyDimension { dimension }
    let kind: ProgressAreaKind
    let competencyScorePercent: Double?
    let quizAverageFraction: Double?
    let quizAttemptsWithTotal: Int
    let evidenceText: String
}

// MARK: - Lab, time, consistency, activity

/// Investigation lab performance, from stored lab results.
/// ExceptionLabStore records real scores (best total and maximum
/// per case, plus the breakdown of the most recent completion),
/// so this summary reports scores honestly. Breakdown aggregates
/// come from the most recent completion of each case only; the
/// store keeps no history of earlier breakdowns.
struct ProgressLabSummary: Equatable {
    /// Cases completed at least once.
    let casesCompleted: Int
    /// Cases in the catalogue passed in as the total.
    let totalCases: Int
    /// Every recorded completion, including repeats.
    let totalCompletions: Int
    /// Mean of the best fraction per completed case. Nil when no
    /// completed case recorded a maximum above zero.
    let meanBestFraction: Double?
    /// Lowest best fraction among completed cases, nil as above.
    let lowestBestFraction: Double?
    /// Highest best fraction among completed cases, nil as above.
    let highestBestFraction: Double?
    /// Steps solved on the first pick, summed over the most
    /// recent completion of each case.
    let stepsSolvedBestFirst: Int
    /// Steps solved after a wrong turn, same scope as above.
    let stepsSolvedAfterWrongTurn: Int
    /// Wrong picks, summed over the most recent completion of
    /// each case.
    let totalWrongPicks: Int
    /// Red herring picks, same scope as above.
    let totalRedHerringPicks: Int
    /// Genuine evidence items opened, same scope as above.
    let evidenceOpenedCount: Int
    /// Genuine evidence items available, same scope as above.
    let evidenceTotalCount: Int
}

/// One completed lab case, with its best recorded score.
struct ProgressLabCaseInsight: Equatable, Identifiable {
    let caseID: String
    var id: String { caseID }
    let bestTotal: Int
    let bestMaximum: Int
    /// Best fraction, nil when the maximum is not above zero.
    let bestFraction: Double?
    let completions: Int
    let lastCompletedAt: Date
}

/// Recorded learning time, split by event type. Only durations
/// the app actually measured are counted: lessonDuration events
/// and audioListened events. Audio time is recorded only when
/// narration plays to the end; partial listens are not recorded,
/// and reading, quiz, lab and studio time are never recorded, so
/// this total understates real study time and must be labelled
/// as recorded time only.
struct ProgressTimeInsight: Equatable {
    let lessonDurationSeconds: Int
    let audioSeconds: Int
    let totalSeconds: Int
    /// Events carrying a lesson duration value.
    let lessonDurationEventCount: Int
    /// Events carrying an audio duration value.
    let audioEventCount: Int

    var hasRecordedTime: Bool { totalSeconds > 0 }
}

/// Learning consistency from real event dates. Neutral counts
/// only: active days, the streak ending at the reference date,
/// and the most recent activity date. Nothing here judges the
/// learner, and no missed day is ever named. Events are the
/// retained events kept on the device (ProgressStore caps the
/// stored list), so long range counts are lower bounds.
struct ProgressConsistencyInsight: Equatable {
    /// Distinct days with at least one event in the 7 days ending
    /// on the reference date, inclusive.
    let activeDaysLast7: Int
    /// Distinct days with at least one event in the 28 days
    /// ending on the reference date, inclusive.
    let activeDaysLast28: Int
    /// Distinct days with at least one retained event, any date.
    let distinctActiveDays: Int
    /// Most recent event date, nil when no event was recorded.
    let lastActivityDate: Date?
    /// Earliest retained event date, nil when none was recorded.
    let firstActivityDate: Date?
    /// Consecutive active days ending on the reference date, or
    /// on the day before it when the reference date has no event
    /// yet. Zero when neither day is active. Mirrors the
    /// ProgressStore streak rule, with an injectable reference
    /// date so the rule can be tested.
    let streakCount: Int
    /// Retained events counted.
    let eventCount: Int
}

/// Recorded activity counts, for separating opens from completions.
/// Distinct lesson counts come from the retained events only, so
/// they are lower bounds when older events were dropped.
struct ProgressActivityCounts: Equatable {
    /// Distinct lessons with a lessonStarted event.
    let distinctLessonsOpened: Int
    /// Distinct lessons with a lessonCompleted event.
    let distinctLessonsCompletedInEvents: Int
    /// Quiz completed events recorded.
    let quizCompletedEventCount: Int
    /// Audio listened events recorded.
    let audioEventCount: Int
}

// MARK: - Pathway and certificates

/// Where the pathway lessons came from, so the view can label the
/// pathway honestly. The view resolves the lessons; this enum only
/// records which resolution won.
enum ProgressPathwaySource: Equatable {
    /// The learner's chosen active path (ActivePathStore).
    case activePath
    /// The guided path named by the learner's role route.
    case roleRoutePath
    /// The guided sessions of the learner's role route, used when
    /// the route names no path or the path does not resolve.
    case roleRouteSessions
    /// No pathway could be resolved.
    case none
}

/// Pathway completion: activity (completed lessons) plus quiz
/// evidence inside the pathway. The fraction is nil when the
/// pathway has no lessons in the catalogue passed in, which means
/// the catalogue is still loading, not that progress is zero.
struct ProgressPathwayInsight: Equatable {
    let completed: Int
    let total: Int
    let fraction: Double?
    /// Pathway lessons whose best quiz fraction reaches the bar.
    let demonstratedLessonCount: Int
    /// Pathway lessons with at least one quiz attempt recorded.
    let quizAttemptedLessonCount: Int
    let source: ProgressPathwaySource
}

/// One guided path's lesson progress, pre-resolved by the caller
/// from the live catalogue. Kept as an input value so this file
/// never depends on ContentService.
struct ProgressPathProgress: Equatable {
    let pathID: String
    let pathTitle: String
    /// The certificate title, nil when the path has no certificate.
    let certificateTitle: String?
    let completed: Int
    let total: Int
}

/// Certificate eligibility for one guided path. Path certificates
/// are earned by completing every required lesson; no exam or
/// assessment is required (see LearningPath.completionCriteria).
/// Eligibility is computed here without calling
/// PFCertificateStore.certificate, because that function stamps
/// an issued date on first read. The view links to CertificateView,
/// which is the only place that issues the certificate.
struct ProgressPathCertificateInsight: Equatable, Identifiable {
    let pathID: String
    var id: String { pathID }
    let pathTitle: String
    let certificateTitle: String?
    let completed: Int
    let total: Int
    let lessonsRemaining: Int

    /// True only when the path carries a certificate, has lessons
    /// in the loaded catalogue, and every one is complete.
    var isEligible: Bool {
        certificateTitle != nil && total > 0 && completed >= total
    }

    /// True when the path carries a certificate at all.
    var hasCertificate: Bool { certificateTitle != nil }
}

/// Whether a course Final Assessment has been passed, can still
/// be attempted, or is locked. Failed attempt scores are not
/// stored anywhere (FinalAssessmentStore keeps only the attempt
/// count and, on a pass, the certificate), so no failed score can
/// ever be shown from this summary.
enum ProgressCourseCertificateStatus: Equatable {
    case passed
    case attemptsLeft
    case locked
}

/// Final Assessment standing for one assessable course, from the
/// stored attempt counts and certificates. Attempt and pass rules
/// mirror FinalAssessmentStore: at most maxAttempts attempts, and
/// a certificate exists exactly when the course was passed.
struct ProgressCourseCertificateInsight: Equatable, Identifiable {
    let productID: String
    var id: String { productID }
    let courseName: String
    /// The issued certificate, present exactly when passed.
    /// Its score is the passing attempt's score.
    let certificate: CourseCertificate?
    let attemptsUsed: Int
    let attemptsRemaining: Int
    let status: ProgressCourseCertificateStatus

    var isPassed: Bool { status == .passed }
}

// MARK: - Studio

/// Studio work summary. Drafts are work in progress saved on the
/// device; they carry no score and no completion state, so this
/// summary reports counts and dates only, and must be presented
/// as activity, never as assessed performance. The local rubric
/// checklist is deliberately not run here: it is a keyword
/// checklist, not an assessment of the writing.
struct ProgressStudioSummary: Equatable {
    /// Drafts saved on the device.
    let draftsCount: Int
    /// Exercises with at least one saved draft.
    let exercisesWithDrafts: Int
    /// Exercises in the catalogue passed in as the total.
    let totalExercises: Int
    /// Drafts where the learner asked for an AI review.
    let aiReviewedDraftCount: Int
    /// Most recent draft update, nil when no draft exists.
    let lastUpdatedAt: Date?

    var hasDrafts: Bool { draftsCount > 0 }
}

// MARK: - Computation

enum ProgressInsights {

    /// The competency score, on the 0 to 100 scale, at or above
    /// which an assessed dimension counts as stronger evidence,
    /// when no quiz evidence contradicts it. Chosen to match the
    /// 80 percent quiz demonstration bar. See the file header.
    static let competencyStrengthThreshold: Double = 80

    // MARK: Quiz

    /// One attempt's fraction correct, clamped to 0 through 1.
    /// Nil when no total was recorded.
    private static func clampedFraction(correct: Int, total: Int) -> Double? {
        guard total > 0 else { return nil }
        return min(1, max(0, Double(correct) / Double(total)))
    }

    /// Every attempt fraction for one lesson, clamped, in recorded
    /// order. Attempts with no total are skipped.
    private static func fractions(for attempts: [QuizAttempt]) -> [Double] {
        attempts.compactMap { clampedFraction(correct: $0.correct, total: $0.total) }
    }

    /// Quiz evidence for every lesson with a recorded attempt.
    /// Lessons with no attempt do not appear in the result.
    static func lessonQuizEvidence(
        history: [String: [QuizAttempt]]
    ) -> [String: ProgressLessonQuizEvidence] {
        var result: [String: ProgressLessonQuizEvidence] = [:]
        for (lessonID, attempts) in history {
            let values = fractions(for: attempts)
            result[lessonID] = ProgressLessonQuizEvidence(
                lessonID: lessonID,
                attemptCount: attempts.count,
                attemptsWithTotal: values.count,
                averageFraction: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count),
                bestFraction: values.max()
            )
        }
        return result
    }

    /// The quiz summary across all lessons in the history.
    static func quizSummary(
        history: [String: [QuizAttempt]]
    ) -> ProgressQuizSummary {
        let evidence = lessonQuizEvidence(history: history)
        let allFractions = history.values.flatMap { fractions(for: $0) }
        return ProgressQuizSummary(
            totalAttempts: history.values.reduce(0) { $0 + $1.count },
            attemptsWithTotal: allFractions.count,
            attemptsWithoutTotal: history.values.reduce(0) { $0 + $1.count } - allFractions.count,
            lessonsAttempted: history.count,
            averageFraction: allFractions.isEmpty ? nil : allFractions.reduce(0, +) / Double(allFractions.count),
            bestFraction: allFractions.max(),
            demonstratedLessonCount: evidence.values.filter { $0.isDemonstrated }.count,
            attemptedNotDemonstratedLessonCount: evidence.values.filter { !$0.isDemonstrated }.count
        )
    }

    /// Completed lessons split by quiz evidence. A completed lesson
    /// with no recorded attempt lands in noQuizEvidenceCount; a
    /// completed lesson with attempts but no fraction at the bar
    /// lands in attemptedNotDemonstratedCount.
    static func demonstratedSummary(
        completedLessonIDs: Set<String>,
        history: [String: [QuizAttempt]]
    ) -> ProgressDemonstratedSummary {
        let evidence = lessonQuizEvidence(history: history)
        var demonstrated = 0
        var attemptedNotDemonstrated = 0
        var noEvidence = 0
        for lessonID in completedLessonIDs {
            guard let lessonEvidence = evidence[lessonID] else {
                noEvidence += 1
                continue
            }
            if lessonEvidence.isDemonstrated {
                demonstrated += 1
            } else {
                attemptedNotDemonstrated += 1
            }
        }
        return ProgressDemonstratedSummary(
            completedLessonCount: completedLessonIDs.count,
            demonstratedLessonCount: demonstrated,
            attemptedNotDemonstratedCount: attemptedNotDemonstrated,
            noQuizEvidenceCount: noEvidence
        )
    }

    /// Completed lessons whose average quiz fraction is below the
    /// demonstration bar, lowest average first, capped at `limit`.
    /// Only lessons with a recorded average appear: a completed
    /// lesson with no fraction recorded is missing evidence, not
    /// weak evidence, and is never listed here. Ties break by
    /// lesson id so the order is stable.
    static func weakQuizLessons(
        history: [String: [QuizAttempt]],
        completedLessonIDs: Set<String>,
        limit: Int
    ) -> [ProgressLessonQuizEvidence] {
        guard limit > 0 else { return [] }
        return lessonQuizEvidence(history: history).values
            .filter { completedLessonIDs.contains($0.lessonID) }
            .compactMap { evidence -> ProgressLessonQuizEvidence? in
                guard let average = evidence.averageFraction,
                      average < RecommendationEngine.masteryThreshold else { return nil }
                return evidence
            }
            .sorted {
                if $0.averageFraction != $1.averageFraction {
                    return ($0.averageFraction ?? 0) < ($1.averageFraction ?? 0)
                }
                return $0.lessonID < $1.lessonID
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Grouped knowledge

    /// One insight per competency dimension, in dimension order.
    /// Lessons are grouped by chapter number from their ids, using
    /// each dimension's chapter list. Lessons whose id carries no
    /// chapter number are in no dimension and are excluded from
    /// every dimension total. Competency scores are passed in as
    /// recorded (0 to 100); a missing dimension means unassessed.
    static func dimensionInsights(
        competencyScores: [CompetencyStore.CompetencyDimension: Double],
        lessons: [SearchEntry],
        completedLessonIDs: Set<String>,
        history: [String: [QuizAttempt]]
    ) -> [ProgressDimensionInsight] {
        let evidence = lessonQuizEvidence(history: history)
        let lessonsByChapter: [Int: [SearchEntry]] = Dictionary(
            grouping: lessons.compactMap { lesson -> (Int, SearchEntry)? in
                guard let number = lesson.chapterNumber else { return nil }
                return (number, lesson)
            },
            by: { $0.0 }
        ).mapValues { pairs in pairs.map { $0.1 } }
        return CompetencyStore.CompetencyDimension.allCases.map { dimension in
            var dimensionLessons: [SearchEntry] = []
            var seen: Set<String> = []
            for number in dimension.chapterNumbers {
                for lesson in lessonsByChapter[number] ?? [] where seen.insert(lesson.id).inserted {
                    dimensionLessons.append(lesson)
                }
            }
            let fractions = dimensionLessons.flatMap { fractions(for: history[$0.id] ?? []) }
            let attempts = dimensionLessons.reduce(0) { $0 + (history[$1.id]?.count ?? 0) }
            return ProgressDimensionInsight(
                dimension: dimension,
                competencyScorePercent: competencyScores[dimension],
                quizAverageFraction: fractions.isEmpty ? nil : fractions.reduce(0, +) / Double(fractions.count),
                quizAttemptCount: attempts,
                quizAttemptsWithTotal: fractions.count,
                quizAttemptsWithoutTotal: attempts - fractions.count,
                demonstratedLessonCount: dimensionLessons.filter { evidence[$0.id]?.isDemonstrated == true }.count,
                lessonsCompleted: dimensionLessons.filter { completedLessonIDs.contains($0.id) }.count,
                lessonsTotal: dimensionLessons.count
            )
        }
    }

    /// Places each dimension with evidence into the stronger or
    /// needs attention list. A dimension needs attention when any
    /// evidence source is below its bar. A dimension shows stronger
    /// evidence when at least one source exists, no source is below
    /// its bar, and at least one source reaches its bar. A dimension
    /// with no evidence is in neither list. Needs attention sorts
    /// lowest evidence first; stronger sorts highest first; ties
    /// break by dimension name so the order is stable.
    static func evidenceAreas(
        _ insights: [ProgressDimensionInsight]
    ) -> (stronger: [ProgressEvidenceArea], needsAttention: [ProgressEvidenceArea]) {
        var stronger: [ProgressEvidenceArea] = []
        var needsAttention: [ProgressEvidenceArea] = []
        for insight in insights {
            let competencyBelow = insight.competencyScorePercent.map { $0 < competencyStrengthThreshold } ?? false
            let quizBelow = insight.quizAverageFraction.map { $0 < RecommendationEngine.masteryThreshold } ?? false
            let competencyAtBar = insight.competencyScorePercent.map { $0 >= competencyStrengthThreshold } ?? false
            let quizAtBar = insight.quizAverageFraction.map { $0 >= RecommendationEngine.masteryThreshold } ?? false
            let hasEvidence = insight.competencyScorePercent != nil || insight.quizAverageFraction != nil
            let areaText = evidenceText(
                competencyScorePercent: insight.competencyScorePercent,
                quizAverageFraction: insight.quizAverageFraction,
                quizAttemptsWithTotal: insight.quizAttemptsWithTotal
            )
            if competencyBelow || quizBelow {
                needsAttention.append(ProgressEvidenceArea(
                    dimension: insight.dimension,
                    kind: .needsAttention,
                    competencyScorePercent: insight.competencyScorePercent,
                    quizAverageFraction: insight.quizAverageFraction,
                    quizAttemptsWithTotal: insight.quizAttemptsWithTotal,
                    evidenceText: areaText
                ))
            } else if hasEvidence && (competencyAtBar || quizAtBar) {
                stronger.append(ProgressEvidenceArea(
                    dimension: insight.dimension,
                    kind: .strongerEvidence,
                    competencyScorePercent: insight.competencyScorePercent,
                    quizAverageFraction: insight.quizAverageFraction,
                    quizAttemptsWithTotal: insight.quizAttemptsWithTotal,
                    evidenceText: areaText
                ))
            }
        }
        needsAttention.sort {
            let leftScore = $0.competencyScorePercent ?? 100
            let rightScore = $1.competencyScorePercent ?? 100
            if leftScore != rightScore { return leftScore < rightScore }
            let leftQuiz = $0.quizAverageFraction ?? 1
            let rightQuiz = $1.quizAverageFraction ?? 1
            if leftQuiz != rightQuiz { return leftQuiz < rightQuiz }
            return $0.dimension.rawValue < $1.dimension.rawValue
        }
        stronger.sort {
            let leftScore = $0.competencyScorePercent ?? 0
            let rightScore = $1.competencyScorePercent ?? 0
            if leftScore != rightScore { return leftScore > rightScore }
            let leftQuiz = $0.quizAverageFraction ?? 0
            let rightQuiz = $1.quizAverageFraction ?? 0
            if leftQuiz != rightQuiz { return leftQuiz > rightQuiz }
            return $0.dimension.rawValue < $1.dimension.rawValue
        }
        return (stronger, needsAttention)
    }

    /// The evidence sentence for one dimension. Every existing
    /// source is named with its number; a missing source is named
    /// as missing, so the sentence never implies evidence that
    /// does not exist.
    private static func evidenceText(
        competencyScorePercent: Double?,
        quizAverageFraction: Double?,
        quizAttemptsWithTotal: Int
    ) -> String {
        var parts: [String] = []
        if let competencyScorePercent {
            parts.append("Competency assessment \(Int(competencyScorePercent.rounded()))%.")
        } else {
            parts.append("No competency assessment recorded yet.")
        }
        if let quizAverageFraction {
            let attemptWord = quizAttemptsWithTotal == 1 ? "attempt" : "attempts"
            parts.append("Quiz average \(Int((quizAverageFraction * 100).rounded()))% across \(quizAttemptsWithTotal) \(attemptWord).")
        } else {
            parts.append("No quiz attempts with a recorded total in this area yet.")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Lab

    /// The best fraction for one stored lab result, clamped to 0
    /// through 1. Nil when the maximum is not above zero.
    static func bestLabFraction(for result: ExceptionLabResult) -> Double? {
        guard result.bestMaximum > 0 else { return nil }
        return min(1, max(0, Double(result.bestTotal) / Double(result.bestMaximum)))
    }

    /// The lab summary over all stored results. The caller supplies
    /// the catalogue case count as totalCases; results for case ids
    /// no longer in the catalogue still count as completed, because
    /// the work was really done.
    static func labSummary(
        results: [ExceptionLabResult],
        totalCases: Int
    ) -> ProgressLabSummary {
        let bestFractions = results.compactMap { bestLabFraction(for: $0) }
        return ProgressLabSummary(
            casesCompleted: results.count,
            totalCases: totalCases,
            totalCompletions: results.reduce(0) { $0 + $1.completions },
            meanBestFraction: bestFractions.isEmpty ? nil : bestFractions.reduce(0, +) / Double(bestFractions.count),
            lowestBestFraction: bestFractions.min(),
            highestBestFraction: bestFractions.max(),
            stepsSolvedBestFirst: results.reduce(0) { $0 + $1.lastBreakdown.stepsSolvedBestFirst },
            stepsSolvedAfterWrongTurn: results.reduce(0) { $0 + $1.lastBreakdown.stepsSolvedAfterWrongTurn },
            totalWrongPicks: results.reduce(0) { $0 + $1.lastBreakdown.totalWrongPicks },
            totalRedHerringPicks: results.reduce(0) { $0 + $1.lastBreakdown.totalRedHerringPicks },
            evidenceOpenedCount: results.reduce(0) { $0 + $1.lastBreakdown.evidenceOpenedCount },
            evidenceTotalCount: results.reduce(0) { $0 + $1.lastBreakdown.evidenceTotalCount }
        )
    }

    /// One insight per completed case, most recently completed
    /// first. Ties break by case id so the order is stable.
    static func labCaseInsights(
        results: [ExceptionLabResult]
    ) -> [ProgressLabCaseInsight] {
        results
            .map { result in
                ProgressLabCaseInsight(
                    caseID: result.caseID,
                    bestTotal: result.bestTotal,
                    bestMaximum: result.bestMaximum,
                    bestFraction: bestLabFraction(for: result),
                    completions: result.completions,
                    lastCompletedAt: result.lastCompletedAt
                )
            }
            .sorted {
                if $0.lastCompletedAt != $1.lastCompletedAt {
                    return $0.lastCompletedAt > $1.lastCompletedAt
                }
                return $0.caseID < $1.caseID
            }
    }

    // MARK: Time, consistency, activity

    /// Recorded learning time split by event type. Only positive
    /// durations count; a missing or non-positive duration adds
    /// nothing and is not counted as a timed event.
    static func timeInsight(events: [LearningEvent]) -> ProgressTimeInsight {
        var lessonSeconds = 0
        var audioSeconds = 0
        var lessonEvents = 0
        var audioEvents = 0
        for event in events {
            guard let seconds = event.durationSeconds, seconds > 0 else { continue }
            switch event.type {
            case .lessonDuration:
                lessonSeconds += seconds
                lessonEvents += 1
            case .audioListened:
                audioSeconds += seconds
                audioEvents += 1
            default:
                break
            }
        }
        return ProgressTimeInsight(
            lessonDurationSeconds: lessonSeconds,
            audioSeconds: audioSeconds,
            totalSeconds: lessonSeconds + audioSeconds,
            lessonDurationEventCount: lessonEvents,
            audioEventCount: audioEvents
        )
    }

    /// A short duration label for a recorded second count:
    /// "0 min", "45 min", "1 hr", "1 hr 5 min", "2 hrs 10 min".
    /// Minutes round to the nearest whole minute, at least 0.
    static func durationLabel(totalSeconds: Int) -> String {
        guard totalSeconds > 0 else { return "0 min" }
        let minutes = max(1, (totalSeconds + 30) / 60)
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        let hourText = hours == 1 ? "1 hr" : "\(hours) hrs"
        if remainder == 0 { return hourText }
        return "\(hourText) \(remainder) min"
    }

    /// Consistency from retained event dates, at a reference date.
    /// Window counts cover the days ending on the reference date,
    /// inclusive. The streak mirrors the ProgressStore rule.
    static func consistency(
        events: [LearningEvent],
        referenceDate: Date,
        calendar: Calendar = Calendar.current
    ) -> ProgressConsistencyInsight {
        let activeDays = Set(events.map { calendar.startOfDay(for: $0.timestamp) })
        let referenceDay = calendar.startOfDay(for: referenceDate)
        func countActiveDays(inLast days: Int) -> Int {
            guard days > 0 else { return 0 }
            var count = 0
            for offset in 0..<days {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: referenceDay) else { continue }
                if activeDays.contains(day) { count += 1 }
            }
            return count
        }
        var streak = 0
        if !activeDays.isEmpty {
            var day = referenceDay
            if !activeDays.contains(day),
               let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
               activeDays.contains(yesterday) {
                day = yesterday
            }
            if activeDays.contains(day) {
                while activeDays.contains(day) {
                    streak += 1
                    guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
                    day = previous
                }
            }
        }
        return ProgressConsistencyInsight(
            activeDaysLast7: countActiveDays(inLast: 7),
            activeDaysLast28: countActiveDays(inLast: 28),
            distinctActiveDays: activeDays.count,
            lastActivityDate: events.map(\.timestamp).max(),
            firstActivityDate: events.map(\.timestamp).min(),
            streakCount: streak,
            eventCount: events.count
        )
    }

    /// Recorded activity counts from retained events.
    static func activityCounts(events: [LearningEvent]) -> ProgressActivityCounts {
        ProgressActivityCounts(
            distinctLessonsOpened: Set(events.filter { $0.type == .lessonStarted }.compactMap(\.lessonID)).count,
            distinctLessonsCompletedInEvents: Set(events.filter { $0.type == .lessonCompleted }.compactMap(\.lessonID)).count,
            quizCompletedEventCount: events.filter { $0.type == .quizCompleted }.count,
            audioEventCount: events.filter { $0.type == .audioListened }.count
        )
    }

    // MARK: Pathway

    /// Pathway completion over the lesson ids passed in, plus quiz
    /// evidence inside the pathway. Duplicate lesson ids count once:
    /// the pathway list is deduped before counting, matching how
    /// RoleRoute.lessons and LearningPath.lessons resolve.
    static func pathwayInsight(
        lessonIDs: [String],
        completedLessonIDs: Set<String>,
        history: [String: [QuizAttempt]],
        source: ProgressPathwaySource
    ) -> ProgressPathwayInsight {
        let uniqueIDs = Array(Set(lessonIDs))
        let completed = uniqueIDs.filter { completedLessonIDs.contains($0) }.count
        let evidence = lessonQuizEvidence(history: history)
        return ProgressPathwayInsight(
            completed: completed,
            total: uniqueIDs.count,
            fraction: uniqueIDs.isEmpty ? nil : Double(completed) / Double(uniqueIDs.count),
            demonstratedLessonCount: uniqueIDs.filter { evidence[$0]?.isDemonstrated == true }.count,
            quizAttemptedLessonCount: uniqueIDs.filter { evidence[$0]?.hasAttempt == true }.count,
            source: source
        )
    }

    // MARK: Certificates

    /// Path certificate eligibility for pre-resolved path progress,
    /// in the order passed in.
    static func pathCertificateInsights(
        _ inputs: [ProgressPathProgress]
    ) -> [ProgressPathCertificateInsight] {
        inputs.map { input in
            ProgressPathCertificateInsight(
                pathID: input.pathID,
                pathTitle: input.pathTitle,
                certificateTitle: input.certificateTitle,
                completed: input.completed,
                total: input.total,
                lessonsRemaining: max(0, input.total - input.completed)
            )
        }
    }

    /// Final Assessment standing for each assessable course, in the
    /// order passed in. Attempt counts above the maximum clamp the
    /// remaining count at zero; a stored certificate always wins
    /// over the attempt count.
    static func courseCertificateInsights(
        courses: [CourseProduct],
        certificates: [String: CourseCertificate],
        attemptsUsed: [String: Int]
    ) -> [ProgressCourseCertificateInsight] {
        courses.map { course in
            let certificate = certificates[course.productID]
            let used = attemptsUsed[course.productID] ?? 0
            let remaining = max(0, FinalAssessmentStore.maxAttempts - used)
            let status: ProgressCourseCertificateStatus
            if certificate != nil {
                status = .passed
            } else if remaining > 0 {
                status = .attemptsLeft
            } else {
                status = .locked
            }
            return ProgressCourseCertificateInsight(
                productID: course.productID,
                courseName: course.name,
                certificate: certificate,
                attemptsUsed: used,
                attemptsRemaining: remaining,
                status: status
            )
        }
    }

    // MARK: Studio

    /// Studio draft counts. Drafts for the same exercise count once
    /// toward exercisesWithDrafts.
    static func studioSummary(
        drafts: [StudioDraft],
        totalExercises: Int
    ) -> ProgressStudioSummary {
        ProgressStudioSummary(
            draftsCount: drafts.count,
            exercisesWithDrafts: Set(drafts.map(\.exerciseID)).count,
            totalExercises: totalExercises,
            aiReviewedDraftCount: drafts.filter { $0.hasRequestedAIReview }.count,
            lastUpdatedAt: drafts.map(\.updatedAt).max()
        )
    }
}
