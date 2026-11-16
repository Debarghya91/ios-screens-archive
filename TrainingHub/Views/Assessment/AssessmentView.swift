// AssessmentView.swift
// Payments Training Hub iOS - Short assessments drawn from real lesson quizzes.
// Each assessment is 5 questions taken from the real quiz questions of
// lessons in the dimension's chapters (or the path's chapters). The
// explanation shown is the real quiz explanation when the lesson page
// supplies one, otherwise a note pointing to the lesson. The result is
// recorded in CompetencyStore only; no score is shown that was not earned.
// Two modes, both optional, are offered on the setup screen:
// - Timed mode: 60 seconds per question, with a total time limit for
//   the session. When a question's time expires the session moves on
//   and the question is marked unanswered, never guessed.
// - Randomised mode: questions and options are shuffled with a fresh
//   seed per session, so a retake is different; the correct answer is
//   tracked by content, never by position.
// The timer lives in AssessmentSession and is stopped when this view
// disappears, so no timer can leak. If fewer than 5 real questions are
// found, the setup screen says so instead of inventing questions.
// No em dashes in any user-facing text.

import SwiftUI

struct AssessmentView: View {
    @EnvironmentObject private var contentService: ContentService
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var competencyStore = CompetencyStore.shared
    @StateObject private var session: AssessmentSession

    let dimension: CompetencyStore.CompetencyDimension
    let chapterNumbers: [Int]
    let sourceTitle: String

    /// The holder key for this assessment: one live session per
    /// dimension and chapter set, so a popped attempt resumes.
    private var sessionKey: String {
        "assessment:\(dimension.rawValue):\(chapterNumbers.map(String.init).joined(separator: ","))"
    }

    /// Assessment for one competency dimension.
    init(dimension: CompetencyStore.CompetencyDimension) {
        self.dimension = dimension
        self.chapterNumbers = dimension.chapterNumbers
        self.sourceTitle = dimension.rawValue
        _session = StateObject(wrappedValue: AssessmentSessionHolder.shared.session(for: "assessment:\(dimension.rawValue):\(dimension.chapterNumbers.map(String.init).joined(separator: ","))"))
    }

    /// Assessment for one learning path, scored against the path's
    /// dimension and drawn from the path's own lessons.
    init(path: LearningPath) {
        self.dimension = path.assessmentDimension
        self.chapterNumbers = path.chapterNumbers
        self.sourceTitle = path.title
        _session = StateObject(wrappedValue: AssessmentSessionHolder.shared.session(for: "assessment:\(path.assessmentDimension.rawValue):\(path.chapterNumbers.map(String.init).joined(separator: ","))"))
    }

    @State private var loadedQuestions: [AssessmentQuestion] = []
    @State private var isLoading = true
    @State private var loadError: String? = nil
    @State private var selectedOption: Int? = nil
    @State private var timedMode = false
    @State private var randomisedMode = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                if isLoading {
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
                            Text("Could not load the assessment")
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
                } else if loadedQuestions.isEmpty {
                    PFCard {
                        Text("No quiz questions were found in these lessons yet. The lesson pages may still be loading, or these lessons have no quiz on the site.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if !session.isStarted {
                    setupView
                } else {
                    questionView
                }
            }
            .padding(PFSpacing.lg)
            .id("assessmentTop")
        }
        .pfScrollToTopOnAppear("assessmentTop", resetWhen: (session.currentIndex, session.isFinished))
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle("Assessment")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadQuestions()
        }
        .onAppear {
            // Resume a paused attempt: the timer restarts with the
            // remaining time recomputed from the wall clock.
            session.resumeTimer()
        }
        .onDisappear {
            session.pauseTimer()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                session.resumeTimer()
            } else if newPhase == .background {
                session.pauseTimer()
            }
        }
        .onChange(of: session.isFinished) { _, finished in
            if finished, !AssessmentSessionHolder.shared.resultRecorded(for: sessionKey) {
                AssessmentSessionHolder.shared.markResultRecorded(for: sessionKey)
                competencyStore.recordAssessment(
                    dimension: dimension,
                    correct: session.correctCount,
                    total: session.questions.count
                )
                // Analytics, consent-gated by the service: the
                // completion plus an improvement check for this
                // dimension. No question or answer text is sent.
                AnalyticsService.shared.recordAssessmentCompleted(
                    dimension: dimension.rawValue,
                    correct: session.correctCount,
                    total: session.questions.count,
                    elapsedSeconds: session.elapsedSeconds,
                    unansweredCount: session.unansweredCount
                )
            }
        }
    }

    // MARK: - Loading real questions

    /// Fetch lesson details in catalogue order until 5 real quiz
    /// questions are collected, trying at most 12 lessons. A lesson
    /// whose page fails to load is skipped, never invented.
    private func loadQuestions() async {
        guard loadedQuestions.isEmpty else { return }
        isLoading = true
        loadError = nil
        var collected: [AssessmentQuestion] = []
        var tried = 0
        outer: for number in chapterNumbers {
            for entry in PFChapterHelper.lessons(forChapter: number, in: contentService) {
                if collected.count >= 5 || tried >= 12 { break outer }
                tried += 1
                guard let detail = try? await contentService.loadLessonDetail(entry: entry) else { continue }
                for quiz in detail.quiz {
                    if collected.count >= 5 { break }
                    collected.append(AssessmentQuestion(
                        id: quiz.id,
                        lessonID: entry.id,
                        lessonTitle: entry.title,
                        question: quiz.question,
                        options: quiz.options,
                        correctOptionIndex: quiz.correctOptionIndex,
                        explanation: quiz.explanation
                    ))
                }
            }
        }
        if collected.isEmpty && contentService.searchIndex == nil {
            loadError = "The course catalogue has not loaded yet. Check your connection and try again."
            // Analytics, consent-gated by the service: the
            // assessment could not load because the catalogue
            // has not loaded. No content is sent.
            AnalyticsService.shared.recordContentLoadFailed(kind: "assessmentQuestions", failureCategory: "catalogueNotLoaded")
        }
        loadedQuestions = collected
        isLoading = false
    }

    // MARK: - Setup

    private var setupView: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    HStack(spacing: PFSpacing.sm) {
                        PFPill(text: dimension.rawValue)
                        Spacer()
                        Text("\(loadedQuestions.count) \(loadedQuestions.count == 1 ? "question" : "questions")")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                    }
                    Text("Assessment for \(sourceTitle)")
                        .font(.pfSectionTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Questions come from the real lesson quizzes for \(sourceTitle).")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if loadedQuestions.count < 5 {
                        Text("Only \(loadedQuestions.count) real quiz \(loadedQuestions.count == 1 ? "question was" : "questions were") found in these lessons, so the assessment uses \(loadedQuestions.count == 1 ? "that one" : "those \(loadedQuestions.count)"). No questions were invented to reach 5.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Toggle("Timed mode", isOn: $timedMode)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    Text("60 seconds per question, with a total limit of \(AssessmentSession.format(seconds: AssessmentSession.secondsPerQuestion * max(loadedQuestions.count, 1))) for the session. When time runs out on a question it is marked unanswered, never guessed.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    Toggle("Randomise questions and options", isOn: $randomisedMode)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    Text("Questions and options are shuffled with a fresh seed each session, so a retake is different. The correct answer is tracked by content, never by position.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            PFPrimaryButton(title: "Start assessment") {
                AssessmentSessionHolder.shared.clearResultRecorded(for: sessionKey)
                selectedOption = nil
                session.start(questions: loadedQuestions, timed: timedMode, randomised: randomisedMode)
                // Analytics, consent-gated by the service.
                AnalyticsService.shared.recordAssessmentStarted(
                    dimension: dimension.rawValue,
                    questionCount: loadedQuestions.count,
                    timed: timedMode,
                    randomised: randomisedMode
                )
            }
        }
    }

    // MARK: - Question

    private var questionView: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    HStack(spacing: PFSpacing.sm) {
                        PFPill(text: dimension.rawValue)
                        Spacer()
                        Text("Question \(session.currentIndex + 1) of \(session.questions.count)")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                    }
                    PFProgressBar(progress: Double(session.currentIndex) / Double(max(session.questions.count, 1)), height: 6)
                    if session.isTimed {
                        HStack(spacing: PFSpacing.sm) {
                            Image(systemName: "timer")
                                .foregroundColor(session.secondsLeftForQuestion <= 10 ? .pfError : .pfRoyal)
                            Text("\(session.secondsLeftForQuestion)s left on this question")
                                .font(.pfCaptionBold)
                                .foregroundColor(session.secondsLeftForQuestion <= 10 ? .pfError : .pfNavy)
                            Spacer()
                            Text("Total \(AssessmentSession.format(seconds: session.totalSecondsLeft)) left")
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfSecondaryText)
                        }
                        PFProgressBar(progress: Double(session.secondsLeftForQuestion) / Double(AssessmentSession.secondsPerQuestion), height: 6)
                    }
                    if let question = session.currentQuestion {
                        Text(question.question)
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
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
            Text("Questions come from the real lesson quizzes for \(sourceTitle).")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    HStack(spacing: PFSpacing.lg) {
                        PFProgressRing(progress: session.scorePercent / 100, size: 110, color: .pfRoyal)
                        VStack(alignment: .leading, spacing: PFSpacing.sm) {
                            Text("\(session.correctCount) of \(session.questions.count) correct")
                                .font(.pfSectionTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(Int(session.scorePercent.rounded()))% in \(dimension.rawValue)")
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
                            Text("Recorded in your competency profile.")
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
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
                        Text(question.question)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Correct answer: \(question.options[question.correctOptionIndex])")
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        if let chosen, chosen != question.correctOptionIndex {
                            Text("Your answer: \(question.options[chosen])")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let seconds = session.timeUsedPerQuestion[question.id] {
                            Text("Time on this question: \(seconds)s")
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                        }
                        PFBodyText(text: question.explanation, textColor: .pfSecondaryText)
                        NavigationLink(destination: lessonDestination(for: question)) {
                            Text("Open the lesson: \(question.lessonTitle)")
                                .font(.pfBody.weight(.semibold))
                                .foregroundColor(.pfRoyal)
                        }
                    }
                }
            }
            PFPrimaryButton(title: "Retake assessment") {
                AssessmentSessionHolder.shared.clearResultRecorded(for: sessionKey)
                selectedOption = nil
                session.start(questions: loadedQuestions, timed: timedMode, randomised: randomisedMode)
                // Analytics, consent-gated by the service: a retake
                // is a fresh start for funnel purposes.
                AnalyticsService.shared.recordAssessmentStarted(
                    dimension: dimension.rawValue,
                    questionCount: loadedQuestions.count,
                    timed: timedMode,
                    randomised: randomisedMode
                )
            }
            PFSecondaryButton(title: "Change options") {
                session.resetToSetup()
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
