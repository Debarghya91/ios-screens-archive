// OnboardingFlowView.swift
// Payments Training Hub iOS - Optional first-time onboarding, in seven short
// steps: welcome, role, knowledge level, objective, intensity,
// an optional diagnostic check, and a summary with a recommended
// route. The flow saves the profile itself (or marks onboarding
// skipped) and then calls onFinish, so it can be presented as a
// fullScreenCover with no other dependencies: the only init
// argument is onFinish.
//
// Every step is skippable: a visible Skip sits at the top of every
// screen, and the welcome screen also has a full width skip button.
// Onboarding never forces sign-in and never gates browsing. The
// diagnostic step can be skipped on its own without skipping the
// rest of onboarding.
//
// Counts on the welcome screen come from ContentManifest only. The
// recommended route comes from OnboardingRecommendation, and the
// first lesson and lesson counts come from the live catalogue, so
// nothing is shown before it is known. The estimated commitment is
// computed honestly from the route lesson count and the chosen
// weekly target, in weeks at the chosen pace. No minutes per lesson
// are ever stated.
//
// The summary offers a free Payment Case to explore: the free
// sample situations in ContentService.freeSampleIDs are ungated.
// The recommended first lesson is the first lesson of its chapter,
// which the lesson screen opens free with full content (see
// LessonView: the first lesson of each chapter is never locked).
// The summary says so only when the catalogue confirms it, and the
// lesson screen itself explains locking for any other lesson.
// No em dashes in any user-facing text.

import SwiftUI

struct OnboardingFlowView: View {
    let onFinish: () -> Void

    @ObservedObject private var contentService = ContentService.shared
    @ObservedObject private var onboardingStore = OnboardingStore.shared
    @ObservedObject private var progressStore = ProgressStore.shared

    private enum Step: Int, CaseIterable {
        case welcome
        case role
        case knowledge
        case objective
        case intensity
        case diagnostic
        case summary
    }

    @State private var step: Step = .welcome
    @State private var selectedRole: LearnerRole? = nil
    @State private var selectedLevel: LearnerKnowledgeLevel? = nil
    @State private var selectedObjective: LearningObjective? = nil
    @State private var selectedIntensity: LearningIntensity? = nil
    @State private var diagnosticOutcome: DiagnosticOutcome? = nil

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerRow
                contentArea
                if step != .welcome {
                    backFooter
                }
            }
            .background(Color.pfBackground)
            .navigationTitle("Get started")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Chrome

    /// Step position plus the Skip control, visible on every step.
    private var headerRow: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            HStack {
                Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfSecondaryText)
                Spacer()
                Button("Skip") {
                    skipAll()
                }
                .font(.pfCallout).fontWeight(.semibold)
                .foregroundColor(.pfRoyal)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Skip onboarding")
            }
            PFProgressBar(progress: Double(step.rawValue + 1) / Double(Step.allCases.count), height: 6)
        }
        .padding(.horizontal, PFSpacing.lg)
        .padding(.top, PFSpacing.sm)
        .padding(.bottom, PFSpacing.md)
    }

    private var backFooter: some View {
        PFSecondaryButton(title: "Back") {
            goBack()
        }
        .accessibilityLabel("Back to the previous step")
        .padding(PFSpacing.lg)
    }

    @ViewBuilder
    private var contentArea: some View {
        if step == .diagnostic {
            DiagnosticAssessmentView { outcome in
                diagnosticOutcome = outcome
                step = .summary
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.lg) {
                    switch step {
                    case .welcome:
                        welcomeView
                    case .role:
                        roleView
                    case .knowledge:
                        knowledgeView
                    case .objective:
                        objectiveView
                    case .intensity:
                        intensityView
                    case .diagnostic:
                        EmptyView()
                    case .summary:
                        summaryView
                    }
                }
                .padding(PFSpacing.lg)
                .id("onboardingTop")
            }
            .pfScrollToTopOnAppear("onboardingTop", resetWhen: step.rawValue)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: PFSpacing.xl)
            }
        }
    }

    private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func goNext() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    /// Skip the whole flow: record the skip, change nothing else,
    /// and finish. The weekly goal is untouched by a skip.
    private func skipAll() {
        onboardingStore.markSkipped()
        onFinish()
    }

    /// Save the completed profile, write the chosen weekly target
    /// into ProgressStore.weeklyGoal (the single home of the weekly
    /// goal), and finish. The knowledge level is deliberately not
    /// written into LearningPreferences experienceLevel: that holds
    /// years of experience bands, a different concept.
    private func finish() {
        guard let role = selectedRole,
              let level = selectedLevel,
              let objective = selectedObjective,
              let intensity = selectedIntensity else { return }
        let profile = OnboardingProfile(
            role: role,
            knowledgeLevel: level,
            objective: objective,
            intensity: intensity,
            weeklyTarget: intensity.weeklyLessonTarget,
            diagnosticScore: diagnosticOutcome?.score,
            diagnosticTakenAt: diagnosticOutcome?.takenAt,
            completedAt: Date(),
            wasSkipped: false
        )
        onboardingStore.saveProfile(profile)
        progressStore.weeklyGoal = intensity.weeklyLessonTarget
        onFinish()
    }

    // MARK: - Step 1: welcome

    private var welcomeView: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            Text("Learn payments, properly.")
                .font(.pfScreenTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Text("Structured courses, real Payment Cases, and interview questions, in one place. This short setup picks a starting route for you. It takes about a minute, and you can skip it entirely and browse everything first.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            PFCard {
                VStack(spacing: PFSpacing.md) {
                    welcomeCountRow(value: ContentManifest.chapterCount, label: "chapters")
                    welcomeCountRow(value: ContentManifest.lessonCount, label: "lessons")
                    welcomeCountRow(value: ContentManifest.situationCount, label: "Payment Cases")
                    welcomeCountRow(value: ContentManifest.interviewQuestionCount, label: "interview questions")
                }
            }
            Text("No sign-in needed. Nothing here locks browsing: you can explore first and come back to a route later.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            PFPrimaryButton(title: "Continue") {
                goNext()
            }
            .accessibilityLabel("Continue with setup")
            PFSecondaryButton(title: "Skip for now") {
                skipAll()
            }
            .accessibilityLabel("Skip setup for now")
        }
    }

    private func welcomeCountRow(value: Int, label: String) -> some View {
        HStack(spacing: PFSpacing.sm) {
            Text("\(value)")
                .font(.pfSectionTitle)
                .foregroundColor(.pfNavy)
            Text(label)
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    // MARK: - Step 2: role

    private var roleView: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFSectionHeader(title: "What do you do?")
            Text("Pick the closest match. This only shapes your recommended route.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(LearnerRole.allCases, id: \.self) { role in
                OnboardingOptionRow(
                    title: role.displayTitle,
                    subtitle: role.displayDescription,
                    isSelected: selectedRole == role
                ) {
                    selectedRole = role
                }
            }
            PFPrimaryButton(title: "Continue", action: goNext, isEnabled: selectedRole != nil)
                .accessibilityLabel("Continue")
        }
    }

    // MARK: - Step 3: knowledge level

    private var knowledgeView: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFSectionHeader(title: "How much payments knowledge do you have?")
            Text("Your honest view of your own knowledge. This is not years of experience, and it does not change any experience setting.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(LearnerKnowledgeLevel.allCases, id: \.self) { level in
                OnboardingOptionRow(
                    title: level.displayTitle,
                    subtitle: knowledgeSubtitle(for: level),
                    isSelected: selectedLevel == level
                ) {
                    selectedLevel = level
                }
            }
            PFPrimaryButton(title: "Continue", action: goNext, isEnabled: selectedLevel != nil)
                .accessibilityLabel("Continue")
        }
    }

    private func knowledgeSubtitle(for level: LearnerKnowledgeLevel) -> String {
        switch level {
        case .beginner: return "You are new to payments, or still learning the basics."
        case .intermediate: return "You work with payments and know the main ideas."
        case .advanced: return "You work deeply in payments and want advanced topics."
        }
    }

    // MARK: - Step 4: objective

    private var objectiveView: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFSectionHeader(title: "What is your main goal?")
            Text("Pick one. You can still study anything else afterwards.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(LearningObjective.allCases, id: \.self) { objective in
                OnboardingOptionRow(
                    title: objective.displayTitle,
                    subtitle: objectiveSubtitle(for: objective),
                    isSelected: selectedObjective == objective
                ) {
                    selectedObjective = objective
                }
            }
            PFPrimaryButton(title: "Continue", action: goNext, isEnabled: selectedObjective != nil)
                .accessibilityLabel("Continue")
        }
    }

    private func objectiveSubtitle(for objective: LearningObjective) -> String {
        switch objective {
        case .buildFoundations: return "Learn how payments work from the ground up."
        case .prepareForInterviews: return "Practise the topics interviewers ask about."
        case .doTheJobBetter: return "Strengthen the payments work you already do."
        case .specialise: return "Go deep in one area of payments."
        case .leadAndDesign: return "Design payments work and lead others doing it."
        }
    }

    // MARK: - Step 5: intensity

    private var intensityView: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFSectionHeader(title: "How much time each week?")
            Text("Your weekly lesson target. It becomes your weekly goal, shown on Home and in Learning Preferences.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(LearningIntensity.allCases, id: \.self) { intensity in
                OnboardingOptionRow(
                    title: intensity.displayTitle,
                    subtitle: "\(intensity.weeklyLessonTarget) lessons a week. \(intensityPace(for: intensity))",
                    isSelected: selectedIntensity == intensity
                ) {
                    selectedIntensity = intensity
                }
            }
            PFPrimaryButton(title: "Continue", action: goNext, isEnabled: selectedIntensity != nil)
                .accessibilityLabel("Continue")
        }
    }

    private func intensityPace(for intensity: LearningIntensity) -> String {
        switch intensity {
        case .light: return "A gentle pace."
        case .steady: return "Steady progress."
        case .intensive: return "A lesson a day."
        }
    }

    // MARK: - Step 7: summary

    private var recommendedPath: LearningPath? {
        guard let role = selectedRole,
              let level = selectedLevel,
              let objective = selectedObjective else { return nil }
        return OnboardingRecommendation.path(for: role, objective: objective, knowledgeLevel: level)
    }

    /// The route's lessons, in catalogue order. Empty while the
    /// catalogue is still loading.
    private var routeLessons: [SearchEntry] {
        guard let path = recommendedPath else { return [] }
        return path.lessons(in: contentService)
    }

    private var firstLesson: SearchEntry? {
        routeLessons.first
    }

    /// The first free Payment Case, resolved from the live catalogue.
    /// Nil while the catalogue is still loading.
    private var freeCase: Situation? {
        guard let id = ContentService.freeSampleIDs.first else { return nil }
        return pfSituation(id: id, in: contentService)
    }

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFSectionHeader(title: "Your starting route")
            Text("A recommendation, not a lock. You can follow any route, and browse everything, from here.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    summaryRow(label: "Recommended route", value: recommendedPath?.title ?? "Not chosen yet")
                    summaryRow(label: "First lesson", value: firstLessonText)
                    summaryRow(label: "Your objective", value: selectedObjective?.displayTitle ?? "Not chosen yet")
                    summaryRow(label: "Weekly target", value: weeklyTargetText)
                    summaryRow(label: "Estimated commitment", value: commitmentText)
                    summaryRow(label: "Starting point", value: startingPointText)
                    summaryRow(label: "Quick check", value: diagnosticSummaryText)
                }
            }
            freeCaseCard
            firstLessonCard
            PFPrimaryButton(title: "Get started", action: finish, isEnabled: canFinish)
                .accessibilityLabel("Get started")
            Text("Choosing Get started saves these choices on this device. Skipping saves nothing.")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var canFinish: Bool {
        selectedRole != nil && selectedLevel != nil && selectedObjective != nil && selectedIntensity != nil
    }

    private func summaryRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.xs) {
            Text(label)
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
            Text(value)
                .font(.pfBody)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var firstLessonText: String {
        if let firstLesson {
            return firstLesson.title
        }
        if contentService.searchIndex == nil {
            return "The course list is still loading, so the first lesson title is not known yet."
        }
        return "No lessons were found for this route yet."
    }

    private var weeklyTargetText: String {
        guard let intensity = selectedIntensity else { return "Not chosen yet" }
        return "\(intensity.weeklyLessonTarget) lessons a week (\(intensity.displayTitle.lowercased()) pace)"
    }

    /// Weeks at the chosen pace, from the real route lesson count.
    /// No minutes per lesson are ever stated: the estimate is weeks
    /// only, rounded up.
    private var commitmentText: String {
        guard let target = selectedIntensity?.weeklyLessonTarget, target > 0 else {
            return "Choose a weekly pace to see an estimate."
        }
        if contentService.searchIndex == nil {
            return "The course list is still loading, so the route length is not known yet."
        }
        let total = routeLessons.count
        guard total > 0 else {
            return "No lessons were found for this route yet."
        }
        let weeks = Int(ceil(Double(total) / Double(target)))
        if weeks == 1 {
            return "About 1 week at \(target) lessons a week (\(total) lessons)."
        }
        return "About \(weeks) weeks at \(target) lessons a week (\(total) lessons)."
    }

    private var startingPointText: String {
        if contentService.searchIndex == nil {
            let done = progressStore.totalLessonsCompleted
            if done == 0 {
                return "Starting fresh: no lessons completed yet."
            }
            return "You have already completed \(done) \(done == 1 ? "lesson" : "lessons")."
        }
        let total = routeLessons.count
        guard total > 0 else {
            let done = progressStore.totalLessonsCompleted
            if done == 0 {
                return "Starting fresh: no lessons completed yet."
            }
            return "You have already completed \(done) \(done == 1 ? "lesson" : "lessons")."
        }
        let done = routeLessons.filter { progressStore.isLessonComplete($0.id) }.count
        if done == 0 {
            return "Starting fresh in this route: no lessons completed yet."
        }
        return "\(done) of \(total) lessons in this route already complete."
    }

    private var diagnosticSummaryText: String {
        guard let outcome = diagnosticOutcome else {
            return "Skipped. You can take assessments later from the Assessments section in My Progress."
        }
        if outcome.isSelfAssessment {
            return "Self-assessment: average confidence \(Int((outcome.score * 100).rounded()))%. Your own rating, not a test score."
        }
        return "Quiz: \(Int((outcome.score * 100).rounded()))% across \(outcome.questionCount) real quiz \(outcome.questionCount == 1 ? "question" : "questions")."
    }

    // MARK: - Free value steps

    /// The free Payment Case step: free sample situations are
    /// ungated, so this always opens real content for free once the
    /// catalogue has loaded. While it loads, the card says so
    /// honestly instead of offering a case that is not there yet.
    @ViewBuilder
    private var freeCaseCard: some View {
        if let freeCase {
            NavigationLink(destination: SituationDetailView(situation: freeCase)) {
                PFCard {
                    HStack(spacing: PFSpacing.md) {
                        PFIconTile(systemImage: "briefcase.fill", size: 44)
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text("Explore a free Payment Case")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(freeCase.title). Free to open, no purchase needed. There are \(ContentService.freeSampleIDs.count) free cases in total.")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.pfSecondaryText)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Explore a free Payment Case: \(freeCase.title)")
        } else {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text("Explore a free Payment Case")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    Text("The free cases will appear here once the course list has loaded. There are \(ContentService.freeSampleIDs.count) free cases, and they stay free without a purchase.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityLabel("Free Payment Cases will appear once the course list has loaded.")
        }
    }

    /// The recommended first lesson. The first lesson of a chapter
    /// opens free with full content, and the card says so only when
    /// the catalogue confirms this lesson is that first lesson. Any
    /// other lesson opens on the lesson screen, which explains what
    /// unlocks it when it is locked.
    @ViewBuilder
    private var firstLessonCard: some View {
        if let firstLesson {
            let isSample = PFChapterHelper.isSampleLesson(firstLesson, in: contentService)
            NavigationLink(destination: LessonView(entry: firstLesson)) {
                PFCard {
                    HStack(spacing: PFSpacing.md) {
                        PFIconTile(systemImage: "play.fill", size: 44)
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text("Start with the first lesson")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(isSample
                                ? "\(firstLesson.title). Free sample lesson: this lesson opens free, with the full content. The rest of its chapter unlocks with the course."
                                : "\(firstLesson.title). The lesson screen explains what unlocks it if it is locked.")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.pfSecondaryText)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start with the first lesson: \(firstLesson.title)")
        }
    }
}

// MARK: - Option row

/// One selectable option: a checkmark plus the option text when
/// selected, so selection is never shown by colour alone.
private struct OnboardingOptionRow: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: PFSpacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .pfRoyal : .pfSecondaryText)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(title)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
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
        .accessibilityLabel(title + (subtitle.map { ", \($0)" } ?? "") + (isSelected ? ", selected" : ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
