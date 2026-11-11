// DashboardView.swift
// PaymentForge iOS - My Progress: learning analytics.
// Native SwiftUI only, no WebView.
// Adaptive layout: flexible stacks and cards that reflow on every iPhone
// width, from the small iPhone SE to a Pro Max, in portrait and landscape.
// No fixed widths anywhere; every card uses maxWidth .infinity.
//
// Every number here comes from the event-based ProgressStore only:
// learningHours() sums recorded lesson and audio durations, never an
// estimate; weeklyActivity() counts recorded events per day; streak,
// lessons completed and quiz averages are all computed from recorded
// events. With no recorded events every statistic is zero or empty,
// and the screen says so honestly instead of showing a made-up
// number. No narration-length fetching, no invented totals.
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

    /// Opens the side drawer. Passed in from the tab bar so the menu
    /// button can sit in this screen's navigation bar, and only here:
    /// pushed detail views have no menu button and keep a clean back button.
    @Binding var isDrawerOpen: Bool

    /// Optional tab selection, for the empty-state action. MainTabView
    /// passes $selectedTab; without it the action navigates in-stack.
    var selectedTab: Binding<Int>?

    init(isDrawerOpen: Binding<Bool>, selectedTab: Binding<Int>? = nil) {
        self._isDrawerOpen = isDrawerOpen
        self.selectedTab = selectedTab
    }

    @State private var showCheckout = false
    @State private var showResetConfirmation = false
    @State private var selectedSegment: ProgressSegment = .overview

    private let goalOptions = [3, 5, 7, 10]

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
            return "No recorded listening time yet"
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

    /// Quiz results, best fraction correct per lesson, from recorded
    /// attempts only. Lessons with no total recorded are listed with
    /// their correct count and no percentage, never an invented one.
    private var quizResults: [(lessonID: String, correct: Int, fraction: Double?)] {
        progressStore.quizHistory
            .map { entry in
                (lessonID: entry.key,
                 correct: entry.value.map(\.correct).max() ?? 0,
                 fraction: progressStore.bestQuizScore(for: entry.key))
            }
            .sorted { $0.lessonID < $1.lessonID }
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.xl) {
                    headerSection

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
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: PFSpacing.xl)
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
                    progressStore.resetAll()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This clears completed lessons, quiz scores, your streak and your weekly progress on this device. It cannot be undone.")
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
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
            .accessibilityLabel("Streak, \(progressStore.streakCount) days")
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
                message: "Complete your first lesson and your progress, learning time and streak will appear here.",
                actionTitle: "Start learning",
                action: { selectedTab?.wrappedValue = 1 }
            )
        } else {
            learningProgressSection
            statsSection
            weeklyActivitySummarySection
            pathwaysSection
            recentHistorySection
            recommendedSection
        }
    }

    private var learningProgressSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Overall progress")
            PFCard {
                if contentService.searchIndex == nil {
                    PFLoadingView(message: "Loading your progress...")
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
                            if progressStore.totalLessonsCompleted == 0 {
                                Text("Complete your first lesson to start your progress.")
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

    private var weeklyActivitySummarySection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Weekly activity")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text("\(progressStore.lessonsCompletedThisWeek) of \(progressStore.weeklyGoal) lessons this week")
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
                action: { selectedTab?.wrappedValue = 1 }
            )
        } else {
            weeklyActivitySection
            weeklyGoalSection
            dailyActivitySection
        }
    }

    private var weeklyActivitySection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Weekly Activity")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text("\(progressStore.lessonsCompletedThisWeek) of \(progressStore.weeklyGoal) lessons this week")
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

    private var weeklyGoalSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Weekly goal")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text("\(progressStore.lessonsCompletedThisWeek) of \(progressStore.weeklyGoal) lessons this week")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    PFProgressBar(progress: progressStore.weeklyProgress)
                    Text("How many lessons do you want to finish each week?")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                    Picker("Lessons per week", selection: $progressStore.weeklyGoal) {
                        ForEach(goalOptions, id: \.self) { option in
                            Text("\(option)").tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Weekly goal in lessons")
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
                }
            }
        }
    }

    // MARK: - Assessments segment

    @ViewBuilder
    private var assessmentsContent: some View {
        if progressStore.totalQuizAttempts == 0 && !competencyStore.hasAssessments {
            PFEmptyStateView(
                systemImage: "checkmark.circle.fill",
                title: "No assessments yet",
                message: "Take a lesson quiz or a competency assessment and your scores will appear here.",
                actionTitle: "Start learning",
                action: { selectedTab?.wrappedValue = 1 }
            )
        } else {
            quizSection
            competencySection
        }
    }

    private var quizSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Quiz Performance")
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
                                Text("Averages come from recorded quiz attempts only.")
                                    .font(.pfCaption)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Divider()
                        ForEach(quizResults.prefix(5), id: \.lessonID) { result in
                            HStack(spacing: PFSpacing.md) {
                                Text(lessonTitle(for: result.lessonID))
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                if let fraction = result.fraction {
                                    Text("\(Int((fraction * 100).rounded()))% best")
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
                            NavigationLink(destination: AssessmentView(dimension: dimension)) {
                                Text("Take the \(dimension.shortName) assessment")
                                    .font(.pfCallout)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.pfRoyal)
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
            PFSectionHeader(title: "Learning Paths")
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
                            }
                            Text("\(lessonProgress.completed) of \(lessonProgress.total) lessons complete")
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
                    Text("You have completed every lesson in the catalogue.")
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

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Progress backup")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text("Your progress stays on this device. Share a backup to keep a copy somewhere safe.")
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

// MARK: - Compact progress summary (in-stack destination)

/// A compact progress summary, for places that link to My Progress
/// from inside another NavigationStack (for example the Home quick
/// links) where the My Progress tab itself cannot be pushed. It shows
/// the same real progress as My Progress, without the analytics
/// that need the full screen.
struct YourProgressDetailView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                PFCard {
                    if contentService.searchIndex == nil {
                        PFLoadingView(message: "Loading your progress...")
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
                            }
                        }
                    }
                }
                HStack(spacing: PFSpacing.sm) {
                    PFStatCard(
                        value: "\(progressStore.totalLessonsCompleted)",
                        label: "Lessons completed",
                        systemImage: "book.fill"
                    )
                    PFStatCard(
                        value: "\(progressStore.streakCount)",
                        label: "Day streak",
                        systemImage: "flame.fill"
                    )
                    PFStatCard(
                        value: "\(progressStore.totalQuizAttempts)",
                        label: "Quiz attempts",
                        systemImage: "checkmark.circle.fill"
                    )
                }
                Text("Full analytics live on the My Progress tab.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .navigationTitle("Your progress")
        .navigationBarTitleDisplayMode(.inline)
    }
}
