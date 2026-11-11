// ProgressStore.swift
// PaymentForge iOS - On-device learner progress, event-based.
// Stored locally with UserDefaults, no accounts, no sign-in.
// The website is open for all, and the app matches that: progress lives
// only on this device, with an export for backup. Signed-in users also
// mirror events to Supabase learning_activity through SyncService;
// guests keep local events only.
//
// LEARNING ACTIVITY MODEL: every learning action is recorded as a
// LearningEvent (lesson started/completed, audio listened, quiz
// attempted/completed, bookmark, path progress) with a timestamp.
// Streak, weekly activity, learning hours and quiz averages are all
// COMPUTED from those events. Nothing is estimated: learning hours
// sum only recorded lesson/audio durations, and with no events every
// statistic is zero or empty. Quiz attempts are HISTORY: every attempt
// is kept per lesson, never overwritten; quizScore(for:) returns the
// best correct count for compatibility.

import Foundation
import Combine

// MARK: - Learning events

/// The kinds of learning activity the app records. Raw values are
/// stored in UserDefaults and mirrored to Supabase, so never rename
/// an existing case.
enum LearningEventType: String, Codable, CaseIterable {
    case lessonStarted = "lessonStarted"
    case lessonCompleted = "lessonCompleted"
    case lessonDuration = "lessonDuration"
    case audioListened = "audioListened"
    case quizAttempted = "quizAttempted"
    case quizCompleted = "quizCompleted"
    case bookmarkCreated = "bookmarkCreated"
    case pathProgress = "pathProgress"
}

/// One recorded learning action. Duration is recorded only when it
/// was actually measured (lesson/audio playback); it is never
/// estimated. Score/total are set for quiz events; pathID and
/// progressPct are set for path events.
struct LearningEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let type: LearningEventType
    let lessonID: String?
    let lessonTitle: String?
    let timestamp: Date
    let durationSeconds: Int?
    let score: Int?
    let total: Int?
    let pathID: String?
    let progressPct: Int?

    init(
        id: UUID = UUID(),
        type: LearningEventType,
        lessonID: String? = nil,
        lessonTitle: String? = nil,
        timestamp: Date = Date(),
        durationSeconds: Int? = nil,
        score: Int? = nil,
        total: Int? = nil,
        pathID: String? = nil,
        progressPct: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.lessonID = lessonID
        self.lessonTitle = lessonTitle
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.score = score
        self.total = total
        self.pathID = pathID
        self.progressPct = progressPct
    }
}

/// One quiz attempt. Attempts are history: a lesson keeps every
/// attempt, with the score, the total and the date it was taken.
struct QuizAttempt: Codable, Equatable, Identifiable {
    let id: UUID
    let lessonID: String
    let correct: Int
    let total: Int
    let attemptedAt: Date

    init(id: UUID = UUID(), lessonID: String, correct: Int, total: Int, attemptedAt: Date = Date()) {
        self.id = id
        self.lessonID = lessonID
        self.correct = correct
        self.total = total
        self.attemptedAt = attemptedAt
    }

    /// The attempt as a fraction correct, nil when no total was
    /// recorded (for example an attempt imported from the old
    /// best-score-only store, which kept no total).
    var fractionCorrect: Double? {
        guard total > 0 else { return nil }
        return Double(correct) / Double(total)
    }
}

/// Stores lesson completion, quiz history, streak and weekly goal on device.
final class ProgressStore: ObservableObject {
    static let shared = ProgressStore()

    // MARK: - Keys

    private enum Keys {
        static let completedLessons = "pf.completedLessons.v1"
        static let quizScoresLegacy = "pf.quizScores.v1"
        static let quizHistory = "pf.quizHistory.v1"
        static let learningEvents = "pf.learningEvents.v1"
        static let lastLessonID = "pf.lastLessonID.v1"
        static let lastLessonTitle = "pf.lastLessonTitle.v1"
        static let lastActivityDateLegacy = "pf.lastActivityDate.v1"
        static let streakCountLegacy = "pf.streakCount.v1"
        static let weeklyGoal = "pf.weeklyGoal.v1"
        static let weeklyCompletedLegacy = "pf.weeklyCompleted.v1"
        static let weekStartLegacy = "pf.weekStart.v1"
        static let lastSyncedAt = "pf.lastSyncedAt.v1"
        static let pendingSync = "pf.pendingSync.v1"
    }

    /// The most events kept on device, to bound UserDefaults size.
    /// The oldest events are dropped first; completion and quiz
    /// history are stored separately and are never dropped.
    private static let maxStoredEvents = 2000

    // MARK: - Published state

    @Published private(set) var completedLessonIDs: Set<String> = []

    /// Full quiz history per lesson, every attempt kept. This is the
    /// source of truth for quiz scores.
    @Published private(set) var quizHistory: [String: [QuizAttempt]] = [:]

    /// Every recorded learning event, oldest first.
    @Published private(set) var events: [LearningEvent] = []

    @Published private(set) var lastLessonID: String? = nil
    @Published private(set) var lastLessonTitle: String? = nil
    @Published var weeklyGoal: Int = 5 {
        didSet { save() }
    }

    /// Best correct count per lesson, derived from quiz history.
    /// Kept so existing readers (Dashboard quiz list, Profile stats,
    /// SyncService) keep working unchanged. It is a computed view,
    /// never stored: the history is what is persisted.
    var quizScores: [String: Int] {
        var best: [String: Int] = [:]
        for (lessonID, attempts) in quizHistory {
            best[lessonID] = attempts.map(\.correct).max()
        }
        return best
    }

    /// Lessons completed this week, computed from lessonCompleted
    /// events in the current calendar week. Zero when there are no
    /// events; never estimated.
    var lessonsCompletedThisWeek: Int {
        let calendar = Calendar.current
        let now = Date()
        return events.filter {
            $0.type == .lessonCompleted && calendar.isDate($0.timestamp, equalTo: now, toGranularity: .weekOfYear)
        }.count
    }

    /// Consecutive days with at least one learning event, ending
    /// today (or yesterday when nothing happened today yet). Zero
    /// when there are no events; never estimated.
    var streakCount: Int {
        let calendar = Calendar.current
        let activeDays = Set(events.map { calendar.startOfDay(for: $0.timestamp) })
        guard !activeDays.isEmpty else { return 0 }
        var day = calendar.startOfDay(for: Date())
        if !activeDays.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
                  activeDays.contains(yesterday) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while activeDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    // MARK: - Sync state (Supabase sync, no behaviour change for guests)

    /// When progress was last synced to the signed-in account, nil when
    /// it has never synced. Guests never sync, so this stays nil for
    /// them and local progress is untouched.
    @Published private(set) var lastSyncedAt: Date? = nil

    /// True when local progress changed since the last successful sync.
    /// SyncService clears it on a successful sync.
    @Published var pendingSync: Bool = false {
        didSet { save() }
    }

    /// Record a successful sync now.
    func markSynced() {
        lastSyncedAt = Date()
        pendingSync = false
        save()
    }

    /// Record that local progress changed and a sync is due.
    func markSyncPending() {
        pendingSync = true
        save()
    }

    /// Export progress as a plain dictionary for sync and backup.
    /// All values are JSON-safe. Quiz scores are exported as the
    /// best-per-lesson map for compatibility, plus the full history
    /// and the event-derived statistics.
    func exportProgressDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "completedLessonIDs": Array(completedLessonIDs).sorted(),
            "quizScores": quizScores,
            "quizHistory": quizHistory.flatMap { lessonID, attempts in
                attempts.map { attempt in
                    [
                        "lessonID": lessonID,
                        "correct": attempt.correct,
                        "total": attempt.total,
                        "attemptedAt": ISO8601DateFormatter().string(from: attempt.attemptedAt)
                    ] as [String: Any]
                }
            },
            "streakCount": streakCount,
            "weeklyGoal": weeklyGoal,
            "lessonsCompletedThisWeek": lessonsCompletedThisWeek,
            "learningHours": learningHours(),
            "totalQuizAttempts": totalQuizAttempts,
            "learningEventCount": events.count,
            "exportedAt": ISO8601DateFormatter().string(from: Date())
        ]
        if let lastLessonID {
            dict["lastLessonID"] = lastLessonID
        }
        if let lastLessonTitle {
            dict["lastLessonTitle"] = lastLessonTitle
        }
        return dict
    }

    /// Import progress from a dictionary, merging with what is already
    /// here. Conflict rule: union of completed lessons, quiz attempts
    /// are appended (never overwritten; a best-score-only import adds
    /// one attempt per lesson when it beats the stored best), and the
    /// existing last lesson is kept unless this device has none.
    /// Nothing already stored is ever removed. Streak and weekly
    /// counts are computed from events, so they are never imported.
    func importProgress(from dict: [String: Any]) {
        if let ids = dict["completedLessonIDs"] as? [String] {
            completedLessonIDs.formUnion(ids)
        }
        if let history = dict["quizHistory"] as? [[String: Any]] {
            let formatter = ISO8601DateFormatter()
            for entry in history {
                guard let lessonID = entry["lessonID"] as? String,
                      let correct = entry["correct"] as? Int,
                      let total = entry["total"] as? Int else { continue }
                let date = (entry["attemptedAt"] as? String).flatMap { formatter.date(from: $0) } ?? Date()
                let attempt = QuizAttempt(lessonID: lessonID, correct: correct, total: total, attemptedAt: date)
                var attempts = quizHistory[lessonID] ?? []
                let alreadyStored = attempts.contains {
                    $0.correct == correct && $0.total == total
                        && Calendar.current.isDate($0.attemptedAt, equalTo: date, toGranularity: .second)
                }
                if !alreadyStored {
                    attempts.append(attempt)
                    attempts.sort { $0.attemptedAt < $1.attemptedAt }
                    quizHistory[lessonID] = attempts
                }
            }
        }
        if let scores = dict["quizScores"] as? [String: Int] {
            for (lessonID, score) in scores {
                // Best-score-only source (old export, or the server):
                // keep it as one attempt with no total, only when it
                // beats the best stored attempt. No total is invented.
                if score > (quizScore(for: lessonID) ?? 0) {
                    let attempt = QuizAttempt(lessonID: lessonID, correct: score, total: 0)
                    quizHistory[lessonID, default: []].append(attempt)
                }
            }
        }
        if lastLessonID == nil, let incomingID = dict["lastLessonID"] as? String {
            lastLessonID = incomingID
            lastLessonTitle = dict["lastLessonTitle"] as? String
        }
        save()
    }

    var totalLessonsCompleted: Int { completedLessonIDs.count }

    var totalQuizAttempts: Int {
        quizHistory.values.reduce(0) { $0 + $1.count }
    }

    var weeklyProgress: Double {
        guard weeklyGoal > 0 else { return 0 }
        return min(1, Double(lessonsCompletedThisWeek) / Double(weeklyGoal))
    }

    // MARK: - Init

    init() {
        load()
    }

    // MARK: - Recording events

    /// Append one event, persist, and flag a sync as due. Events are
    /// the only source for streak, weekly activity and learning hours.
    private func recordEvent(_ event: LearningEvent) {
        events.append(event)
        if events.count > Self.maxStoredEvents {
            events.removeFirst(events.count - Self.maxStoredEvents)
        }
        pendingSync = true
        save()
    }

    /// Record that a lesson was opened. Called from LessonView when
    /// the lesson screen appears.
    func recordLessonStarted(lessonID: String, title: String? = nil) {
        recordEvent(LearningEvent(type: .lessonStarted, lessonID: lessonID, lessonTitle: title))
    }

    /// Record measured audio listening time for a lesson, in seconds.
    /// Called when narration finishes (AudioPlayerService). Only real
    /// playback time is recorded; zero or negative values are ignored.
    func recordAudioListened(lessonID: String, seconds: Int) {
        guard seconds > 0 else { return }
        recordEvent(LearningEvent(type: .audioListened, lessonID: lessonID, durationSeconds: seconds))
    }

    /// Record a measured lesson duration, in seconds, when the app
    /// knows it (for example the narration length of a completed
    /// lesson). Never called with an estimate.
    func recordLessonDuration(lessonID: String, seconds: Int) {
        guard seconds > 0 else { return }
        recordEvent(LearningEvent(type: .lessonDuration, lessonID: lessonID, durationSeconds: seconds))
    }

    /// Record that a lesson or path was bookmarked.
    func recordBookmark(lessonID: String? = nil, pathID: String? = nil) {
        guard lessonID != nil || pathID != nil else { return }
        recordEvent(LearningEvent(type: .bookmarkCreated, lessonID: lessonID, pathID: pathID))
    }

    /// Record progress on a learning path (0 to 100). The latest
    /// pathProgress event for a path is its current completion.
    func recordPathProgress(pathID: String, progressPct: Int) {
        let clamped = min(100, max(0, progressPct))
        recordEvent(LearningEvent(type: .pathProgress, pathID: pathID, progressPct: clamped))
    }

    /// Mark a lesson complete and record the completion event.
    /// Streak and weekly progress are recomputed from events.
    func markLessonComplete(id: String, title: String) {
        let isNew = completedLessonIDs.insert(id).inserted
        lastLessonID = id
        lastLessonTitle = title
        if isNew {
            recordEvent(LearningEvent(type: .lessonCompleted, lessonID: id, lessonTitle: title))
        } else {
            save()
        }
    }

    /// Record a quiz result for a lesson. The attempt is APPENDED to
    /// the lesson's history, never overwriting earlier attempts, and
    /// a quizCompleted event is recorded.
    func recordQuizScore(lessonID: String, correct: Int, total: Int) {
        let attempt = QuizAttempt(lessonID: lessonID, correct: correct, total: total)
        quizHistory[lessonID, default: []].append(attempt)
        recordEvent(LearningEvent(type: .quizCompleted, lessonID: lessonID, score: correct, total: total))
    }

    /// Record a quiz attempt that was started but not finished.
    func recordQuizAttempted(lessonID: String) {
        recordEvent(LearningEvent(type: .quizAttempted, lessonID: lessonID))
    }

    // MARK: - Reading quiz history

    /// The best correct count for a lesson, across all attempts.
    /// Nil when the lesson has no recorded attempt.
    func quizScore(for lessonID: String) -> Int? {
        quizHistory[lessonID]?.map(\.correct).max()
    }

    /// Every recorded attempt for a lesson, oldest first.
    func quizAttempts(for lessonID: String) -> [QuizAttempt] {
        quizHistory[lessonID] ?? []
    }

    /// The mean fraction correct for a lesson (0 to 1), across
    /// attempts that recorded a total. Nil when there is no attempt
    /// with a total.
    func averageQuizScore(for lessonID: String) -> Double? {
        let fractions = (quizHistory[lessonID] ?? []).compactMap(\.fractionCorrect)
        guard !fractions.isEmpty else { return nil }
        return fractions.reduce(0, +) / Double(fractions.count)
    }

    /// The mean fraction correct across all lessons (0 to 1).
    /// Nil when no attempt with a total has been recorded.
    func averageQuizScore() -> Double? {
        let fractions = quizHistory.values.flatMap { $0 }.compactMap(\.fractionCorrect)
        guard !fractions.isEmpty else { return nil }
        return fractions.reduce(0, +) / Double(fractions.count)
    }

    /// The best fraction correct for a lesson (0 to 1). Nil when the
    /// lesson has no attempt with a total.
    func bestQuizScore(for lessonID: String) -> Double? {
        (quizHistory[lessonID] ?? []).compactMap(\.fractionCorrect).max()
    }

    /// The best fraction correct across all lessons (0 to 1).
    /// Nil when no attempt with a total has been recorded.
    func bestQuizScoreOverall() -> Double? {
        quizHistory.values.flatMap { $0 }.compactMap(\.fractionCorrect).max()
    }

    func isLessonComplete(_ id: String) -> Bool {
        completedLessonIDs.contains(id)
    }

    // MARK: - Event-derived statistics

    /// Learning hours, from recorded lesson and audio durations
    /// only. Never estimated: with no duration events this is 0.
    func learningHours() -> Double {
        let seconds = events
            .filter { $0.type == .lessonDuration || $0.type == .audioListened }
            .compactMap(\.durationSeconds)
            .reduce(0, +)
        return Double(seconds) / 3600
    }

    /// Recorded learning time in minutes, from duration events only.
    var learningMinutes: Int {
        Int(learningHours() * 60)
    }

    /// The number of learning events on one calendar day.
    func dailyActivity(on date: Date) -> Int {
        let calendar = Calendar.current
        return events.filter { calendar.isDate($0.timestamp, inSameDayAs: date) }.count
    }

    /// Activity for each of the last 7 days including today,
    /// oldest first: (day, event count). Days with no events are 0.
    func weeklyActivity() -> [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().map { daysAgo in
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            return (date: day, count: dailyActivity(on: day))
        }
    }

    /// The latest recorded completion percentage (0 to 100) for a
    /// learning path, from its pathProgress events. Nil when the
    /// path has no recorded progress.
    func pathCompletion(pathID: String) -> Int? {
        events
            .filter { $0.type == .pathProgress && $0.pathID == pathID }
            .sorted { $0.timestamp < $1.timestamp }
            .last?.progressPct
    }

    /// The most recent activity date, or nil when nothing was ever
    /// recorded.
    var lastActivityDate: Date? {
        events.map(\.timestamp).max()
    }

    // MARK: - Backup and export

    /// A plain-text backup of progress, for the user to save or share.
    func backupText() -> String {
        var lines: [String] = []
        lines.append("Payments Training Hub progress backup")
        lines.append("Lessons completed: \(totalLessonsCompleted)")
        lines.append("Streak: \(streakCount) days")
        lines.append("Weekly goal: \(weeklyGoal) lessons per week")
        lines.append("Completed this week: \(lessonsCompletedThisWeek)")
        lines.append(String(format: "Learning time: %.1f hours (from recorded listening only)", learningHours()))
        lines.append("Quiz attempts: \(totalQuizAttempts)")
        if let last = lastLessonTitle {
            lines.append("Last lesson: \(last)")
        }
        lines.append("")
        lines.append("Completed lessons:")
        for id in completedLessonIDs.sorted() {
            lines.append("- \(id)")
        }
        return lines.joined(separator: "\n")
    }

    /// Reset all progress on this device. Clears events, completed
    /// lessons, quiz history, streak and weekly counters (both are
    /// computed from events, so clearing events clears them), the
    /// last lesson, the last activity date and the sync flags, all
    /// consistently. The weekly goal is a preference, not progress,
    /// so it is kept.
    func resetAll() {
        completedLessonIDs = []
        quizHistory = [:]
        events = []
        lastLessonID = nil
        lastLessonTitle = nil
        lastSyncedAt = nil
        pendingSync = false
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.lastActivityDateLegacy)
        defaults.removeObject(forKey: Keys.streakCountLegacy)
        defaults.removeObject(forKey: Keys.weeklyCompletedLegacy)
        defaults.removeObject(forKey: Keys.weekStartLegacy)
        defaults.removeObject(forKey: Keys.quizScoresLegacy)
        save()
    }

    // MARK: - Persistence

    private func load() {
        let defaults = UserDefaults.standard
        if let ids = defaults.array(forKey: Keys.completedLessons) as? [String] {
            completedLessonIDs = Set(ids)
        }
        if let data = defaults.data(forKey: Keys.quizHistory),
           let history = try? JSONDecoder().decode([String: [QuizAttempt]].self, from: data) {
            quizHistory = history
        } else if let legacy = defaults.dictionary(forKey: Keys.quizScoresLegacy) as? [String: Int] {
            // One-time migration from the old best-score-only store:
            // each stored best score becomes one attempt with no total
            // (the old store kept no total, and none is invented).
            // quizScore(for:) still returns the same best value.
            for (lessonID, score) in legacy where score > 0 {
                quizHistory[lessonID] = [QuizAttempt(lessonID: lessonID, correct: score, total: 0)]
            }
            defaults.removeObject(forKey: Keys.quizScoresLegacy)
        }
        if let data = defaults.data(forKey: Keys.learningEvents),
           let stored = try? JSONDecoder().decode([LearningEvent].self, from: data) {
            events = stored
        }
        lastLessonID = defaults.string(forKey: Keys.lastLessonID)
        lastLessonTitle = defaults.string(forKey: Keys.lastLessonTitle)
        let goal = defaults.integer(forKey: Keys.weeklyGoal)
        weeklyGoal = goal > 0 ? goal : 5
        lastSyncedAt = defaults.object(forKey: Keys.lastSyncedAt) as? Date
        pendingSync = defaults.bool(forKey: Keys.pendingSync)
        // Legacy counters were stored, not computed; they are gone
        // now (streak and weekly counts come from events). Remove
        // the stale keys so they can never be read as progress.
        defaults.removeObject(forKey: Keys.streakCountLegacy)
        defaults.removeObject(forKey: Keys.weeklyCompletedLegacy)
        defaults.removeObject(forKey: Keys.weekStartLegacy)
        defaults.removeObject(forKey: Keys.lastActivityDateLegacy)
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(Array(completedLessonIDs), forKey: Keys.completedLessons)
        if let historyData = try? JSONEncoder().encode(quizHistory) {
            defaults.set(historyData, forKey: Keys.quizHistory)
        }
        if let eventData = try? JSONEncoder().encode(events) {
            defaults.set(eventData, forKey: Keys.learningEvents)
        }
        defaults.set(lastLessonID, forKey: Keys.lastLessonID)
        defaults.set(lastLessonTitle, forKey: Keys.lastLessonTitle)
        defaults.set(weeklyGoal, forKey: Keys.weeklyGoal)
        defaults.set(lastSyncedAt, forKey: Keys.lastSyncedAt)
        defaults.set(pendingSync, forKey: Keys.pendingSync)
    }
}

// MARK: - Recently opened lessons

/// Recently opened lessons, most recent first, kept in
/// UserDefaults (key pf.recentLessons.v1, last 10). Drives the
/// Home "Pick up where you left off" section: only lessons the
/// learner opened and has not completed are shown there. LessonView
/// records every open; nothing is invented.
final class RecentLessonsStore: ObservableObject {
    static let shared = RecentLessonsStore()

    private static let key = "pf.recentLessons.v1"
    private static let maxKept = 10

    @Published private(set) var lessonIDs: [String] = []

    private init() {
        lessonIDs = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    /// Record a lesson open: move it to the front, keep the last 10.
    func record(lessonID: String) {
        lessonIDs.removeAll { $0 == lessonID }
        lessonIDs.insert(lessonID, at: 0)
        if lessonIDs.count > Self.maxKept {
            lessonIDs = Array(lessonIDs.prefix(Self.maxKept))
        }
        UserDefaults.standard.set(lessonIDs, forKey: Self.key)
    }
}
