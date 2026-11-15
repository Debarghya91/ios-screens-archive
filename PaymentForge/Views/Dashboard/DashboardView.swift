// DashboardView.swift
// Payments Training Hub iOS - My Progress: learning analytics.
// Native SwiftUI only, no WebView.
// Adaptive layout: flexible stacks and cards that reflow on every iPhone
// width, from the small iPhone SE to a Pro Max, in portrait and landscape.
// No fixed widths anywhere; every card uses maxWidth .infinity.
//
// Every number here comes from recorded data only, computed by
// ProgressInsights over the existing stores: learningHours() sums
// recorded lesson and audio durations, never an estimate; weekly
// activity counts recorded events per day; streak, lessons
// completed and quiz averages are all computed from recorded
// events. With no recorded events every statistic is zero or empty,
// and the screen says so honestly instead of showing a made-up
// number. No narration-length fetching, no invented totals.
//
// Activity and demonstrated competence are labelled separately
// throughout: "completed" and "opened" count activity, while
// "demonstrated" counts only quiz, assessment and lab evidence.
// Opening or completing a lesson alone never earns a proficiency
// claim. Knowledge is grouped by competency dimension, because the
// app has no domain grouping for lessons; dimension rows always
// name the evidence behind them. Certificate rows state the real
// rules from code: path certificates need every required lesson
// complete and no exam, course certificates need a passed Final
// Assessment, and no certificate implies formal accreditation or
// bank endorsement. Gating follows the settled model: the first
// lesson of each chapter is free, the rest unlock with a purchase.
// No em dashes in any user-facing text.

import SwiftUI

/// The My Progress segments, matching the second board:
/// Overview, Activity, Assessments.
private enum ProgressSegment: String, CaseIterable {
    case overview = "Overview"
    case activity = "Activity"
    case assessments = "Assessments"
}

struct DashboardView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore

    /// Read-only stores for the insight sections. This view never
    /// writes to any of them: it only reads recorded progress,
    /// assessments, lab results and drafts. The competency,
    /// revision and notes stores are declared with the sections
    /// that already used them, further down this file.
    @ObservedObject private var onboardingStore = OnboardingStore.shared
    @ObservedObject private var activePathStore = ActivePathStore.shared
    @ObservedObject private var finalAssessmentStore = FinalAssessmentStore.shared
    @ObservedObject private var labStore = ExceptionLabStore.shared
    @ObservedObject private var investigationStore = InvestigationStore.shared
    @ObservedObject private var studioStore = StudioDraftStore.shared

    /// Opens the side drawer. Passed in from the tab bar so the menu
    /// button can sit in this screen's navigation bar, and only here:
    /// pushed detail views have no menu button and keep a clean back button.
    @Binding var isDrawerOpen: Bool

    /// Optional tab selection, for the empty-state action. MainTabView
    /// always passes $selectedTab, so the action switches to Home.
    var selectedTab: Binding<Int>?

    /// The Home section the empty-state action lands on. MainTabView
    /// passes its target binding, so "Start learning" switches to
    /// Home and lands on the course browsing below the Continue
    /// learning block. There is no Learn tab any more.
    var homeSectionTarget: Binding<HomeSectionTarget?>?

    /// The empty-state action: switch to Home and land on the
    /// course browsing. Both bindings are set together, so Home
    /// scrolls to the browsing section on arrival.
    private func startLearning() {
        selectedTab?.wrappedValue = 0
        homeSectionTarget?.wrappedValue = .learn(.courses)
    }

    init(
        isDrawerOpen: Binding<Bool>,
        selectedTab: Binding<Int>? = nil,
        homeSectionTarget: Binding<HomeSectionTarget?>? = nil
    ) {
        self._isDrawerOpen = isDrawerOpen
        self.selectedTab = selectedTab
        self.homeSectionTarget = homeSectionTarget
    }

    @State private var showCheckout = false
    @State private var showResetConfirmation = false
    @State private var showResetCompleteAlert = false
    @State private var selectedSegment: ProgressSegment = .overview
    @State private var showAllQuizResults = false


    // MARK: - Derived data, all event-based

    /// Total lessons in the catalogue, from the loaded search index.
    /// Zero while the catalogue is still loading, so callers show a
    /// loading state instead of a made-up total.
    private var totalLessonCount: Int {
        if let count = contentService.searchIndex?.counts.lesson, count > 0 {
            return count
        }
        return contentService.allLessons.count
    }

    private var overallProgress: Double {
        guard totalLessonCount > 0 else { return 0 }
        return Double(progressStore.totalLessonsCompleted) / Double(totalLessonCount)
    }

    /// True once the learner has finished a whole chapter: the
    /// point where the overall progress ring and counters may
    /// appear. Before that, the progress section shows the
    /// starter state, never a "0 of N" counter or a 0% ring.
    private var hasMeaningfulProgress: Bool {
        ProgressVisibility.hasMeaningfulProgress(
            completedIDs: progressStore.completedLessonIDs,
            lessonEntries: contentService.allLessons
        )
    }

    /// Learning time, from recorded durations only. Hours when there
    /// is at least an hour, minutes when there is some recorded time
    /// under an hour, 0h when nothing was ever recorded.
    private var hoursValue: String {
        let hours = progressStore.learningHours()
        if hours >= 1 { return String(format: "%.1fh", hours) }
        let minutes = progressStore.learningMinutes
        if minutes > 0 { return "\(minutes)m" }
        return "0h"
    }

    private var hoursCaption: String {
        if progressStore.events.isEmpty {
            return "No activity yet"
        }
        if progressStore.learningHours() == 0 {
            return "No recorded learning time yet"
        }
        return "From recorded lesson and audio time only"
    }

    /// Weekly activity from recorded events, oldest first, with a
    /// short weekday label for each day.
    private var weeklyActivity: [(date: Date, count: Int)] {
        progressStore.weeklyActivity()
    }

    private var weeklyValues: [Double] {
        weeklyActivity.map { Double($0.count) }
    }

    private var weeklyLabels: [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return weeklyActivity.map { formatter.string(from: $0.date) }
    }

    /// Quiz results, one row per lesson, from recorded attempts only.
    /// Each row pairs the best fraction correct with that same
    /// attempt's correct count and total, so the percentage and the
    /// numbers always belong together. Lessons with no total
    /// recorded are listed with their correct count and no
    /// percentage, never an invented one. Most recently attempted
    /// first.
    private var quizResults: [(lessonID: String, correct: Int, total: Int?, fraction: Double?, lastAttempt: Date)] {
        progressStore.quizHistory
            .map { entry in
                let attempts = entry.value
                let best = attempts.compactMap { attempt -> (attempt: QuizAttempt, fraction: Double)? in
                    guard let fraction = attempt.fractionCorrect else { return nil }
                    return (attempt, fraction)
                }.max { $0.fraction < $1.fraction }
                return (
                    lessonID: entry.key,
                    correct: best?.attempt.correct ?? attempts.map(\.correct).max() ?? 0,
                    total: best.map { $0.attempt.total },
                    fraction: best?.fraction,
                    lastAttempt: attempts.map(\.attemptedAt).max() ?? Date.distantPast
                )
            }
            .sorted { $0.lastAttempt > $1.lastAttempt }
    }

    private func lessonTitle(for id: String) -> String {
        contentService.allLessons.first(where: { $0.id == id })?.title ?? id
    }

    private var lastLessonEntry: SearchEntry? {
        guard let id = progressStore.lastLessonID else { return nil }
        return contentService.allLessons.first { $0.id == id }
    }

    /// Recent completed lessons, from recorded completion events,
    /// most recent first. Titles come from the events themselves.
    private var recentCompletions: [LearningEvent] {
        progressStore.events
            .filter { $0.type == .lessonCompleted }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(5)
            .map { $0 }
    }

    private var recommendedLessons: [SearchEntry] {
        PFChapterHelper.recommendedLessons(in: contentService, progress: progressStore, limit: 3)
    }

    private var hasAnyProgress: Bool {
        !progressStore.events.isEmpty || progressStore.totalLessonsCompleted > 0
    }

    // MARK: - ProgressInsights, all computed from recorded data

    /// The onboarding profile when the learner chose it. A skipped
    /// profile is treated as no profile, exactly as HomeView does:
    /// its role was never chosen, so it must not steer the pathway
    /// or the recommendation.
    private var effectiveProfile: OnboardingProfile? {
        guard let profile = onboardingStore.profile, !profile.wasSkipped else { return nil }
        return profile
    }

    /// The role route for the learner's chosen role, when one exists.
    private var roleRoute: RoleRoute? {
        guard let profile = effectiveProfile else { return nil }
        return RoleRouteCatalogue.route(for: profile.role)
    }

    /// The guided path the pathway card links to: the active path
    /// when one is set, otherwise the path named by the role route.
    /// Nil when neither resolves, for example a sessions-only route.
    private var pathwayPath: LearningPath? {
        if let active = activePathStore.activePath {
            return active
        }
        return roleRoute?.learningPath()
    }

    /// The pathway lessons and where they came from. The active
    /// path wins when one is set. Otherwise the full role route
    /// (path lessons plus session lessons, deduped) is used, so
    /// session progress is not hidden when a route pairs a path
    /// with sessions. Empty while the catalogue is loading.
    private var pathwayLessons: (lessons: [SearchEntry], source: ProgressPathwaySource) {
        if let path = activePathStore.activePath {
            return (path.lessons(in: contentService), .activePath)
        }
        guard let route = roleRoute else { return ([], .none) }
        let lessons = route.lessons(in: contentService)
        if route.learningPath() != nil {
            return (lessons, .roleRoutePath)
        }
        return (lessons, .roleRouteSessions)
    }

    /// The pathway title shown on the card, naming the path or the
    /// role route so the learner knows which pathway the numbers
    /// describe.
    private var pathwayTitle: String {
        switch pathwayLessons.source {
        case .activePath:
            return pathwayPath.map { "Your journey: \($0.title)" } ?? "Your journey"
        case .roleRoutePath, .roleRouteSessions:
            return roleRoute.map { "Your role journey: \($0.title)" } ?? "Your role journey"
        case .none:
            return "No journey chosen yet"
        }
    }

    private var pathwayInsight: ProgressPathwayInsight {
        ProgressInsights.pathwayInsight(
            lessonIDs: pathwayLessons.lessons.map(\.id),
            completedLessonIDs: progressStore.completedLessonIDs,
            history: progressStore.quizHistory,
            source: pathwayLessons.source
        )
    }

    private var quizSummary: ProgressQuizSummary {
        ProgressInsights.quizSummary(history: progressStore.quizHistory)
    }

    private var demonstratedSummary: ProgressDemonstratedSummary {
        ProgressInsights.demonstratedSummary(
            completedLessonIDs: progressStore.completedLessonIDs,
            history: progressStore.quizHistory
        )
    }

    private var dimensionInsights: [ProgressDimensionInsight] {
        ProgressInsights.dimensionInsights(
            competencyScores: competencyStore.scores,
            lessons: contentService.allLessons,
            completedLessonIDs: progressStore.completedLessonIDs,
            history: progressStore.quizHistory
        )
    }

    private var evidenceAreas: (stronger: [ProgressEvidenceArea], needsAttention: [ProgressEvidenceArea]) {
        ProgressInsights.evidenceAreas(dimensionInsights)
    }

    /// Completed lessons to revisit: the lowest average quiz
    /// scores below the demonstration bar, at most three.
    private var weakQuizLessons: [ProgressLessonQuizEvidence] {
        ProgressInsights.weakQuizLessons(
            history: progressStore.quizHistory,
            completedLessonIDs: progressStore.completedLessonIDs,
            limit: 3
        )
    }

    private var labSummary: ProgressLabSummary {
        ProgressInsights.labSummary(
            results: labStore.results,
            totalCases: ExceptionCaseCatalogue.allCases.count
        )
    }

    private var labCaseInsights: [ProgressLabCaseInsight] {
        ProgressInsights.labCaseInsights(results: labStore.results)
    }

    private func labCaseTitle(for caseID: String) -> String {
        ExceptionCaseCatalogue.allCases.first(where: { $0.id == caseID })?.title ?? caseID
    }

    private var timeInsight: ProgressTimeInsight {
        ProgressInsights.timeInsight(events: progressStore.events)
    }

    private var consistencyInsight: ProgressConsistencyInsight {
        ProgressInsights.consistency(events: progressStore.events, referenceDate: Date())
    }

    private var activityCounts: ProgressActivityCounts {
        ProgressInsights.activityCounts(events: progressStore.events)
    }

    private var pathCertificateInsights: [ProgressPathCertificateInsight] {
        ProgressInsights.pathCertificateInsights(
            LearningPath.all.map { path in
                let progress = path.progress(in: progressStore, service: contentService)
                return ProgressPathProgress(
                    pathID: path.id,
                    pathTitle: path.title,
                    certificateTitle: path.certificateTitle,
                    completed: progress.completed,
                    total: progress.total
                )
            }
        )
    }

    private var courseCertificateInsights: [ProgressCourseCertificateInsight] {
        ProgressInsights.courseCertificateInsights(
            courses: FinalAssessmentStore.assessableCourses,
            certificates: finalAssessmentStore.certificates,
            attemptsUsed: finalAssessmentStore.attemptsUsed
        )
    }

    /// Path and course certificates earned, from eligibility and
    /// stored certificates only. Path eligibility is computed from
    /// lesson completion here; issuing happens only in
    /// CertificateView, which this count never calls.
    private var certificatesEarnedCount: Int {
        let paths = pathCertificateInsights.filter(\.isEligible).count
        let courses = courseCertificateInsights.filter(\.isPassed).count
        return paths + courses
    }

    /// Dimensions with no competency score and no quiz average:
    /// shown as having no evidence yet, never as weak.
    private var unassessedDimensions: [ProgressDimensionInsight] {
        dimensionInsights.filter { !$0.hasAnyEvidence }
    }

    /// Path certificates already earned by completion, course
    /// certificates already earned by passing, paths still to
    /// complete, and courses whose Final Assessment is still open.
    private var earnedPathCertificates: [ProgressPathCertificateInsight] {
        pathCertificateInsights.filter(\.isEligible)
    }

    private var earnedCourseCertificates: [ProgressCourseCertificateInsight] {
        courseCertificateInsights.filter(\.isPassed)
    }

    private var pendingPathCertificates: [ProgressPathCertificateInsight] {
        pathCertificateInsights.filter { $0.hasCertificate && !$0.isEligible }
    }

    private var openCourseCertificates: [ProgressCourseCertificateInsight] {
        courseCertificateInsights.filter { $0.status == .attemptsLeft }
    }

    private var studioSummary: ProgressStudioSummary {
        ProgressInsights.studioSummary(
            drafts: studioStore.drafts,
            totalExercises: StudioExercise.all.count
        )
    }

    /// The suggested next action, from the recommendation engine
    /// with its reason. Nil while the catalogue is loading or when
    /// every lesson is complete.
    private var nextRecommendation: LessonRecommendation? {
        RecommendationEngine.nextLesson(
            for: effectiveProfile,
            progress: progressStore,
            competency: competencyStore,
            service: contentService
        )
    }

    /// True when any assessment evidence exists: quiz attempts,
    /// competency assessments, lab completions, Final Assessment
    /// attempts or certificates, or a diagnostic score. The
    /// Assessments segment shows its empty state only when none
    /// of these exists.
    private var hasAnyAssessmentEvidence: Bool {
        progressStore.totalQuizAttempts > 0
            || competencyStore.hasAssessments
            || !labStore.results.isEmpty
            || !finalAssessmentStore.attemptsUsed.isEmpty
            || !finalAssessmentStore.certificates.isEmpty
            || effectiveProfile?.diagnosticScore != nil
    }

    /// Lessons in a list whose best quiz fraction reaches the
    /// demonstration bar. Used for the per-path demonstrated line.
    private func demonstratedCount(in lessons: [SearchEntry]) -> Int {
        lessons.filter { lesson in
            guard let best = progressStore.bestQuizScore(for: lesson.id) else { return false }
            return best >= RecommendationEngine.masteryThreshold
        }.count
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.xl) {
                    headerSection
                        .id("dashboardTop")

                    segmentPicker

                    switch selectedSegment {
                    case .overview:
                        overviewContent
                    case .activity:
                        activityContent
                    case .assessments:
                        assessmentsContent
                    }

                    // Learning tools and account sections live under
                    // every segment: they are navigation, not analytics.
                    learningToolsSection
                    backupSection
                    purchasesSection
                }
                .padding(PFSpacing.lg)
            }
            .background(Color.pfBackground)
            // Extra scrollable space at the bottom so the last card clears
            // the tab bar on every iPhone size.
            .pfTabBarClearance()
            .onChange(of: selectedSegment) { _, _ in
                withAnimation {
                    proxy.scrollTo("dashboardTop", anchor: .top)
                }
            }
            .onAppear {
                // The scroll rule: Back and tab switches land
                // at the top, never at the restored offset.
                proxy.scrollTo("dashboardTop", anchor: .top)
            }
            .navigationTitle("My Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    DrawerMenuButton(isDrawerOpen: $isDrawerOpen)
                }
            }
            .sheet(isPresented: $showCheckout) {
                CheckoutView()
            }
            .confirmationDialog(
                "Reset all progress?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset progress", role: .destructive) {
                    // resetAll() is synchronous: it clears and saves
                    // before returning, so the success alert set on
                    // the next line can only show after the wipe
                    // has completed, never before or in parallel.
                    progressStore.resetAll()
                    showResetCompleteAlert = true
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This clears completed lessons, quiz scores, your streak and your weekly progress on this device. Your weekly goal, notes, bookmarks and competency assessments are not affected. It cannot be undone.")
            }
            .alert("Progress reset", isPresented: $showResetCompleteAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your completed lessons, quiz scores, streak and weekly progress have been cleared on this device. Your weekly goal, notes, bookmarks and competency assessments were not affected.")
            }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: PFSpacing.md) {
            Text("My Progress")
                .font(.pfHeroTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            HStack(spacing: PFSpacing.xs) {
                Image(systemName: "flame.fill")
                    .foregroundColor(.pfGold)
                Text("\(progressStore.streakCount)")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                Text(progressStore.streakCount == 1 ? "day" : "days")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, PFSpacing.md)
            .padding(.vertical, PFSpacing.sm)
            .background(Color.pfCard)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.pfBorder, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
            .accessibilityLabel("Streak, \(progressStore.streakCount) \(progressStore.streakCount == 1 ? "day" : "days")")
        }
    }

    private var segmentPicker: some View {
        Picker("Progress section", selection: $selectedSegment) {
            ForEach(ProgressSegment.allCases, id: \.self) { segment in
                Text(segment.rawValue).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Progress section")
    }

    // MARK: - Overview segment

    @ViewBuilder
    private var overviewContent: some View {
        if !hasAnyProgress {
            PFEmptyStateView(
                systemImage: "chart.bar.fill",
                title: "No progress yet",
                message: "Complete your first lesson and your progress and streak will appear here. Learning time appears once listening or lesson time has been recorded.",
                actionTitle: "Start learning",
                action: { startLearning() }
            )
            // A new learner still gets a next action, a pathway and
            // the certificate rules, so the screen is useful before
            // any progress exists. The suggested lesson is labelled
            // when it is the free first lesson of its chapter.
            nextActionSection
            pathwaySection
            certificateSummarySection
        } else {
            nextActionSection
            learningProgressSection
            pathwaySection
            statsSection
            demonstratedStatsSection
            knowledgeSection
            strengthsSection
            certificateSummarySection
            weeklyActivitySummarySection
            pathwaysSection
            recentHistorySection
            recommendedSection
        }
    }

    // MARK: - Suggested next action

    /// The engine's single next lesson, with the engine's reason
    /// shown in full. The reason names its real evidence, so the
    /// suggestion can be checked. Tapping opens the lesson; lock
    /// handling stays with LessonView and nothing here bypasses it.
    private var nextActionSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Suggested next action")
            if contentService.searchIndex == nil {
                PFCard {
                    PFLoadingView(message: "Loading your next lesson...")
                }
            } else if let recommendation = nextRecommendation {
                NavigationLink(destination: LessonView(entry: recommendation.lesson)) {
                    PFCard {
                        VStack(alignment: .leading, spacing: PFSpacing.md) {
                            HStack(spacing: PFSpacing.md) {
                                PFIconTile(systemImage: "play.fill", size: 52)
                                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                    Text(recommendation.lesson.title)
                                        .font(.pfCardTitle)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(PFChapterHelper.chapterTitle(for: recommendation.lesson))
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let position = PFChapterHelper.readingPositionLabel(for: recommendation.lesson, in: contentService) {
                                        Text(position)
                                            .font(.pfCaption)
                                            .foregroundColor(.pfSecondaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    if PFChapterHelper.isSampleLesson(recommendation.lesson, in: contentService) {
                                        Text("Free sample lesson: the first lesson of its chapter, free with full content.")
                                            .font(.pfCaptionBold)
                                            .foregroundColor(.pfSuccess)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            Text(recommendation.reason)
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .buttonStyle(PFCardButtonStyle())
            } else {
                PFCard {
                    Text("You have completed every lesson in the catalogue. Revision, assessments and the investigation lab are still available below.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Pathway completion

    /// Overall pathway completion for the active path or role
    /// route, with quiz evidence inside the pathway kept separate
    /// from completion. While the catalogue is loading the card
    /// says so instead of showing 0 percent.
    private var pathwaySection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Your journey")
            if contentService.searchIndex == nil {
                PFCard {
                    PFLoadingView(message: "Loading your pathway...")
                }
            } else if pathwayLessons.source == .none {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text(pathwayTitle)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Choose a learning journey to work through, or complete onboarding to get a journey for your role. Your progress is counted per lesson either way, and choosing a journey later never clears it.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("The first lesson of each chapter is free. Other lessons unlock with a purchase.")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if let fraction = pathwayInsight.fraction {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        if pathwayInsight.completed > 0 {
                            HStack(spacing: PFSpacing.lg) {
                                PFProgressRing(progress: fraction, size: 110, color: .pfRoyal)
                                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                                    Text(pathwayTitle)
                                        .font(.pfCardTitle)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("\(pathwayInsight.completed) of \(pathwayInsight.total) lessons completed")
                                        .font(.pfBody)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("Completed means marked complete. Demonstrated is counted separately below.")
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Divider()
                            Text("Demonstrated on quizzes in this journey: \(pathwayInsight.demonstratedLessonCount) of \(pathwayInsight.total) lessons at 80% or above on their best quiz score. \(pathwayInsight.quizAttemptedLessonCount) lessons have a quiz attempt recorded.")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                                Text(pathwayTitle)
                                    .font(.pfCardTitle)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("No lessons completed on this journey yet.")
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if let path = pathwayPath {
                            NavigationLink(destination: PathDetailView(path: path)) {
                                Text("Open \(path.title)")
                                    .font(.pfCallout)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.pfRoyal)
                                    .padding(.horizontal, PFSpacing.md)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .background(Color.pfRoyal.opacity(0.08))
                                    .cornerRadius(PFSpacing.cornerRadius)
                            }
                        } else if pathwayLessons.source == .roleRouteSessions, let route = roleRoute {
                            Text("This route follows guided sessions: \(route.sessions().map(\.title).joined(separator: ", ")).")
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                // The catalogue loaded but the pathway resolved to
                // no lessons. This means the route's chapters have
                // no lessons in the loaded catalogue, not that
                // progress is zero, so it is stated, not shown as
                // a loading state or as 0 percent.
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text(pathwayTitle)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("This journey has no lessons in the loaded catalogue, so no completion can be shown yet.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Demonstrated competence stats

    /// What the learner has demonstrated, kept apart from the
    /// activity stats above it. Quiz accuracy is the mean of
    /// recorded attempt fractions; lab performance is the mean of
    /// best case scores; certificates counts only earned
    /// certificates. Each card says when it has no evidence yet.
    private var demonstratedStatsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Demonstrated")
            HStack(spacing: PFSpacing.sm) {
                PFStatCard(
                    value: quizSummary.averageFraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "No data",
                    label: "Quiz accuracy",
                    systemImage: "checkmark.circle.fill",
                    caption: quizSummary.totalAttempts == 0
                        ? "No quiz attempts recorded yet"
                        : "\(quizSummary.totalAttempts) \(quizSummary.totalAttempts == 1 ? "attempt" : "attempts") recorded"
                )
                PFStatCard(
                    value: labSummary.meanBestFraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "No data",
                    label: "Lab best scores",
                    systemImage: "flask.fill",
                    caption: labSummary.casesCompleted == 0
                        ? "No lab cases completed yet"
                        : "\(labSummary.casesCompleted) of \(labSummary.totalCases) cases completed"
                )
                PFStatCard(
                    value: "\(certificatesEarnedCount)",
                    label: "Certificates earned",
                    systemImage: "seal.fill",
                    caption: "Certificates of Completion only"
                )
            }
            Text("Demonstrated means shown on a quiz, an assessment or in the lab. Completed lessons without that evidence are counted under Overall progress, not here.")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Knowledge by area

    /// Competency dimension scores with the quiz evidence for the
    /// same chapters beside them. A dimension with no assessment
    /// shows "Not assessed yet", never a made-up score, and a
    /// dimension with no quiz attempts says so. Completion is
    /// shown as activity only. Full detail and the assessment
    /// links live in the Assessments segment.
    private var knowledgeSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Knowledge by area")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text("By competency area, from recorded assessments and lesson quizzes. These are the \(CompetencyStore.CompetencyDimension.allCases.count) competency areas, not the \(ContentManifest.domainCount) catalogue domains: the app has no domain grouping for lessons.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(dimensionInsights) { insight in
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            HStack(spacing: PFSpacing.sm) {
                                Image(systemName: insight.dimension.systemImage)
                                    .foregroundColor(.pfRoyal)
                                Text(insight.dimension.rawValue)
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                if let score = insight.competencyScorePercent {
                                    Text("\(Int(score.rounded()))% assessed")
                                        .font(.pfCaptionBold)
                                        .foregroundColor(.pfRoyal)
                                        .fixedSize(horizontal: true, vertical: false)
                                } else {
                                    Text("Not assessed yet")
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                            if let average = insight.quizAverageFraction {
                                Text("Quiz average \(Int((average * 100).rounded()))% across \(insight.quizAttemptsWithTotal) \(insight.quizAttemptsWithTotal == 1 ? "attempt" : "attempts"). \(insight.lessonsCompleted > 0 ? "\(insight.lessonsCompleted) of \(insight.lessonsTotal) lessons completed in this area." : "No lessons completed in this area yet.")")
                                    .font(.pfCaption)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text("No quiz attempts with a recorded total in this area yet. \(insight.lessonsCompleted > 0 ? "\(insight.lessonsCompleted) of \(insight.lessonsTotal) lessons completed in this area." : "No lessons completed in this area yet.")")
                                    .font(.pfCaption)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            PFProgressBar(progress: (insight.competencyScorePercent ?? 0) / 100, height: 6)
                        }
                    }
                    Button("See assessments and detail") {
                        selectedSegment = .assessments
                    }
                    .font(.pfCallout)
                    .fontWeight(.semibold)
                    .foregroundColor(.pfRoyal)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Strong and weak areas

    /// Stronger evidence and areas needing attention, each with
    /// its evidence stated. Only dimensions with recorded evidence
    /// appear; unassessed areas are listed separately as having
    /// no evidence yet, never as weak. Lessons to revisit are
    /// completed lessons with a low recorded quiz average.
    private var strengthsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Stronger and weaker areas")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    if evidenceAreas.stronger.isEmpty && evidenceAreas.needsAttention.isEmpty {
                        Text("No assessment or quiz evidence yet")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Take a lesson quiz or a competency assessment and this section will show where your evidence is stronger and where it needs attention. Completed lessons alone do not place an area here.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        if !evidenceAreas.stronger.isEmpty {
                            Text("Stronger evidence")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                            ForEach(evidenceAreas.stronger) { area in
                                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                    Text(area.dimension.rawValue)
                                        .font(.pfBody)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(area.evidenceText)
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        if !evidenceAreas.needsAttention.isEmpty {
                            Text("Needs attention")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                            ForEach(evidenceAreas.needsAttention) { area in
                                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                    Text(area.dimension.rawValue)
                                        .font(.pfBody)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(area.evidenceText)
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        if !unassessedDimensions.isEmpty {
                            Text("No evidence yet: \(unassessedDimensions.map(\.dimension.rawValue).joined(separator: ", ")).")
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !weakQuizLessons.isEmpty {
                        Divider()
                        Text("Lessons to revisit")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        ForEach(weakQuizLessons, id: \.lessonID) { lesson in
                            HStack(spacing: PFSpacing.md) {
                                Text(lessonTitle(for: lesson.lessonID))
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                if let average = lesson.averageFraction {
                                    Text("Quiz average \(Int((average * 100).rounded()))%")
                                        .font(.pfCaptionBold)
                                        .foregroundColor(.pfRoyal)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                        }
                        Text("These lessons are complete, but their recorded quiz averages are below 80%. Revisit the lesson, then retake its quiz.")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Certificate eligibility summary

    /// What is earned and what is still needed, under the real
    /// rules: path certificates need every required lesson
    /// complete, course certificates need a passed Final
    /// Assessment. No certificate here implies formal
    /// accreditation or bank endorsement. Detail and issuing live
    /// in Certificates, linked from this card and from Learning
    /// tools below.
    private var certificateSummarySection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Certificates")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    if contentService.searchIndex == nil {
                        PFLoadingView(message: "Loading certificate progress...")
                    } else {
                        if earnedPathCertificates.isEmpty && earnedCourseCertificates.isEmpty {
                            Text("No certificates earned yet")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("\(certificatesEarnedCount) \(certificatesEarnedCount == 1 ? "certificate" : "certificates") earned")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(earnedPathCertificates) { path in
                                Text("\(path.certificateTitle ?? path.pathTitle): earned by completing every required lesson.")
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            ForEach(earnedCourseCertificates) { course in
                                if let certificate = course.certificate {
                                    Text("\(course.courseName): earned with \(certificate.scoreText) (\(Int(certificate.scorePercent.rounded()))%) on the Final Assessment.")
                                        .font(.pfBody)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        ForEach(pendingPathCertificates) { path in
                            Text("\(path.certificateTitle ?? path.pathTitle): \(path.lessonsRemaining) \(path.lessonsRemaining == 1 ? "lesson" : "lessons") left to complete. No exam is required.")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !openCourseCertificates.isEmpty {
                            Text("Final Assessments still open: \(openCourseCertificates.map(\.courseName).joined(separator: ", ")). Pass with more than 70% to earn the course certificate. Each course allows \(FinalAssessmentStore.maxAttempts) attempts.")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Certificates of Completion certify completion of the named course or path. They are not accredited qualifications and carry no bank endorsement.")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        NavigationLink(destination: CertificatesListView()) {
                            Text("View certificates")
                                .font(.pfCallout)
                                .fontWeight(.semibold)
                                .foregroundColor(.pfRoyal)
                                .padding(.horizontal, PFSpacing.md)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .background(Color.pfRoyal.opacity(0.08))
                                .cornerRadius(PFSpacing.cornerRadius)
                        }
                    }
                }
            }
        }
    }

    private var learningProgressSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Overall progress")
            if contentService.searchIndex == nil, let error = contentService.indexError {
                PFErrorStateView(
                    title: "Could not load the course catalogue",
                    message: error,
                    retryTitle: "Retry"
                ) {
                    Task { await contentService.loadSearchIndex() }
                }
            } else {
                PFCard {
                    if contentService.searchIndex == nil {
                        PFLoadingView(message: "Loading your progress...")
                    } else if !hasMeaningfulProgress {
                        VStack(alignment: .leading, spacing: PFSpacing.sm) {
                            Text("Your progress will show here once you finish your first chapter.")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Complete your first lesson to start your progress.")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            if let tabBinding = selectedTab {
                                PFPrimaryButton(title: "Start learning") {
                                    startLearning()
                                }
                                .accessibilityLabel("Start learning")
                            }
                        }
                    } else {
                        HStack(spacing: PFSpacing.lg) {
                            PFProgressRing(progress: overallProgress, size: 110, color: .pfRoyal)
                            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                                Text("\(progressStore.totalLessonsCompleted) of \(totalLessonCount) lessons completed")
                                    .font(.pfCardTitle)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(Int((overallProgress * 100).rounded()))% of the curriculum complete")
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Demonstrated on quizzes: \(demonstratedSummary.demonstratedLessonCount) of \(demonstratedSummary.completedLessonCount) completed lessons at 80% or above on their best quiz score. \(demonstratedSummary.noQuizEvidenceCount) completed \(demonstratedSummary.noQuizEvidenceCount == 1 ? "lesson has" : "lessons have") no quiz attempt recorded.")
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "At a glance")
            HStack(spacing: PFSpacing.sm) {
                PFStatCard(
                    value: "\(progressStore.totalLessonsCompleted)",
                    label: "Lessons completed",
                    systemImage: "book.fill"
                )
                PFStatCard(
                    value: hoursValue,
                    label: "Learning time",
                    systemImage: "clock.fill",
                    caption: hoursCaption
                )
                PFStatCard(
                    value: "\(progressStore.streakCount)",
                    label: "Day streak",
                    systemImage: "flame.fill"
                )
            }
        }
    }

    /// "3 of 5 lessons this week", or a starter sentence when
    /// nothing is complete this week: no "0 of 5" counter.
    private var weeklyGoalLine: String {
        if progressStore.lessonsCompletedThisWeek > 0 {
            return "\(progressStore.lessonsCompletedThisWeek) of \(progressStore.weeklyGoal) lessons this week"
        }
        return "No lessons completed this week yet."
    }

    private var weeklyActivitySummarySection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Weekly activity")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text(weeklyGoalLine)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    PFWeeklyBarChart(values: weeklyValues, labels: weeklyLabels)
                    Text("Bars count recorded learning events per day. Days with no activity show no bar.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Activity segment

    @ViewBuilder
    private var activityContent: some View {
        if !hasAnyProgress {
            PFEmptyStateView(
                systemImage: "calendar",
                title: "No activity yet",
                message: "Your daily activity will appear here once you start learning. Each day you learn adds to your streak.",
                actionTitle: "Start learning",
                action: { startLearning() }
            )
        } else {
            weeklyActivitySection
            weeklyGoalSection
            consistencySection
            timeDetailSection
            dailyActivitySection
        }
    }

    // MARK: - Consistency and recorded time

    /// Learning consistency from real event dates: active days in
    /// the last 7 and 28 days, the streak, and the most recent
    /// activity. Neutral counts only, with no judgement about
    /// missed days. Counts come from the retained events kept on
    /// this device.
    private var consistencySection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Consistency")
            HStack(spacing: PFSpacing.sm) {
                PFStatCard(
                    value: "\(consistencyInsight.activeDaysLast7)",
                    label: "Active days, last 7 days",
                    systemImage: "calendar"
                )
                PFStatCard(
                    value: "\(consistencyInsight.activeDaysLast28)",
                    label: "Active days, last 28 days",
                    systemImage: "calendar.badge.clock"
                )
                PFStatCard(
                    value: "\(consistencyInsight.distinctActiveDays)",
                    label: "Active days in total",
                    systemImage: "checkmark.circle.fill"
                )
            }
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    if let lastActivity = consistencyInsight.lastActivityDate {
                        Text("Most recent activity: \(lastActivity, format: .dateTime.day().month().year()). Current streak: \(consistencyInsight.streakCount) \(consistencyInsight.streakCount == 1 ? "day" : "days").")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Active means at least one recorded learning event that day, such as completing a lesson, finishing a quiz or listening to narration. Older events are dropped once the stored list is full, so the total is a lower bound.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Recorded learning time, split by what was actually measured:
    /// lesson durations and finished audio listens. Partial listens
    /// are not recorded, and reading, quiz, lab and studio time are
    /// never recorded, so this is recorded time only, never an
    /// estimate of total study time. When nothing was recorded the
    /// card says so instead of showing a made-up number.
    private var timeDetailSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Time spent learning")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    if timeInsight.hasRecordedTime {
                        Text("Recorded time: \(ProgressInsights.durationLabel(totalSeconds: timeInsight.totalSeconds))")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Lesson time recorded: \(ProgressInsights.durationLabel(totalSeconds: timeInsight.lessonDurationSeconds)) from \(timeInsight.lessonDurationEventCount) \(timeInsight.lessonDurationEventCount == 1 ? "event" : "events").")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Audio time recorded: \(ProgressInsights.durationLabel(totalSeconds: timeInsight.audioSeconds)) from \(timeInsight.audioEventCount) finished \(timeInsight.audioEventCount == 1 ? "listen" : "listens").")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No learning time recorded yet")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Time is recorded only from measured lesson durations and narration played to the end. Listen to a full narration and the time will appear here.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Opened lessons in recorded events: \(activityCounts.distinctLessonsOpened). Completed lessons in recorded events: \(activityCounts.distinctLessonsCompletedInEvents). Opening a lesson is activity; it does not by itself demonstrate knowledge.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var weeklyActivitySection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Weekly activity")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text(weeklyGoalLine)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    PFWeeklyBarChart(values: weeklyValues, labels: weeklyLabels)
                    Text("Bars count recorded learning events per day, from the last 7 days. Days with no activity show no bar.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// "About 9 weeks left at 5 lessons a week · About 38 hrs of
    /// listening to go", from the lessons still to finish and the
    /// weekly goal. Nil when everything is complete or the goal
    /// is not set.
    private var paceLine: String? {
        let remaining = contentService.allLessons.filter { !progressStore.isLessonComplete($0.id) }
        guard !remaining.isEmpty, progressStore.weeklyGoal > 0 else { return nil }
        let weeks = (remaining.count + progressStore.weeklyGoal - 1) / progressStore.weeklyGoal
        let weekText = weeks == 1 ? "About 1 week left" : "About \(weeks) weeks left"
        let goalText = "at \(progressStore.weeklyGoal) lessons a week"
        let remainingSeconds = remaining.reduce(0) { $0 + (LessonDurations.seconds(for: $1.id) ?? 0) }
        guard remainingSeconds > 0 else {
            return "\(weekText) \(goalText)."
        }
        return "\(weekText) \(goalText) · About \(LessonDurations.durationText(remainingSeconds)) of listening to go."
    }

    private var weeklyGoalSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Weekly goal")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text(weeklyGoalLine)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    if progressStore.lessonsCompletedThisWeek > 0 {
                        PFProgressBar(progress: progressStore.weeklyProgress)
                    }
                    Text("How many lessons do you want to finish each week?")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                    HStack(spacing: PFSpacing.md) {
                        Text("\(progressStore.weeklyGoal)")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .frame(minWidth: 44, alignment: .center)
                        Text("lessons per week")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                        Spacer()
                        // Any goal from 1 to ContentManifest.lessonCount lessons: the same
                        // range as LearningPreferencesView.
                        Stepper("", value: $progressStore.weeklyGoal, in: 1...ContentManifest.lessonCount)
                            .labelsHidden()
                            .accessibilityLabel("Weekly goal in lessons")
                    }
                    if let paceLine {
                        Text(paceLine)
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var dailyActivitySection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Last 7 days")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    ForEach(Array(weeklyActivity.enumerated()), id: \.offset) { index, day in
                        HStack(spacing: PFSpacing.md) {
                            Text(day.date, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                                .font(.pfBody)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Text(day.count == 0 ? "No activity" : "\(day.count) \(day.count == 1 ? "event" : "events")")
                                .font(.pfCaptionBold)
                                .foregroundColor(day.count == 0 ? .pfSecondaryText : .pfRoyal)
                        }
                        if index < weeklyActivity.count - 1 {
                            Divider()
                        }
                    }
                    Text("Each event is one recorded action, such as completing a lesson, finishing a quiz or listening to narration.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Assessments segment

    @ViewBuilder
    private var assessmentsContent: some View {
        if !hasAnyAssessmentEvidence {
            PFEmptyStateView(
                systemImage: "checkmark.circle.fill",
                title: "No assessments yet",
                message: "Take a lesson quiz, a competency assessment, a Final Assessment or an investigation lab case and your scores will appear here. Quizzes, competency scores, Final Assessments and lab scores are shown in separate sections.",
                actionTitle: "Start learning",
                action: { startLearning() }
            )
        } else {
            quizSection
            competencySection
            diagnosticSection
            finalAssessmentsSection
            labSection
            studioSection
        }
    }

    /// The onboarding diagnostic score, shown only when one was
    /// recorded. It is a starting point from onboarding, not a
    /// current measure, and it never feeds the competency scores.
    @ViewBuilder
    private var diagnosticSection: some View {
        if let profile = effectiveProfile, let score = profile.diagnosticScore {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                PFSectionHeader(title: "Onboarding diagnostic")
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("\(Int((min(1, max(0, score)) * 100).rounded()))% at onboarding")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        if let takenAt = profile.diagnosticTakenAt {
                            Text("Taken \(takenAt, format: .dateTime.day().month().year()).")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("A starting point from when onboarding was completed. It does not change as you learn, and it is not part of your competency scores.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Final Assessments

    /// Final Assessment standing for every assessable course, from
    /// the stored attempt counts and certificates. Failed attempt
    /// scores are not stored, so only the passing score (on the
    /// certificate) is ever shown. Rows do not link straight to
    /// the exam: Certificates applies the ownership rules, so the
    /// single link below goes there.
    private var finalAssessmentsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Final Assessments")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text("\(FinalAssessmentStore.questionCount) questions per course, pass mark more than 70%, that is at least \(FinalAssessmentStore.passCorrectCount) out of \(FinalAssessmentStore.questionCount) correct. Each course allows \(FinalAssessmentStore.maxAttempts) attempts.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(courseCertificateInsights) { course in
                        HStack(spacing: PFSpacing.md) {
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                Text(course.courseName)
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let certificate = course.certificate {
                                    Text("Passed: \(certificate.scoreText) (\(Int(certificate.scorePercent.rounded()))%). Certificate earned.")
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSuccess)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else if course.status == .locked {
                                    Text("Locked: all \(FinalAssessmentStore.maxAttempts) attempts used without a pass. Contact support for another attempt.")
                                        .font(.pfCaption)
                                        .foregroundColor(.pfError)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else if course.attemptsUsed > 0 {
                                    Text("\(course.attemptsUsed) \(course.attemptsUsed == 1 ? "attempt" : "attempts") used, \(course.attemptsRemaining) left. Scores for attempts that did not pass are not kept.")
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else {
                                    Text("Not attempted yet. \(course.attemptsRemaining) attempts available.")
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer()
                        }
                    }
                    NavigationLink(destination: CertificatesListView()) {
                        Text("View certificates and Final Assessments")
                            .font(.pfCallout)
                            .fontWeight(.semibold)
                            .foregroundColor(.pfRoyal)
                            .padding(.horizontal, PFSpacing.md)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .background(Color.pfRoyal.opacity(0.08))
                            .cornerRadius(PFSpacing.cornerRadius)
                    }
                }
            }
        }
    }

    // MARK: - Investigation lab

    /// Practical investigation performance, from the stored lab
    /// scores. Scores measure investigation quality (best-first
    /// actions, wrong turns, red herrings, evidence opened), and
    /// the best score per case is kept. There is no pass mark for
    /// the lab, so none is shown. Breakdown totals come from the
    /// most recent completion of each case. Lab scores stay on
    /// this device.
    private var labSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Investigation lab")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    if labSummary.casesCompleted == 0 {
                        Text("No lab cases completed yet")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Complete an investigation case and your best scores will appear here. The lab has \(labSummary.totalCases) cases.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(spacing: PFSpacing.lg) {
                            if let mean = labSummary.meanBestFraction {
                                PFProgressRing(progress: mean, size: 110, color: .pfRoyal)
                            }
                            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                                if let mean = labSummary.meanBestFraction {
                                    Text("\(Int((mean * 100).rounded()))% average best score")
                                        .font(.pfSectionTitle)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Text("\(labSummary.casesCompleted) of \(labSummary.totalCases) cases completed, \(labSummary.totalCompletions) \(labSummary.totalCompletions == 1 ? "completion" : "completions") in total")
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let lowest = labSummary.lowestBestFraction, let highest = labSummary.highestBestFraction {
                                    Text("Best scores range from \(Int((lowest * 100).rounded()))% to \(Int((highest * 100).rounded()))%.")
                                        .font(.pfBody)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        Divider()
                        Text("From the most recent completion of each case: \(labSummary.stepsSolvedBestFirst) steps solved on the first pick, \(labSummary.stepsSolvedAfterWrongTurn) solved after a wrong turn, \(labSummary.totalWrongPicks) wrong picks, \(labSummary.totalRedHerringPicks) red herring picks, \(labSummary.evidenceOpenedCount) of \(labSummary.evidenceTotalCount) genuine evidence items opened.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(labCaseInsights) { result in
                            HStack(spacing: PFSpacing.md) {
                                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                    Text(labCaseTitle(for: result.caseID))
                                        .font(.pfBody)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("\(result.completions) \(result.completions == 1 ? "completion" : "completions"), last completed \(result.lastCompletedAt, format: .dateTime.day().month().year()).")
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let best = investigationStore.bestOverall(for: result.caseID) {
                                        Text("Investigation best score: \(best) of 100.")
                                            .font(.pfCaption)
                                            .foregroundColor(.pfSecondaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer()
                                if let fraction = result.bestFraction {
                                    Text("Best \(result.bestTotal) of \(result.bestMaximum) (\(Int((fraction * 100).rounded()))%)")
                                        .font(.pfCaptionBold)
                                        .foregroundColor(.pfRoyal)
                                        .fixedSize(horizontal: true, vertical: false)
                                } else {
                                    Text("Best \(result.bestTotal)")
                                        .font(.pfCaptionBold)
                                        .foregroundColor(.pfRoyal)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                        }
                        Text("Your lab scores stay on this device.")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    NavigationLink(destination: ExceptionInvestigationLabView()) {
                        Text("Open the investigation lab")
                            .font(.pfCallout)
                            .fontWeight(.semibold)
                            .foregroundColor(.pfRoyal)
                            .padding(.horizontal, PFSpacing.md)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .background(Color.pfRoyal.opacity(0.08))
                            .cornerRadius(PFSpacing.cornerRadius)
                    }
                }
            }
        }
    }

    // MARK: - Studio drafts

    /// Studio work is activity, not assessed performance: drafts
    /// carry no score and no completion state. This card reports
    /// counts and dates only, and says so. Drafts stay on this
    /// device.
    private var studioSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "BA and PO Studio")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    if !studioSummary.hasDrafts {
                        Text("No studio drafts yet")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Save a draft in the studio and it will be counted here. The studio has \(studioSummary.totalExercises) exercises.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("\(studioSummary.draftsCount) \(studioSummary.draftsCount == 1 ? "draft" : "drafts") saved, across \(studioSummary.exercisesWithDrafts) of \(studioSummary.totalExercises) exercises")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        if let updated = studioSummary.lastUpdatedAt {
                            Text("Most recent draft updated \(updated, format: .dateTime.day().month().year()).")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Drafts are work in progress, not scores. Saving a draft does not demonstrate competence, and no draft is marked.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Your drafts stay on this device.")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    NavigationLink(destination: BAProductStudioView()) {
                        Text("Open the studio")
                            .font(.pfCallout)
                            .fontWeight(.semibold)
                            .foregroundColor(.pfRoyal)
                            .padding(.horizontal, PFSpacing.md)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .background(Color.pfRoyal.opacity(0.08))
                            .cornerRadius(PFSpacing.cornerRadius)
                    }
                }
            }
        }
    }

    private var quizSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Quiz performance")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    if quizResults.isEmpty {
                        Text("No quizzes taken yet")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Take a lesson quiz to see your results here.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(spacing: PFSpacing.lg) {
                            if let average = progressStore.averageQuizScore() {
                                PFProgressRing(progress: average, size: 110, color: .pfRoyal)
                            }
                            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                                if let average = progressStore.averageQuizScore() {
                                    Text("\(Int((average * 100).rounded()))% average score")
                                        .font(.pfSectionTitle)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if let best = progressStore.bestQuizScoreOverall() {
                                    Text("Best score: \(Int((best * 100).rounded()))%")
                                        .font(.pfBody)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Text("\(progressStore.totalQuizAttempts) \(progressStore.totalQuizAttempts == 1 ? "attempt" : "attempts") recorded")
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Demonstrated: \(quizSummary.demonstratedLessonCount) \(quizSummary.demonstratedLessonCount == 1 ? "lesson" : "lessons") at 80% or above on their best quiz score, out of \(quizSummary.lessonsAttempted) \(quizSummary.lessonsAttempted == 1 ? "lesson" : "lessons") with a quiz attempt.")
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Averages come from recorded quiz attempts only.")
                                    .font(.pfCaption)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Divider()
                        ForEach(quizResults.prefix(showAllQuizResults ? quizResults.count : 5), id: \.lessonID) { result in
                            HStack(spacing: PFSpacing.md) {
                                Text(lessonTitle(for: result.lessonID))
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                if let fraction = result.fraction, let total = result.total {
                                    Text("\(Int((fraction * 100).rounded()))% best (\(result.correct) of \(total))")
                                        .font(.pfCaptionBold)
                                        .foregroundColor(.pfRoyal)
                                        .fixedSize(horizontal: true, vertical: false)
                                } else {
                                    Text("\(result.correct) correct")
                                        .font(.pfCaptionBold)
                                        .foregroundColor(.pfRoyal)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                        }
                        if quizResults.contains(where: { $0.fraction == nil }) {
                            Text("Some older results recorded only the number correct, with no total.")
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if quizResults.count > 5 {
                            Button(showAllQuizResults ? "Show fewer quiz results" : "Show all quiz results") {
                                showAllQuizResults.toggle()
                            }
                            .font(.pfCallout)
                            .fontWeight(.semibold)
                            .foregroundColor(.pfRoyal)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Competency (from recorded assessments only)

    /// Competency by dimension, from CompetencyStore. A dimension with
    /// no assessment shows "Not assessed yet", never a made-up score.
    /// The ring shows the overall score only when at least one
    /// assessment has been recorded.
    @ObservedObject private var competencyStore = CompetencyStore.shared

    private var competencySection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Competency")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    if competencyStore.hasAssessments {
                        HStack(spacing: PFSpacing.lg) {
                            PFProgressRing(progress: competencyStore.overallScore / 100, size: 110, color: .pfRoyal)
                            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                                Text("\(Int(competencyStore.overallScore.rounded()))% overall")
                                    .font(.pfSectionTitle)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Level: \(competencyStore.overallLevel)")
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("From recorded assessments only.")
                                    .font(.pfCaption)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        Text("No assessments taken yet")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Take an assessment below to earn a competency score. Nothing is shown until you do.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(CompetencyStore.CompetencyDimension.allCases, id: \.self) { dimension in
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            HStack(spacing: PFSpacing.sm) {
                                Image(systemName: dimension.systemImage)
                                    .foregroundColor(.pfRoyal)
                                Text(dimension.rawValue)
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                if let score = competencyStore.score(for: dimension) {
                                    Text("\(Int(score.rounded()))%")
                                        .font(.pfCaptionBold)
                                        .foregroundColor(.pfRoyal)
                                        .fixedSize(horizontal: true, vertical: false)
                                } else {
                                    Text("Not assessed yet")
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                            PFProgressBar(progress: (competencyStore.score(for: dimension) ?? 0) / 100, height: 6)
                            if let insight = dimensionInsights.first(where: { $0.dimension == dimension }) {
                                if let average = insight.quizAverageFraction {
                                    Text("Lesson quizzes in this area: average \(Int((average * 100).rounded()))% across \(insight.quizAttemptsWithTotal) \(insight.quizAttemptsWithTotal == 1 ? "attempt" : "attempts"). \(insight.lessonsCompleted > 0 ? "\(insight.lessonsCompleted) of \(insight.lessonsTotal) lessons completed, \(insight.demonstratedLessonCount) demonstrated at 80% or above." : "No lessons completed in this area yet.")")
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else {
                                    Text("No lesson quiz attempts with a recorded total in this area yet. \(insight.lessonsCompleted > 0 ? "\(insight.lessonsCompleted) of \(insight.lessonsTotal) lessons completed." : "No lessons completed in this area yet.")")
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if insight.quizAttemptsWithoutTotal > 0 {
                                    Text("\(insight.quizAttemptsWithoutTotal) older \(insight.quizAttemptsWithoutTotal == 1 ? "attempt recorded" : "attempts recorded") only the number correct, with no total, so they are not in the average.")
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            NavigationLink(destination: AssessmentView(dimension: dimension)) {
                                Text(competencyStore.score(for: dimension) == nil ? "Take the \(dimension.shortName) assessment" : "Retake the \(dimension.shortName) assessment")
                                    .font(.pfCallout)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.pfRoyal)
                                    .padding(.horizontal, PFSpacing.md)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .background(Color.pfRoyal.opacity(0.08))
                                    .cornerRadius(PFSpacing.cornerRadius)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Learning tools

    /// Revision Centre, Daily Challenge, My Notes and Certificates.
    /// Revision due count is real, from RevisionService.
    @ObservedObject private var revisionService = RevisionService.shared
    @ObservedObject private var notesStore = NotesStore.shared

    private var learningToolsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Learning tools")
            NavigationLink(destination: RevisionCentreView()) {
                toolRow(
                    title: "Revision Centre",
                    subtitle: revisionService.dueToday.isEmpty
                        ? "Nothing due for revision today"
                        : "\(revisionService.dueToday.count) \(revisionService.dueToday.count == 1 ? "concept" : "concepts") due for revision today",
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(PFCardButtonStyle())
            NavigationLink(destination: DailyChallengeView()) {
                toolRow(
                    title: "Daily Challenge",
                    subtitle: "One real situation a day, 3 to 5 minutes",
                    systemImage: "bolt.fill"
                )
            }
            .buttonStyle(PFCardButtonStyle())
            NavigationLink(destination: NotesView()) {
                toolRow(
                    title: "My Notes",
                    subtitle: notesStore.allNotes().isEmpty
                        ? "No notes yet"
                        : "\(notesStore.allNotes().count) \(notesStore.allNotes().count == 1 ? "note" : "notes") saved on this device",
                    systemImage: "note.text"
                )
            }
            .buttonStyle(PFCardButtonStyle())
            NavigationLink(destination: CertificatesListView()) {
                toolRow(
                    title: "Certificates",
                    subtitle: "Path certificates and course certificates from Final Assessments",
                    systemImage: "seal.fill"
                )
            }
            .buttonStyle(PFCardButtonStyle())
        }
    }

    private func toolRow(title: String, subtitle: String, systemImage: String) -> some View {
        PFCard {
            HStack(spacing: PFSpacing.md) {
                PFIconTile(systemImage: systemImage, size: 44)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(title)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.pfSecondaryText)
            }
        }
    }

    // MARK: - Learning pathways progress

    private var pathwaysSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Learning Journeys")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    ForEach(LearningPath.all) { path in
                        let lessonProgress = path.progress(in: progressStore, service: contentService)
                        // The recorded path completion wins when the
                        // app has recorded one; otherwise the real
                        // lesson completion for the path is shown.
                        let recorded = progressStore.pathCompletion(pathID: path.id)
                        let percent: Int = {
                            if let recorded {
                                return recorded
                            } else if lessonProgress.total > 0 {
                                return Int((Double(lessonProgress.completed) / Double(lessonProgress.total) * 100).rounded())
                            } else {
                                return 0
                            }
                        }()
                        NavigationLink(destination: PathDetailView(path: path)) {
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                HStack(spacing: PFSpacing.sm) {
                                    Text(path.title)
                                        .font(.pfBody)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    Text("\(percent)%")
                                        .font(.pfCaptionBold)
                                        .foregroundColor(.pfRoyal)
                                        .fixedSize(horizontal: true, vertical: false)
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.pfSecondaryText)
                                }
                                Text("\(lessonProgress.completed) of \(lessonProgress.total) lessons complete")
                                    .font(.pfCaption)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(demonstratedCount(in: path.lessons(in: contentService))) demonstrated on quizzes at 80% or above.")
                                    .font(.pfCaption)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                PFProgressBar(progress: Double(percent) / 100, height: 6)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recent learning history

    private var recentHistorySection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Recent learning")
            if recentCompletions.isEmpty {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("No learning history yet")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Your most recent lessons will appear here once you start learning.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                ForEach(recentCompletions) { event in
                    PFCard {
                        VStack(alignment: .leading, spacing: PFSpacing.sm) {
                            Text(event.lessonTitle ?? lessonTitle(for: event.lessonID ?? ""))
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(event.timestamp, format: .dateTime.day().month().hour().minute())
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                            if let id = event.lessonID,
                               let entry = contentService.allLessons.first(where: { $0.id == id }) {
                                NavigationLink(destination: LessonView(entry: entry)) {
                                    Text("Open lesson")
                                        .font(.pfBody)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.pfRoyal)
                                        .cornerRadius(PFSpacing.cornerRadius)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recommended next lessons

    private var recommendedSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Recommended next lessons")
            if contentService.isLoadingIndex && recommendedLessons.isEmpty && contentService.searchIndex == nil {
                PFLoadingView(message: "Loading recommendations...")
            } else if recommendedLessons.isEmpty {
                PFCard {
                    Text(contentService.searchIndex == nil ? "Lessons will appear here once the course catalogue has loaded." : "You have completed every lesson in the catalogue.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(recommendedLessons) { lesson in
                    NavigationLink(destination: LessonView(entry: lesson)) {
                        LessonRow(entry: lesson)
                    }
                    .buttonStyle(PFCardButtonStyle())
                }
            }
        }
    }

    // MARK: - Progress backup

    /// The short readable backup, reachable by guests too. The complete
    /// JSON export (account, profile, full history, preferences) lives
    /// in Profile; the two serve different purposes and both are kept.
    private var backupSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Progress backup")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text("Share a readable backup to keep a copy somewhere safe. It lists your completed lessons, quiz attempts, streak and learning time, and does not include your name or email.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                    ShareLink(item: progressStore.backupText()) {
                        Label("Share progress backup", systemImage: "square.and.arrow.up")
                            .font(.pfBody)
                            .fontWeight(.semibold)
                            .foregroundColor(.pfRoyal)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.pfRoyal.opacity(0.08))
                            .cornerRadius(PFSpacing.cornerRadius)
                    }
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Text("Reset all progress")
                            .font(.pfBody)
                            .fontWeight(.semibold)
                            .foregroundColor(.pfError)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    // MARK: - My purchases

    private var purchasesSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "My purchases")
            Button {
                showCheckout = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Payment Situations")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("View enrolment and payment")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(.callout, design: .default).weight(.semibold))
                        .foregroundColor(.pfSecondaryText)
                }
                .padding(PFSpacing.lg)
                .background(Color.pfCard)
                .cornerRadius(PFSpacing.cardRadius)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Payment Situations. View enrolment and payment")
        }
    }
}

