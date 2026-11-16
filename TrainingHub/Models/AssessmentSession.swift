// AssessmentSession.swift
// Payments Training Hub iOS - Timed and randomised assessment sessions.
//
// An assessment session runs over real lesson quiz questions only:
// questions are collected by AssessmentView from the lesson pages and
// handed to this session. This session never invents a question, an
// option or a correct answer. It adds two modes on top of that real
// question set:
// - Timed mode: 60 seconds per question (configurable), shown as a
//   countdown bar, with a total time limit for the whole session.
//   When a question's time expires the session auto-advances and the
//   question is marked unanswered, never guessed. When the total time
//   expires the session finishes.
// - Randomised mode: questions and options are shuffled with a seed
//   drawn per session, so a retake is different. The correct answer
//   is tracked by content (the option index is remapped through the
//   shuffle permutation), never by position, so it can never be
//   derived from where an option sits.
// The timer is a single Foundation Timer owned by this session, but
// the remaining time is always computed from a stored wall-clock
// end time, never by counting ticks. Backgrounding the app suspends
// the timer, but the end time keeps passing, so no extra time is
// ever gained. The end time can be persisted under a caller key so
// a Final Assessment started earlier can be resumed with the time
// left. The timer is invalidated when the session finishes, when
// stop() is called (the view calls stop() in onDisappear), and in
// deinit, so no timer can leak past the view.
// No em dashes in any user-facing text.

import Foundation
import Combine

// MARK: - Seeded random source

/// A small deterministic random source (xorshift64star) so one
/// session's shuffle is reproducible from its seed, while each new
/// session draws a fresh seed and shuffles differently.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Zero is a fixed point for xorshift, so never seed with it.
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        var x = state
        x ^= x >> 12
        x ^= x << 25
        x ^= x >> 27
        state = x
        return x &* 0x2545F4914F6CDD1D
    }
}

// MARK: - Assessment question (shared with AssessmentView)

/// One assessment question, built from a real lesson quiz question.
/// `options` are in display order; `correctOptionIndex` is the index
/// of the correct option in that same order.
struct AssessmentQuestion: Identifiable, Hashable {
    let id: String
    let lessonID: String
    let lessonTitle: String
    let question: String
    let options: [String]
    let correctOptionIndex: Int
    let explanation: String
}

// MARK: - Session

/// Runs one assessment: timing, randomisation, answers and results.
/// The view owns this as a StateObject and drives it; the session
/// owns the timer and the shuffle.
final class AssessmentSession: ObservableObject {
    /// Seconds allowed per question in timed mode.
    static let secondsPerQuestion = 60
    /// The Final Assessment total time limit: 30 minutes for all
    /// 20 questions. It is always on for the Final Assessment.
    static let finalAssessmentTimeLimit = 30 * 60

    /// The seed this session shuffled with. Drawn fresh per session
    /// (start or retake), so a retake shuffles differently.
    @Published private(set) var seed: UInt64 = 0
    @Published private(set) var questions: [AssessmentQuestion] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var answers: [String: Int] = [:]
    /// Seconds spent on each question, by question id. Recorded when
    /// the learner leaves a question, whether by answering, by
    /// timeout or at the end of the session.
    @Published private(set) var timeUsedPerQuestion: [String: Int] = [:]
    @Published private(set) var isTimed = false
    @Published private(set) var isRandomised = false
    @Published private(set) var isStarted = false
    @Published private(set) var isFinished = false

    /// Seconds left on the current question, timed mode only.
    @Published private(set) var secondsLeftForQuestion: Int = secondsPerQuestion
    /// Seconds left for the whole session, timed mode only.
    @Published private(set) var totalSecondsLeft: Int = 0
    /// Total seconds the session has run, timed or not.
    @Published private(set) var elapsedSeconds: Int = 0
    /// True when the per-question countdown is on. The Final
    /// Assessment turns it off: it has only the 30-minute total.
    @Published private(set) var perQuestionTimeoutEnabled = false

    private var timer: Timer?
    private var questionStartedAt: Date?
    private var sessionStartedAt: Date?
    private var totalTimeLimit: Int = 0
    /// The wall-clock moment this timed session ends. Remaining
    /// time is always computed from this, never by counting ticks,
    /// so backgrounding the app cannot gain extra time.
    private var examEndsAt: Date?
    /// UserDefaults key the end time is persisted under, if any.
    /// The caller supplies a fully namespaced key from
    /// AccountScopedStorage.currentKey, so one account's running
    /// exam clock never resumes under another account. Kept so
    /// finish() can clear it.
    private var persistKey: String?

    var currentQuestion: AssessmentQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var correctCount: Int {
        questions.filter { answers[$0.id] == $0.correctOptionIndex }.count
    }

    var scorePercent: Double {
        guard !questions.isEmpty else { return 0 }
        return 100 * Double(correctCount) / Double(questions.count)
    }

    /// Questions left unanswered (timed out or skipped by finishing).
    var unansweredCount: Int {
        questions.filter { answers[$0.id] == nil }.count
    }

    /// Total time limit for this session in timed mode, in seconds.
    var totalLimitSeconds: Int { totalTimeLimit }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Start

    /// Start a session over the given real questions. In randomised
    /// mode the questions and their options are shuffled with a fresh
    /// per-session seed; the correct answer follows its option through
    /// the shuffle. In timed mode the per-question and total clocks
    /// start. Calling start again (a retake) draws a new seed.
    /// totalTimeLimit overrides the default total (60 seconds per
    /// question); the Final Assessment passes 30 minutes. Set
    /// perQuestionTimeout false to turn off the per-question
    /// auto-advance: the Final Assessment has only the total clock.
    /// persistKey saves the wall-clock end time under that fully
    /// namespaced UserDefaults key so an unfinished exam can be
    /// resumed with the time left; finish() clears it.
    func start(
        questions: [AssessmentQuestion],
        timed: Bool,
        randomised: Bool,
        totalTimeLimit: Int? = nil,
        perQuestionTimeout: Bool = true,
        persistKey: String? = nil
    ) {
        stopTimer()
        seed = UInt64.random(in: 1...UInt64.max)
        isTimed = timed
        isRandomised = randomised
        if randomised {
            var generator = SeededRandomNumberGenerator(seed: seed)
            self.questions = questions.shuffled(using: &generator).map { shuffledOptions(for: $0, using: &generator) }
        } else {
            self.questions = questions
        }
        currentIndex = 0
        answers = [:]
        timeUsedPerQuestion = [:]
        elapsedSeconds = 0
        isFinished = false
        isStarted = true
        self.totalTimeLimit = totalTimeLimit ?? (timed ? Self.secondsPerQuestion * max(self.questions.count, 1) : 0)
        totalSecondsLeft = self.totalTimeLimit
        secondsLeftForQuestion = Self.secondsPerQuestion
        perQuestionTimeoutEnabled = timed && perQuestionTimeout
        sessionStartedAt = Date()
        questionStartedAt = Date()
        self.persistKey = persistKey
        if timed {
            examEndsAt = Date().addingTimeInterval(TimeInterval(self.totalTimeLimit))
            if let key = persistKey, let endsAt = examEndsAt {
                UserDefaults.standard.set(endsAt, forKey: key)
            }
            startTimer()
        } else {
            examEndsAt = nil
            if let key = persistKey {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    /// The wall-clock end of a timed exam started earlier, if one
    /// was persisted under this fully namespaced key and has not
    /// been cleared by a finish. The Final Assessment setup screen
    /// uses it to offer a resume with the time left.
    static func storedEndTime(forKey key: String) -> Date? {
        UserDefaults.standard.object(forKey: key) as? Date
    }

    /// Drop a persisted end time, for example when it has expired
    /// and the learner starts a fresh attempt.
    static func clearStoredEndTime(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Shuffle one question's options, remapping the correct index
    /// through the permutation so the correct answer is tracked by
    /// content, never by position.
    private func shuffledOptions(for question: AssessmentQuestion, using generator: inout SeededRandomNumberGenerator) -> AssessmentQuestion {
        var order = Array(question.options.indices)
        order.shuffle(using: &generator)
        let newOptions = order.map { question.options[$0] }
        let newCorrect = order.firstIndex(of: question.correctOptionIndex) ?? question.correctOptionIndex
        return AssessmentQuestion(
            id: question.id,
            lessonID: question.lessonID,
            lessonTitle: question.lessonTitle,
            question: question.question,
            options: newOptions,
            correctOptionIndex: newCorrect,
            explanation: question.explanation
        )
    }

    // MARK: - Answering

    /// Record an answer for the current question and move on. The
    /// last question finishes the session.
    func answerCurrentQuestion(option: Int) {
        guard isStarted, !isFinished, let question = currentQuestion else { return }
        recordTimeForCurrentQuestion()
        answers[question.id] = option
        advance()
    }

    /// Move to the next question without answering. Used only when
    /// the per-question timer expires: the question stays unanswered.
    private func advanceUnanswered() {
        guard isStarted, !isFinished else { return }
        recordTimeForCurrentQuestion()
        advance()
    }

    private func advance() {
        if currentIndex >= questions.count - 1 {
            finish()
        } else {
            currentIndex += 1
            secondsLeftForQuestion = Self.secondsPerQuestion
            questionStartedAt = Date()
        }
    }

    /// Finish the session: stop the timer and record the time spent
    /// on the final question. Safe to call twice. Clears any
    /// persisted end time, so the next attempt starts a fresh clock.
    func finish() {
        guard isStarted, !isFinished else { return }
        recordTimeForCurrentQuestion()
        isFinished = true
        stopTimer()
        if let key = persistKey {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Recompute the remaining time from the wall clock and finish
    /// the exam if the limit has passed. Called when the app returns
    /// to the foreground, so background time counts against the
    /// limit even though the timer was suspended while away.
    func recheckTime() {
        guard isStarted, !isFinished, let endsAt = examEndsAt else { return }
        totalSecondsLeft = max(0, Int(endsAt.timeIntervalSinceNow.rounded()))
        elapsedSeconds = max(0, totalTimeLimit - totalSecondsLeft)
        if totalSecondsLeft <= 0 {
            totalSecondsLeft = 0
            finish()
        }
    }

    /// Stop the session and its timer. The view calls this in
    /// onDisappear so no timer outlives the screen.
    func stop() {
        stopTimer()
        isStarted = false
    }

    /// Return to the setup screen (for "Change options"): the timer
    /// is stopped and the finished flag cleared. Loaded questions are
    /// kept by the view and can be started again.
    func resetToSetup() {
        stopTimer()
        isStarted = false
        isFinished = false
    }

    private func recordTimeForCurrentQuestion() {
        guard let question = currentQuestion,
              let started = questionStartedAt else { return }
        let spent = max(0, Int(Date().timeIntervalSince(started).rounded()))
        timeUsedPerQuestion[question.id] = (timeUsedPerQuestion[question.id] ?? 0) + spent
        questionStartedAt = Date()
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isStarted, !isFinished else {
            stopTimer()
            return
        }
        if let endsAt = examEndsAt {
            // Wall clock, never tick counting: background time counts.
            totalSecondsLeft = max(0, Int(endsAt.timeIntervalSinceNow.rounded()))
            elapsedSeconds = max(0, totalTimeLimit - totalSecondsLeft)
            if totalSecondsLeft <= 0 {
                totalSecondsLeft = 0
                finish()
                return
            }
        } else {
            elapsedSeconds += 1
        }
        if perQuestionTimeoutEnabled {
            secondsLeftForQuestion -= 1
            if secondsLeftForQuestion <= 0 {
                // Time expired on this question: mark it unanswered
                // (no answer is recorded) and move on.
                secondsLeftForQuestion = Self.secondsPerQuestion
                advanceUnanswered()
            }
        }
    }

    // MARK: - Formatting

    /// Format a duration as m:ss, for example 4:05.
    static func format(seconds: Int) -> String {
        let clamped = max(0, seconds)
        return "\(clamped / 60):\(String(format: "%02d", clamped % 60))"
    }
}
