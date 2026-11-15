// AnalyticsTests.swift
// PaymentForge iOS - Phase 4 (item 31) tests: the local analytics
// event layer, opt-in consent, first-occurrence semantics, score
// improvement, the event catalogue, account isolation, and the
// optional local log.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the final app source before writing.
//
// No test requires network: consent, recording, the buffer, and the
// local log are all local. All tests run in test-only namespaces
// that tearDown removes, and the namespace is reset to guest
// afterwards. Tests assume serial execution, like the other suites
// in this target: the service is a singleton with an in-memory
// buffer, so parallel test classes recording events would interleave.
//
// No em dashes in any user-facing text.

import XCTest
@testable import PaymentForge

final class AnalyticsTests: XCTestCase {

    private let testNamespace = "test-analytics"
    private let secondNamespace = "test-analytics-b"
    private let lastLaunchDayBaseKey = "pf.analytics.lastLaunchDay.v1"

    private var service: AnalyticsService { AnalyticsService.shared }

    private func recordedNames() -> [String] {
        service.recordedEvents.map { $0.name }
    }

    override func setUp() {
        super.setUp()
        AccountScopedStorage.setCurrentNamespace(testNamespace)
        AccountScopedStorage.removeAllKeys(in: testNamespace)
        service.deleteLocalLogForCurrentAccount()
        service.reloadForCurrentAccount()
    }

    override func tearDown() {
        service.deleteLocalLogForCurrentAccount()
        AccountScopedStorage.removeAllKeys(in: testNamespace)
        AccountScopedStorage.removeAllKeys(in: secondNamespace)
        AccountScopedStorage.setCurrentNamespace(nil)
        service.reloadForCurrentAccount()
        super.tearDown()
    }

    // MARK: - Consent defaults and decisions

    func testConsentDefaultsOffWithNoDecision() {
        XCTAssertFalse(service.isConsented)
        XCTAssertFalse(service.hasMadeConsentDecision)
        XCTAssertFalse(service.isLocalLogEnabled)
        XCTAssertTrue(service.recordedEvents.isEmpty)
    }

    func testDeclineRecordsDecisionAndStaysOff() {
        service.declineConsent()
        XCTAssertFalse(service.isConsented)
        XCTAssertTrue(service.hasMadeConsentDecision)
        service.track(.appLaunched)
        XCTAssertTrue(service.recordedEvents.isEmpty)
    }

    func testGrantEnablesRecording() {
        service.grantConsent()
        XCTAssertTrue(service.isConsented)
        XCTAssertTrue(service.hasMadeConsentDecision)
        service.track(.appLaunched)
        XCTAssertEqual(recordedNames(), ["app_launched"])
    }

    func testNoEventsRecordedBeforeConsent() {
        service.track(.purchaseCompleted(productID: "com.paymentforge.app.integrated"))
        service.track(.lessonCompleted(lessonID: "ch1s1", chapterID: "ch1"))
        service.track(.syncFailed(failureCategory: "network"))
        XCTAssertTrue(service.recordedEvents.isEmpty)
        XCTAssertEqual(service.debugExportJSON(), "[]")
    }

    func testGrantDoesNotEmitRetroactiveEvents() {
        service.recordLessonStarted(lessonID: "ch1s1", chapterID: "ch1")
        service.recordAppLaunch()
        service.grantConsent()
        XCTAssertTrue(service.recordedEvents.isEmpty)
    }

    func testWithdrawStopsRecordingAndPurgesBuffer() {
        service.grantConsent()
        service.track(.appLaunched)
        XCTAssertEqual(service.recordedEventCount, 1)
        service.withdrawConsent()
        XCTAssertFalse(service.isConsented)
        XCTAssertTrue(service.hasMadeConsentDecision)
        XCTAssertTrue(service.recordedEvents.isEmpty)
        service.track(.appLaunched)
        XCTAssertTrue(service.recordedEvents.isEmpty)
    }

    func testWithdrawClearsPreviousScoresButKeepsFirstFlags() {
        service.grantConsent()
        service.recordLessonStarted(lessonID: "ch1s1", chapterID: "ch1")
        service.recordAssessmentCompleted(dimension: "Lifecycle", correct: 2, total: 5, elapsedSeconds: 60, unansweredCount: 0)
        service.withdrawConsent()
        service.grantConsent()
        service.recordLessonStarted(lessonID: "ch1s2", chapterID: "ch1")
        service.recordAssessmentCompleted(dimension: "Lifecycle", correct: 4, total: 5, elapsedSeconds: 50, unansweredCount: 0)
        // No second first_lesson_started: the first flag survived
        // withdrawal. No score_improved: the previous score was
        // cleared by withdrawal, so the 80 percent score has
        // nothing real to improve on.
        XCTAssertEqual(recordedNames(), ["lesson_started", "assessment_completed"])
    }

    // MARK: - Launch and return markers

    func testRecordAppLaunchEmitsFirstLaunchAndAppLaunchedOnce() {
        service.grantConsent()
        service.recordAppLaunch()
        service.recordAppLaunch()
        XCTAssertEqual(recordedNames(), ["first_launch", "app_launched"])
    }

    func testRecordAppLaunchWithoutConsentConsumesNothing() {
        service.recordAppLaunch()
        XCTAssertTrue(service.recordedEvents.isEmpty)
        service.grantConsent()
        service.recordAppLaunch()
        XCTAssertEqual(recordedNames(), ["first_launch", "app_launched"])
    }

    func testReloadAllowsFreshLaunchRecordWithoutRepeatingFirstLaunch() {
        service.grantConsent()
        service.recordAppLaunch()
        XCTAssertEqual(recordedNames(), ["first_launch", "app_launched"])
        service.reloadForCurrentAccount()
        // Reload clears the in-memory buffer for the new account
        // state, but the first-launch flag persists in storage.
        XCTAssertTrue(service.recordedEvents.isEmpty)
        service.recordAppLaunch()
        XCTAssertEqual(recordedNames(), ["app_launched"])
    }

    func testReturnAfterAbsenceEmitsWhenLastLaunchWasFiveDaysAgo() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        UserDefaults.standard.set(
            formatter.string(from: fiveDaysAgo),
            forKey: AccountScopedStorage.currentKey(lastLaunchDayBaseKey)
        )
        service.grantConsent()
        service.recordAppLaunch()
        XCTAssertEqual(recordedNames(), ["first_launch", "return_after_absence", "app_launched"])
        let marker = service.recordedEvents.first { $0.name == "return_after_absence" }
        XCTAssertEqual(marker?.properties["days_since_last_launch"], AnalyticsPropertyValue.integer(5))
    }

    func testNoReturnMarkerForYesterday() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        UserDefaults.standard.set(
            formatter.string(from: yesterday),
            forKey: AccountScopedStorage.currentKey(lastLaunchDayBaseKey)
        )
        service.grantConsent()
        service.recordAppLaunch()
        XCTAssertEqual(recordedNames(), ["first_launch", "app_launched"])
    }

    // MARK: - First-occurrence semantics

    func testFirstLessonStartedEmittedOnce() {
        service.grantConsent()
        service.recordLessonStarted(lessonID: "ch1s1", chapterID: "ch1")
        service.recordLessonStarted(lessonID: "ch1s2", chapterID: "ch1")
        XCTAssertEqual(recordedNames(), ["lesson_started", "first_lesson_started", "lesson_started"])
    }

    func testFirstLessonCompletedEmittedOnce() {
        service.grantConsent()
        service.recordLessonCompleted(lessonID: "ch1s1", chapterID: "ch1")
        service.recordLessonCompleted(lessonID: "ch1s2", chapterID: "ch1")
        XCTAssertEqual(recordedNames().filter { $0 == "first_lesson_completed" }.count, 1)
        XCTAssertEqual(recordedNames().filter { $0 == "lesson_completed" }.count, 2)
    }

    func testFirstQuizCompletedEmittedOnce() {
        service.grantConsent()
        service.recordQuizCompleted(lessonID: "ch1s1", correct: 3, total: 4)
        service.recordQuizCompleted(lessonID: "ch1s2", correct: 4, total: 4)
        XCTAssertEqual(recordedNames().filter { $0 == "first_quiz_completed" }.count, 1)
        XCTAssertEqual(recordedNames().filter { $0 == "quiz_completed" }.count, 2)
    }

    func testFirstPathSelectedAndPathContinued() {
        service.grantConsent()
        service.recordPathSelected(pathID: "path-ba", role: "Business Analyst")
        service.recordPathSelected(pathID: "path-po", role: "Product Owner")
        service.recordPathContinued(pathID: "path-ba")
        XCTAssertEqual(recordedNames(), ["path_selected", "first_path_selected", "path_selected", "path_continued"])
        let first = service.recordedEvents.first { $0.name == "first_path_selected" }
        XCTAssertEqual(first?.properties["path_id"], AnalyticsPropertyValue.string("path-ba"))
        XCTAssertEqual(first?.properties["role"], AnalyticsPropertyValue.string("Business Analyst"))
    }

    func testFirstPracticalExerciseCompletedEmittedOnce() {
        service.grantConsent()
        service.recordPracticalExerciseCompleted(exerciseID: "studio-1", kind: "studio")
        service.recordPracticalExerciseCompleted(exerciseID: "lab-1", kind: "lab")
        XCTAssertEqual(recordedNames().filter { $0 == "first_practical_exercise_completed" }.count, 1)
        XCTAssertEqual(recordedNames().filter { $0 == "practical_exercise_completed" }.count, 2)
    }

    func testFirstChallengeCompletedEmittedOnce() {
        service.grantConsent()
        service.recordChallengeViewed()
        service.recordChallengeCompleted(correct: false)
        service.recordChallengeCompleted(correct: true)
        XCTAssertEqual(recordedNames(), ["challenge_viewed", "challenge_completed", "first_challenge_completed", "challenge_completed"])
    }

    // MARK: - Assessments and improvement

    func testAssessmentStartAndCompletionProperties() {
        service.grantConsent()
        service.recordAssessmentStarted(dimension: "Lifecycle", questionCount: 5, timed: true, randomised: true)
        service.recordAssessmentCompleted(dimension: "Lifecycle", correct: 4, total: 5, elapsedSeconds: 120, unansweredCount: 1)
        XCTAssertEqual(recordedNames(), ["assessment_started", "assessment_completed"])
        let completed = service.recordedEvents.first { $0.name == "assessment_completed" }
        XCTAssertEqual(completed?.properties["dimension"], AnalyticsPropertyValue.string("Lifecycle"))
        XCTAssertEqual(completed?.properties["correct"], AnalyticsPropertyValue.integer(4))
        XCTAssertEqual(completed?.properties["total"], AnalyticsPropertyValue.integer(5))
        XCTAssertEqual(completed?.properties["score_percent"], AnalyticsPropertyValue.number(80))
        XCTAssertEqual(completed?.properties["elapsed_seconds"], AnalyticsPropertyValue.integer(120))
        XCTAssertEqual(completed?.properties["unanswered_count"], AnalyticsPropertyValue.integer(1))
    }

    func testScoreImprovedFiresOnlyOnNewBest() {
        service.grantConsent()
        service.recordAssessmentCompleted(dimension: "Lifecycle", correct: 2, total: 5, elapsedSeconds: 60, unansweredCount: 0)
        service.recordAssessmentCompleted(dimension: "Lifecycle", correct: 4, total: 5, elapsedSeconds: 55, unansweredCount: 0)
        service.recordAssessmentCompleted(dimension: "Lifecycle", correct: 3, total: 5, elapsedSeconds: 50, unansweredCount: 0)
        service.recordAssessmentCompleted(dimension: "Lifecycle", correct: 4, total: 5, elapsedSeconds: 45, unansweredCount: 0)
        let improved = service.recordedEvents.filter { $0.name == "score_improved" }
        XCTAssertEqual(improved.count, 1)
        XCTAssertEqual(improved.first?.properties["kind"], AnalyticsPropertyValue.string("assessment"))
        XCTAssertEqual(improved.first?.properties["scope_id"], AnalyticsPropertyValue.string("Lifecycle"))
        XCTAssertEqual(improved.first?.properties["previous_score_percent"], AnalyticsPropertyValue.number(40))
        XCTAssertEqual(improved.first?.properties["current_score_percent"], AnalyticsPropertyValue.number(80))
    }

    func testScoreImprovedIsScopedPerDimension() {
        service.grantConsent()
        service.recordAssessmentCompleted(dimension: "Lifecycle", correct: 2, total: 5, elapsedSeconds: 60, unansweredCount: 0)
        service.recordAssessmentCompleted(dimension: "Architecture", correct: 5, total: 5, elapsedSeconds: 60, unansweredCount: 0)
        XCTAssertTrue(service.recordedEvents.filter { $0.name == "score_improved" }.isEmpty)
    }

    func testQuizImprovementIsScopedPerLesson() {
        service.grantConsent()
        service.recordQuizCompleted(lessonID: "ch1s1", correct: 2, total: 4)
        service.recordQuizCompleted(lessonID: "ch1s1", correct: 4, total: 4)
        service.recordQuizCompleted(lessonID: "ch1s2", correct: 4, total: 4)
        XCTAssertEqual(service.recordedEvents.filter { $0.name == "score_improved" }.count, 1)
    }

    func testFinalAssessmentStartCompletionAndCertificate() {
        service.grantConsent()
        service.recordFinalAssessmentStarted(productID: "com.paymentforge.app.part-1", attemptNumber: 2, isResume: true)
        service.recordFinalAssessmentCompleted(productID: "com.paymentforge.app.part-1", attemptNumber: 2, correct: 16, total: 20, passed: true, elapsedSeconds: 900, unansweredCount: 0)
        service.recordCertificateEarned(productID: "com.paymentforge.app.part-1")
        XCTAssertEqual(recordedNames(), ["final_assessment_started", "final_assessment_completed", "certificate_earned"])
        let started = service.recordedEvents.first { $0.name == "final_assessment_started" }
        XCTAssertEqual(started?.properties["attempt_number"], AnalyticsPropertyValue.integer(2))
        XCTAssertEqual(started?.properties["is_resume"], AnalyticsPropertyValue.boolean(true))
        let completed = service.recordedEvents.first { $0.name == "final_assessment_completed" }
        XCTAssertEqual(completed?.properties["passed"], AnalyticsPropertyValue.boolean(true))
        XCTAssertEqual(completed?.properties["score_percent"], AnalyticsPropertyValue.number(80))
    }

    // MARK: - Monetisation and technical events

    func testMonetisationFunnelEvents() {
        service.grantConsent()
        service.recordPaywallViewed(source: "lesson", productID: nil)
        service.recordPaywallViewed(source: "situations", productID: "com.paymentforge.app.practice")
        service.recordProductSelected(productID: "com.paymentforge.app.integrated", source: "purchases")
        service.recordPurchaseStarted(productID: "com.paymentforge.app.integrated")
        service.recordPurchaseCompleted(productID: "com.paymentforge.app.integrated")
        service.recordPurchaseFailed(productID: "com.paymentforge.app.integrated", failureCategory: "verificationFailed")
        service.recordPurchaseCancelled(productID: "com.paymentforge.app.integrated")
        service.recordRestoreStarted()
        service.recordRestoreCompleted(restoredCount: 0)
        service.recordRestoreFailed(failureCategory: "network")
        service.recordEntitlementRevoked(productID: "com.paymentforge.app.integrated", reason: "revoked")
        XCTAssertEqual(recordedNames(), [
            "paywall_viewed", "paywall_viewed", "product_selected",
            "purchase_started", "purchase_completed", "purchase_failed",
            "purchase_cancelled", "restore_started", "restore_completed",
            "restore_failed", "entitlement_revoked",
        ])
        let cataloguePaywall = service.recordedEvents[0]
        XCTAssertNil(cataloguePaywall.properties["product_id"])
        let completed = service.recordedEvents.first { $0.name == "purchase_completed" }
        XCTAssertEqual(Set(completed?.properties.keys ?? []), ["product_id"])
    }

    func testTechnicalEvents() {
        service.grantConsent()
        service.recordContentLoadFailed(kind: "assessmentQuestions", failureCategory: "catalogueNotLoaded")
        service.recordLessonLoadFailed(lessonID: "ch1s1", failureCategory: "network")
        service.recordAudioPlaybackFailed(lessonID: "ch1s1", failureCategory: "playbackFailed")
        service.recordAudioDownloadFailed(lessonID: "ch1s1", failureCategory: "network")
        service.recordSyncFailed(failureCategory: "network")
        service.recordSearchNoResults(source: "search")
        XCTAssertEqual(recordedNames(), [
            "content_load_failed", "lesson_load_failed",
            "audio_playback_failed", "audio_download_failed",
            "sync_failed", "search_no_results",
        ])
        let search = service.recordedEvents.first { $0.name == "search_no_results" }
        XCTAssertEqual(Set(search?.properties.keys ?? []), ["source"])
        let playback = service.recordedEvents.first { $0.name == "audio_playback_failed" }
        XCTAssertEqual(Set(playback?.properties.keys ?? []), ["lesson_id", "failure_category"])
    }

    // MARK: - Catalogue integrity

    func testCatalogueNamesAndCategories() {
        let cases: [(AnalyticsEvent, String, String)] = [
            (.firstLaunch, "first_launch", "acquisition"),
            (.firstLessonStarted(lessonID: "ch1s1", chapterID: "ch1"), "first_lesson_started", "acquisition"),
            (.lessonStarted(lessonID: "ch1s1", chapterID: "ch1"), "lesson_started", "activation"),
            (.lessonCompleted(lessonID: "ch1s1", chapterID: "ch1"), "lesson_completed", "activation"),
            (.firstLessonCompleted(lessonID: "ch1s1", chapterID: "ch1"), "first_lesson_completed", "activation"),
            (.quizCompleted(lessonID: "ch1s1", correct: 1, total: 2, scorePercent: 50), "quiz_completed", "activation"),
            (.firstQuizCompleted(lessonID: "ch1s1", correct: 1, total: 2, scorePercent: 50), "first_quiz_completed", "activation"),
            (.practicalExerciseCompleted(exerciseID: "studio-1", kind: "studio"), "practical_exercise_completed", "activation"),
            (.firstPracticalExerciseCompleted(exerciseID: "studio-1", kind: "studio"), "first_practical_exercise_completed", "activation"),
            (.pathSelected(pathID: "path-ba", role: "Business Analyst"), "path_selected", "activation"),
            (.firstPathSelected(pathID: "path-ba", role: "Business Analyst"), "first_path_selected", "activation"),
            (.appLaunched, "app_launched", "retention"),
            (.returnAfterAbsence(daysSinceLastLaunch: 3), "return_after_absence", "retention"),
            (.pathContinued(pathID: "path-ba"), "path_continued", "retention"),
            (.challengeViewed, "challenge_viewed", "retention"),
            (.challengeCompleted(correct: true), "challenge_completed", "retention"),
            (.firstChallengeCompleted(correct: true), "first_challenge_completed", "retention"),
            (.assessmentStarted(dimension: "Lifecycle", questionCount: 5, timed: false, randomised: true), "assessment_started", "learning_effectiveness"),
            (.assessmentCompleted(dimension: "Lifecycle", correct: 4, total: 5, scorePercent: 80, elapsedSeconds: 60, unansweredCount: 0), "assessment_completed", "learning_effectiveness"),
            (.finalAssessmentStarted(productID: "com.paymentforge.app.integrated", attemptNumber: 1, isResume: false), "final_assessment_started", "learning_effectiveness"),
            (.finalAssessmentCompleted(productID: "com.paymentforge.app.integrated", attemptNumber: 1, correct: 15, total: 20, passed: true, scorePercent: 75, elapsedSeconds: 900, unansweredCount: 0), "final_assessment_completed", "learning_effectiveness"),
            (.scoreImproved(kind: "quiz", scopeID: "ch1s1", previousScorePercent: 50, currentScorePercent: 100), "score_improved", "learning_effectiveness"),
            (.certificateEarned(productID: "com.paymentforge.app.integrated"), "certificate_earned", "learning_effectiveness"),
            (.paywallViewed(source: "lesson", productID: nil), "paywall_viewed", "monetisation"),
            (.productSelected(productID: "com.paymentforge.app.integrated", source: "purchases"), "product_selected", "monetisation"),
            (.purchaseStarted(productID: "com.paymentforge.app.integrated"), "purchase_started", "monetisation"),
            (.purchaseCompleted(productID: "com.paymentforge.app.integrated"), "purchase_completed", "monetisation"),
            (.purchaseFailed(productID: "com.paymentforge.app.integrated", failureCategory: "network"), "purchase_failed", "monetisation"),
            (.purchaseCancelled(productID: "com.paymentforge.app.integrated"), "purchase_cancelled", "monetisation"),
            (.restoreStarted, "restore_started", "monetisation"),
            (.restoreCompleted(restoredCount: 2), "restore_completed", "monetisation"),
            (.restoreFailed(failureCategory: "network"), "restore_failed", "monetisation"),
            (.entitlementRevoked(productID: "com.paymentforge.app.integrated", reason: "revoked"), "entitlement_revoked", "monetisation"),
            (.contentLoadFailed(kind: "catalogue", failureCategory: "network"), "content_load_failed", "technical_quality"),
            (.lessonLoadFailed(lessonID: "ch1s1", failureCategory: "network"), "lesson_load_failed", "technical_quality"),
            (.audioPlaybackFailed(lessonID: "ch1s1", failureCategory: "playbackFailed"), "audio_playback_failed", "technical_quality"),
            (.audioDownloadFailed(lessonID: "ch1s1", failureCategory: "network"), "audio_download_failed", "technical_quality"),
            (.syncFailed(failureCategory: "network"), "sync_failed", "technical_quality"),
            (.searchNoResults(source: "search"), "search_no_results", "technical_quality"),
        ]
        XCTAssertEqual(cases.count, 39)
        for (event, expectedName, expectedCategory) in cases {
            XCTAssertEqual(event.name, expectedName)
            XCTAssertEqual(event.category.rawValue, expectedCategory)
        }
        XCTAssertEqual(Set(cases.map { $0.1 }).count, cases.count, "Event names must be unique.")
        XCTAssertEqual(Set(cases.map { $0.2 }), Set(AnalyticsEventCategory.allCases.map { $0.rawValue }), "Every category must have at least one event.")
    }

    // MARK: - Buffer, sanitisation, export, and local log

    func testBufferCapsAtTwoHundredOldestFirstOut() {
        service.grantConsent()
        for index in 0..<250 {
            service.track(.lessonStarted(lessonID: "lesson-\(index)", chapterID: "ch1"))
        }
        XCTAssertEqual(service.recordedEventCount, AnalyticsService.maxBufferedEvents)
        XCTAssertEqual(service.recordedEvents.first?.properties["lesson_id"], AnalyticsPropertyValue.string("lesson-50"))
        XCTAssertEqual(service.recordedEvents.last?.properties["lesson_id"], AnalyticsPropertyValue.string("lesson-249"))
    }

    func testStringPropertiesAreSanitised() {
        service.grantConsent()
        let longText = String(repeating: "x", count: 300) + "\nsecond line"
        service.track(.assessmentStarted(dimension: longText, questionCount: 5, timed: false, randomised: false))
        guard case .string(let stored) = service.recordedEvents.first?.properties["dimension"] else {
            return XCTFail("Expected a string dimension property.")
        }
        XCTAssertEqual(stored.count, AnalyticsService.maxPropertyLength)
        XCTAssertFalse(stored.contains("\n"))
    }

    func testDebugExportIsValidJSONWithoutIdentifiers() {
        service.grantConsent()
        service.track(.appLaunched)
        service.track(.challengeViewed)
        let export = service.debugExportJSON()
        XCTAssertFalse(export.contains(testNamespace))
        XCTAssertFalse(export.contains("email"))
        guard let data = export.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return XCTFail("Expected the export to parse as a JSON array.")
        }
        XCTAssertEqual(json.count, 2)
        XCTAssertEqual(json[0]["name"] as? String, "app_launched")
        XCTAssertEqual(json[1]["name"] as? String, "challenge_viewed")
    }

    func testRecordCodableRoundTrip() throws {
        // Whole-second timestamp: ISO8601 encoding without
        // fractional seconds truncates sub-second precision, so a
        // Date() timestamp would not round-trip exactly.
        let record = AnalyticsRecord(
            name: "quiz_completed",
            category: "activation",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            properties: [
                "lesson_id": .string("ch1s1"),
                "correct": .integer(3),
                "score_percent": .number(75),
                "passed": .boolean(true),
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AnalyticsRecord.self, from: data)
        XCTAssertEqual(decoded, record)
    }

    func testLocalLogWritesAndDeletes() throws {
        service.grantConsent()
        service.setLocalLogEnabled(true)
        XCTAssertTrue(service.isLocalLogEnabled)
        service.track(.appLaunched)
        let url = service.localLogFileURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("app_launched"))
        service.deleteLocalLogForCurrentAccount()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testLocalLogStaysEmptyWhenDisabled() {
        service.grantConsent()
        XCTAssertFalse(service.isLocalLogEnabled)
        service.track(.appLaunched)
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.localLogFileURL.path))
    }

    func testWithdrawDeletesLocalLog() throws {
        service.grantConsent()
        service.setLocalLogEnabled(true)
        service.track(.appLaunched)
        XCTAssertTrue(FileManager.default.fileExists(atPath: service.localLogFileURL.path))
        service.withdrawConsent()
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.localLogFileURL.path))
    }

    // MARK: - Account isolation

    func testConsentAndBufferAreAccountScoped() {
        service.grantConsent()
        service.track(.appLaunched)
        XCTAssertEqual(service.recordedEventCount, 1)

        AccountScopedStorage.setCurrentNamespace(secondNamespace)
        service.reloadForCurrentAccount()
        XCTAssertFalse(service.isConsented)
        XCTAssertFalse(service.hasMadeConsentDecision)
        XCTAssertTrue(service.recordedEvents.isEmpty)
        service.track(.appLaunched)
        XCTAssertTrue(service.recordedEvents.isEmpty)

        AccountScopedStorage.setCurrentNamespace(testNamespace)
        service.reloadForCurrentAccount()
        XCTAssertTrue(service.isConsented)
        XCTAssertTrue(service.recordedEvents.isEmpty, "The buffer is in-memory only and does not survive an account change.")
    }
}
