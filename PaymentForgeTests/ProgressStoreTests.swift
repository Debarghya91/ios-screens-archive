// ProgressStoreTests.swift
// PaymentForge iOS - Phase 7 unit tests: progress synchronisation.
// Events are the source of truth: streak, weekly counts and learning
// hours are all computed from recorded events, and quiz attempts are
// history (appended, never overwritten). Each test starts from a
// clean store and resets in tearDown, so no test leaks progress
// into another test.

import XCTest
@testable import PaymentForge

@MainActor
final class ProgressStoreTests: XCTestCase {

    private var store: ProgressStore!

    override func setUp() {
        super.setUp()
        store = ProgressStore()
        store.resetAll()
        store.weeklyGoal = 5
    }

    override func tearDown() {
        store.resetAll()
        store = nil
        super.tearDown()
    }

    func testEmptyStoreHasZeroStatistics() {
        XCTAssertEqual(store.totalLessonsCompleted, 0)
        XCTAssertEqual(store.streakCount, 0)
        XCTAssertEqual(store.lessonsCompletedThisWeek, 0)
        XCTAssertEqual(store.learningHours(), 0)
        XCTAssertEqual(store.totalQuizAttempts, 0)
        XCTAssertNil(store.averageQuizScore())
        XCTAssertNil(store.lastActivityDate)
    }

    func testMarkLessonCompleteRecordsOneEvent() {
        store.markLessonComplete(id: "ch1s1", title: "What a payment is")
        XCTAssertTrue(store.isLessonComplete("ch1s1"))
        XCTAssertEqual(store.totalLessonsCompleted, 1)
        XCTAssertEqual(store.lessonsCompletedThisWeek, 1)
        XCTAssertEqual(store.streakCount, 1)
        XCTAssertEqual(store.events.filter { $0.type == .lessonCompleted }.count, 1)

        // Completing the same lesson again does not record a second event.
        store.markLessonComplete(id: "ch1s1", title: "What a payment is")
        XCTAssertEqual(store.totalLessonsCompleted, 1)
        XCTAssertEqual(store.events.filter { $0.type == .lessonCompleted }.count, 1)
    }

    func testQuizHistoryIsPreservedNotOverwritten() {
        store.recordQuizScore(lessonID: "ch1s1", correct: 2, total: 3)
        store.recordQuizScore(lessonID: "ch1s1", correct: 3, total: 3)
        XCTAssertEqual(store.totalQuizAttempts, 2)
        XCTAssertEqual(store.quizAttempts(for: "ch1s1").count, 2)
        XCTAssertEqual(store.quizScore(for: "ch1s1"), 3, "Best correct count across attempts.")
        XCTAssertEqual(store.quizAttempts(for: "ch1s1").first?.correct, 2, "The first attempt is kept, not replaced.")
        XCTAssertEqual(store.quizAttempts(for: "ch1s1").last?.correct, 3)
        let average = store.averageQuizScore(for: "ch1s1")
        XCTAssertNotNil(average)
        XCTAssertEqual(average!, (2.0 / 3.0 + 1.0) / 2.0, accuracy: 0.001)
    }

    func testQuizScoreIsNilWithNoAttempts() {
        XCTAssertNil(store.quizScore(for: "ch9s9"))
        XCTAssertTrue(store.quizAttempts(for: "ch9s9").isEmpty)
        XCTAssertNil(store.averageQuizScore(for: "ch9s9"))
    }

    func testWeeklyProgressComesFromEvents() {
        store.markLessonComplete(id: "ch1s1", title: "Lesson 1")
        store.markLessonComplete(id: "ch1s2", title: "Lesson 2")
        XCTAssertEqual(store.lessonsCompletedThisWeek, 2)
        XCTAssertEqual(store.weeklyProgress, 2.0 / 5.0, accuracy: 0.001)
    }

    func testLearningHoursComeOnlyFromRecordedDurations() {
        XCTAssertEqual(store.learningHours(), 0)
        store.recordAudioListened(lessonID: "ch1s1", seconds: 3600)
        XCTAssertEqual(store.learningHours(), 1.0, accuracy: 0.001)
        XCTAssertEqual(store.learningMinutes, 60)
        // Zero or negative durations are ignored, never recorded.
        store.recordAudioListened(lessonID: "ch1s1", seconds: 0)
        store.recordAudioListened(lessonID: "ch1s1", seconds: -30)
        XCTAssertEqual(store.learningHours(), 1.0, accuracy: 0.001)
    }

    func testWeeklyActivityHasSevenDaysEndingToday() {
        store.recordLessonStarted(lessonID: "ch1s1")
        let week = store.weeklyActivity()
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.last?.count, 1, "Today has the one recorded event.")
        XCTAssertTrue(week.dropLast().allSatisfy { $0.count == 0 })
        XCTAssertEqual(store.dailyActivity(on: Date()), 1)
    }

    func testStreakCountsTodayOnlyWhenNothingBefore() {
        XCTAssertEqual(store.streakCount, 0)
        store.recordLessonStarted(lessonID: "ch1s1")
        XCTAssertEqual(store.streakCount, 1)
    }

    func testExportImportRoundTripPreservesHistory() {
        store.markLessonComplete(id: "ch1s1", title: "Lesson 1")
        store.recordQuizScore(lessonID: "ch1s1", correct: 2, total: 3)
        store.recordQuizScore(lessonID: "ch1s1", correct: 3, total: 3)
        let exported = store.exportProgressDictionary()

        store.resetAll()
        XCTAssertEqual(store.totalLessonsCompleted, 0)

        store.importProgress(from: exported)
        XCTAssertTrue(store.isLessonComplete("ch1s1"))
        XCTAssertEqual(store.quizAttempts(for: "ch1s1").count, 2, "Import appends history, it does not collapse it to a best score.")
        XCTAssertEqual(store.quizScore(for: "ch1s1"), 3)
        XCTAssertEqual(store.lastLessonID, "ch1s1")
    }

    func testResetAllClearsProgressButKeepsWeeklyGoal() {
        store.markLessonComplete(id: "ch1s1", title: "Lesson 1")
        store.recordQuizScore(lessonID: "ch1s1", correct: 3, total: 3)
        store.weeklyGoal = 7
        store.resetAll()
        XCTAssertEqual(store.totalLessonsCompleted, 0)
        XCTAssertTrue(store.quizHistory.isEmpty)
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertEqual(store.streakCount, 0)
        XCTAssertEqual(store.weeklyGoal, 7, "The weekly goal is a preference, not progress.")
    }
}
