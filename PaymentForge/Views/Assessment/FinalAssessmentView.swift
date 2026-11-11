// FinalAssessmentView.swift
// PaymentForge iOS - Final Assessment for one course bundle.
// 20 questions drawn ONLY from the real lesson quiz questions of
// the course's chapters, loaded in batches. No question, option or
// correct answer is ever invented. The pass mark is strictly above
// 70 percent, so 15 or more correct out of 20. Each course allows at
// most 3 attempts, tracked per course in FinalAssessmentStore; when
// the attempts are exhausted without a pass the assessment locks and
// the learner must contact support. Questions and options are
// shuffled with a fresh seed on every attempt, so each attempt is
// different. Passing issues a Certificate of Completion for the
// course. Questions are PaymentForge-specific because they come from
// the real lesson quizzes, grounded in the course content, so they
// are not answerable from generic knowledge.
// The exam has a 30-minute countdown for all 20 questions, shown
// pinned at the top of the screen and red under 5 minutes. It runs
// on a wall-clock end time, so it keeps counting if the app is
// backgrounded or the learner leaves the screen; at zero the exam
// auto-submits with the answers given so far. The end time is kept
// per course, so leaving and coming back resumes the same clock.
// Questions are medium level: they test understanding and
// application from the lessons, not trivial recall and not obscure
// detail. Question and option text cannot be copied, so it cannot
// be pasted into another app.
// No em dashes in any user-facing text.

import SwiftUI

struct FinalAssessmentView: View {
    @EnvironmentObject private var contentService: ContentService
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var authService = AuthService.shared
    @ObservedObject private var assessmentStore = FinalAssessmentStore.shared
    @StateObject private var session = AssessmentSession()

    let course: CourseProduct

    @State private var loadedQuestions: [AssessmentQuestion] = []
    @State private var isLoading = true
    @State private var loadError: String? = nil
    @State private var selectedOption: Int? = nil
    @State private var didRecordAttempt = false
    @State private var earnedCertificate: CourseCertificate? = nil

    /// UserDefaults key for this course's exam end time. The timer
    /// is wall-clock based, so the end time is kept here while an
    /// exam is running and cleared when it finishes.
    private var endTimeKey: String {
        "pf.finalAssessment.endTime.\(course.productID).v1"
    }

    /// The wall-clock end of an exam started earlier for this
    /// course, if the learner left the screen before finishing.
    /// The timer kept running, so resuming uses the time left.
    private var storedEndTime: Date? {
        AssessmentSession.storedEndTime(forKey: endTimeKey)
    }

    /// Seconds left on an earlier exam, or nil when there is no
    /// unfinished exam for this course.
    private var storedRemainingSeconds: Int? {
        guard let end = storedEndTime else { return nil }
        let remaining = Int(end.timeIntervalSinceNow.rounded())
        return remaining > 0 ? remaining : nil
    }

    private var learnerName: String {
        if let name = authService.currentUser?.displayName,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        if let name = authService.profile?.displayName {
            return name
        }
        return "Guest Learner"
    }

    private var existingCertificate: CourseCertificate? {
        assessmentStore.certificate(for: course.productID)
    }

    private var attemptsUsed: Int {
        assessmentStore.attemptsUsedCount(for: course.productID)
    }

    private var attemptsRemaining: Int {
        assessmentStore.attemptsRemaining(for: course.productID)
    }

    private var isLocked: Bool {
        assessmentStore.isLocked(courseID: course.productID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                if session.isFinished {
                    resultsView
                } else if let certificate = existingCertificate ?? earnedCertificate {
                    certificateSection(certificate)
                } else if isLocked {
                    lockedView
                } else if isLoading {
                    HStack(spacing: PFSpacing.sm) {
                        ProgressView()
                        Text("Loading real quiz questions...")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let loadError {
                    PFCard {
                        VStack(alignment: .leading, spacing: PFSpacing.sm) {
                            Text("Could not load the Final Assessment")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                            Text(loadError)
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                            PFPrimaryButton(title: "Retry") {
                                Task { await loadQuestions() }
                            }
                        }
                    }
                } else if session.isFinished {
                    resultsView
                } else if loadedQuestions.count < FinalAssessmentStore.questionCount {
                    PFCard {
                        VStack(alignment: .leading, spacing: PFSpacing.sm) {
                            Text("Not enough real questions yet")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                            Text("Only \(loadedQuestions.count) real quiz \(loadedQuestions.count == 1 ? "question was" : "questions were") found in \(course.name). The Final Assessment needs \(FinalAssessmentStore.questionCount). No questions were invented to fill the gap. Check your connection and try again.")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            PFPrimaryButton(title: "Retry") {
                                Task { await loadQuestions() }
                            }
                        }
                    }
                } else if !session.isStarted {
                    setupView
                } else {
                    questionView
                }
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .safeAreaInset(edge: .top) {
            if session.isStarted && !session.isFinished {
                examTimerBar
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .navigationTitle("Final Assessment")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if existingCertificate == nil && !isLocked {
                await loadQuestions()
            } else {
                isLoading = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // The app came back to the foreground: recompute the
            // remaining time from the wall clock at once, so time
            // spent backgrounded counts and an expired exam submits
            // immediately instead of waiting for the next tick.
            if newPhase == .active {
                session.recheckTime()
            }
        }
        .onDisappear {
            session.stop()
        }
        .onChange(of: session.isFinished) { _, finished in
            if finished, !didRecordAttempt {
                didRecordAttempt = true
                earnedCertificate = assessmentStore.recordAttempt(
                    for: course,
                    correct: session.correctCount,
                    total: session.questions.count,
                    learnerName: learnerName
                )
            }
        }
    }

    // MARK: - Loading real questions

    /// Collect 20 real quiz questions from the course's chapters, in
    /// chapter order. Lesson pages are loaded in batches of 8 at a
    /// time; a lesson whose page fails to load is skipped, never
    /// invented. Stops as soon as 20 questions are found.
    private func loadQuestions() async {
        guard loadedQuestions.count < FinalAssessmentStore.questionCount else { return }
        isLoading = true
        loadError = nil
        var entries: [SearchEntry] = []
        var seen: Set<String> = []
        for chapterID in course.chapterIDs {
            guard let number = PFChapterHelper.chapterNumber(from: chapterID + "s1") else { continue }
            for lesson in PFChapterHelper.lessons(forChapter: number, in: contentService) {
                if seen.insert(lesson.id).inserted { entries.append(lesson) }
            }
        }
        var collected: [AssessmentQuestion] = []
        var index = 0
        while collected.count < FinalAssessmentStore.questionCount && index < entries.count {
            let end = min(index + 8, entries.count)
            let batch = Array(entries[index..<end])
            index = end
            let batchQuestions = await withTaskGroup(of: (Int, [AssessmentQuestion]).self) { group in
                for (offset, entry) in batch.enumerated() {
                    group.addTask {
                        guard let detail = try? await contentService.loadLessonDetail(entry: entry) else {
                            return (offset, [])
                        }
                        let questions = detail.quiz.map { quiz in
                            AssessmentQuestion(
                                id: quiz.id,
                                lessonID: entry.id,
                                lessonTitle: entry.title,
                                question: quiz.question,
                                options: quiz.options,
                                correctOptionIndex: quiz.correctOptionIndex,
                                explanation: quiz.explanation
                            )
                        }
                        return (offset, questions)
                    }
                }
                var ordered: [(Int, [AssessmentQuestion])] = []
                for await pair in group { ordered.append(pair) }
                return ordered.sorted { $0.0 < $1.0 }.flatMap { $0.1 }
            }
            for question in batchQuestions {
                if collected.count >= FinalAssessmentStore.questionCount { break }
                collected.append(question)
            }
        }
        if collected.isEmpty && contentService.searchIndex == nil {
            loadError = "The course catalogue has not loaded yet. Check your connection and try again."
        }
        loadedQuestions = collected
        isLoading = false
    }

    // MARK: - Starting and resuming

    /// Start the exam: 20 questions, 30 minutes on a wall-clock
    /// end time, no per-question auto-advance. The end time is kept
    /// per course so leaving and coming back resumes the same clock.
    private func startExam(totalLimit: Int) {
        didRecordAttempt = false
        earnedCertificate = nil
        selectedOption = nil
        session.start(
            questions: loadedQuestions,
            timed: true,
            randomised: true,
            totalTimeLimit: totalLimit,
            perQuestionTimeout: false,
            persistKey: endTimeKey
        )
    }

    /// Resume an exam started earlier: use the time left on its
    /// clock. If the clock has run out since, drop it and start a
    /// fresh 30 minutes.
    private func resumeExam() {
        if let remaining = storedRemainingSeconds {
            startExam(totalLimit: remaining)
        } else {
            AssessmentSession.clearStoredEndTime(forKey: endTimeKey)
            startExam(totalLimit: AssessmentSession.finalAssessmentTimeLimit)
        }
    }

    /// The 30-minute countdown, pinned to the top of the exam screen
    /// so it stays visible while the learner scrolls. Red under
    /// 5 minutes. It updates every second from the session.
    private var examTimerBar: some View {
        let lowTime = session.totalSecondsLeft <= 5 * 60
        return VStack(spacing: 6) {
            HStack(spacing: PFSpacing.sm) {
                Image(systemName: "timer")
                    .foregroundColor(lowTime ? .pfError : .pfRoyal)
                Text("\(AssessmentSession.format(seconds: session.totalSecondsLeft)) left")
                    .font(.pfSectionTitle)
                    .foregroundColor(lowTime ? .pfError : .pfNavy)
                Spacer()
                Text("Question \(session.currentIndex + 1) of \(session.questions.count)")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfSecondaryText)
            }
            PFProgressBar(
                progress: Double(session.totalSecondsLeft) / Double(max(session.totalLimitSeconds, 1)),
                height: 6
            )
        }
        .padding(.horizontal, PFSpacing.lg)
        .padding(.vertical, PFSpacing.sm)
        .background(Color.pfCard)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(Color.pfBorder),
            alignment: .bottom
        )
        .accessibilityLabel("\(AssessmentSession.format(seconds: session.totalSecondsLeft)) left in the Final Assessment")
    }

    // MARK: - Locked (attempts exhausted)

    private var lockedView: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("No attempts left")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                Text("All \(FinalAssessmentStore.maxAttempts) attempts for \(course.name) have been used without a pass. The Final Assessment is locked. Contact Payments Training Hub support if you need another attempt.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Certificate (already earned)

    private func certificateSection(_ certificate: CourseCertificate) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            CourseCertificateCard(certificate: certificate)
            NavigationLink(destination: CourseCertificateView(certificate: certificate)) {
                Text("View, share or save certificate")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.pfRoyal)
                    .cornerRadius(PFSpacing.cornerRadius)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Setup

    private var setupView: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    HStack(spacing: PFSpacing.sm) {
                        PFPill(text: course.name)
                        Spacer()
                        Text("\(loadedQuestions.count) questions")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                    }
                    Text("Final Assessment for \(course.name)")
                        .font(.pfSectionTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("20 questions drawn from the real lesson quizzes for this course. These questions test what the course itself teaches, so they are not answerable from generic knowledge. You need more than 70 percent to pass, that is at least 15 out of 20 correct.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    HStack(spacing: PFSpacing.sm) {
                        Image(systemName: "arrow.counterclockwise.circle")
                            .foregroundColor(.pfRoyal)
                        Text("Attempt \(attemptsUsed + 1) of \(FinalAssessmentStore.maxAttempts). \(attemptsRemaining) \(attemptsRemaining == 1 ? "attempt" : "attempts") left.")
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Questions and options are shuffled with a fresh seed on every attempt, so each attempt is different. Passing issues your Certificate of Completion for this course.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    HStack(spacing: PFSpacing.sm) {
                        Image(systemName: "timer")
                            .foregroundColor(.pfRoyal)
                        Text("30-minute limit")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                    }
                    Text("You have 30 minutes for all 20 questions. The timer starts when you tap Start and keeps running even if you leave the app or lock your phone. When it reaches zero, your answers so far are submitted. Unanswered questions count as wrong.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let remaining = storedRemainingSeconds {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        Text("Exam in progress")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text("You started this assessment earlier and the timer kept running. You have \(AssessmentSession.format(seconds: remaining)) left.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        PFPrimaryButton(title: "Resume Final Assessment") {
                            resumeExam()
                        }
                    }
                }
            } else {
                PFPrimaryButton(title: "Start Final Assessment") {
                    startExam(totalLimit: AssessmentSession.finalAssessmentTimeLimit)
                }
            }
        }
    }

    // MARK: - Question

    private var questionView: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    HStack(spacing: PFSpacing.sm) {
                        PFPill(text: course.name)
                        Spacer()
                        Text("Question \(session.currentIndex + 1) of \(session.questions.count)")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                    }
                    PFProgressBar(progress: Double(session.currentIndex) / Double(max(session.questions.count, 1)), height: 6)
                    if let question = session.currentQuestion {
                        // Question text cannot be selected or copied,
                        // so it cannot be pasted into another app.
                        Text(question.question)
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.disabled)
                        ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                            Button {
                                selectedOption = index
                            } label: {
                                HStack(alignment: .top, spacing: PFSpacing.sm) {
                                    Image(systemName: selectedOption == index ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedOption == index ? .pfRoyal : .pfSecondaryText)
                                        .padding(.top, 2)
                                    Text(option)
                                        .font(.pfBody)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .multilineTextAlignment(.leading)
                                        .textSelection(.disabled)
                                    Spacer()
                                }
                                .padding(PFSpacing.md)
                                .background(selectedOption == index ? Color.pfRoyal.opacity(0.08) : Color.pfCard)
                                .cornerRadius(PFSpacing.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                                        .stroke(selectedOption == index ? Color.pfRoyal : Color.pfBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            PFPrimaryButton(title: session.currentIndex == session.questions.count - 1 ? "See my score" : "Next question") {
                guard let selectedOption else { return }
                session.answerCurrentQuestion(option: selectedOption)
                self.selectedOption = nil
            }
            .disabled(selectedOption == nil)
            .opacity(selectedOption == nil ? 0.5 : 1)
            Text("Questions come from the real lesson quizzes for \(course.name).")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            let passed = session.correctCount >= FinalAssessmentStore.passCorrectCount
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    HStack(spacing: PFSpacing.lg) {
                        PFProgressRing(progress: session.scorePercent / 100, size: 110, color: passed ? .pfSuccess : .pfRoyal)
                        VStack(alignment: .leading, spacing: PFSpacing.sm) {
                            Text(passed ? "Passed" : "Not passed")
                                .font(.pfSectionTitle)
                                .foregroundColor(passed ? .pfSuccess : .pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(session.correctCount) of \(session.questions.count) correct")
                                .font(.pfSectionTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(Int(session.scorePercent.rounded()))% in \(course.name)")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Pass mark: more than 70%, at least \(FinalAssessmentStore.passCorrectCount) out of \(session.questions.count).")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Time used: \(AssessmentSession.format(seconds: session.elapsedSeconds))")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            if session.unansweredCount > 0 {
                                Text("\(session.unansweredCount) \(session.unansweredCount == 1 ? "question was" : "questions were") left unanswered.")
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            if passed, let certificate = earnedCertificate ?? existingCertificate {
                CourseCertificateCard(certificate: certificate)
                NavigationLink(destination: CourseCertificateView(certificate: certificate)) {
                    Text("View, share or save certificate")
                        .font(.pfBody.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.pfRoyal)
                        .cornerRadius(PFSpacing.cornerRadius)
                }
                .buttonStyle(.plain)
            } else if isLocked {
                lockedView
            } else {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("\(attemptsRemaining) \(attemptsRemaining == 1 ? "attempt" : "attempts") left")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text("Review your answers below, then retake the assessment. Questions and options are shuffled again, so the retake is different.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                PFPrimaryButton(title: "Retake Final Assessment") {
                    startExam(totalLimit: AssessmentSession.finalAssessmentTimeLimit)
                }
            }
            Text("Review")
                .font(.pfSectionTitle)
                .foregroundColor(.pfNavy)
            ForEach(session.questions) { question in
                let chosen = session.answers[question.id]
                let wasCorrect = chosen == question.correctOptionIndex
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        HStack(spacing: PFSpacing.sm) {
                            Image(systemName: chosen == nil ? "minus.circle.fill" : (wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"))
                                .foregroundColor(chosen == nil ? .pfSecondaryText : (wasCorrect ? .pfSuccess : .pfError))
                            Text(chosen == nil ? "Not answered" : (wasCorrect ? "Correct" : "Not correct"))
                                .font(.pfCaptionBold)
                                .foregroundColor(chosen == nil ? .pfSecondaryText : (wasCorrect ? .pfSuccess : .pfError))
                            Spacer()
                            Text(question.lessonTitle)
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                                .lineLimit(1)
                        }
                        // Review text cannot be selected or copied
                        // either, so questions cannot be lifted after
                        // the exam any more than during it.
                        Text(question.question)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.disabled)
                        Text("Correct answer: \(question.options[question.correctOptionIndex])")
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.disabled)
                        if let chosen, chosen != question.correctOptionIndex {
                            Text("Your answer: \(question.options[chosen])")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.disabled)
                        }
                        if let seconds = session.timeUsedPerQuestion[question.id] {
                            Text("Time on this question: \(seconds)s")
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                        }
                        Text(question.explanation)
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.disabled)
                        NavigationLink(destination: lessonDestination(for: question)) {
                            Text("Open the lesson: \(question.lessonTitle)")
                                .font(.pfBody.weight(.semibold))
                                .foregroundColor(.pfRoyal)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lessonDestination(for question: AssessmentQuestion) -> some View {
        if let entry = contentService.allLessons.first(where: { $0.id == question.lessonID }) {
            LessonView(entry: entry)
        } else {
            Text("That lesson is not in the loaded catalogue.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .padding()
        }
    }
}
