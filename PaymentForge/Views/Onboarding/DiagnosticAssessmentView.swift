// DiagnosticAssessmentView.swift
// PaymentForge iOS - The optional onboarding diagnostic: a short
// check of about 3 minutes, drawn only from real lesson quiz
// questions. No question, option or correct answer is ever
// invented: questions are loaded with ContentService.loadLessonDetail
// from the first lessons of early chapters, following the
// AssessmentView pattern, and lessons with no quiz are skipped.
//
// When no real questions load (the catalogue is still loading, the
// lesson pages fail, or the lessons have no quiz), the view offers
// a confidence self-assessment instead, plainly labelled as a
// self-assessment and never presented as a test score. The result
// is returned to the caller and stored in the onboarding profile
// only. It is never written into CompetencyStore, whose
// recordAssessment is for dimension assessments, and never into
// ProgressStore quiz history.
//
// There is no timer and no pass mark: the 3 minutes is a guide, and
// nobody fails on time. Skipping leaves the diagnostic score nil
// and does not block completing onboarding.
// No em dashes in any user-facing text.

import SwiftUI

/// The outcome of one diagnostic run, returned to the onboarding
/// flow. score is a fraction from 0 to 1: the fraction correct in
/// quiz mode, or the average confidence in self-assessment mode.
/// questionCount is the number of quiz questions answered, and 0 in
/// self-assessment mode. takenAt is when the run finished.
struct DiagnosticOutcome: Hashable {
    let score: Double
    let takenAt: Date
    let isSelfAssessment: Bool
    let questionCount: Int

    /// Quiz score as a fraction correct, nil when there were no
    /// questions. A score is never computed from zero questions.
    static func quizScore(correct: Int, total: Int) -> Double? {
        guard total > 0, correct >= 0, correct <= total else { return nil }
        return Double(correct) / Double(total)
    }

    /// Self-assessment score from confidence ratings of 1 to 5, one
    /// per competency dimension. Each rating maps to a fraction:
    /// 1 is 0, 2 is 0.25, 3 is 0.5, 4 is 0.75 and 5 is 1. The result
    /// is the average across the ratings given. Nil when no rating
    /// was given, or when any rating is outside 1 to 5.
    static func selfAssessmentScore(ratings: [Int]) -> Double? {
        guard !ratings.isEmpty else { return nil }
        guard ratings.allSatisfy({ (1...5).contains($0) }) else { return nil }
        let fractions = ratings.map { Double($0 - 1) / 4.0 }
        return fractions.reduce(0, +) / Double(fractions.count)
    }
}

struct DiagnosticAssessmentView: View {
    /// Called once when the diagnostic ends. A non-nil outcome
    /// carries the score; nil means the learner skipped the check.
    let onComplete: (DiagnosticOutcome?) -> Void

    @ObservedObject private var contentService = ContentService.shared

    private enum Phase {
        case loading
        case quiz
        case selfAssessment
        case result
    }

    /// Early chapters whose first lessons supply the diagnostic
    /// questions, in order. Only real quiz questions from these
    /// lessons are used, up to 6, trying at most 12 lessons.
    private static let sourceChapterNumbers = [69, 1, 4, 2, 3]
    private static let maxQuestions = 6
    private static let maxLessonsTried = 12

    /// Confidence labels for ratings 1 to 5, in order.
    private static let confidenceLabels = [
        "Not confident",
        "A little confident",
        "Fairly confident",
        "Confident",
        "Very confident"
    ]

    @State private var phase: Phase = .loading
    @State private var questions: [AssessmentQuestion] = []
    @State private var loadAttempted = false
    @State private var currentIndex = 0
    @State private var selectedOption: Int? = nil
    @State private var answers: [String: Int] = [:]
    @State private var confidence: [CompetencyStore.CompetencyDimension: Int] = [:]
    @State private var result: DiagnosticOutcome? = nil

    init(onComplete: @escaping (DiagnosticOutcome?) -> Void) {
        self.onComplete = onComplete
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                introCard
                switch phase {
                case .loading:
                    loadingView
                case .quiz:
                    quizView
                case .selfAssessment:
                    selfAssessmentView
                case .result:
                    resultView
                }
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .task {
            await loadQuestions()
        }
        .onChange(of: contentService.searchIndex == nil) { _, catalogueMissing in
            if !catalogueMissing, phase == .loading, questions.isEmpty {
                loadAttempted = false
                Task { await loadQuestions() }
            }
        }
    }

    // MARK: - Intro

    private var introCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("Quick check: about 3 minutes")
                    .font(.pfSectionTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Up to \(Self.maxQuestions) questions from real lesson quizzes. There is no timer and no pass mark. This only sets your starting point, and you can skip it.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFCard {
                HStack(spacing: PFSpacing.sm) {
                    ProgressView()
                    Text(contentService.searchIndex == nil
                        ? "Loading the course list, then the quiz questions..."
                        : "Loading real quiz questions...")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(contentService.searchIndex == nil
                    ? "Loading the course list, then the quiz questions."
                    : "Loading real quiz questions.")
            }
            PFSecondaryButton(title: "Try again") {
                loadAttempted = false
                Task { await loadQuestions() }
            }
            .accessibilityLabel("Try loading the quiz questions again")
            PFSecondaryButton(title: "Skip this check") {
                onComplete(nil)
            }
            .accessibilityLabel("Skip this check")
        }
    }

    // MARK: - Loading real questions

    /// Fetch lesson details in catalogue order until the question
    /// cap is reached. A lesson whose page fails to load, or which
    /// has no quiz, contributes nothing and is skipped, never
    /// invented. A question with an unusable option list or an
    /// out-of-range correct index is dropped, never guessed.
    private func loadQuestions() async {
        guard !loadAttempted else { return }
        loadAttempted = true
        phase = .loading
        var collected: [AssessmentQuestion] = []
        var tried = 0
        outer: for number in Self.sourceChapterNumbers {
            for entry in PFChapterHelper.lessons(forChapter: number, in: contentService) {
                if collected.count >= Self.maxQuestions || tried >= Self.maxLessonsTried { break outer }
                tried += 1
                guard let detail = try? await contentService.loadLessonDetail(entry: entry) else { continue }
                for quiz in detail.quiz {
                    if collected.count >= Self.maxQuestions { break }
                    guard quiz.options.count > 1,
                          quiz.correctOptionIndex >= 0,
                          quiz.correctOptionIndex < quiz.options.count else { continue }
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
        questions = collected
        if collected.isEmpty, contentService.searchIndex == nil {
            phase = .loading
        } else if collected.isEmpty {
            phase = .selfAssessment
        } else {
            currentIndex = 0
            selectedOption = nil
            answers = [:]
            phase = .quiz
        }
    }

    // MARK: - Quiz

    private var quizView: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    HStack(spacing: PFSpacing.sm) {
                        PFPill(text: "Real lesson quiz")
                        Spacer()
                        Text("Question \(currentIndex + 1) of \(questions.count)")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                    }
                    PFProgressBar(progress: Double(currentIndex) / Double(max(questions.count, 1)), height: 6)
                    if let question = currentQuestion {
                        Text(question.question)
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                            DiagnosticOptionRow(
                                text: option,
                                isSelected: selectedOption == index
                            ) {
                                selectedOption = index
                            }
                        }
                        Text("From the lesson: \(question.lessonTitle)")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            PFPrimaryButton(
                title: currentIndex == questions.count - 1 ? "See my starting point" : "Next question",
                action: answerAndAdvance,
                isEnabled: selectedOption != nil
            )
            .accessibilityLabel(currentIndex == questions.count - 1 ? "See my starting point" : "Next question")
            PFSecondaryButton(title: "Skip this check") {
                onComplete(nil)
            }
            .accessibilityLabel("Skip this check")
        }
    }

    private var currentQuestion: AssessmentQuestion? {
        guard questions.indices.contains(currentIndex) else { return nil }
        return questions[currentIndex]
    }

    private func answerAndAdvance() {
        guard let question = currentQuestion, let selectedOption else { return }
        answers[question.id] = selectedOption
        self.selectedOption = nil
        if currentIndex == questions.count - 1 {
            finishQuiz()
        } else {
            currentIndex += 1
        }
    }

    private func finishQuiz() {
        let correct = questions.filter { answers[$0.id] == $0.correctOptionIndex }.count
        guard let score = DiagnosticOutcome.quizScore(correct: correct, total: questions.count) else {
            onComplete(nil)
            return
        }
        result = DiagnosticOutcome(
            score: score,
            takenAt: Date(),
            isSelfAssessment: false,
            questionCount: questions.count
        )
        phase = .result
    }

    // MARK: - Self-assessment fallback

    private var selfAssessmentView: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text("Self-assessment, not a test")
                        .font(.pfSectionTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("No quiz questions could be loaded, so there is no test to take. Rate how confident you feel in each area instead. Your ratings are your own view, not a test score.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(CompetencyStore.CompetencyDimension.allCases, id: \.self) { dimension in
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text(dimension.rawValue)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: PFSpacing.sm) {
                            ForEach(1...5, id: \.self) { rating in
                                let isSelected = confidence[dimension] == rating
                                Button {
                                    confidence[dimension] = rating
                                } label: {
                                    Text("\(rating)")
                                        .font(.pfCardTitle)
                                        .foregroundColor(isSelected ? .white : .pfNavy)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .background(isSelected ? Color.pfRoyal : Color.pfCard)
                                        .cornerRadius(PFSpacing.cornerRadius)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                                                .stroke(isSelected ? Color.pfRoyal : Color.pfBorder, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(dimension.rawValue): \(rating), \(Self.confidenceLabels[rating - 1])")
                                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
                            }
                        }
                        if let rating = confidence[dimension] {
                            Text(Self.confidenceLabels[rating - 1])
                                .font(.pfBody)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("Selected: \(Self.confidenceLabels[rating - 1])")
                        } else {
                            Text("Not rated yet")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                        }
                    }
                }
            }
            PFPrimaryButton(
                title: "See my starting point",
                action: finishSelfAssessment,
                isEnabled: allDimensionsRated
            )
            .accessibilityLabel("See my starting point")
            PFSecondaryButton(title: "Skip this check") {
                onComplete(nil)
            }
            .accessibilityLabel("Skip this check")
        }
    }

    private var allDimensionsRated: Bool {
        CompetencyStore.CompetencyDimension.allCases.allSatisfy { confidence[$0] != nil }
    }

    private func finishSelfAssessment() {
        let ratings = CompetencyStore.CompetencyDimension.allCases.compactMap { confidence[$0] }
        guard let score = DiagnosticOutcome.selfAssessmentScore(ratings: ratings) else { return }
        result = DiagnosticOutcome(
            score: score,
            takenAt: Date(),
            isSelfAssessment: true,
            questionCount: 0
        )
        phase = .result
    }

    // MARK: - Result

    private var resultView: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    HStack(spacing: PFSpacing.lg) {
                        PFProgressRing(progress: result?.score ?? 0, size: 110, color: .pfRoyal)
                        VStack(alignment: .leading, spacing: PFSpacing.sm) {
                            Text(resultTitle)
                                .font(.pfSectionTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(resultDetail)
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("This is a starting point, not a grade. It only helps place you, and it is stored in your onboarding profile.")
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if result?.isSelfAssessment == false {
                Text("Review")
                    .font(.pfSectionTitle)
                    .foregroundColor(.pfNavy)
                ForEach(questions) { question in
                    let chosen = answers[question.id]
                    let wasCorrect = chosen == question.correctOptionIndex
                    PFCard {
                        VStack(alignment: .leading, spacing: PFSpacing.sm) {
                            HStack(spacing: PFSpacing.sm) {
                                Image(systemName: wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(wasCorrect ? .pfSuccess : .pfError)
                                    .accessibilityHidden(true)
                                Text(wasCorrect ? "Correct" : "Not correct")
                                    .font(.pfCaptionBold)
                                    .foregroundColor(wasCorrect ? .pfSuccess : .pfError)
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
                            PFBodyText(text: question.explanation, textColor: .pfSecondaryText)
                        }
                    }
                }
                PFSecondaryButton(title: "Retake the check") {
                    answers = [:]
                    selectedOption = nil
                    currentIndex = 0
                    result = nil
                    phase = .quiz
                }
                .accessibilityLabel("Retake the check")
            }
            PFPrimaryButton(title: "Continue") {
                onComplete(result)
            }
            .accessibilityLabel("Continue")
        }
    }

    private var resultTitle: String {
        guard let result else { return "Your starting point" }
        if result.isSelfAssessment {
            return "Average confidence: \(Int((result.score * 100).rounded()))%"
        }
        let correct = questions.filter { answers[$0.id] == $0.correctOptionIndex }.count
        return "\(correct) of \(questions.count) correct"
    }

    private var resultDetail: String {
        guard let result else { return "" }
        if result.isSelfAssessment {
            return "This is your own confidence rating, not a test score."
        }
        return "\(Int((result.score * 100).rounded()))% across \(result.questionCount) real quiz \(result.questionCount == 1 ? "question" : "questions")."
    }
}

// MARK: - Option row

/// One quiz option: a checkmark plus the option text when selected,
/// so selection is never shown by colour alone.
private struct DiagnosticOptionRow: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: PFSpacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .pfRoyal : .pfSecondaryText)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.pfBody)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(PFSpacing.md)
            .frame(minHeight: 44)
            .background(isSelected ? Color.pfRoyal.opacity(0.08) : Color.pfCard)
            .cornerRadius(PFSpacing.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                    .stroke(isSelected ? Color.pfRoyal : Color.pfBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text + (isSelected ? ", selected" : ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
