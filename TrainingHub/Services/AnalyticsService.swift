// AnalyticsService.swift
// Payments Training Hub iOS - Local, privacy-respecting analytics.
//
// UNCOMPILED: written on a Linux VM with no Xcode. Statically checked
// only. Do not present this file as compiled or tested until it has
// been built in Xcode and the AnalyticsTests target has run.
//
// What this is: a local event layer with explicit opt-in consent.
// No analytics SDK is integrated. No event leaves this device: every
// recorded event goes to an in-memory buffer and, only when the
// optional local log is enabled, to a JSON lines file in Application
// Support. There is exactly one backend hookup point,
// forwardToBackend(_:), which does nothing today. A future transport
// plugs in there and nowhere else, and it must keep the consent gate
// in track(_:) in front of it.
//
// Consent: default OFF. The consent flag is account-scoped through
// AccountScopedStorage, so the guest and each signed-in account
// decide separately, and signing out never inherits another
// account's choice. No event is recorded before consent: track(_:)
// drops every event while consent is off, and no event is emitted
// retroactively when consent is granted later. Withdrawing consent
// stops recording and deletes the buffered events, the local log
// file for the current account, and the stored previous scores used
// for improvement comparisons. First-occurrence flags and the
// first-launch flag are deliberately kept across withdrawal: they
// record only that a milestone event was already emitted once, they
// hold no learning content, and keeping them stops a re-consent from
// re-emitting a "first" event for a milestone that already happened.
// The consent flag must never be added to the guest migration lists
// in AuthService: a guest choice must never become an account
// choice automatically. No legacy analytics keys exist (no earlier
// build recorded analytics), so no legacy adoption is needed.
//
// What is never recorded: names, emails, account identifiers,
// question text, answer text, note text, search words,
// payment details, transaction identifiers, prices, precise
// location, or device identifiers. Event properties carry only
// content identifiers (lesson, chapter, product, exercise, path),
// counts, scores as numbers, and controlled category words supplied
// by call sites (kind, source, failure category, reason). Call sites
// must never pass free text into those category parameters. Records
// carry no account identifier: the in-memory buffer is cleared on
// every account change by reloadForCurrentAccount(), and the local
// log file is per namespace.
//
// First launch: a true install event is not observable on iOS
// without an attribution SDK, so no install event is defined and
// none must be fabricated from first launch data. firstLaunch means
// the first launch observed while consent is active for the current
// account. For a fresh install that is normally a later launch than
// the real first launch, because consent starts off. That is the
// honest definition under opt-in consent, and funnel reporting must
// use it as stated, never relabel it as installs.
//
// Improvement: scoreImproved fires only when a new score beats the
// best previous score stored for the same kind and scope (an
// assessment dimension, a lesson quiz, or a final assessment
// course). Scores compared are always real recorded scores; no
// score is estimated or seeded.
//
// Threading: track(_:) and the record helpers are safe to call from
// any thread; the buffer is guarded by a lock. The consent methods
// (grant, decline, withdraw) and reloadForCurrentAccount() are
// called from the UI and from AuthService account transitions, and
// update @Published state, so call them from the main thread, the
// same pattern the other stores follow.
//
// No em dashes in any user-facing text.

import Foundation
import Combine

// MARK: - Event catalogue

/// The six analytics categories.
enum AnalyticsEventCategory: String, Codable, CaseIterable {
    case acquisition
    case activation
    case retention
    case learningEffectiveness = "learning_effectiveness"
    case monetisation
    case technicalQuality = "technical_quality"
}

/// One property value. String properties are sanitised at record
/// time by AnalyticsService (trimmed, single line, capped at 200
/// characters). Numbers stay numbers so a future backend can query
/// counts and scores without parsing strings.
enum AnalyticsPropertyValue: Codable, Equatable {
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case string
        case integer
        case number
        case boolean
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let value):
            try container.encode(Kind.string, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .integer(let value):
            try container.encode(Kind.integer, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .number(let value):
            try container.encode(Kind.number, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .boolean(let value):
            try container.encode(Kind.boolean, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .integer:
            self = .integer(try container.decode(Int.self, forKey: .value))
        case .number:
            self = .number(try container.decode(Double.self, forKey: .value))
        case .boolean:
            self = .boolean(try container.decode(Bool.self, forKey: .value))
        }
    }
}

/// One recorded analytics event: its catalogue name, its category,
/// when it happened, and its properties. No account identifier is
/// stored on a record, by design.
struct AnalyticsRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let category: String
    let timestamp: Date
    let properties: [String: AnalyticsPropertyValue]

    init(
        id: UUID = UUID(),
        name: String,
        category: String,
        timestamp: Date = Date(),
        properties: [String: AnalyticsPropertyValue] = [:]
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.timestamp = timestamp
        self.properties = properties
    }
}

/// The full event catalogue. Every case is one event a call site may
/// record. Cases that take identifiers take content identifiers
/// only (lesson, chapter, product, exercise, path). Cases that take
/// a kind, source, failure category, or reason take a controlled
/// vocabulary word from the call site, never free text and never
/// user content. See AnalyticsService for which events are wired
/// today and which await future call sites.
enum AnalyticsEvent: Equatable {
    // MARK: Acquisition

    /// First launch observed while consent is active for the
    /// current account. Not an install event; see the file header.
    case firstLaunch
    /// The first lesson the learner started, once per account.
    case firstLessonStarted(lessonID: String, chapterID: String)

    // MARK: Activation

    /// A lesson opened. Emitted for every lesson start; the first
    /// one also emits firstLessonStarted.
    case lessonStarted(lessonID: String, chapterID: String)
    /// A lesson marked complete. Emitted for every completion; the
    /// first one also emits firstLessonCompleted.
    case lessonCompleted(lessonID: String, chapterID: String)
    /// The first lesson completed, once per account.
    case firstLessonCompleted(lessonID: String, chapterID: String)
    /// A lesson quiz finished. scorePercent is 100 * correct / total.
    case quizCompleted(lessonID: String, correct: Int, total: Int, scorePercent: Double)
    /// The first lesson quiz finished, once per account.
    case firstQuizCompleted(lessonID: String, correct: Int, total: Int, scorePercent: Double)
    /// A practical exercise finished. kind is one of "studio",
    /// "lab", or "practice". exerciseID is the exercise or case id.
    case practicalExerciseCompleted(exerciseID: String, kind: String)
    /// The first practical exercise finished, once per account.
    case firstPracticalExerciseCompleted(exerciseID: String, kind: String)
    /// A learning path selected. pathID is the path id; role is the
    /// role name the path belongs to, for example a pathway role.
    case pathSelected(pathID: String, role: String)
    /// The first learning path selected, once per account.
    case firstPathSelected(pathID: String, role: String)

    // MARK: Retention

    /// The app launched while consent is active. Emitted at most
    /// once per process launch, from the splash screen.
    case appLaunched
    /// The learner returned after at least 2 days away, counted
    /// from the last launch day stored while consent was active.
    case returnAfterAbsence(daysSinceLastLaunch: Int)
    /// The learner continued a path they had already selected.
    case pathContinued(pathID: String)
    /// The Daily Challenge screen appeared.
    case challengeViewed
    /// The Daily Challenge was answered for the day.
    case challengeCompleted(correct: Bool)
    /// The first Daily Challenge answered, once per account.
    case firstChallengeCompleted(correct: Bool)

    // MARK: Learning effectiveness

    /// A short assessment started. dimension is the competency
    /// dimension name. timed and randomised record the setup
    /// choices, so timed and untimed results stay comparable.
    case assessmentStarted(dimension: String, questionCount: Int, timed: Bool, randomised: Bool)
    /// A short assessment finished. scorePercent is
    /// 100 * correct / total. elapsedSeconds is the session time
    /// used. unansweredCount counts questions left unanswered.
    case assessmentCompleted(dimension: String, correct: Int, total: Int, scorePercent: Double, elapsedSeconds: Int, unansweredCount: Int)
    /// A Final Assessment started. attemptNumber is 1 based.
    /// isResume is true when resuming an exam already running on
    /// its wall clock rather than starting a fresh attempt.
    case finalAssessmentStarted(productID: String, attemptNumber: Int, isResume: Bool)
    /// A Final Assessment finished. passed applies the store pass
    /// rule (at least 15 correct out of 20); the view supplies it
    /// so the rule lives in exactly one place.
    case finalAssessmentCompleted(productID: String, attemptNumber: Int, correct: Int, total: Int, passed: Bool, scorePercent: Double, elapsedSeconds: Int, unansweredCount: Int)
    /// A new best score for a kind and scope. kind is one of
    /// "assessment", "quiz", or "finalAssessment". scopeID is the
    /// dimension name, the lesson id, or the course product id.
    case scoreImproved(kind: String, scopeID: String, previousScorePercent: Double, currentScorePercent: Double)
    /// A course certificate was issued on passing a Final
    /// Assessment. productID is the course product id.
    case certificateEarned(productID: String)

    // MARK: Monetisation

    /// A paywall or locked-content upsell was shown. source names
    /// the screen, for example "lesson" or "situations".
    /// productID is the product offered, when a single product is
    /// offered; nil when the paywall offers the catalogue.
    case paywallViewed(source: String, productID: String?)
    /// The learner selected a product, for example tapped a course
    /// card on the purchases screen. source names the screen.
    case productSelected(productID: String, source: String)
    /// A StoreKit purchase was started for a product.
    case purchaseStarted(productID: String)
    /// A verified purchase completed. No price and no transaction
    /// identifier is recorded, by design.
    case purchaseCompleted(productID: String)
    /// A purchase failed. failureCategory is a controlled word
    /// from the store layer, for example "loadFailed",
    /// "verificationFailed", or "unknown"; it never carries a raw
    /// StoreKit error message, which may contain account detail.
    case purchaseFailed(productID: String, failureCategory: String)
    /// The learner cancelled the purchase sheet.
    case purchaseCancelled(productID: String)
    /// A restore of past purchases was started.
    case restoreStarted
    /// A restore finished. restoredCount is the number of products
    /// restored, which may be zero.
    case restoreCompleted(restoredCount: Int)
    /// A restore failed. failureCategory follows the same rule as
    /// purchaseFailed: a controlled word, never a raw error.
    case restoreFailed(failureCategory: String)
    /// An entitlement was removed. reason is a controlled word, for
    /// example "revoked" or "refunded", supplied by the store layer
    /// from the StoreKit transaction state.
    case entitlementRevoked(productID: String, reason: String)

    // MARK: Technical quality

    /// Content failed to load. kind names what failed, for example
    /// "assessmentQuestions", "finalAssessmentQuestions", or
    /// "catalogue". failureCategory is a controlled word, for
    /// example "catalogueNotLoaded" or "network".
    case contentLoadFailed(kind: String, failureCategory: String)
    /// A lesson detail page failed to load.
    case lessonLoadFailed(lessonID: String, failureCategory: String)
    /// Lesson audio playback failed.
    case audioPlaybackFailed(lessonID: String, failureCategory: String)
    /// A lesson audio download failed.
    case audioDownloadFailed(lessonID: String, failureCategory: String)
    /// A cloud sync run failed. failureCategory is a controlled
    /// word from the sync layer, never a raw error message.
    case syncFailed(failureCategory: String)
    /// A search returned no results. The search words are never
    /// recorded; source names the screen the search ran from.
    case searchNoResults(source: String)

    /// The stable event name sent in the record and used by any
    /// future backend. Names are snake_case and must not be
    /// renamed once shipped, or funnel history breaks.
    var name: String {
        switch self {
        case .firstLaunch: return "first_launch"
        case .firstLessonStarted: return "first_lesson_started"
        case .lessonStarted: return "lesson_started"
        case .lessonCompleted: return "lesson_completed"
        case .firstLessonCompleted: return "first_lesson_completed"
        case .quizCompleted: return "quiz_completed"
        case .firstQuizCompleted: return "first_quiz_completed"
        case .practicalExerciseCompleted: return "practical_exercise_completed"
        case .firstPracticalExerciseCompleted: return "first_practical_exercise_completed"
        case .pathSelected: return "path_selected"
        case .firstPathSelected: return "first_path_selected"
        case .appLaunched: return "app_launched"
        case .returnAfterAbsence: return "return_after_absence"
        case .pathContinued: return "path_continued"
        case .challengeViewed: return "challenge_viewed"
        case .challengeCompleted: return "challenge_completed"
        case .firstChallengeCompleted: return "first_challenge_completed"
        case .assessmentStarted: return "assessment_started"
        case .assessmentCompleted: return "assessment_completed"
        case .finalAssessmentStarted: return "final_assessment_started"
        case .finalAssessmentCompleted: return "final_assessment_completed"
        case .scoreImproved: return "score_improved"
        case .certificateEarned: return "certificate_earned"
        case .paywallViewed: return "paywall_viewed"
        case .productSelected: return "product_selected"
        case .purchaseStarted: return "purchase_started"
        case .purchaseCompleted: return "purchase_completed"
        case .purchaseFailed: return "purchase_failed"
        case .purchaseCancelled: return "purchase_cancelled"
        case .restoreStarted: return "restore_started"
        case .restoreCompleted: return "restore_completed"
        case .restoreFailed: return "restore_failed"
        case .entitlementRevoked: return "entitlement_revoked"
        case .contentLoadFailed: return "content_load_failed"
        case .lessonLoadFailed: return "lesson_load_failed"
        case .audioPlaybackFailed: return "audio_playback_failed"
        case .audioDownloadFailed: return "audio_download_failed"
        case .syncFailed: return "sync_failed"
        case .searchNoResults: return "search_no_results"
        }
    }

    /// The brief category this event belongs to.
    var category: AnalyticsEventCategory {
        switch self {
        case .firstLaunch, .firstLessonStarted:
            return .acquisition
        case .lessonStarted, .lessonCompleted, .firstLessonCompleted,
             .quizCompleted, .firstQuizCompleted,
             .practicalExerciseCompleted, .firstPracticalExerciseCompleted,
             .pathSelected, .firstPathSelected:
            return .activation
        case .appLaunched, .returnAfterAbsence, .pathContinued,
             .challengeViewed, .challengeCompleted, .firstChallengeCompleted:
            return .retention
        case .assessmentStarted, .assessmentCompleted,
             .finalAssessmentStarted, .finalAssessmentCompleted,
             .scoreImproved, .certificateEarned:
            return .learningEffectiveness
        case .paywallViewed, .productSelected, .purchaseStarted,
             .purchaseCompleted, .purchaseFailed, .purchaseCancelled,
             .restoreStarted, .restoreCompleted, .restoreFailed,
             .entitlementRevoked:
            return .monetisation
        case .contentLoadFailed, .lessonLoadFailed,
             .audioPlaybackFailed, .audioDownloadFailed,
             .syncFailed, .searchNoResults:
            return .technicalQuality
        }
    }

    /// The event properties. Identifiers and counts only; see the
    /// enum documentation for what must never be passed in.
    var properties: [String: AnalyticsPropertyValue] {
        switch self {
        case .firstLaunch, .appLaunched, .challengeViewed, .restoreStarted:
            return [:]
        case .firstLessonStarted(let lessonID, let chapterID),
             .lessonStarted(let lessonID, let chapterID),
             .lessonCompleted(let lessonID, let chapterID),
             .firstLessonCompleted(let lessonID, let chapterID):
            return [
                "lesson_id": .string(lessonID),
                "chapter_id": .string(chapterID),
            ]
        case .quizCompleted(let lessonID, let correct, let total, let scorePercent),
             .firstQuizCompleted(let lessonID, let correct, let total, let scorePercent):
            return [
                "lesson_id": .string(lessonID),
                "correct": .integer(correct),
                "total": .integer(total),
                "score_percent": .number(scorePercent),
            ]
        case .practicalExerciseCompleted(let exerciseID, let kind),
             .firstPracticalExerciseCompleted(let exerciseID, let kind):
            return [
                "exercise_id": .string(exerciseID),
                "kind": .string(kind),
            ]
        case .pathSelected(let pathID, let role),
             .firstPathSelected(let pathID, let role):
            return [
                "path_id": .string(pathID),
                "role": .string(role),
            ]
        case .returnAfterAbsence(let days):
            return ["days_since_last_launch": .integer(days)]
        case .pathContinued(let pathID):
            return ["path_id": .string(pathID)]
        case .challengeCompleted(let correct),
             .firstChallengeCompleted(let correct):
            return ["correct": .boolean(correct)]
        case .assessmentStarted(let dimension, let questionCount, let timed, let randomised):
            return [
                "dimension": .string(dimension),
                "question_count": .integer(questionCount),
                "timed": .boolean(timed),
                "randomised": .boolean(randomised),
            ]
        case .assessmentCompleted(let dimension, let correct, let total, let scorePercent, let elapsedSeconds, let unansweredCount):
            return [
                "dimension": .string(dimension),
                "correct": .integer(correct),
                "total": .integer(total),
                "score_percent": .number(scorePercent),
                "elapsed_seconds": .integer(elapsedSeconds),
                "unanswered_count": .integer(unansweredCount),
            ]
        case .finalAssessmentStarted(let productID, let attemptNumber, let isResume):
            return [
                "product_id": .string(productID),
                "attempt_number": .integer(attemptNumber),
                "is_resume": .boolean(isResume),
            ]
        case .finalAssessmentCompleted(let productID, let attemptNumber, let correct, let total, let passed, let scorePercent, let elapsedSeconds, let unansweredCount):
            return [
                "product_id": .string(productID),
                "attempt_number": .integer(attemptNumber),
                "correct": .integer(correct),
                "total": .integer(total),
                "passed": .boolean(passed),
                "score_percent": .number(scorePercent),
                "elapsed_seconds": .integer(elapsedSeconds),
                "unanswered_count": .integer(unansweredCount),
            ]
        case .scoreImproved(let kind, let scopeID, let previous, let current):
            return [
                "kind": .string(kind),
                "scope_id": .string(scopeID),
                "previous_score_percent": .number(previous),
                "current_score_percent": .number(current),
            ]
        case .certificateEarned(let productID),
             .purchaseStarted(let productID),
             .purchaseCompleted(let productID),
             .purchaseCancelled(let productID):
            return ["product_id": .string(productID)]
        case .paywallViewed(let source, let productID):
            var result: [String: AnalyticsPropertyValue] = ["source": .string(source)]
            if let productID {
                result["product_id"] = .string(productID)
            }
            return result
        case .productSelected(let productID, let source):
            return [
                "product_id": .string(productID),
                "source": .string(source),
            ]
        case .purchaseFailed(let productID, let failureCategory):
            return [
                "product_id": .string(productID),
                "failure_category": .string(failureCategory),
            ]
        case .restoreCompleted(let restoredCount):
            return ["restored_count": .integer(restoredCount)]
        case .restoreFailed(let failureCategory),
             .syncFailed(let failureCategory):
            return ["failure_category": .string(failureCategory)]
        case .entitlementRevoked(let productID, let reason):
            return [
                "product_id": .string(productID),
                "reason": .string(reason),
            ]
        case .contentLoadFailed(let kind, let failureCategory):
            return [
                "kind": .string(kind),
                "failure_category": .string(failureCategory),
            ]
        case .lessonLoadFailed(let lessonID, let failureCategory),
             .audioPlaybackFailed(let lessonID, let failureCategory),
             .audioDownloadFailed(let lessonID, let failureCategory):
            return [
                "lesson_id": .string(lessonID),
                "failure_category": .string(failureCategory),
            ]
        case .searchNoResults(let source):
            return ["source": .string(source)]
        }
    }
}

// MARK: - Service

/// The analytics event layer. See the file header for the consent
/// model, the privacy rules, and the backend hookup point.
final class AnalyticsService: ObservableObject {
    static let shared = AnalyticsService()

    /// Maximum events kept in the in-memory buffer. Older events
    /// drop off the front; nothing is fabricated to fill the gap.
    static let maxBufferedEvents = 200

    /// Maximum characters kept in one string property. Longer
    /// values are truncated at record time.
    static let maxPropertyLength = 200

    /// Maximum bytes kept in the optional local log file. When an
    /// append would pass it, the file restarts from the new event.
    /// The log is a developer diagnostic, not an archive.
    static let maxLocalLogBytes = 512_000

    private enum Keys {
        /// The opt-in consent flag. Absent means no decision and no
        /// consent. Deliberately never migrated guest to account.
        static let consent = "pf.analytics.consent.v1"
        /// Set once the firstLaunch event has been emitted for this
        /// account. Kept across consent withdrawal; see the header.
        static let firstLaunchRecorded = "pf.analytics.firstLaunchRecorded.v1"
        /// The last launch day ("yyyy-MM-dd") stored while consent
        /// was active, for return-after-absence detection.
        static let lastLaunchDay = "pf.analytics.lastLaunchDay.v1"
        /// The optional local log switch. Default off.
        static let localLogEnabled = "pf.analytics.localLogEnabled.v1"
        /// Best previous scores by "kind:scopeID", for improvement
        /// comparisons. Cleared on consent withdrawal.
        static let previousScores = "pf.analytics.previousScores.v1"

        /// The first-occurrence flag for one milestone suffix, for
        /// example "lessonStarted". Kept across withdrawal.
        static func firstFlag(_ suffix: String) -> String {
            "pf.analytics.first.\(suffix).v1"
        }
    }

    /// True when the current account has opted in. Default false.
    /// Call sites never need to check this: track(_:) gates.
    @Published private(set) var isConsented: Bool

    /// True when the optional local log file receives events.
    /// Default false. Enabling it does not enable recording:
    /// consent still gates every event.
    @Published private(set) var isLocalLogEnabled: Bool

    /// True when the current account has made a consent decision,
    /// granted or declined. False until the first decision, which
    /// lets presentation logic tell "never asked" from "declined".
    var hasMadeConsentDecision: Bool {
        UserDefaults.standard.object(forKey: AccountScopedStorage.currentKey(Keys.consent)) != nil
    }

    /// A snapshot of the in-memory buffer, oldest first. Empty when
    /// consent is off or after withdrawal or account change.
    var recordedEvents: [AnalyticsRecord] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    /// The number of events currently buffered.
    var recordedEventCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    /// The local log file for the current account namespace. The
    /// file lives in Application Support, inside the app sandbox,
    /// and is never shared or exported by this service.
    var localLogFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("TrainingHubAnalytics", isDirectory: true)
        return directory.appendingPathComponent("\(sanitisedNamespaceFileName()).jsonl")
    }

    private var buffer: [AnalyticsRecord] = []
    private let lock = NSLock()

    /// True once recordAppLaunch() has emitted for this process and
    /// account. Reset by reloadForCurrentAccount(), so an account
    /// change starts a fresh launch record for the new account.
    private var didRecordLaunchThisProcess = false

    init() {
        isConsented = UserDefaults.standard.bool(forKey: AccountScopedStorage.currentKey(Keys.consent))
        isLocalLogEnabled = UserDefaults.standard.bool(forKey: AccountScopedStorage.currentKey(Keys.localLogEnabled))
    }

    // MARK: - Consent

    /// Opt in for the current account. Nothing recorded before this
    /// call is emitted retroactively.
    func grantConsent() {
        UserDefaults.standard.set(true, forKey: AccountScopedStorage.currentKey(Keys.consent))
        isConsented = true
    }

    /// Record a No for the current account, and defensively clear
    /// any buffered events and the local log. Normally nothing is
    /// buffered when declining, because nothing is recorded before
    /// consent; the clear covers a decline tapped after a grant.
    func declineConsent() {
        UserDefaults.standard.set(false, forKey: AccountScopedStorage.currentKey(Keys.consent))
        isConsented = false
        clearRecordedEvents()
        deleteLocalLogForCurrentAccount()
    }

    /// Withdraw a previous opt-in for the current account: stop
    /// recording, delete the buffered events, the local log file,
    /// and the stored previous scores. First-occurrence flags and
    /// the first-launch flag are kept; see the file header.
    func withdrawConsent() {
        UserDefaults.standard.set(false, forKey: AccountScopedStorage.currentKey(Keys.consent))
        isConsented = false
        clearRecordedEvents()
        deleteLocalLogForCurrentAccount()
        UserDefaults.standard.removeObject(forKey: AccountScopedStorage.currentKey(Keys.previousScores))
    }

    /// Re-read consent and the local log switch for the current
    /// namespace, clear the in-memory buffer, and allow a fresh
    /// launch record for the new account. AuthService must call
    /// this from reloadAllStores() on every identity transition;
    /// until that hook is wired, an account change mid-process
    /// keeps the previous account's in-memory buffer, which is a
    /// known integration gap, not a behaviour to rely on.
    func reloadForCurrentAccount() {
        isConsented = UserDefaults.standard.bool(forKey: AccountScopedStorage.currentKey(Keys.consent))
        isLocalLogEnabled = UserDefaults.standard.bool(forKey: AccountScopedStorage.currentKey(Keys.localLogEnabled))
        clearRecordedEvents()
        didRecordLaunchThisProcess = false
    }

    // MARK: - Local log and export

    /// Turn the optional local log on or off for the current
    /// account. Turning it off stops new writes; it does not delete
    /// an existing file. Use deleteLocalLogForCurrentAccount() or
    /// withdrawConsent() to delete the file.
    func setLocalLogEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: AccountScopedStorage.currentKey(Keys.localLogEnabled))
        isLocalLogEnabled = enabled
    }

    /// Delete the local log file for the current account, if any.
    func deleteLocalLogForCurrentAccount() {
        try? FileManager.default.removeItem(at: localLogFileURL)
    }

    /// Clear the in-memory buffer without touching consent or the
    /// local log file.
    func clearRecordedEvents() {
        lock.lock()
        buffer.removeAll()
        lock.unlock()
    }

    /// The buffered events as a JSON array string, for diagnostics.
    /// Returns "[]" when the buffer is empty. Records carry no
    /// account identifier, so the export carries none either.
    func debugExportJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(recordedEvents),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    // MARK: - Recording

    /// Record one catalogue event, if consent is active for the
    /// current account. Without consent the event is dropped
    /// silently: no buffer entry, no log line, no backend call.
    /// String properties are sanitised here, at the one record
    /// point, so no call site can smuggle free text into storage.
    func track(_ event: AnalyticsEvent) {
        guard isConsented else { return }
        let record = AnalyticsRecord(
            name: event.name,
            category: event.category.rawValue,
            properties: sanitisedProperties(event.properties)
        )
        lock.lock()
        buffer.append(record)
        if buffer.count > Self.maxBufferedEvents {
            buffer.removeFirst(buffer.count - Self.maxBufferedEvents)
        }
        lock.unlock()
        appendToLocalLog(record)
        forwardToBackend(record)
    }

    // MARK: - Backend hookup point (the only one)

    /// BACKEND HOOKUP POINT: the single place a future analytics
    /// transport plugs in. It does nothing today: no SDK, no
    /// network call, no queue. A future implementation must:
    ///   - keep the consent gate in track(_:) in front of it, so it
    ///     is never called without consent;
    ///   - send only the record it is given, adding no account
    ///     identifier, device identifier, or location;
    ///   - fail silently and never block the caller or surface an
    ///     error to the learner.
    /// Do not add a second transport call anywhere else in this
    /// file or in any call site.
    private func forwardToBackend(_ record: AnalyticsRecord) {
        // No backend today. See the documentation above.
        _ = record
    }

    // MARK: - Launch and retention

    /// Record the app launch, at most once per process and account.
    /// Emits firstLaunch once per account, returnAfterAbsence when
    /// the last consented launch day was at least 2 days ago, and
    /// appLaunched for every recorded launch. Called from the
    /// splash screen, which appears once per launch. Without
    /// consent nothing is recorded and no launch day is stored.
    func recordAppLaunch() {
        guard isConsented else { return }
        guard !didRecordLaunchThisProcess else { return }
        didRecordLaunchThisProcess = true
        let defaults = UserDefaults.standard
        let firstKey = AccountScopedStorage.currentKey(Keys.firstLaunchRecorded)
        if defaults.object(forKey: firstKey) == nil {
            defaults.set(true, forKey: firstKey)
            track(.firstLaunch)
        }
        let lastKey = AccountScopedStorage.currentKey(Keys.lastLaunchDay)
        if let lastString = defaults.string(forKey: lastKey),
           let lastDate = Self.dayFormatter.date(from: lastString) {
            let calendar = Calendar.current
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: lastDate),
                to: calendar.startOfDay(for: Date())
            ).day ?? 0
            if days >= 2 {
                track(.returnAfterAbsence(daysSinceLastLaunch: days))
            }
        }
        defaults.set(Self.dayKey(for: Date()), forKey: lastKey)
        track(.appLaunched)
    }

    // MARK: - Learning events

    /// Record a lesson start, plus firstLessonStarted once per
    /// account. Future call site: LessonView, when a lesson opens.
    func recordLessonStarted(lessonID: String, chapterID: String) {
        guard isConsented else { return }
        track(.lessonStarted(lessonID: lessonID, chapterID: chapterID))
        recordFirstTime(suffix: "lessonStarted", event: .firstLessonStarted(lessonID: lessonID, chapterID: chapterID))
    }

    /// Record a lesson completion, plus firstLessonCompleted once
    /// per account. Future call site: LessonView, where
    /// ProgressStore.markLessonComplete is called.
    func recordLessonCompleted(lessonID: String, chapterID: String) {
        guard isConsented else { return }
        track(.lessonCompleted(lessonID: lessonID, chapterID: chapterID))
        recordFirstTime(suffix: "lessonCompleted", event: .firstLessonCompleted(lessonID: lessonID, chapterID: chapterID))
    }

    /// Record a finished lesson quiz, plus firstQuizCompleted once
    /// per account, plus an improvement check for this lesson.
    /// Future call site: LessonView, where the quiz result is
    /// recorded. total must be greater than zero; a zero total is
    /// recorded with a score of zero rather than dropped, so the
    /// quiz attempt itself stays visible in the funnel.
    func recordQuizCompleted(lessonID: String, correct: Int, total: Int) {
        guard isConsented else { return }
        let scorePercent = total > 0 ? 100 * Double(correct) / Double(total) : 0
        track(.quizCompleted(lessonID: lessonID, correct: correct, total: total, scorePercent: scorePercent))
        recordFirstTime(suffix: "quizCompleted", event: .firstQuizCompleted(lessonID: lessonID, correct: correct, total: total, scorePercent: scorePercent))
        recordScoreForImprovement(kind: "quiz", scopeID: lessonID, scorePercent: scorePercent)
    }

    /// Record a finished practical exercise, plus
    /// firstPracticalExerciseCompleted once per account. kind is
    /// one of "studio", "lab", or "practice". Future call sites:
    /// the studio completion path, the exception lab completion
    /// path, and the practice mode completion path.
    func recordPracticalExerciseCompleted(exerciseID: String, kind: String) {
        guard isConsented else { return }
        track(.practicalExerciseCompleted(exerciseID: exerciseID, kind: kind))
        recordFirstTime(suffix: "practicalExerciseCompleted", event: .firstPracticalExerciseCompleted(exerciseID: exerciseID, kind: kind))
    }

    /// Record a path selection, plus firstPathSelected once per
    /// account. Future call site: the path selection action that
    /// sets the active path.
    func recordPathSelected(pathID: String, role: String) {
        guard isConsented else { return }
        track(.pathSelected(pathID: pathID, role: role))
        recordFirstTime(suffix: "pathSelected", event: .firstPathSelected(pathID: pathID, role: role))
    }

    /// Record a path continuation: the learner resumed a path they
    /// had already selected. Future call site: the continue-path
    /// entry point on the home screen.
    func recordPathContinued(pathID: String) {
        track(.pathContinued(pathID: pathID))
    }

    /// Record a Daily Challenge view. Called from DailyChallengeView
    /// when the screen appears.
    func recordChallengeViewed() {
        track(.challengeViewed)
    }

    /// Record a Daily Challenge answer, plus
    /// firstChallengeCompleted once per account. Called from
    /// DailyChallengeView when the learner checks an answer.
    func recordChallengeCompleted(correct: Bool) {
        guard isConsented else { return }
        track(.challengeCompleted(correct: correct))
        recordFirstTime(suffix: "challengeCompleted", event: .firstChallengeCompleted(correct: correct))
    }

    // MARK: - Assessments

    /// Record an assessment start. Called from AssessmentView when
    /// the learner starts or retakes an assessment.
    func recordAssessmentStarted(dimension: String, questionCount: Int, timed: Bool, randomised: Bool) {
        track(.assessmentStarted(dimension: dimension, questionCount: questionCount, timed: timed, randomised: randomised))
    }

    /// Record a finished assessment, plus an improvement check for
    /// this dimension. Called from AssessmentView when the session
    /// finishes, next to the CompetencyStore recording.
    func recordAssessmentCompleted(dimension: String, correct: Int, total: Int, elapsedSeconds: Int, unansweredCount: Int) {
        guard isConsented else { return }
        let scorePercent = total > 0 ? 100 * Double(correct) / Double(total) : 0
        track(.assessmentCompleted(dimension: dimension, correct: correct, total: total, scorePercent: scorePercent, elapsedSeconds: elapsedSeconds, unansweredCount: unansweredCount))
        recordScoreForImprovement(kind: "assessment", scopeID: dimension, scorePercent: scorePercent)
    }

    /// Record a Final Assessment start. Called from
    /// FinalAssessmentView when the exam starts or resumes.
    func recordFinalAssessmentStarted(productID: String, attemptNumber: Int, isResume: Bool) {
        track(.finalAssessmentStarted(productID: productID, attemptNumber: attemptNumber, isResume: isResume))
    }

    /// Record a finished Final Assessment, plus an improvement
    /// check for this course. Called from FinalAssessmentView when
    /// the session finishes, next to the attempt recording. The
    /// caller supplies passed from the store pass rule.
    func recordFinalAssessmentCompleted(productID: String, attemptNumber: Int, correct: Int, total: Int, passed: Bool, elapsedSeconds: Int, unansweredCount: Int) {
        guard isConsented else { return }
        let scorePercent = total > 0 ? 100 * Double(correct) / Double(total) : 0
        track(.finalAssessmentCompleted(productID: productID, attemptNumber: attemptNumber, correct: correct, total: total, passed: passed, scorePercent: scorePercent, elapsedSeconds: elapsedSeconds, unansweredCount: unansweredCount))
        recordScoreForImprovement(kind: "finalAssessment", scopeID: productID, scorePercent: scorePercent)
    }

    /// Record a certificate issue. Called from FinalAssessmentView
    /// when recordAttempt returns a certificate.
    func recordCertificateEarned(productID: String) {
        track(.certificateEarned(productID: productID))
    }

    /// Compare a score with the best previous score for the same
    /// kind and scope, emit scoreImproved when the new score beats
    /// it, and store the new best. A first score for a scope is
    /// stored without emitting an improvement: there is nothing
    /// real to improve on yet. Scores are stored per account and
    /// cleared on consent withdrawal.
    func recordScoreForImprovement(kind: String, scopeID: String, scorePercent: Double) {
        guard isConsented else { return }
        let key = "\(kind):\(scopeID)"
        var scores = loadPreviousScores()
        if let previous = scores[key], scorePercent > previous {
            track(.scoreImproved(kind: kind, scopeID: scopeID, previousScorePercent: previous, currentScorePercent: scorePercent))
        }
        if scores[key] == nil || scorePercent > (scores[key] ?? 0) {
            scores[key] = scorePercent
            savePreviousScores(scores)
        }
    }

    // MARK: - Monetisation

    /// Record a paywall view. Future call sites: the locked lesson
    /// section in LessonView, the situations unlock card, and any
    /// other locked-content upsell. productID is nil when the
    /// paywall offers the catalogue rather than one product.
    func recordPaywallViewed(source: String, productID: String?) {
        track(.paywallViewed(source: source, productID: productID))
    }

    /// Record a product selection. Future call site: the purchases
    /// screen, when the learner taps a course card.
    func recordProductSelected(productID: String, source: String) {
        track(.productSelected(productID: productID, source: source))
    }

    /// Record a purchase start. Future call site: StoreManager,
    /// where a purchase begins.
    func recordPurchaseStarted(productID: String) {
        track(.purchaseStarted(productID: productID))
    }

    /// Record a verified purchase completion. Future call site:
    /// StoreManager, where a verified transaction is handled.
    /// Only verified completions may call this; a failed
    /// verification must call recordPurchaseFailed instead.
    func recordPurchaseCompleted(productID: String) {
        track(.purchaseCompleted(productID: productID))
    }

    /// Record a purchase failure. failureCategory is a controlled
    /// word from the store layer, never a raw error message.
    /// Future call site: StoreManager, where a purchase fails or
    /// verification fails.
    func recordPurchaseFailed(productID: String, failureCategory: String) {
        track(.purchaseFailed(productID: productID, failureCategory: failureCategory))
    }

    /// Record a learner-cancelled purchase. Future call site:
    /// StoreManager, where the purchase sheet is dismissed by the
    /// learner without buying.
    func recordPurchaseCancelled(productID: String) {
        track(.purchaseCancelled(productID: productID))
    }

    /// Record a restore start. Future call site: StoreManager,
    /// where a restore begins.
    func recordRestoreStarted() {
        track(.restoreStarted)
    }

    /// Record a restore completion. Future call site: StoreManager,
    /// where a restore finishes, including a zero restore.
    func recordRestoreCompleted(restoredCount: Int) {
        track(.restoreCompleted(restoredCount: restoredCount))
    }

    /// Record a restore failure. failureCategory follows the same
    /// controlled-word rule as purchase failures. Future call site:
    /// StoreManager, where a restore fails.
    func recordRestoreFailed(failureCategory: String) {
        track(.restoreFailed(failureCategory: failureCategory))
    }

    /// Record an entitlement removal after a refund or revocation.
    /// reason is a controlled word from the store layer, for
    /// example "revoked" or "refunded". Future call site:
    /// StoreManager, where a transaction update removes an
    /// entitlement.
    func recordEntitlementRevoked(productID: String, reason: String) {
        track(.entitlementRevoked(productID: productID, reason: reason))
    }

    // MARK: - Technical quality

    /// Record a content load failure. Called from AssessmentView
    /// and FinalAssessmentView when the catalogue has not loaded;
    /// future call sites may add other kinds, for example a
    /// catalogue load failure in ContentService.
    func recordContentLoadFailed(kind: String, failureCategory: String) {
        track(.contentLoadFailed(kind: kind, failureCategory: failureCategory))
    }

    /// Record a lesson detail load failure. Future call site:
    /// ContentService, where a lesson detail load fails.
    func recordLessonLoadFailed(lessonID: String, failureCategory: String) {
        track(.lessonLoadFailed(lessonID: lessonID, failureCategory: failureCategory))
    }

    /// Record an audio playback failure. Future call site:
    /// AudioPlayerService, where playback fails or failover is
    /// exhausted.
    func recordAudioPlaybackFailed(lessonID: String, failureCategory: String) {
        track(.audioPlaybackFailed(lessonID: lessonID, failureCategory: failureCategory))
    }

    /// Record an audio download failure. Future call site:
    /// LessonDownloadStore, where a download fails.
    func recordAudioDownloadFailed(lessonID: String, failureCategory: String) {
        track(.audioDownloadFailed(lessonID: lessonID, failureCategory: failureCategory))
    }

    /// Record a sync failure. failureCategory is a controlled word
    /// from the sync layer, never a raw error message. Future call
    /// site: SyncService, where a sync run records its last error.
    func recordSyncFailed(failureCategory: String) {
        track(.syncFailed(failureCategory: failureCategory))
    }

    /// Record a search with no results. The search words are never
    /// passed here. Future call site: SearchService, where a search
    /// returns an empty result set.
    func recordSearchNoResults(source: String) {
        track(.searchNoResults(source: source))
    }

    // MARK: - Private helpers

    /// Emit a first-occurrence event once per account. The flag is
    /// set only while consent is active, so a pre-consent milestone
    /// never consumes the one emission.
    private func recordFirstTime(suffix: String, event: AnalyticsEvent) {
        guard isConsented else { return }
        let key = AccountScopedStorage.currentKey(Keys.firstFlag(suffix))
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        UserDefaults.standard.set(true, forKey: key)
        track(event)
    }

    /// Sanitise every string property: trim, collapse line breaks
    /// and tabs to spaces, and cap the length. Numbers and booleans
    /// pass through unchanged.
    private func sanitisedProperties(_ properties: [String: AnalyticsPropertyValue]) -> [String: AnalyticsPropertyValue] {
        var result: [String: AnalyticsPropertyValue] = [:]
        for (key, value) in properties {
            switch value {
            case .string(let text):
                result[key] = .string(sanitisedText(text))
            default:
                result[key] = value
            }
        }
        return result
    }

    private func sanitisedText(_ text: String) -> String {
        let singleLine = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        if singleLine.count > Self.maxPropertyLength {
            return String(singleLine.prefix(Self.maxPropertyLength))
        }
        return singleLine
    }

    private func loadPreviousScores() -> [String: Double] {
        guard let data = UserDefaults.standard.data(forKey: AccountScopedStorage.currentKey(Keys.previousScores)),
              let decoded = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func savePreviousScores(_ scores: [String: Double]) {
        if let data = try? JSONEncoder().encode(scores) {
            UserDefaults.standard.set(data, forKey: AccountScopedStorage.currentKey(Keys.previousScores))
        }
    }

    private func appendToLocalLog(_ record: AnalyticsRecord) {
        guard isLocalLogEnabled else { return }
        guard let data = try? JSONEncoder().encode(record) else { return }
        let url = localLogFileURL
        let line = data + Data("\n".utf8)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? NSNumber,
               size.intValue >= Self.maxLocalLogBytes {
                try? FileManager.default.removeItem(at: url)
            }
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: url, options: [.atomic])
            }
        } catch {
            // The local log is a diagnostic only. A failure to
            // write it must never surface to the learner or affect
            // recording, so it is swallowed here deliberately.
        }
    }

    private func sanitisedNamespaceFileName() -> String {
        let raw = AccountScopedStorage.currentNamespace
        let chars = raw.map { char in
            (char.isLetter || char.isNumber || char == "-" || char == "_") ? char : "-"
        }
        let result = String(chars)
        return result.isEmpty ? AccountScopedStorage.guestNamespace : result
    }

    private static var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }

    private static func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }
}
