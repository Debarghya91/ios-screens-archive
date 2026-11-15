// ProgressInsightsTests.swift
// PaymentForge iOS - Phase 4 unit tests: pure progress computations
// for My Progress (ProgressInsights.swift).
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only.
//
// No test constructs a store and none touches UserDefaults:
// ProgressInsights takes recorded values only, so every input here
// is built directly from value types. No namespace pinning is
// needed and no test can leak state into another test.
//
// Thresholds asserted here are the app's own: the quiz bar is
// RecommendationEngine.masteryThreshold (0.8) and the competency
// bar is ProgressInsights.competencyStrengthThreshold (80 on the
// 0 to 100 scale). Consistency tests use a fixed UTC calendar and
// noon UTC dates, so no timezone or daylight saving boundary can
// move a day.
// No em dashes in any user-facing text.

import XCTest
@testable import PaymentForge

final class ProgressInsightsTests: XCTestCase {

    // MARK: - Helpers

    private func lesson(id: String) -> SearchEntry {
        SearchEntry(id: id, title: id, url: "", type: .lesson, text: "")
    }

    private func attempt(lessonID: String, correct: Int, total: Int, dayOffset: Int = 0) -> QuizAttempt {
        QuizAttempt(
            lessonID: lessonID,
            correct: correct,
            total: total,
            attemptedAt: Date(timeIntervalSince1970: 1_794_484_800 + Double(dayOffset * 86_400))
        )
    }

    private func event(
        type: LearningEventType,
        lessonID: String? = nil,
        dayOffset: Int = 0,
        durationSeconds: Int? = nil
    ) -> LearningEvent {
        LearningEvent(
            type: type,
            lessonID: lessonID,
            timestamp: Date(timeIntervalSince1970: 1_794_484_800 + Double(dayOffset * 86_400)),
            durationSeconds: durationSeconds
        )
    }

    private func breakdown(
        total: Int,
        maximum: Int,
        bestFirst: Int = 0,
        recovered: Int = 0,
        wrongPicks: Int = 0,
        redHerringPicks: Int = 0,
        evidenceOpened: Int = 0,
        evidenceTotal: Int = 0
    ) -> ExceptionLabScoreBreakdown {
        ExceptionLabScoreBreakdown(
            bestFirstPoints: 0,
            recoveredPoints: 0,
            wrongTurnDeductions: 0,
            redHerringDeductions: 0,
            efficiencyBonus: 0,
            thoroughnessPoints: 0,
            total: total,
            maximum: maximum,
            stepsSolvedBestFirst: bestFirst,
            stepsSolvedAfterWrongTurn: recovered,
            totalWrongPicks: wrongPicks,
            totalRedHerringPicks: redHerringPicks,
            evidenceOpenedCount: evidenceOpened,
            evidenceTotalCount: evidenceTotal
        )
    }

    private func labResult(
        caseID: String,
        bestTotal: Int,
        bestMaximum: Int,
        completions: Int = 1,
        dayOffset: Int = 0,
        lastBreakdown: ExceptionLabScoreBreakdown? = nil
    ) -> ExceptionLabResult {
        ExceptionLabResult(
            caseID: caseID,
            bestTotal: bestTotal,
            bestMaximum: bestMaximum,
            completions: completions,
            lastCompletedAt: Date(timeIntervalSince1970: 1_794_484_800 + Double(dayOffset * 86_400)),
            lastBreakdown: lastBreakdown ?? breakdown(total: bestTotal, maximum: bestMaximum)
        )
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    /// 2026-11-12 12:00 UTC, the reference date for consistency tests.
    private var referenceDate: Date {
        Date(timeIntervalSince1970: 1_794_484_800)
    }

    private func course(id: String, productID: String, name: String) -> CourseProduct {
        CourseProduct(
            id: id,
            productID: productID,
            name: name,
            tagline: "",
            description: "",
            priceINR: 0,
            chapterIDs: ["ch1"],
            situationCount: 0
        )
    }

    private func certificate(courseID: String, correct: Int, total: Int) -> CourseCertificate {
        CourseCertificate(
            id: "PF-TEST-0001",
            courseID: courseID,
            courseName: "Test Course",
            learnerName: "Test Learner",
            issuedAt: referenceDate,
            correctCount: correct,
            totalQuestions: total
        )
    }

    // MARK: - Quiz summary

    func testEmptyHistoryHasNoAveragesAndNoDemonstratedLessons() {
        let summary = ProgressInsights.quizSummary(history: [:])
        XCTAssertEqual(summary.totalAttempts, 0)
        XCTAssertEqual(summary.attemptsWithTotal, 0)
        XCTAssertEqual(summary.attemptsWithoutTotal, 0)
        XCTAssertEqual(summary.lessonsAttempted, 0)
        XCTAssertNil(summary.averageFraction)
        XCTAssertNil(summary.bestFraction)
        XCTAssertEqual(summary.demonstratedLessonCount, 0)
        XCTAssertEqual(summary.attemptedNotDemonstratedLessonCount, 0)
    }

    func testQuizSummaryAveragesAttemptFractionsNotCounts() {
        // 2 of 3 and 3 of 3: the mean of fractions, not of counts.
        // quizScores (best counts) could never express this (D82).
        let history = [
            "ch1s1": [attempt(lessonID: "ch1s1", correct: 2, total: 3)],
            "ch1s2": [attempt(lessonID: "ch1s2", correct: 3, total: 3)]
        ]
        let summary = ProgressInsights.quizSummary(history: history)
        XCTAssertEqual(summary.totalAttempts, 2)
        XCTAssertEqual(summary.attemptsWithTotal, 2)
        XCTAssertEqual(summary.lessonsAttempted, 2)
        XCTAssertEqual(summary.averageFraction!, (2.0 / 3.0 + 1.0) / 2.0, accuracy: 0.001)
        XCTAssertEqual(summary.bestFraction!, 1.0, accuracy: 0.001)
        XCTAssertEqual(summary.demonstratedLessonCount, 1)
        XCTAssertEqual(summary.attemptedNotDemonstratedLessonCount, 1)
    }

    func testAttemptsWithoutTotalCountButDoNotFeedAverages() {
        let history = [
            "ch1s1": [attempt(lessonID: "ch1s1", correct: 3, total: 0)],
            "ch1s2": [attempt(lessonID: "ch1s2", correct: 1, total: 2)]
        ]
        let summary = ProgressInsights.quizSummary(history: history)
        XCTAssertEqual(summary.totalAttempts, 2)
        XCTAssertEqual(summary.attemptsWithTotal, 1)
        XCTAssertEqual(summary.attemptsWithoutTotal, 1)
        XCTAssertEqual(summary.averageFraction!, 0.5, accuracy: 0.001)
        XCTAssertEqual(summary.demonstratedLessonCount, 0)
        XCTAssertEqual(summary.attemptedNotDemonstratedLessonCount, 2)
    }

    func testQuizFractionsClampAboveOne() {
        // A stored attempt with correct above total cannot push an
        // average above 100 percent.
        let history = ["ch1s1": [attempt(lessonID: "ch1s1", correct: 5, total: 3)]]
        let summary = ProgressInsights.quizSummary(history: history)
        XCTAssertEqual(summary.averageFraction!, 1.0, accuracy: 0.001)
        XCTAssertEqual(summary.bestFraction!, 1.0, accuracy: 0.001)
        XCTAssertEqual(summary.demonstratedLessonCount, 1)
    }

    func testLessonEvidenceBestAndAverageAreSeparate() {
        let history = ["ch1s1": [
            attempt(lessonID: "ch1s1", correct: 1, total: 4),
            attempt(lessonID: "ch1s1", correct: 4, total: 4)
        ]]
        let evidence = ProgressInsights.lessonQuizEvidence(history: history)["ch1s1"]!
        XCTAssertEqual(evidence.attemptCount, 2)
        XCTAssertEqual(evidence.attemptsWithTotal, 2)
        XCTAssertEqual(evidence.averageFraction!, (0.25 + 1.0) / 2.0, accuracy: 0.001)
        XCTAssertEqual(evidence.bestFraction!, 1.0, accuracy: 0.001)
        XCTAssertTrue(evidence.isDemonstrated)
        XCTAssertTrue(evidence.hasAttempt)
    }

    func testLessonEvidenceWithNoTotalIsNotDemonstrated() {
        let history = ["ch1s1": [attempt(lessonID: "ch1s1", correct: 4, total: 0)]]
        let evidence = ProgressInsights.lessonQuizEvidence(history: history)["ch1s1"]!
        XCTAssertNil(evidence.averageFraction)
        XCTAssertNil(evidence.bestFraction)
        XCTAssertFalse(evidence.isDemonstrated)
        XCTAssertTrue(evidence.hasAttempt)
    }

    // MARK: - Demonstrated summary

    func testDemonstratedSummarySplitsCompletedLessonsIntoThreeBuckets() {
        let completed: Set<String> = ["ch1s1", "ch1s2", "ch1s3", "ch1s4"]
        let history = [
            "ch1s1": [attempt(lessonID: "ch1s1", correct: 4, total: 4)],
            "ch1s2": [attempt(lessonID: "ch1s2", correct: 1, total: 4)],
            "ch1s3": [attempt(lessonID: "ch1s3", correct: 3, total: 0)]
        ]
        let summary = ProgressInsights.demonstratedSummary(completedLessonIDs: completed, history: history)
        XCTAssertEqual(summary.completedLessonCount, 4)
        XCTAssertEqual(summary.demonstratedLessonCount, 1)
        XCTAssertEqual(summary.attemptedNotDemonstratedCount, 2)
        XCTAssertEqual(summary.noQuizEvidenceCount, 1)
        XCTAssertEqual(
            summary.demonstratedLessonCount + summary.attemptedNotDemonstratedCount + summary.noQuizEvidenceCount,
            summary.completedLessonCount
        )
    }

    func testDemonstratedSummaryIgnoresUncompletedLessons() {
        let summary = ProgressInsights.demonstratedSummary(
            completedLessonIDs: [],
            history: ["ch1s1": [attempt(lessonID: "ch1s1", correct: 4, total: 4)]]
        )
        XCTAssertEqual(summary.completedLessonCount, 0)
        XCTAssertEqual(summary.demonstratedLessonCount, 0)
        XCTAssertEqual(summary.noQuizEvidenceCount, 0)
    }

    // MARK: - Weak quiz lessons

    func testWeakQuizLessonsAreCompletedLowestAverageFirstWithLimit() {
        let completed: Set<String> = ["ch1s1", "ch1s2", "ch1s3", "ch1s4"]
        let history = [
            "ch1s1": [attempt(lessonID: "ch1s1", correct: 3, total: 4)],
            "ch1s2": [attempt(lessonID: "ch1s2", correct: 1, total: 4)],
            "ch1s3": [attempt(lessonID: "ch1s3", correct: 4, total: 4)],
            "ch1s4": [attempt(lessonID: "ch1s4", correct: 2, total: 4)]
        ]
        let weak = ProgressInsights.weakQuizLessons(history: history, completedLessonIDs: completed, limit: 2)
        XCTAssertEqual(weak.map(\.lessonID), ["ch1s2", "ch1s4"])
    }

    func testWeakQuizLessonsExcludeUncompletedAndNoFractionLessons() {
        let completed: Set<String> = ["ch1s1", "ch1s2"]
        let history = [
            "ch1s1": [attempt(lessonID: "ch1s1", correct: 1, total: 4)],
            "ch1s2": [attempt(lessonID: "ch1s2", correct: 3, total: 0)],
            "ch9s9": [attempt(lessonID: "ch9s9", correct: 0, total: 4)]
        ]
        let weak = ProgressInsights.weakQuizLessons(history: history, completedLessonIDs: completed, limit: 5)
        XCTAssertEqual(weak.map(\.lessonID), ["ch1s1"])
    }

    func testWeakQuizLessonsWithZeroLimitIsEmpty() {
        let weak = ProgressInsights.weakQuizLessons(
            history: ["ch1s1": [attempt(lessonID: "ch1s1", correct: 0, total: 4)]],
            completedLessonIDs: ["ch1s1"],
            limit: 0
        )
        XCTAssertTrue(weak.isEmpty)
    }

    // MARK: - Dimension insights

    func testDimensionInsightsGroupLessonsByDimensionChapters() {
        // Architecture chapters include 25; lifecycle chapters
        // include 4. A lesson with no chapter number is excluded.
        let lessons = [lesson(id: "ch25s1"), lesson(id: "ch4s1"), lesson(id: "LAB-01")]
        let insights = ProgressInsights.dimensionInsights(
            competencyScores: [:],
            lessons: lessons,
            completedLessonIDs: ["ch25s1"],
            history: ["ch25s1": [attempt(lessonID: "ch25s1", correct: 4, total: 4)]]
        )
        XCTAssertEqual(insights.count, CompetencyStore.CompetencyDimension.allCases.count)
        let architecture = insights.first { $0.dimension == .architecture }!
        XCTAssertEqual(architecture.lessonsTotal, 1)
        XCTAssertEqual(architecture.lessonsCompleted, 1)
        XCTAssertEqual(architecture.quizAverageFraction!, 1.0, accuracy: 0.001)
        XCTAssertEqual(architecture.demonstratedLessonCount, 1)
        XCTAssertNil(architecture.competencyScorePercent)
        XCTAssertTrue(architecture.hasAnyEvidence)
        let lifecycle = insights.first { $0.dimension == .lifecycle }!
        XCTAssertEqual(lifecycle.lessonsTotal, 1)
        XCTAssertEqual(lifecycle.lessonsCompleted, 0)
        XCTAssertNil(lifecycle.quizAverageFraction)
        XCTAssertFalse(lifecycle.hasAnyEvidence)
        XCTAssertEqual(insights.reduce(0) { $0 + $1.lessonsTotal }, 2)
    }

    func testDimensionInsightFractionCompletedIsNilWhenNoLessons() {
        let insights = ProgressInsights.dimensionInsights(
            competencyScores: [.architecture: 90],
            lessons: [],
            completedLessonIDs: [],
            history: [:]
        )
        let architecture = insights.first { $0.dimension == .architecture }!
        XCTAssertEqual(architecture.lessonsTotal, 0)
        XCTAssertNil(architecture.fractionCompleted)
        XCTAssertEqual(architecture.competencyScorePercent!, 90, accuracy: 0.001)
    }

    func testDimensionQuizAttemptsWithoutTotalAreReportedSeparately() {
        let lessons = [lesson(id: "ch25s1")]
        let insights = ProgressInsights.dimensionInsights(
            competencyScores: [:],
            lessons: lessons,
            completedLessonIDs: [],
            history: ["ch25s1": [
                attempt(lessonID: "ch25s1", correct: 3, total: 0),
                attempt(lessonID: "ch25s1", correct: 2, total: 4)
            ]]
        )
        let architecture = insights.first { $0.dimension == .architecture }!
        XCTAssertEqual(architecture.quizAttemptCount, 2)
        XCTAssertEqual(architecture.quizAttemptsWithTotal, 1)
        XCTAssertEqual(architecture.quizAttemptsWithoutTotal, 1)
        XCTAssertEqual(architecture.quizAverageFraction!, 0.5, accuracy: 0.001)
    }

    // MARK: - Evidence areas

    private func dimensionInsight(
        dimension: CompetencyStore.CompetencyDimension,
        competency: Double?,
        quizAverage: Double?,
        quizAttemptsWithTotal: Int = 0
    ) -> ProgressDimensionInsight {
        ProgressDimensionInsight(
            dimension: dimension,
            competencyScorePercent: competency,
            quizAverageFraction: quizAverage,
            quizAttemptCount: quizAttemptsWithTotal,
            quizAttemptsWithTotal: quizAttemptsWithTotal,
            quizAttemptsWithoutTotal: 0,
            demonstratedLessonCount: 0,
            lessonsCompleted: 0,
            lessonsTotal: 0
        )
    }

    func testEvidenceAreasSplitByThresholdsAndExcludeNoEvidence() {
        let areas = ProgressInsights.evidenceAreas([
            dimensionInsight(dimension: .architecture, competency: 90, quizAverage: 0.9, quizAttemptsWithTotal: 4),
            dimensionInsight(dimension: .lifecycle, competency: 60, quizAverage: nil),
            dimensionInsight(dimension: .businessAnalysis, competency: nil, quizAverage: 0.5, quizAttemptsWithTotal: 2),
            dimensionInsight(dimension: .exceptionHandling, competency: nil, quizAverage: nil),
            dimensionInsight(dimension: .reconciliation, competency: 85, quizAverage: nil)
        ])
        XCTAssertEqual(areas.stronger.map(\.dimension), [.architecture, .reconciliation])
        XCTAssertEqual(areas.needsAttention.map(\.dimension), [.lifecycle, .businessAnalysis])
        XCTAssertFalse(areas.stronger.contains { $0.dimension == .exceptionHandling })
        XCTAssertFalse(areas.needsAttention.contains { $0.dimension == .exceptionHandling })
    }

    func testContradictingQuizEvidencePreventsStrongerPlacement() {
        // Competency at the bar but quiz below it: needs attention,
        // not stronger. One low source is enough.
        let areas = ProgressInsights.evidenceAreas([
            dimensionInsight(dimension: .architecture, competency: 90, quizAverage: 0.4, quizAttemptsWithTotal: 3)
        ])
        XCTAssertTrue(areas.stronger.isEmpty)
        XCTAssertEqual(areas.needsAttention.count, 1)
    }

    func testEvidenceTextNamesBothSourcesAndMissingSources() {
        let areas = ProgressInsights.evidenceAreas([
            dimensionInsight(dimension: .architecture, competency: 82, quizAverage: 0.84, quizAttemptsWithTotal: 6),
            dimensionInsight(dimension: .lifecycle, competency: nil, quizAverage: 0.5, quizAttemptsWithTotal: 1)
        ])
        let strong = areas.stronger.first { $0.dimension == .architecture }!
        XCTAssertTrue(strong.evidenceText.contains("82%"))
        XCTAssertTrue(strong.evidenceText.contains("84%"))
        XCTAssertTrue(strong.evidenceText.contains("6 attempts"))
        let weak = areas.needsAttention.first { $0.dimension == .lifecycle }!
        XCTAssertTrue(weak.evidenceText.contains("No competency assessment"))
        XCTAssertTrue(weak.evidenceText.contains("50%"))
        XCTAssertTrue(weak.evidenceText.contains("1 attempt"))
    }

    func testNeedsAttentionSortsLowestEvidenceFirst() {
        let areas = ProgressInsights.evidenceAreas([
            dimensionInsight(dimension: .architecture, competency: 70, quizAverage: nil),
            dimensionInsight(dimension: .lifecycle, competency: 40, quizAverage: nil),
            dimensionInsight(dimension: .businessAnalysis, competency: nil, quizAverage: 0.3, quizAttemptsWithTotal: 2)
        ])
        XCTAssertEqual(areas.needsAttention.map(\.dimension), [.lifecycle, .architecture, .businessAnalysis])
    }

    // MARK: - Lab

    func testLabSummaryIsEmptyWithNoResults() {
        let summary = ProgressInsights.labSummary(results: [], totalCases: 12)
        XCTAssertEqual(summary.casesCompleted, 0)
        XCTAssertEqual(summary.totalCases, 12)
        XCTAssertEqual(summary.totalCompletions, 0)
        XCTAssertNil(summary.meanBestFraction)
        XCTAssertNil(summary.lowestBestFraction)
        XCTAssertNil(summary.highestBestFraction)
        XCTAssertEqual(summary.stepsSolvedBestFirst, 0)
    }

    func testLabSummaryMeansBestFractionsAndAggregatesLastBreakdowns() {
        let results = [
            labResult(
                caseID: "lab-a",
                bestTotal: 40,
                bestMaximum: 50,
                completions: 2,
                lastBreakdown: breakdown(total: 35, maximum: 50, bestFirst: 2, recovered: 1, wrongPicks: 1, evidenceOpened: 3, evidenceTotal: 4)
            ),
            labResult(
                caseID: "lab-b",
                bestTotal: 25,
                bestMaximum: 50,
                completions: 1,
                lastBreakdown: breakdown(total: 25, maximum: 50, bestFirst: 1, redHerringPicks: 1, evidenceOpened: 2, evidenceTotal: 4)
            )
        ]
        let summary = ProgressInsights.labSummary(results: results, totalCases: 12)
        XCTAssertEqual(summary.casesCompleted, 2)
        XCTAssertEqual(summary.totalCompletions, 3)
        XCTAssertEqual(summary.meanBestFraction!, 0.65, accuracy: 0.001)
        XCTAssertEqual(summary.lowestBestFraction!, 0.5, accuracy: 0.001)
        XCTAssertEqual(summary.highestBestFraction!, 0.8, accuracy: 0.001)
        XCTAssertEqual(summary.stepsSolvedBestFirst, 3)
        XCTAssertEqual(summary.stepsSolvedAfterWrongTurn, 1)
        XCTAssertEqual(summary.totalWrongPicks, 1)
        XCTAssertEqual(summary.totalRedHerringPicks, 1)
        XCTAssertEqual(summary.evidenceOpenedCount, 5)
        XCTAssertEqual(summary.evidenceTotalCount, 8)
    }

    func testLabFractionIsNilWhenMaximumIsZero() {
        let result = labResult(caseID: "lab-a", bestTotal: 10, bestMaximum: 0)
        XCTAssertNil(ProgressInsights.bestLabFraction(for: result))
        let summary = ProgressInsights.labSummary(results: [result], totalCases: 12)
        XCTAssertEqual(summary.casesCompleted, 1)
        XCTAssertNil(summary.meanBestFraction)
    }

    func testLabCaseInsightsSortMostRecentFirst() {
        let results = [
            labResult(caseID: "lab-old", bestTotal: 10, bestMaximum: 50, dayOffset: -5),
            labResult(caseID: "lab-new", bestTotal: 20, bestMaximum: 50, dayOffset: 0)
        ]
        let insights = ProgressInsights.labCaseInsights(results: results)
        XCTAssertEqual(insights.map(\.caseID), ["lab-new", "lab-old"])
        XCTAssertEqual(insights[0].bestFraction!, 0.4, accuracy: 0.001)
    }

    // MARK: - Time

    func testTimeInsightSplitsLessonAndAudioDurations() {
        let events = [
            event(type: .lessonDuration, lessonID: "ch1s1", durationSeconds: 600),
            event(type: .audioListened, lessonID: "ch1s1", durationSeconds: 300),
            event(type: .lessonCompleted, lessonID: "ch1s1"),
            event(type: .audioListened, lessonID: "ch1s2", durationSeconds: nil),
            event(type: .lessonDuration, lessonID: "ch1s2", durationSeconds: 0)
        ]
        let insight = ProgressInsights.timeInsight(events: events)
        XCTAssertEqual(insight.lessonDurationSeconds, 600)
        XCTAssertEqual(insight.audioSeconds, 300)
        XCTAssertEqual(insight.totalSeconds, 900)
        XCTAssertEqual(insight.lessonDurationEventCount, 1)
        XCTAssertEqual(insight.audioEventCount, 1)
        XCTAssertTrue(insight.hasRecordedTime)
    }

    func testTimeInsightIsZeroWithNoDurations() {
        let insight = ProgressInsights.timeInsight(events: [event(type: .lessonCompleted, lessonID: "ch1s1")])
        XCTAssertEqual(insight.totalSeconds, 0)
        XCTAssertFalse(insight.hasRecordedTime)
    }

    func testDurationLabelFormatsHoursAndMinutes() {
        XCTAssertEqual(ProgressInsights.durationLabel(totalSeconds: 0), "0 min")
        XCTAssertEqual(ProgressInsights.durationLabel(totalSeconds: 2700), "45 min")
        XCTAssertEqual(ProgressInsights.durationLabel(totalSeconds: 3600), "1 hr")
        XCTAssertEqual(ProgressInsights.durationLabel(totalSeconds: 3900), "1 hr 5 min")
        XCTAssertEqual(ProgressInsights.durationLabel(totalSeconds: 7200), "2 hrs")
        XCTAssertEqual(ProgressInsights.durationLabel(totalSeconds: 7800), "2 hrs 10 min")
    }

    // MARK: - Consistency and activity

    func testConsistencyCountsActiveDaysInWindows() {
        let events = [
            event(type: .lessonCompleted, dayOffset: 0),
            event(type: .quizCompleted, dayOffset: 0),
            event(type: .lessonCompleted, dayOffset: -1),
            event(type: .lessonCompleted, dayOffset: -6),
            event(type: .lessonCompleted, dayOffset: -7),
            event(type: .lessonCompleted, dayOffset: -27),
            event(type: .lessonCompleted, dayOffset: -40)
        ]
        let insight = ProgressInsights.consistency(events: events, referenceDate: referenceDate, calendar: utcCalendar)
        XCTAssertEqual(insight.activeDaysLast7, 3)
        XCTAssertEqual(insight.activeDaysLast28, 5)
        XCTAssertEqual(insight.distinctActiveDays, 6)
        XCTAssertEqual(insight.eventCount, 7)
        XCTAssertEqual(insight.lastActivityDate, referenceDate)
    }

    func testConsistencyStreakEndsTodayOrYesterday() {
        let todayRun = ProgressInsights.consistency(
            events: [event(type: .lessonCompleted, dayOffset: 0), event(type: .lessonCompleted, dayOffset: -1), event(type: .lessonCompleted, dayOffset: -2)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(todayRun.streakCount, 3)
        let yesterdayRun = ProgressInsights.consistency(
            events: [event(type: .lessonCompleted, dayOffset: -1), event(type: .lessonCompleted, dayOffset: -2)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(yesterdayRun.streakCount, 2)
        let brokenRun = ProgressInsights.consistency(
            events: [event(type: .lessonCompleted, dayOffset: 0), event(type: .lessonCompleted, dayOffset: -2)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(brokenRun.streakCount, 1)
        let staleRun = ProgressInsights.consistency(
            events: [event(type: .lessonCompleted, dayOffset: -3)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(staleRun.streakCount, 0)
    }

    func testConsistencyIsEmptyWithNoEvents() {
        let insight = ProgressInsights.consistency(events: [], referenceDate: referenceDate, calendar: utcCalendar)
        XCTAssertEqual(insight.activeDaysLast7, 0)
        XCTAssertEqual(insight.activeDaysLast28, 0)
        XCTAssertEqual(insight.distinctActiveDays, 0)
        XCTAssertNil(insight.lastActivityDate)
        XCTAssertNil(insight.firstActivityDate)
        XCTAssertEqual(insight.streakCount, 0)
    }

    func testActivityCountsDistinctLessonsOpenedAndCompleted() {
        let events = [
            event(type: .lessonStarted, lessonID: "ch1s1"),
            event(type: .lessonStarted, lessonID: "ch1s1"),
            event(type: .lessonStarted, lessonID: "ch1s2"),
            event(type: .lessonCompleted, lessonID: "ch1s1"),
            event(type: .quizCompleted, lessonID: "ch1s1"),
            event(type: .audioListened, lessonID: "ch1s1")
        ]
        let counts = ProgressInsights.activityCounts(events: events)
        XCTAssertEqual(counts.distinctLessonsOpened, 2)
        XCTAssertEqual(counts.distinctLessonsCompletedInEvents, 1)
        XCTAssertEqual(counts.quizCompletedEventCount, 1)
        XCTAssertEqual(counts.audioEventCount, 1)
    }

    // MARK: - Pathway

    func testPathwayInsightDedupesAndCountsEvidence() {
        let insight = ProgressInsights.pathwayInsight(
            lessonIDs: ["ch1s1", "ch1s1", "ch1s2", "ch1s3"],
            completedLessonIDs: ["ch1s1", "ch1s2"],
            history: [
                "ch1s1": [attempt(lessonID: "ch1s1", correct: 4, total: 4)],
                "ch1s2": [attempt(lessonID: "ch1s2", correct: 1, total: 4)]
            ],
            source: .activePath
        )
        XCTAssertEqual(insight.total, 3)
        XCTAssertEqual(insight.completed, 2)
        XCTAssertEqual(insight.fraction!, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(insight.demonstratedLessonCount, 1)
        XCTAssertEqual(insight.quizAttemptedLessonCount, 2)
        XCTAssertEqual(insight.source, .activePath)
    }

    func testPathwayFractionIsNilWhenNoLessons() {
        let insight = ProgressInsights.pathwayInsight(
            lessonIDs: [],
            completedLessonIDs: [],
            history: [:],
            source: .none
        )
        XCTAssertNil(insight.fraction)
        XCTAssertEqual(insight.total, 0)
    }

    // MARK: - Certificates

    func testPathCertificateEligibilityNeedsTitleAndFullCompletion() {
        let insights = ProgressInsights.pathCertificateInsights([
            ProgressPathProgress(pathID: "a", pathTitle: "A", certificateTitle: "A Cert", completed: 5, total: 5),
            ProgressPathProgress(pathID: "b", pathTitle: "B", certificateTitle: "B Cert", completed: 3, total: 5),
            ProgressPathProgress(pathID: "c", pathTitle: "C", certificateTitle: nil, completed: 5, total: 5),
            ProgressPathProgress(pathID: "d", pathTitle: "D", certificateTitle: "D Cert", completed: 0, total: 0)
        ])
        XCTAssertTrue(insights[0].isEligible)
        XCTAssertEqual(insights[0].lessonsRemaining, 0)
        XCTAssertFalse(insights[1].isEligible)
        XCTAssertEqual(insights[1].lessonsRemaining, 2)
        XCTAssertFalse(insights[2].isEligible)
        XCTAssertFalse(insights[2].hasCertificate)
        XCTAssertFalse(insights[3].isEligible)
    }

    func testCourseCertificateInsightsCoverPassedOpenAndLocked() {
        let courses = [
            course(id: "a", productID: "com.paymentforge.app.a", name: "Course A"),
            course(id: "b", productID: "com.paymentforge.app.b", name: "Course B"),
            course(id: "c", productID: "com.paymentforge.app.c", name: "Course C"),
            course(id: "d", productID: "com.paymentforge.app.d", name: "Course D")
        ]
        let insights = ProgressInsights.courseCertificateInsights(
            courses: courses,
            certificates: ["com.paymentforge.app.a": certificate(courseID: "com.paymentforge.app.a", correct: 18, total: 20)],
            attemptsUsed: [
                "com.paymentforge.app.a": 1,
                "com.paymentforge.app.b": 1,
                "com.paymentforge.app.c": FinalAssessmentStore.maxAttempts,
                "com.paymentforge.app.d": FinalAssessmentStore.maxAttempts + 2
            ]
        )
        XCTAssertEqual(insights[0].status, .passed)
        XCTAssertTrue(insights[0].isPassed)
        XCTAssertEqual(insights[0].certificate?.scoreText, "18/20")
        XCTAssertEqual(insights[1].status, .attemptsLeft)
        XCTAssertEqual(insights[1].attemptsRemaining, FinalAssessmentStore.maxAttempts - 1)
        XCTAssertEqual(insights[2].status, .locked)
        XCTAssertEqual(insights[2].attemptsRemaining, 0)
        XCTAssertEqual(insights[3].status, .locked)
        XCTAssertEqual(insights[3].attemptsRemaining, 0)
    }

    func testCourseCertificateWithNoAttemptsIsOpen() {
        let insights = ProgressInsights.courseCertificateInsights(
            courses: [course(id: "a", productID: "com.paymentforge.app.a", name: "Course A")],
            certificates: [:],
            attemptsUsed: [:]
        )
        XCTAssertEqual(insights[0].status, .attemptsLeft)
        XCTAssertEqual(insights[0].attemptsUsed, 0)
        XCTAssertEqual(insights[0].attemptsRemaining, FinalAssessmentStore.maxAttempts)
    }

    // MARK: - Studio

    func testStudioSummaryCountsDraftsAndExercisesOnceEach() {
        let drafts = [
            StudioDraft(exerciseID: "ex-1", text: "First draft", updatedAt: Date(timeIntervalSince1970: 1_794_484_800)),
            StudioDraft(exerciseID: "ex-1", text: "Second draft", updatedAt: Date(timeIntervalSince1970: 1_794_571_200)),
            StudioDraft(exerciseID: "ex-2", text: "Reviewed draft", updatedAt: Date(timeIntervalSince1970: 1_794_398_400), aiReviewRequestedAt: Date(timeIntervalSince1970: 1_794_398_400))
        ]
        let summary = ProgressInsights.studioSummary(drafts: drafts, totalExercises: 15)
        XCTAssertEqual(summary.draftsCount, 3)
        XCTAssertEqual(summary.exercisesWithDrafts, 2)
        XCTAssertEqual(summary.totalExercises, 15)
        XCTAssertEqual(summary.aiReviewedDraftCount, 1)
        XCTAssertEqual(summary.lastUpdatedAt, Date(timeIntervalSince1970: 1_794_571_200))
        XCTAssertTrue(summary.hasDrafts)
    }

    func testStudioSummaryIsEmptyWithNoDrafts() {
        let summary = ProgressInsights.studioSummary(drafts: [], totalExercises: 15)
        XCTAssertEqual(summary.draftsCount, 0)
        XCTAssertNil(summary.lastUpdatedAt)
        XCTAssertFalse(summary.hasDrafts)
    }
}
