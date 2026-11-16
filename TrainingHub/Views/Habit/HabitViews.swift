// HabitViews.swift
// Payments Training Hub iOS - Learning habit cards for Home.
//
// One section, "Your learning habit", sitting between progress and
// Explore: today's small goal, the weekly target with a neutrally
// worded streak, the question of the day, the weekly investigation
// challenge entry, revision reminders, weak-area recommendations
// and honest milestones. Every card reads recorded progress and
// real catalogue content; nothing is invented, and no card changes
// gating, purchase or entitlement behaviour. Destinations keep
// their own lock handling: tapping a locked lesson opens the
// lesson screen, which handles the lock itself, exactly as the
// other Home cards do. The first lesson of each chapter is free;
// no copy here claims otherwise.
// No em dashes in any user-facing text.

import SwiftUI

// MARK: - Habit section

/// The habit section for Home. Each card reads its own stores, so
/// this view only stacks them. The weak-area card is included only
/// when the engine returns weak-area evidence, so a learner with
/// no evidence sees no empty weak-area card.
struct HabitSectionView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @ObservedObject private var onboardingStore = OnboardingStore.shared
    @ObservedObject private var competencyStore = CompetencyStore.shared

    /// The onboarding profile when the learner chose it. A skipped
    /// profile is treated as no profile, matching HomeView.
    private var effectiveProfile: OnboardingProfile? {
        guard let profile = onboardingStore.profile, !profile.wasSkipped else { return nil }
        return profile
    }

    /// Weak-area picks from the engine, at most two. Empty when no
    /// weak-area evidence exists.
    private var weakAreaPicks: [LessonRecommendation] {
        LearningHabitPlanner.weakAreaRecommendations(
            for: effectiveProfile,
            progress: progressStore,
            competency: competencyStore,
            service: contentService,
            limit: 2
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Your learning habit")
            DailyObjectiveHabitCard()
            WeeklyTargetHabitCard()
            DailyQuestionHabitCard()
            WeeklyChallengeHabitCard()
            RevisionHabitCard()
            if !weakAreaPicks.isEmpty {
                WeakAreaHabitCard(picks: weakAreaPicks)
            }
            MilestonesHabitCard()
        }
    }
}

// MARK: - Daily objective

/// Today's small goal: the engine's next lesson with its reason.
/// Done means the lesson was finished today. When the catalogue
/// has not loaded yet the card says so; when every lesson is
/// complete it says that instead of pointing at a finished lesson.
private struct DailyObjectiveHabitCard: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @ObservedObject private var onboardingStore = OnboardingStore.shared
    @ObservedObject private var competencyStore = CompetencyStore.shared

    private var effectiveProfile: OnboardingProfile? {
        guard let profile = onboardingStore.profile, !profile.wasSkipped else { return nil }
        return profile
    }

    private var objective: DailyLearningObjective? {
        LearningHabitPlanner.dailyObjective(
            for: effectiveProfile,
            progress: progressStore,
            competency: competencyStore,
            service: contentService
        )
    }

    private var catalogueLoading: Bool {
        contentService.searchIndex == nil && contentService.allLessons.isEmpty
    }

    private var everyLessonComplete: Bool {
        let lessons = contentService.allLessons
        return !lessons.isEmpty && lessons.allSatisfy { progressStore.isLessonComplete($0.id) }
    }

    var body: some View {
        if let objective {
            NavigationLink(destination: LessonView(entry: objective.lesson)) {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        HStack(spacing: PFSpacing.sm) {
                            Text("Today's small goal")
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfRoyal)
                            Spacer()
                            if objective.isComplete {
                                PFPill(
                                    text: "Finished today",
                                    background: Color.pfSuccess.opacity(0.12),
                                    foreground: .pfSuccess
                                )
                            }
                        }
                        Text(objective.lesson.title)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(PFChapterHelper.chapterTitle(for: objective.lesson))
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let duration = LessonDurations.listenLabel(for: objective.lesson.id) {
                            Text(duration)
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                        }
                        Text(objective.reason)
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(objective.isComplete ? "Review it again" : "Open this lesson")
                            .font(.pfBody.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.pfRoyal)
                            .cornerRadius(PFSpacing.cornerRadius)
                    }
                }
            }
            .buttonStyle(PFCardButtonStyle())
            .accessibilityLabel("Today's small goal: \(objective.lesson.title)")
            .accessibilityHint("Opens the lesson")
        } else if catalogueLoading {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text("Today's small goal")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                    Text("Your daily goal will appear here once the catalogue loads.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if everyLessonComplete {
            NavigationLink(destination: RevisionCentreView()) {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("Today's small goal")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                        Text("You have completed every lesson in the catalogue.")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Revisit what you have learned in the Revision Centre.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .buttonStyle(PFCardButtonStyle())
            .accessibilityLabel("You have completed every lesson. Open the Revision Centre")
            .accessibilityHint("Opens the Revision Centre")
        } else {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text("Today's small goal")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                    Text("No lesson is available right now. Check your connection and try again.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Weekly target and streak

/// The weekly target, read from ProgressStore.weeklyGoal, with the
/// streak shown neutrally: a plain count, never guilt copy. The
/// target itself is edited in Learning Preferences, linked from
/// here, so there is no second weekly target anywhere.
private struct WeeklyTargetHabitCard: View {
    @EnvironmentObject private var progressStore: ProgressStore

    private var targetReached: Bool {
        progressStore.weeklyGoal > 0
            && progressStore.lessonsCompletedThisWeek >= progressStore.weeklyGoal
    }

    var body: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                HStack(spacing: PFSpacing.sm) {
                    Image(systemName: "target")
                        .font(.pfCardTitle.weight(.semibold))
                        .foregroundColor(.pfRoyal)
                        .accessibilityHidden(true)
                    Text("This week")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    Spacer()
                    if targetReached {
                        PFPill(
                            text: "Target reached",
                            background: Color.pfSuccess.opacity(0.12),
                            foreground: .pfSuccess
                        )
                    }
                }
                Text(LearningHabitPlanner.weeklyTargetText(
                    completedThisWeek: progressStore.lessonsCompletedThisWeek,
                    weeklyGoal: progressStore.weeklyGoal
                ))
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
                PFProgressBar(progress: progressStore.weeklyProgress)
                Label(
                    LearningHabitPlanner.streakText(streakCount: progressStore.streakCount),
                    systemImage: "flame"
                )
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
                NavigationLink(destination: LearningPreferencesView()) {
                    Text("Change your weekly target")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                }
                .accessibilityHint("Opens Learning Preferences, where the weekly target is set")
            }
        }
    }
}

// MARK: - Daily question

/// One real interview question per day, from the bundled bank, the
/// same question for every learner that day. The model answer is
/// the bank's own answer, revealed on tap. When the bank cannot be
/// loaded the card says so, with a Try again action.
private struct DailyQuestionHabitCard: View {
    @State private var showAnswer = false
    /// Bumped by Try again so the view re-reads the bundled bank
    /// after InterviewQuestionStore.reload().
    @State private var loadAttempt = 0

    private var todaysQuestion: InterviewQuestion? {
        _ = loadAttempt
        return LearningHabitPlanner.dailyQuestion(
            for: Date(),
            questions: InterviewQuestionStore.allQuestions
        )
    }

    var body: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("Question of the day")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfRoyal)
                if let question = todaysQuestion {
                    if let category = InterviewQuestionStore.categoryTitle(for: question.id) {
                        PFPill(text: category)
                    }
                    Text(question.question)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    if showAnswer {
                        PFBodyText(text: question.answer)
                    }
                    PFSecondaryButton(title: showAnswer ? "Hide model answer" : "Show model answer") {
                        showAnswer.toggle()
                    }
                    NavigationLink(destination: InterviewQuestionsView()) {
                        Text("Browse all interview questions")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                    }
                    .accessibilityHint("Opens the interview questions bank")
                } else {
                    Text("The question bank did not load, so today's question is not available.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    PFSecondaryButton(title: "Try again") {
                        InterviewQuestionStore.reload()
                        loadAttempt += 1
                    }
                }
            }
        }
    }
}

// MARK: - Weekly investigation challenge

/// This week's investigation case in the Exception Lab: one case
/// per week, the same case all week. Only the title, incident type
/// and level are shown, the same fields the lab shows for a locked
/// case. Tapping opens the lab itself; there is no deep link to a
/// single case, and the lab's own gating decides what opens.
private struct WeeklyChallengeHabitCard: View {
    @ObservedObject private var labStore = ExceptionLabStore.shared

    private var weeklyCase: ExceptionCase? {
        LearningHabitPlanner.weeklyInvestigationCase(
            for: Date(),
            cases: ExceptionCaseCatalogue.allCases
        )
    }

    var body: some View {
        if let weeklyCase {
            NavigationLink(destination: ExceptionInvestigationLabView()) {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        HStack(spacing: PFSpacing.sm) {
                            Text("Weekly investigation challenge")
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfRoyal)
                            Spacer()
                            if labStore.isCompleted(weeklyCase.id) {
                                PFPill(
                                    text: "Completed before",
                                    background: Color.pfSuccess.opacity(0.12),
                                    foreground: .pfSuccess
                                )
                            }
                        }
                        Text(weeklyCase.title)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: PFSpacing.sm) {
                            PFPill(text: weeklyCase.incidentType)
                            PFPill(
                                text: weeklyCase.level.displayName,
                                background: Color.pfGoldSoft,
                                foreground: Color.pfGoldText
                            )
                        }
                        Text("This week's case in the Exception Lab. Open the lab to investigate it.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .buttonStyle(PFCardButtonStyle())
            .accessibilityLabel("Weekly investigation challenge: \(weeklyCase.title)")
            .accessibilityHint("Opens the Exception Lab")
        } else {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text("Weekly investigation challenge")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                    Text("This week's case is not available right now.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Revision reminders

/// Revision due today, from the shared revision service. Zero means
/// nothing is due, and the card says so honestly. Tapping opens the
/// Revision Centre, which owns the schedule.
private struct RevisionHabitCard: View {
    @ObservedObject private var revisionService = RevisionService.shared

    var body: some View {
        NavigationLink(destination: RevisionCentreView()) {
            PFCard {
                HStack(spacing: PFSpacing.md) {
                    PFIconTile(systemImage: "arrow.clockwise", size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Revision reminders")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(revisionService.dueToday.isEmpty
                            ? "Nothing due for revision today"
                            : "\(revisionService.dueToday.count) concepts due for revision today")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.pfSecondaryText)
                }
            }
        }
        .buttonStyle(PFCardButtonStyle())
        .accessibilityLabel("Revision reminders")
        .accessibilityHint("Opens the Revision Centre")
    }
}

// MARK: - Weak areas

/// Weak-area recommendations from the engine, with the engine's own
/// reasons naming the real evidence. Shown only when the engine
/// returns weak-area picks.
private struct WeakAreaHabitCard: View {
    let picks: [LessonRecommendation]

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text("Worth another look")
                .font(.pfCardTitle)
                .foregroundColor(.pfNavy)
            ForEach(picks) { pick in
                NavigationLink(destination: LessonView(entry: pick.lesson)) {
                    PFCard {
                        HStack(spacing: PFSpacing.md) {
                            PFIconTile(systemImage: "questionmark.circle.fill", size: 44)
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                Text(pick.lesson.title)
                                    .font(.pfCardTitle)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(pick.reason)
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.pfSecondaryText)
                        }
                    }
                }
                .buttonStyle(PFCardButtonStyle())
                .accessibilityLabel("Worth another look: \(pick.lesson.title)")
                .accessibilityHint("Opens the lesson to review it")
            }
        }
    }
}

// MARK: - Milestones

/// Honest progress milestones from recorded completions: progress
/// to the next milestone, and the milestones already reached. When
/// every milestone is reached the card says so.
private struct MilestonesHabitCard: View {
    @EnvironmentObject private var progressStore: ProgressStore

    private var milestones: [LearningHabitMilestone] {
        LearningHabitPlanner.milestones(completedCount: progressStore.totalLessonsCompleted)
    }

    private var next: LearningHabitMilestone? {
        LearningHabitPlanner.nextMilestone(completedCount: progressStore.totalLessonsCompleted)
    }

    private var reachedTitles: String? {
        let reached = milestones.filter(\.isReached)
        guard !reached.isEmpty else { return nil }
        return reached.map(\.title).joined(separator: ", ")
    }

    var body: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                HStack(spacing: PFSpacing.sm) {
                    Image(systemName: "seal.fill")
                        .font(.pfCardTitle.weight(.semibold))
                        .foregroundColor(.pfRoyal)
                        .accessibilityHidden(true)
                    Text("Milestones")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                }
                if let next {
                    Text("Next: \(next.title)")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(progressStore.totalLessonsCompleted) of \(next.threshold) lessons")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfNavy)
                    PFProgressBar(progress: Double(progressStore.totalLessonsCompleted) / Double(next.threshold))
                } else {
                    Text("You have reached every milestone.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let reachedTitles {
                    Text("Reached: \(reachedTitles)")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Your first milestone is finishing one lesson.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
