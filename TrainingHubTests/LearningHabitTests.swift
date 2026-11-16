// LearningHabitTests.swift
// TrainingHub iOS - Phase 4 unit tests: the non-manipulative
// learning habit loop (brief item 18). Covers reminder frequency
// and settings values, the store's namespaced persistence and
// account separation, the notification scheduler's request
// construction and copy, the planner's deterministic daily
// question and weekly case picks, neutral streak and weekly
// target wording, honest milestones, and engine-backed objective
// and weak-area invariants. Views are not tested: there is no UI
// test harness in this suite for them.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests
// were never compiled or run. Statically checked only: symbol
// names and signatures were read from the final app source before
// writing. No test calls enableReminders: it requests system
// notification authorisation, which must never be prompted from a
// test. Scheduler tests assert request construction only; no test
// adds a request to the notification centre.
//
// Test namespaces ("test-learning-habit-a" and friends) are
// removed in tearDown, the guest habit key is removed too, and
// the current namespace is reset to guest, so no test leaks state
// into another test file sharing the process. Tests use fresh
// LearningHabitStore instances, never LearningHabitStore.shared.

import XCTest
import UserNotifications
@testable import TrainingHub

@MainActor
final class LearningHabitTests: XCTestCase {

    private let namespaceA = "test-learning-habit-a"
    private let namespaceB = "test-learning-habit-b"

    /// A fixed UTC Gregorian calendar, so day and week numbers do
    /// not depend on the machine running the tests.
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }

    override func setUp() {
        super.setUp()
        AccountScopedStorage.setCurrentNamespace(nil)
        removeHabitKeys(in: AccountScopedStorage.guestNamespace)
        AccountScopedStorage.removeAllKeys(in: namespaceA)
        AccountScopedStorage.removeAllKeys(in: namespaceB)
    }

    override func tearDown() {
        removeHabitKeys(in: AccountScopedStorage.guestNamespace)
        AccountScopedStorage.removeAllKeys(in: namespaceA)
        AccountScopedStorage.removeAllKeys(in: namespaceB)
        AccountScopedStorage.setCurrentNamespace(nil)
        super.tearDown()
    }

    private func removeHabitKeys(in namespace: String) {
        UserDefaults.standard.removeObject(forKey: AccountScopedStorage.key(LearningHabitStore.settingsBaseKey, namespace: namespace))
    }

    private func fixtureQuestions() -> [InterviewQuestion] {
        [
            InterviewQuestion(id: "q1", question: "First question?", answer: "First answer."),
            InterviewQuestion(id: "q2", question: "Second question?", answer: "Second answer."),
            InterviewQuestion(id: "q3", question: "Third question?", answer: "Third answer.")
        ]
    }

    private func sampleProfile() -> OnboardingProfile {
        OnboardingProfile(
            role: .businessAnalyst,
            knowledgeLevel: .intermediate,
            objective: .doTheJobBetter,
            intensity: .steady,
            weeklyTarget: 5,
            diagnosticScore: nil,
            diagnosticTakenAt: nil,
            completedAt: Date(timeIntervalSince1970: 1_700_000_100),
            wasSkipped: false
        )
    }

    // MARK: - Frequency

    func testFrequencyCasesAndRawValues() {
        XCTAssertEqual(LearningHabitReminderFrequency.allCases.count, 3)
        XCTAssertEqual(LearningHabitReminderFrequency.off.rawValue, "off")
        XCTAssertEqual(LearningHabitReminderFrequency.daily.rawValue, "daily")
        XCTAssertEqual(LearningHabitReminderFrequency.weekly.rawValue, "weekly")
    }

    func testFrequencyDisplayTitlesArePresent() {
        XCTAssertEqual(LearningHabitReminderFrequency.off.displayTitle, "Off")
        XCTAssertEqual(LearningHabitReminderFrequency.daily.displayTitle, "Daily")
        XCTAssertEqual(LearningHabitReminderFrequency.weekly.displayTitle, "Weekly")
        for frequency in LearningHabitReminderFrequency.allCases {
            XCTAssertFalse(frequency.scheduleText.isEmpty)
            XCTAssertFalse(frequency.explainer.isEmpty)
        }
    }

    func testWeeklyScheduleTextNamesMonday() {
        XCTAssertEqual(LearningHabitReminderFrequency.weekly.scheduleText, "Every Monday")
        XCTAssertTrue(LearningHabitReminderFrequency.weekly.explainer.contains("Monday"))
    }

    // MARK: - Settings

    func testDefaultSettingsAreOffAtNineAM() {
        let settings = LearningHabitReminderSettings.default
        XCTAssertEqual(settings.frequency, .off)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(settings.hour, 9)
        XCTAssertEqual(settings.minute, 0)
    }

    func testSettingsClampHourAndMinuteIntoRange() {
        let high = LearningHabitReminderSettings(frequency: .daily, hour: 25, minute: 61)
        XCTAssertEqual(high.hour, 23)
        XCTAssertEqual(high.minute, 59)
        let low = LearningHabitReminderSettings(frequency: .daily, hour: -1, minute: -5)
        XCTAssertEqual(low.hour, 0)
        XCTAssertEqual(low.minute, 0)
        let valid = LearningHabitReminderSettings(frequency: .weekly, hour: 18, minute: 30)
        XCTAssertEqual(valid.hour, 18)
        XCTAssertEqual(valid.minute, 30)
    }

    func testSettingsEnabledOnlyWhenFrequencyIsOn() {
        XCTAssertFalse(LearningHabitReminderSettings(frequency: .off, hour: 9, minute: 0).isEnabled)
        XCTAssertTrue(LearningHabitReminderSettings(frequency: .daily, hour: 9, minute: 0).isEnabled)
        XCTAssertTrue(LearningHabitReminderSettings(frequency: .weekly, hour: 9, minute: 0).isEnabled)
    }

    func testSettingsEncodeDecodeRoundTrip() throws {
        for frequency in LearningHabitReminderFrequency.allCases {
            let settings = LearningHabitReminderSettings(frequency: frequency, hour: 7, minute: 45)
            let data = try JSONEncoder().encode(settings)
            let decoded = try JSONDecoder().decode(LearningHabitReminderSettings.self, from: data)
            XCTAssertEqual(decoded, settings)
        }
    }

    // MARK: - Store persistence and account separation

    func testSettingsBaseKeyMatchesTheContract() {
        XCTAssertEqual(LearningHabitStore.settingsBaseKey, "pf.learningHabit.reminderSettings.v1")
    }

    func testFreshStoreDefaultsToRemindersOff() {
        let store = LearningHabitStore()
        XCTAssertEqual(store.reminderSettings, .default)
        XCTAssertFalse(store.remindersEnabled)
        XCTAssertEqual(store.notificationAuthorizationStatus, .notDetermined)
    }

    func testSavePersistsUnderTheNamespacedKey() {
        let store = LearningHabitStore()
        let settings = LearningHabitReminderSettings(frequency: .daily, hour: 8, minute: 15)
        store.saveReminderSettings(settings)
        XCTAssertEqual(store.reminderSettings, settings)
        XCTAssertTrue(store.remindersEnabled)
        let key = AccountScopedStorage.currentKey(LearningHabitStore.settingsBaseKey)
        XCTAssertNotNil(UserDefaults.standard.data(forKey: key), "Settings are persisted as data under the namespaced key.")
        let reloaded = LearningHabitStore()
        XCTAssertEqual(reloaded.reminderSettings, settings)
    }

    func testReloadAcrossNamespacesKeepsAccountsSeparate() {
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let store = LearningHabitStore()
        store.saveReminderSettings(LearningHabitReminderSettings(frequency: .weekly, hour: 18, minute: 30))
        XCTAssertTrue(store.remindersEnabled)

        AccountScopedStorage.setCurrentNamespace(namespaceB)
        store.reloadForCurrentAccount()
        XCTAssertEqual(store.reminderSettings, .default, "A new account starts with reminders off: no settings leak across namespaces.")
        XCTAssertFalse(store.remindersEnabled)

        AccountScopedStorage.setCurrentNamespace(namespaceA)
        store.reloadForCurrentAccount()
        XCTAssertEqual(store.reminderSettings.frequency, .weekly)
        XCTAssertEqual(store.reminderSettings.hour, 18)
        XCTAssertEqual(store.reminderSettings.minute, 30)
    }

    func testReloadDoesNotWriteDefaultsIntoAnEmptyNamespace() {
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let store = LearningHabitStore()
        store.saveReminderSettings(LearningHabitReminderSettings(frequency: .daily, hour: 9, minute: 0))
        AccountScopedStorage.setCurrentNamespace(namespaceB)
        store.reloadForCurrentAccount()
        XCTAssertNil(
            UserDefaults.standard.object(forKey: AccountScopedStorage.key(LearningHabitStore.settingsBaseKey, namespace: namespaceB)),
            "Reloading into an empty namespace must not create a settings key there, or guest migration for it would be blocked."
        )
    }

    func testGuestSettingsMigrateThroughTheSharedMigrationPath() {
        AccountScopedStorage.setCurrentNamespace(nil)
        let guestStore = LearningHabitStore()
        let settings = LearningHabitReminderSettings(frequency: .daily, hour: 7, minute: 45)
        guestStore.saveReminderSettings(settings)
        let migrated = AccountScopedStorage.migrateGuestKeys([LearningHabitStore.settingsBaseKey], to: namespaceA)
        XCTAssertEqual(migrated, [LearningHabitStore.settingsBaseKey])
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let accountStore = LearningHabitStore()
        XCTAssertEqual(accountStore.reminderSettings, settings)
    }

    func testDisableKeepsTheChosenTime() {
        let store = LearningHabitStore()
        store.saveReminderSettings(LearningHabitReminderSettings(frequency: .daily, hour: 20, minute: 30))
        store.disableReminders()
        XCTAssertEqual(store.reminderSettings.frequency, .off)
        XCTAssertEqual(store.reminderSettings.hour, 20)
        XCTAssertEqual(store.reminderSettings.minute, 30)
        XCTAssertFalse(store.remindersEnabled)
    }

    // MARK: - Scheduler requests

    func testSchedulerIdentifiersAreDistinct() {
        XCTAssertEqual(LearningHabitScheduler.dailyRequestIdentifier, "pf.learningHabit.dailyReminder")
        XCTAssertEqual(LearningHabitScheduler.weeklyRequestIdentifier, "pf.learningHabit.weeklyReminder")
        XCTAssertNotEqual(LearningHabitScheduler.dailyRequestIdentifier, LearningHabitScheduler.weeklyRequestIdentifier)
        XCTAssertEqual(
            Set(LearningHabitScheduler.allRequestIdentifiers),
            [LearningHabitScheduler.dailyRequestIdentifier, LearningHabitScheduler.weeklyRequestIdentifier]
        )
    }

    func testNoRequestWhenRemindersAreOff() {
        XCTAssertNil(LearningHabitScheduler.request(for: .default))
        XCTAssertNil(LearningHabitScheduler.content(for: .off))
    }

    func testDailyRequestRepeatsDailyAtTheChosenTime() {
        let settings = LearningHabitReminderSettings(frequency: .daily, hour: 8, minute: 15)
        let request = LearningHabitScheduler.request(for: settings)
        XCTAssertEqual(request?.identifier, LearningHabitScheduler.dailyRequestIdentifier)
        let trigger = request?.trigger as? UNCalendarNotificationTrigger
        XCTAssertNotNil(trigger)
        XCTAssertEqual(trigger?.repeats, true)
        XCTAssertEqual(trigger?.dateComponents.hour, 8)
        XCTAssertEqual(trigger?.dateComponents.minute, 15)
        XCTAssertNil(trigger?.dateComponents.weekday, "A daily trigger matches no weekday.")
    }

    func testWeeklyRequestRepeatsOnMondaysAtTheChosenTime() {
        XCTAssertEqual(LearningHabitScheduler.weeklyReminderWeekday, 2, "Weekday 2 is Monday in DateComponents numbering.")
        let settings = LearningHabitReminderSettings(frequency: .weekly, hour: 18, minute: 30)
        let request = LearningHabitScheduler.request(for: settings)
        XCTAssertEqual(request?.identifier, LearningHabitScheduler.weeklyRequestIdentifier)
        let trigger = request?.trigger as? UNCalendarNotificationTrigger
        XCTAssertNotNil(trigger)
        XCTAssertEqual(trigger?.repeats, true)
        XCTAssertEqual(trigger?.dateComponents.weekday, 2)
        XCTAssertEqual(trigger?.dateComponents.hour, 18)
        XCTAssertEqual(trigger?.dateComponents.minute, 30)
    }

    func testNotificationContentHasNoGuiltOrShameWords() {
        let banned = ["missed", "behind", "forget", "forgot", "guilt", "shame", "lose", "lost", "broken", "should", "must", "don't", "failing", "streak is"]
        for frequency in [LearningHabitReminderFrequency.daily, .weekly] {
            let content = LearningHabitScheduler.content(for: frequency)
            XCTAssertNotNil(content)
            XCTAssertEqual(content?.title, "Payments Training Hub")
            XCTAssertFalse(content?.body.isEmpty == true)
            let body = (content?.body ?? "").lowercased()
            for word in banned {
                XCTAssertFalse(body.contains(word), "Reminder copy must never shame: \(frequency) body contains \(word).")
            }
            XCTAssertFalse(body.unicodeScalars.contains { $0.value == 0x2014 }, "No em dashes in notification copy.")
        }
    }

    // MARK: - Deterministic picks

    func testDayNumberAdvancesByOnePerDay() {
        let calendar = utcCalendar
        let first = Date(timeIntervalSince1970: 86400 * 100)
        let second = Date(timeIntervalSince1970: 86400 * 101)
        XCTAssertEqual(
            LearningHabitPlanner.dayNumber(for: second, calendar: calendar),
            LearningHabitPlanner.dayNumber(for: first, calendar: calendar) + 1
        )
    }

    func testDailyQuestionIsTheSameAllDay() {
        let calendar = utcCalendar
        let questions = fixtureQuestions()
        let morning = Date(timeIntervalSince1970: 86400 * 200 + 3600 * 8)
        let evening = Date(timeIntervalSince1970: 86400 * 200 + 3600 * 20)
        XCTAssertEqual(
            LearningHabitPlanner.dailyQuestion(for: morning, questions: questions, calendar: calendar),
            LearningHabitPlanner.dailyQuestion(for: evening, questions: questions, calendar: calendar)
        )
    }

    func testDailyQuestionChangesAcrossDaysAndStaysInTheBank() {
        let calendar = utcCalendar
        let questions = fixtureQuestions()
        var seen: Set<String> = []
        for dayOffset in 0..<10 {
            let date = Date(timeIntervalSince1970: TimeInterval(86400 * (300 + dayOffset)))
            let pick = LearningHabitPlanner.dailyQuestion(for: date, questions: questions, calendar: calendar)
            XCTAssertNotNil(pick)
            XCTAssertTrue(questions.contains(pick!), "Every daily pick is a real bank question.")
            seen.insert(pick!.id)
        }
        XCTAssertEqual(seen.count, 3, "Ten days rotate through all three fixture questions.")
    }

    func testDailyQuestionIsNilWhenTheBankIsEmpty() {
        XCTAssertNil(LearningHabitPlanner.dailyQuestion(for: Date(), questions: [], calendar: utcCalendar))
    }

    func testWeeklyCaseIsTheSameAllWeekAndStaysInTheCatalogue() {
        let calendar = utcCalendar
        let cases = ExceptionCaseCatalogue.allCases
        XCTAssertFalse(cases.isEmpty)
        let startOfWeek = Date(timeIntervalSince1970: 86400 * 7 * 10)
        let midWeek = Date(timeIntervalSince1970: 86400 * 7 * 10 + 86400 * 3)
        let first = LearningHabitPlanner.weeklyInvestigationCase(for: startOfWeek, cases: cases, calendar: calendar)
        let second = LearningHabitPlanner.weeklyInvestigationCase(for: midWeek, cases: cases, calendar: calendar)
        XCTAssertEqual(first, second, "The weekly case does not change mid-week.")
        XCTAssertTrue(cases.contains(first!), "Every weekly pick is a real lab case.")
    }

    func testWeeklyCaseChangesAcrossWeeks() {
        let calendar = utcCalendar
        let cases = ExceptionCaseCatalogue.allCases
        var seen: Set<String> = []
        for weekOffset in 0..<12 {
            let date = Date(timeIntervalSince1970: TimeInterval(86400 * 7 * (20 + weekOffset)))
            let pick = LearningHabitPlanner.weeklyInvestigationCase(for: date, cases: cases, calendar: calendar)
            XCTAssertNotNil(pick)
            seen.insert(pick!.id)
        }
        XCTAssertGreaterThan(seen.count, 1, "Twelve weeks surface more than one case.")
    }

    func testWeeklyCaseIsNilWhenTheCatalogueIsEmpty() {
        XCTAssertNil(LearningHabitPlanner.weeklyInvestigationCase(for: Date(), cases: [], calendar: utcCalendar))
    }

    // MARK: - Neutral wording

    func testStreakTextIsNeutral() {
        XCTAssertEqual(LearningHabitPlanner.streakText(streakCount: 0), "No streak right now.")
        XCTAssertEqual(LearningHabitPlanner.streakText(streakCount: 1), "1 day in a row.")
        XCTAssertEqual(LearningHabitPlanner.streakText(streakCount: 5), "5 days in a row.")
        XCTAssertEqual(LearningHabitPlanner.streakText(streakCount: -1), "No streak right now.")
        for count in [0, 1, 2, 30] {
            let text = LearningHabitPlanner.streakText(streakCount: count).lowercased()
            XCTAssertFalse(text.contains("start today"))
            XCTAssertFalse(text.contains("missed"))
            XCTAssertFalse(text.contains("don't"))
        }
    }

    func testWeeklyTargetText() {
        XCTAssertEqual(LearningHabitPlanner.weeklyTargetText(completedThisWeek: 3, weeklyGoal: 5), "3 of 5 lessons this week")
        XCTAssertEqual(LearningHabitPlanner.weeklyTargetText(completedThisWeek: 1, weeklyGoal: 1), "1 of 1 lesson this week")
        XCTAssertEqual(LearningHabitPlanner.weeklyTargetText(completedThisWeek: 0, weeklyGoal: 0), "Weekly target not set")
        XCTAssertEqual(LearningHabitPlanner.weeklyTargetText(completedThisWeek: 0, weeklyGoal: -2), "Weekly target not set")
    }

    // MARK: - Milestones

    func testMilestonesIncludeTheWholeCatalogueThreshold() {
        let milestones = LearningHabitPlanner.milestones(completedCount: 0)
        XCTAssertTrue(milestones.contains { $0.threshold == ContentManifest.lessonCount })
        XCTAssertEqual(milestones.map(\.threshold), milestones.map(\.threshold).sorted(), "Milestones are in threshold order.")
        XCTAssertEqual(Set(milestones.map(\.threshold)).count, milestones.count, "No threshold repeats.")
        XCTAssertTrue(milestones.allSatisfy { $0.threshold <= ContentManifest.lessonCount })
    }

    func testMilestoneTitles() {
        let milestones = LearningHabitPlanner.milestones(completedCount: 0)
        XCTAssertEqual(milestones.first?.title, "First lesson complete")
        XCTAssertEqual(milestones.first { $0.threshold == 5 }?.title, "5 lessons complete")
        XCTAssertEqual(
            milestones.first { $0.threshold == ContentManifest.lessonCount }?.title,
            "All \(ContentManifest.lessonCount) lessons complete"
        )
    }

    func testMilestoneReachedFlagsFollowRecordedCompletions() {
        let none = LearningHabitPlanner.milestones(completedCount: 0)
        XCTAssertTrue(none.allSatisfy { !$0.isReached })
        let twelve = LearningHabitPlanner.milestones(completedCount: 12)
        XCTAssertTrue(twelve.filter { $0.threshold <= 10 }.allSatisfy(\.isReached))
        XCTAssertFalse(twelve.filter { $0.threshold > 12 }.contains { $0.isReached })
        let all = LearningHabitPlanner.milestones(completedCount: ContentManifest.lessonCount)
        XCTAssertTrue(all.allSatisfy(\.isReached))
    }

    func testNextMilestone() {
        XCTAssertEqual(LearningHabitPlanner.nextMilestone(completedCount: 0)?.threshold, 1)
        XCTAssertEqual(LearningHabitPlanner.nextMilestone(completedCount: 1)?.threshold, 5)
        XCTAssertEqual(LearningHabitPlanner.nextMilestone(completedCount: 5)?.threshold, 10)
        XCTAssertEqual(LearningHabitPlanner.nextMilestone(completedCount: 500)?.threshold, ContentManifest.lessonCount)
        XCTAssertNil(LearningHabitPlanner.nextMilestone(completedCount: ContentManifest.lessonCount))
        XCTAssertNil(LearningHabitPlanner.nextMilestone(completedCount: ContentManifest.lessonCount + 10))
    }

    // MARK: - Completion today

    func testDidCompleteLessonTodayFollowsRecordedEvents() {
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let progress = ProgressStore()
        progress.resetAll()
        XCTAssertFalse(LearningHabitPlanner.didCompleteLessonToday("ch1s1", progress: progress))
        progress.markLessonComplete(id: "ch1s1", title: "Lesson 1")
        XCTAssertTrue(LearningHabitPlanner.didCompleteLessonToday("ch1s1", progress: progress))
        XCTAssertFalse(LearningHabitPlanner.didCompleteLessonToday("ch1s2", progress: progress))
        progress.resetAll()
    }

    // MARK: - Engine-backed invariants

    func testDailyObjectiveIsNilOrACatalogueLesson() {
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let progress = ProgressStore()
        progress.resetAll()
        let competency = CompetencyStore()
        let service = ContentService.shared
        let objective = LearningHabitPlanner.dailyObjective(
            for: sampleProfile(),
            progress: progress,
            competency: competency,
            service: service
        )
        if let objective {
            XCTAssertTrue(service.allLessons.contains(objective.lesson), "An objective always names a real catalogue lesson.")
            XCTAssertFalse(objective.reason.isEmpty, "An objective always carries the engine's reason.")
        }
        progress.resetAll()
    }

    func testWeakAreaRecommendationsAreOnlyWeakAreaPicksWithinLimit() {
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let progress = ProgressStore()
        progress.resetAll()
        let competency = CompetencyStore()
        let service = ContentService.shared
        for profile in [sampleProfile(), nil] {
            let picks = LearningHabitPlanner.weakAreaRecommendations(
                for: profile,
                progress: progress,
                competency: competency,
                service: service,
                limit: 2
            )
            XCTAssertLessThanOrEqual(picks.count, 2)
            XCTAssertTrue(picks.allSatisfy { $0.kind == .weakArea })
            XCTAssertEqual(Set(picks.map(\.lesson.id)).count, picks.count, "No lesson repeats.")
        }
        XCTAssertTrue(LearningHabitPlanner.weakAreaRecommendations(
            for: sampleProfile(),
            progress: progress,
            competency: competency,
            service: service,
            limit: 0
        ).isEmpty)
        progress.resetAll()
    }
}
