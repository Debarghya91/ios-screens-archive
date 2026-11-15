// LearningHabit.swift
// Payments Training Hub iOS - Non-manipulative learning habit loop.
//
// One small achievable goal per day, a weekly target reused from
// ProgressStore, one real question per day, a weekly investigation
// challenge entry, revision reminders, weak-area recommendations
// and honest progress milestones. Nothing here punishes a missed
// day: streaks are displayed neutrally, reminder copy is
// encouraging and never shaming, and reminders default to off
// with explicit opt-in.
//
// This file invents no content and duplicates no engine logic. The
// daily goal and the weak-area picks come from
// RecommendationEngine read-only. The daily question comes from
// the bundled interview bank (InterviewQuestionStore). The weekly
// challenge pick comes from ExceptionCaseCatalogue. The weekly
// target is ProgressStore.weeklyGoal, read-only here; editing it
// stays in LearningPreferencesView. Gating, purchase and
// entitlement behaviour are untouched: destinations keep their own
// lock handling, and the weekly challenge card shows only the
// case title, incident type and level, the same fields the lab
// itself shows for a locked case.
//
// Reminder persistence is namespaced per account through
// AccountScopedStorage, following the OnboardingStore pattern:
// one Codable settings value, suppress-save while loading, legacy
// adoption on load, reload clears in-memory state first. The
// coordinator must add LearningHabitStore to AuthService
// reloadAllStores and settingsBaseKey to its guest migration list,
// or reminder settings will not follow account changes or the
// guest-to-account migration. Notifications are local only, via
// UNUserNotificationCenter, scheduled only when the learner has
// enabled reminders and the system has granted authorisation.
// No em dashes in any user-facing text.

import Foundation
import Combine
import UserNotifications

// MARK: - Reminder frequency

/// How often learning reminders fire. Raw values are stored in the
/// persisted settings, so never rename an existing case.
enum LearningHabitReminderFrequency: String, CaseIterable, Codable, Hashable {
    case off
    case daily
    case weekly

    var displayTitle: String {
        switch self {
        case .off: return "Off"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        }
    }

    /// Short schedule wording for status lines. Weekly reminders
    /// always fire on Monday; see LearningHabitScheduler.
    var scheduleText: String {
        switch self {
        case .off: return "Off"
        case .daily: return "Daily"
        case .weekly: return "Every Monday"
        }
    }

    /// One line explaining when reminders fire at this frequency.
    var explainer: String {
        switch self {
        case .off: return "No reminders."
        case .daily: return "Every day at your chosen time."
        case .weekly: return "Every Monday at your chosen time."
        }
    }
}

// MARK: - Reminder settings

/// The learner's reminder choice. Hour is 0 to 23, minute is 0 to
/// 59; out-of-range values are clamped on init, so a stored or
/// constructed value can never schedule an invalid time. Turning
/// reminders off keeps the last chosen time, so turning them back
/// on restores it.
struct LearningHabitReminderSettings: Codable, Equatable, Hashable {
    var frequency: LearningHabitReminderFrequency
    var hour: Int
    var minute: Int

    /// The default: reminders off, 9:00 AM. Off is the default
    /// because reminders require explicit opt-in.
    static let `default` = LearningHabitReminderSettings(frequency: .off, hour: 9, minute: 0)

    init(frequency: LearningHabitReminderFrequency, hour: Int, minute: Int) {
        self.frequency = frequency
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
    }

    /// True when the learner has chosen a firing frequency. This
    /// alone does not mean a notification is scheduled: scheduling
    /// also needs system authorisation.
    var isEnabled: Bool { frequency != .off }
}

// MARK: - Notification scheduler

/// Builds and applies the local notification requests for reminder
/// settings. Stateless and pure apart from the UNUserNotificationCenter
/// calls in apply and cancelAll, so the request construction is
/// unit testable without touching the notification centre.
///
/// Exactly one request exists at a time: daily and weekly use
/// distinct identifiers, and apply always removes both before
/// adding. No badge is set, and no request is ever scheduled for
/// the off frequency.
enum LearningHabitScheduler {
    /// Pending request identifier for the daily reminder.
    static let dailyRequestIdentifier = "pf.learningHabit.dailyReminder"
    /// Pending request identifier for the weekly reminder.
    static let weeklyRequestIdentifier = "pf.learningHabit.weeklyReminder"

    /// Both identifiers, for removal before rescheduling.
    static let allRequestIdentifiers = [dailyRequestIdentifier, weeklyRequestIdentifier]

    /// The weekday weekly reminders fire on: Monday. Weekday
    /// numbering in DateComponents is fixed (1 is Sunday), whatever
    /// the calendar's first weekday is.
    static let weeklyReminderWeekday = 2

    /// The notification content for one frequency. Nil for off.
    /// Copy is encouraging and never shaming: no mention of missed
    /// days, falling behind, or broken streaks.
    static func content(for frequency: LearningHabitReminderFrequency) -> UNMutableNotificationContent? {
        let body: String
        switch frequency {
        case .off:
            return nil
        case .daily:
            body = "One small lesson is here when you have a few minutes. No rush."
        case .weekly:
            body = "A new week. One small step is plenty, and your next lesson is ready when you are."
        }
        let content = UNMutableNotificationContent()
        content.title = "Payments Training Hub"
        content.body = body
        content.sound = .default
        return content
    }

    /// The repeating request for these settings, or nil when
    /// reminders are off. Daily repeats every day at the chosen
    /// time; weekly repeats every Monday at the chosen time.
    static func request(for settings: LearningHabitReminderSettings) -> UNNotificationRequest? {
        guard let content = content(for: settings.frequency) else { return nil }
        switch settings.frequency {
        case .off:
            return nil
        case .daily:
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: settings.hour, minute: settings.minute),
                repeats: true
            )
            return UNNotificationRequest(identifier: dailyRequestIdentifier, content: content, trigger: trigger)
        case .weekly:
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(
                    hour: settings.hour,
                    minute: settings.minute,
                    weekday: weeklyReminderWeekday
                ),
                repeats: true
            )
            return UNNotificationRequest(identifier: weeklyRequestIdentifier, content: content, trigger: trigger)
        }
    }

    /// Replace any scheduled habit reminder with the request for
    /// these settings, or with nothing when reminders are off.
    /// Adding a request the system is not authorised to deliver is
    /// harmless: the system simply does not deliver it. Callers
    /// that care about authorisation check it first; see
    /// LearningHabitStore.applyCurrentSchedule.
    static func apply(settings: LearningHabitReminderSettings, center: UNUserNotificationCenter = .current()) async {
        cancelAll(center: center)
        guard let request = request(for: settings) else { return }
        try? await center.add(request)
    }

    /// Remove every scheduled habit reminder.
    static func cancelAll(center: UNUserNotificationCenter = .current()) {
        center.removePendingNotificationRequests(withIdentifiers: allRequestIdentifiers)
    }

    /// Ask the system for notification authorisation. The system
    /// prompts at most once; later calls return the stored decision
    /// without prompting. Only alert and sound are requested: no
    /// badge, so no unread count ever pressures the learner.
    static func requestAuthorization(center: UNUserNotificationCenter = .current()) async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// The current system authorisation status.
    static func authorizationStatus(center: UNUserNotificationCenter = .current()) async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }
}

// MARK: - Reminder store

/// Keeps the reminder settings for the current account namespace.
/// Follows the OnboardingStore pattern: suppress-save while
/// loading, adoptLegacyKey on load, reload clears in-memory state
/// first. Scheduling is applied from the stored settings whenever
/// they change through this store and whenever the account
/// reloads, so a previous account's reminder can never keep
/// firing after a switch.
@MainActor
final class LearningHabitStore: ObservableObject {
    static let shared = LearningHabitStore()

    /// Base key, namespaced per account by AccountScopedStorage.
    /// AuthService duplicates this literal in its guest migration
    /// list; keep the two in step.
    static let settingsBaseKey = "pf.learningHabit.reminderSettings.v1"

    /// The learner's reminder choice for the current account.
    /// Defaults to off.
    @Published private(set) var reminderSettings: LearningHabitReminderSettings = .default {
        didSet { save() }
    }

    /// The system notification authorisation status, last read.
    /// Starts as not determined; refreshed by
    /// refreshAuthorizationStatus and applyCurrentSchedule. Never
    /// persisted: the system is the source of truth.
    @Published private(set) var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    /// True when the learner has chosen a firing frequency. A
    /// scheduled notification additionally needs authorisation.
    var remindersEnabled: Bool { reminderSettings.isEnabled }

    /// Suppresses save() while loading, so a reload into an account
    /// with no stored settings does not write a default value into
    /// that namespace (which would block guest migration for it).
    private var suppressSave = false

    private func withoutSaving(_ work: () -> Void) {
        let previous = suppressSave
        suppressSave = true
        defer { suppressSave = previous }
        work()
    }

    init() {
        load()
    }

    /// Persist settings without touching the notification centre.
    /// Used by the enable, disable and update paths after they
    /// have decided what scheduling must happen, and by tests.
    func saveReminderSettings(_ settings: LearningHabitReminderSettings) {
        reminderSettings = settings
    }

    /// The explicit opt-in path: ask the system for authorisation,
    /// and only when it is granted save the settings and schedule
    /// the reminder. Returns false when authorisation is denied or
    /// unavailable, leaving the stored settings untouched. Passing
    /// off behaves as disableReminders and returns true.
    func enableReminders(frequency: LearningHabitReminderFrequency, hour: Int, minute: Int) async -> Bool {
        guard frequency != .off else {
            disableReminders()
            return true
        }
        let granted = await LearningHabitScheduler.requestAuthorization()
        await refreshAuthorizationStatus()
        guard granted else { return false }
        saveReminderSettings(LearningHabitReminderSettings(frequency: frequency, hour: hour, minute: minute))
        await LearningHabitScheduler.apply(settings: reminderSettings)
        return true
    }

    /// Turn reminders off: keep the last chosen time, stop the
    /// schedule, and persist the off choice.
    func disableReminders() {
        var settings = reminderSettings
        settings.frequency = .off
        saveReminderSettings(settings)
        LearningHabitScheduler.cancelAll()
    }

    /// Change the firing frequency while reminders are on. When
    /// the new frequency is off this behaves as disableReminders.
    /// Scheduling is reapplied only when the system authorisation
    /// allows delivery; otherwise any stale request is removed.
    func updateReminderFrequency(_ frequency: LearningHabitReminderFrequency) async {
        guard frequency != .off else {
            disableReminders()
            return
        }
        var settings = reminderSettings
        settings.frequency = frequency
        saveReminderSettings(settings)
        await applyCurrentSchedule()
    }

    /// Change the reminder time, keeping the current frequency.
    /// When reminders are on, the schedule moves to the new time.
    func updateReminderTime(hour: Int, minute: Int) async {
        saveReminderSettings(LearningHabitReminderSettings(
            frequency: reminderSettings.frequency,
            hour: hour,
            minute: minute
        ))
        await applyCurrentSchedule()
    }

    /// Re-read the system authorisation status.
    func refreshAuthorizationStatus() async {
        notificationAuthorizationStatus = await LearningHabitScheduler.authorizationStatus()
    }

    /// Make the scheduled notification match the stored settings
    /// and the current authorisation: schedule when reminders are
    /// on and delivery is allowed, otherwise remove any scheduled
    /// habit reminder. Called on account reload and from the
    /// settings view, so a stale request can never outlive its
    /// settings or its account.
    func applyCurrentSchedule() async {
        await refreshAuthorizationStatus()
        let allowed = notificationAuthorizationStatus == .authorized
            || notificationAuthorizationStatus == .provisional
        if remindersEnabled && allowed {
            await LearningHabitScheduler.apply(settings: reminderSettings)
        } else {
            LearningHabitScheduler.cancelAll()
        }
    }

    /// Reload for the current account namespace, clearing the
    /// previous account's settings first, then reapplying the
    /// schedule for the newly loaded settings.
    func reloadForCurrentAccount() {
        withoutSaving {
            reminderSettings = .default
            notificationAuthorizationStatus = .notDetermined
        }
        load()
        Task { await applyCurrentSchedule() }
    }

    private func load() {
        withoutSaving {
            AccountScopedStorage.adoptLegacyKey(Self.settingsBaseKey)
            let defaults = UserDefaults.standard
            if let data = defaults.data(forKey: AccountScopedStorage.currentKey(Self.settingsBaseKey)),
               let decoded = try? JSONDecoder().decode(LearningHabitReminderSettings.self, from: data) {
                reminderSettings = decoded
            } else {
                reminderSettings = .default
            }
        }
    }

    private func save() {
        guard !suppressSave else { return }
        if let data = try? JSONEncoder().encode(reminderSettings) {
            UserDefaults.standard.set(data, forKey: AccountScopedStorage.currentKey(Self.settingsBaseKey))
        }
    }
}

// MARK: - Daily objective

/// One small goal for today: the engine's next lesson, with the
/// engine's own reason. Done means the lesson was finished today,
/// from recorded completion events, so a revisit goal for an
/// already finished lesson never shows as done just because the
/// lesson was finished on an earlier day.
struct DailyLearningObjective: Identifiable, Hashable {
    let lesson: SearchEntry
    let reason: String
    let kind: RecommendationKind
    let isComplete: Bool

    var id: String { lesson.id }
}

/// One honest progress milestone: a lesson count threshold, its
/// title, and whether the learner's recorded completions reach it.
struct LearningHabitMilestone: Identifiable, Hashable {
    let threshold: Int
    let title: String
    let isReached: Bool

    var id: Int { threshold }
}

// MARK: - Planner

/// Pure habit computations over recorded progress and real
/// catalogue content. No state, no persistence, no gating: every
/// function reads only what it is passed, so each is unit testable
/// with fixture data.
enum LearningHabitPlanner {
    /// Lesson-count thresholds for milestones, before the final
    /// whole-catalogue threshold is added from ContentManifest.
    static let milestoneThresholds = [1, 5, 10, 25, 50, 100, 250, 500]

    /// Today's small goal: the recommendation engine's single best
    /// next lesson for the learner's profile, read-only. Nil when
    /// the engine has no pick, for example while the catalogue is
    /// still loading or when every lesson is complete.
    static func dailyObjective(
        for profile: OnboardingProfile?,
        progress: ProgressStore,
        competency: CompetencyStore,
        service: ContentService
    ) -> DailyLearningObjective? {
        guard let pick = RecommendationEngine.nextLesson(
            for: profile,
            progress: progress,
            competency: competency,
            service: service
        ) else { return nil }
        return DailyLearningObjective(
            lesson: pick.lesson,
            reason: pick.reason,
            kind: pick.kind,
            isComplete: didCompleteLessonToday(pick.lesson.id, progress: progress)
        )
    }

    /// Weak-area recommendations from the engine, weakest evidence
    /// first in engine order, at most `limit`. This filters the
    /// engine's own weak-area picks; it computes no weakness of
    /// its own and never calls a lesson weak without engine
    /// evidence. The engine is asked for more than `limit` picks
    /// because weak-area picks sit behind the route head in its
    /// order.
    static func weakAreaRecommendations(
        for profile: OnboardingProfile?,
        progress: ProgressStore,
        competency: CompetencyStore,
        service: ContentService,
        limit: Int
    ) -> [LessonRecommendation] {
        guard limit > 0 else { return [] }
        let picks = RecommendationEngine.recommendations(
            for: profile,
            progress: progress,
            competency: competency,
            service: service,
            limit: max(limit, 10)
        )
        return Array(picks.filter { $0.kind == .weakArea }.prefix(limit))
    }

    /// True when a completion event for this lesson is recorded
    /// today, in the current calendar.
    static func didCompleteLessonToday(_ lessonID: String, progress: ProgressStore, calendar: Calendar = .current) -> Bool {
        progress.events.contains {
            $0.type == .lessonCompleted
                && $0.lessonID == lessonID
                && calendar.isDateInToday($0.timestamp)
        }
    }

    /// Days since the epoch, local calendar, start of day: the
    /// deterministic seed for the daily question. Mirrors the
    /// DailyChallengeView seed so both rotate on the same day
    /// boundary.
    static func dayNumber(for date: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: date)
        let epoch = calendar.startOfDay(for: Date(timeIntervalSince1970: 0))
        return calendar.dateComponents([.day], from: epoch, to: start).day ?? 0
    }

    /// One question per day from the real bank, deterministic by
    /// calendar day: every learner sees the same question on the
    /// same day, and it changes daily. Nil when the bank is empty.
    /// No question is ever invented.
    static func dailyQuestion(
        for date: Date,
        questions: [InterviewQuestion],
        calendar: Calendar = .current
    ) -> InterviewQuestion? {
        guard !questions.isEmpty else { return nil }
        let index = ((dayNumber(for: date, calendar: calendar) % questions.count) + questions.count) % questions.count
        return questions[index]
    }

    /// Whole weeks since the epoch: the deterministic seed for the
    /// weekly investigation challenge.
    static func weekNumber(for date: Date, calendar: Calendar = .current) -> Int {
        dayNumber(for: date, calendar: calendar) / 7
    }

    /// One investigation case per week from the real lab catalogue,
    /// deterministic by week: the same case all week, a new case
    /// each week. Nil when the catalogue is empty. Only the case
    /// title, incident type and level are ever shown outside the
    /// lab; the narrative and evidence stay inside it.
    static func weeklyInvestigationCase(
        for date: Date,
        cases: [ExceptionCase],
        calendar: Calendar = .current
    ) -> ExceptionCase? {
        guard !cases.isEmpty else { return nil }
        let index = ((weekNumber(for: date, calendar: calendar) % cases.count) + cases.count) % cases.count
        return cases[index]
    }

    /// Neutral streak wording: a plain count of days in a row, or a
    /// plain statement that there is no streak right now. Never
    /// guilt copy, never a call to start today.
    static func streakText(streakCount: Int) -> String {
        switch streakCount {
        case ...0:
            return "No streak right now."
        case 1:
            return "1 day in a row."
        default:
            return "\(streakCount) days in a row."
        }
    }

    /// Weekly target wording from the shared ProgressStore goal.
    /// Read-only: the goal itself is edited in Learning Preferences.
    static func weeklyTargetText(completedThisWeek: Int, weeklyGoal: Int) -> String {
        guard weeklyGoal > 0 else { return "Weekly target not set" }
        let lessonWord = weeklyGoal == 1 ? "lesson" : "lessons"
        return "\(completedThisWeek) of \(weeklyGoal) \(lessonWord) this week"
    }

    /// Every milestone for this catalogue, in threshold order: the
    /// fixed thresholds plus the whole-catalogue threshold from
    /// ContentManifest, deduped. Reached means recorded completions
    /// reach the threshold. Nothing is estimated.
    static func milestones(
        completedCount: Int,
        totalLessons: Int = ContentManifest.lessonCount
    ) -> [LearningHabitMilestone] {
        var thresholds = Set(milestoneThresholds)
        if totalLessons > 0 {
            thresholds.insert(totalLessons)
        }
        let ordered = thresholds
            .filter { totalLessons <= 0 || $0 <= totalLessons }
            .sorted()
        return ordered.map { threshold in
            LearningHabitMilestone(
                threshold: threshold,
                title: milestoneTitle(for: threshold, totalLessons: totalLessons),
                isReached: completedCount >= threshold
            )
        }
    }

    /// The next unreached milestone, or nil when every milestone
    /// is reached.
    static func nextMilestone(
        completedCount: Int,
        totalLessons: Int = ContentManifest.lessonCount
    ) -> LearningHabitMilestone? {
        milestones(completedCount: completedCount, totalLessons: totalLessons)
            .first { !$0.isReached }
    }

    private static func milestoneTitle(for threshold: Int, totalLessons: Int) -> String {
        if totalLessons > 0 && threshold == totalLessons && threshold != 1 {
            return "All \(totalLessons) lessons complete"
        }
        if threshold == 1 {
            return "First lesson complete"
        }
        return "\(threshold) lessons complete"
    }
}
