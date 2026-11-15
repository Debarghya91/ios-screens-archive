// HomeView.swift
// Payments Training Hub iOS - Home tab, personalised to the mockup.
// Native SwiftUI only, no WebView. Uses the shared DesignSystem.
// No em dashes in any user-facing text.
//
// Section order on this screen: greeting, then a dashboard that
// depends on the learner. A new learner (no completed lessons)
// sees a welcome with their chosen objective, one recommended
// lesson with its reason, a recommended route card, the daily
// challenge, one practical exercise, and progress. A returning
// learner sees resume learning first, then the active path, the
// daily challenge, weak areas from real evidence, and progress.
// Both then get one collapsed "Explore" disclosure holding the
// guided sessions, interview questions, daily revision,
// the practice experiences, recent lessons and
// certification (plus Practice Mode
// for returning learners, who do not see it above Explore).
// Home never overwhelms: the dashboard is the path, Explore is
// one tap away. The learning habit section sits between progress
// and Explore for both new and returning learners. Guest is the default: the screen works fully as
// a guest and never blocks on sign-in. The greeting shows a name
// only when a user is actually signed in
// (AuthService.currentUser); as a guest it says "Learner".

import SwiftUI
import Foundation

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore

    /// Concepts due for revision today, from the shared revision
    /// service. The count drives the Daily Revision card; when it is
    /// zero the card says so honestly instead of inventing a number.
    @ObservedObject private var revisionService = RevisionService.shared

    /// The onboarding profile, when the learner has been through
    /// onboarding. Home only reads it, to personalise the welcome,
    /// the recommendation and the route.
    @ObservedObject private var onboardingStore = OnboardingStore.shared

    /// The learner's active path, when one is set. Home only reads
    /// it; the paths screens set it.
    @ObservedObject private var activePathStore = ActivePathStore.shared

    /// Recorded competency scores, for the weak areas section. A
    /// dimension appears only after an assessment recorded a score.
    @ObservedObject private var competencyStore = CompetencyStore.shared

    /// The same shared auth service the sign-in screens use. Nil
    /// currentUser means a guest; the greeting then shows no name.
    @StateObject private var authService = AuthService.shared

    /// Presents the profile as a sheet, matching the drawer path.
    /// ProfileView owns its own NavigationStack, so pushing it
    /// with a NavigationLink nests two stacks: the inner bar
    /// replaces the outer one, the pushed Profile has no Back
    /// button, and pushes and gestures behave unreliably.
    @State private var showProfileSheet = false

    /// Opens the side drawer. Passed in from the tab bar so the menu
    /// button can sit in this screen's navigation bar, and only here:
    /// pushed detail views have no menu button and keep a clean back button.
    @Binding var isDrawerOpen: Bool

    /// Optional tab selection, for the quick links row. MainTabView
    /// passes $selectedTab, so the tiles switch tabs. (The old
    /// comment saying it did not pass it yet was stale.)
    var selectedTab: Binding<Int>?

    init(isDrawerOpen: Binding<Bool>, selectedTab: Binding<Int>? = nil) {
        self._isDrawerOpen = isDrawerOpen
        self.selectedTab = selectedTab
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.xxl) {
                    loadStateView

                    greetingSection

                    if isReturningLearner {
                        resumeLessonSection

                        activePathSection

                        dailyChallengeSection

                        reviewWeakAreasSection

                        yourProgressSection

                        habitSection

                        exploreSection(includePractice: true)
                    } else {
                        primaryRecommendationSection

                        recommendedRouteSection

                        dailyChallengeSection

                        practiceExerciseSection

                        yourProgressSection

                        habitSection

                        exploreSection(includePractice: false)
                    }
                }
                .padding(20)
                .id("homeTop")
            }
            .pfScrollToTopOnAppear("homeTop")
            .background(Color.pfBackground)
            // Extra scrollable space at the bottom so the last card clears
            // the tab bar on every iPhone size.
            .pfTabBarClearance()
            .navigationTitle("Payments Training Hub")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    DrawerMenuButton(isDrawerOpen: $isDrawerOpen)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showProfileSheet = true } label: {
                        avatarView
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open your profile").accessibilityHint("Opens your profile, separate from My Progress")
                }
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileView()
            }
        }
    }

    // MARK: - Loading and error

    @ViewBuilder
    private var loadStateView: some View {
        if contentService.isShowingCachedContent {
            PFOfflineBanner()
        }
        if contentService.indexError != nil {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text("Could not load the course catalogue")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    Text("Check your connection and try again. Your progress is saved on this device.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                    PFPrimaryButton(title: "Retry") {
                        Task { await contentService.loadSearchIndex() }
                    }
                }
            }
        } else if contentService.isLoadingIndex && contentService.searchIndex == nil {
            HStack(spacing: PFSpacing.sm) {
                ProgressView()
                Text("Loading the course catalogue...")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Greeting

    /// Time-based greeting. The name appears only when a user is
    /// signed in and has a display name; guests get "Learner" so
    /// the greeting never ends in a trailing space. Hours are
    /// covered honestly: night is night, not evening.
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let base: String
        switch hour {
        case 5..<12: base = "Good morning"
        case 12..<17: base = "Good afternoon"
        case 17..<22: base = "Good evening"
        default: base = "Good night"
        }
        if authService.isSignedIn,
           let fullName = authService.currentUser?.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fullName.isEmpty,
           let firstName = fullName.split(separator: " ").first {
            return "\(base), \(firstName)"
        }
        return "\(base), Learner"
    }

    /// Hero card: deep navy gradient with the greeting in white,
    /// the date and tagline below, and a subtle bank illustration
    /// drawn from SF Symbols. Each line has its own size, weight
    /// and lightness, so the greeting, date, tagline, welcome and
    /// supporting lines read as separate levels instead of one
    /// flat block. The greeting shows a name only when a
    /// user is actually signed in; guests get the greeting alone.
    /// The avatar in the navigation bar (top right) opens Profile.
    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            Text(greetingText + " 👋")
                .font(.pfScreenTitle)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(greetingText)
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide).year())
                .font(.pfCaptionBold)
                .foregroundColor(.white.opacity(0.70))
                .fixedSize(horizontal: false, vertical: true)
            Text("Master the world of payments, one lesson at a time.")
                .font(.pfSectionTitle)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            // New learners get a welcome line. The chosen objective
            // shows only when the learner chose a profile; a skipped
            // profile or no profile gets the generic line, which
            // names only some of the free value: the free
            // Payment Cases and the browsable catalogue. The free
            // sample lesson (first lesson of each chapter) also
            // exists; the greeting simply does not name it.
            if isNewLearner {
                Text("Welcome to Payments Training Hub.")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let profile = effectiveProfile {
                Text("Your goal: \(profile.objective.displayTitle)")
                    .font(.pfCallout)
                    .foregroundColor(.white.opacity(0.80))
                    .fixedSize(horizontal: false, vertical: true)
            } else if isNewLearner {
                Text("Browse the Payment Cases free and explore the full catalogue.")
                    .font(.pfCallout)
                    .foregroundColor(.white.opacity(0.80))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: PFSpacing.md) {
                Image(systemName: "building.columns.fill")
                    .font(.system(.title2, design: .default))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(.title3, design: .default))
                    .foregroundColor(.pfGold)
                    .accessibilityHidden(true)
                Image(systemName: "creditcard.fill")
                    .font(.system(.title2, design: .default))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                Spacer()
                Text("Payments Training Hub")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfNavy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.pfGold)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
            }
        }
        .padding(PFSpacing.lg)
        .background(Color.pfHeroGradient)
        .cornerRadius(PFSpacing.cardRadius)
        .shadow(color: Color.pfNavy.opacity(0.20), radius: 16, x: 0, y: 8)
    }

    // MARK: - Learning plan

    /// The guided session the learner is currently in, derived from
    /// the next lesson the plan points to, so the pill and the next
    /// step below can never disagree. Nil when the whole guided
    /// path is complete or the catalogue has not loaded.
    private var currentGuidedSession: GuidedSession? {
        guard let next = nextGuidedLesson else { return nil }
        return ContentService.guidedSessions.first { session in
            PFChapterHelper.lessons(forSession: session, in: contentService)
                .contains { $0.id == next.id }
        }
    }

    /// The next uncompleted lesson across the guided path, in session
    /// order. Nil when the path is complete or nothing has loaded.
    private var nextGuidedLesson: SearchEntry? {
        for session in ContentService.guidedSessions {
            let lessons = PFChapterHelper.lessons(forSession: session, in: contentService)
            if let next = lessons.first(where: { !progressStore.isLessonComplete($0.id) }) {
                return next
            }
        }
        return nil
    }

    /// The 8-session plan, each session with its correct sequential
    /// number and its own progress, so the plan never reads as a
    /// single "Session 1". The current session is marked; tapping
    /// any session opens it. The next lesson itself lives in the
    /// Resume or Recommended card above, so this section is the
    /// plan only, not a second Continue button.
    private var learningPlanSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFHomeSectionHeader(title: "Your 8 sessions", systemImage: "list.number", accent: .royal)
            if contentService.searchIndex == nil && contentService.allLessons.isEmpty {
                PFHomeStripeCard(accent: .royal) {
                    Text("Your learning plan will appear here once the catalogue loads.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if nextGuidedLesson == nil {
                PFHomeStripeCard(accent: .royal) {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("You have finished the guided path")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Revisit any lesson from Learn, or practise with the Payment Cases.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                PFHomeStripeCard(accent: .royal) {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        ForEach(ContentService.guidedSessions) { session in
                            NavigationLink(destination: GuidedPathDetailView(session: session)) {
                                learningPlanSessionRow(for: session)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(learningPlanAccessibilityLabel(for: session))
                            .accessibilityHint("Opens the session")
                        }
                    }
                }
            }
        }
    }

    /// Completed and total lessons for one guided session, from the
    /// real catalogue and real progress.
    private func guidedSessionProgress(for session: GuidedSession) -> (completed: Int, total: Int) {
        let lessons = PFChapterHelper.lessons(forSession: session, in: contentService)
        let completed = lessons.filter { progressStore.isLessonComplete($0.id) }.count
        return (completed, lessons.count)
    }

    /// Accessibility label for one learning plan row, with the real
    /// progress fraction so progress is never colour-only.
    private func learningPlanAccessibilityLabel(for session: GuidedSession) -> String {
        let progress = guidedSessionProgress(for: session)
        if progress.total > 0 {
            return "Session \(session.id): \(session.title), \(progress.completed) of \(progress.total) lessons complete"
        }
        return "Session \(session.id): \(session.title)"
    }

    /// One row of the learning plan session list: the session's
    /// sequential number, title and progress, with the current
    /// session marked.
    private func learningPlanSessionRow(for session: GuidedSession) -> some View {
        let progress = guidedSessionProgress(for: session)
        let isCurrent = currentGuidedSession?.id == session.id
        return HStack(alignment: .top, spacing: PFSpacing.md) {
            Text("\(session.id)")
                .font(.pfBody.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(isCurrent ? Color.pfRoyal : Color.pfSecondaryText)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                HStack(spacing: PFSpacing.sm) {
                    Text("Session \(session.id)")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                    if isCurrent {
                        PFPill(text: "Current", background: Color.pfGoldSoft, foreground: .pfNavy)
                    }
                }
                Text(session.title)
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                if progress.total > 0 {
                    Text("\(progress.completed) of \(progress.total) lessons complete")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    PFProgressBar(progress: Double(progress.completed) / Double(progress.total), height: 6)
                } else {
                    Text(session.description)
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.pfSecondaryText)
                .padding(.top, PFSpacing.xs)
        }
    }

    // MARK: - Dashboard personalisation

    /// A returning learner has finished at least one lesson, or has
    /// a last lesson recorded. Everyone else is a new learner, with
    /// or without an onboarding profile.
    private var isReturningLearner: Bool {
        !progressStore.completedLessonIDs.isEmpty || progressStore.lastLessonID != nil
    }

    private var isNewLearner: Bool { !isReturningLearner }

    /// The onboarding profile when the learner chose it. A skipped
    /// profile is treated as no profile: its role and objective were
    /// never chosen, so Home falls back to the guided path and the
    /// fundamentals route instead of presenting defaults as choices.
    private var effectiveProfile: OnboardingProfile? {
        guard let profile = onboardingStore.profile, !profile.wasSkipped else { return nil }
        return profile
    }

    /// The weekly lesson target for estimates: the onboarding target
    /// when the learner chose one, otherwise the goal stored in
    /// ProgressStore. Home never writes the goal.
    private var weeklyTargetForEstimates: Int {
        if let profile = effectiveProfile, profile.weeklyTarget > 0 {
            return profile.weeklyTarget
        }
        return progressStore.weeklyGoal
    }

    // MARK: - Primary recommendation (new learners)

    /// The one primary recommendation for a new learner: the engine's
    /// pick when a chosen profile exists, otherwise the next guided
    /// lesson with a plain statement of where it sits in the path.
    /// The reason is always shown next to the lesson, never hidden.
    private var primaryRecommendation: (lesson: SearchEntry, reason: String)? {
        if let profile = effectiveProfile,
           let pick = RecommendationEngine.nextLesson(for: profile, progress: progressStore, competency: competencyStore, service: contentService) {
            return (lesson: pick.lesson, reason: pick.reason)
        }
        if let entry = continueEntry {
            return (lesson: entry, reason: "Start here: the first unfinished lesson of the guided path.")
        }
        return nil
    }

    /// The single primary recommendation card for a new learner, with
    /// the reason shown in full. Tapping opens the lesson; when the
    /// lesson is locked, the lesson screen's own lock handling
    /// applies and nothing here bypasses it.
    private var primaryRecommendationSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFHomeSectionHeader(title: "Recommended for you", systemImage: "sparkles", accent: .gold)
            if let recommendation = primaryRecommendation {
                NavigationLink(destination: LessonView(entry: recommendation.lesson)) {
                    PFHomeTabCard(accent: .gold) {
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
                                    if let duration = LessonDurations.label(for: recommendation.lesson.id) {
                                        Text(duration)
                                            .font(.pfCaption)
                                            .foregroundColor(.pfSecondaryText)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Text(recommendation.reason)
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Start this lesson")
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
                .accessibilityLabel("Recommended lesson: \(recommendation.lesson.title)")
                .accessibilityHint("Opens the recommended lesson")
            } else {
                PFHomeTabCard(accent: .gold) {
                    Text("Your first recommendation will appear here once the catalogue loads.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Recommended route (new learners)

    /// The role route for the learner's chosen role, when one exists.
    private var roleRoute: RoleRoute? {
        guard let profile = effectiveProfile else { return nil }
        return RoleRouteCatalogue.route(for: profile.role)
    }

    /// The guided path the route card points at: the route's path
    /// when it names one that exists, otherwise the fundamentals
    /// path for learners with no chosen profile.
    private var recommendedPath: LearningPath? {
        if let pathID = roleRoute?.pathID,
           let path = LearningPath.all.first(where: { $0.id == pathID }) {
            return path
        }
        if effectiveProfile == nil {
            return LearningPath.all.first(where: { $0.id == "fundamentals" }) ?? LearningPath.all.first
        }
        return nil
    }

    /// The guided sessions the route card points at when no path
    /// resolves: the route's sessions when it names any that exist,
    /// otherwise the first guided session.
    private var recommendedSessions: [GuidedSession] {
        if let route = roleRoute, !route.sessionIDs.isEmpty {
            let found = ContentService.guidedSessions.filter { route.sessionIDs.contains($0.id) }
            if !found.isEmpty { return found }
        }
        if let first = ContentService.guidedSessions.first {
            return [first]
        }
        return []
    }

    /// Every lesson the recommended route covers, in order, from the
    /// live catalogue. Empty while the catalogue is loading.
    private var recommendedRouteLessons: [SearchEntry] {
        if let path = recommendedPath {
            return path.lessons(in: contentService)
        }
        var seen: Set<String> = []
        var result: [SearchEntry] = []
        for session in recommendedSessions {
            for lesson in PFChapterHelper.lessons(forSession: session, in: contentService) {
                if seen.insert(lesson.id).inserted { result.append(lesson) }
            }
        }
        return result
    }

    /// The first unfinished lesson of the recommended route, or the
    /// first lesson when the route is complete. Nil while the
    /// catalogue is loading.
    private var recommendedRouteEntryLesson: SearchEntry? {
        let lessons = recommendedRouteLessons
        return lessons.first(where: { !progressStore.isLessonComplete($0.id) }) ?? lessons.first
    }

    /// Whole weeks the route takes at the learner's weekly target,
    /// rounded up. Nil when the count or the target is not known.
    private var recommendedRouteWeeks: Int? {
        let total = recommendedRouteLessons.count
        let target = weeklyTargetForEstimates
        guard total > 0, target > 0 else { return nil }
        return (total + target - 1) / target
    }

    private var recommendedRouteWeeksText: String? {
        guard let weeks = recommendedRouteWeeks else { return nil }
        let target = weeklyTargetForEstimates
        let weekWord = weeks == 1 ? "week" : "weeks"
        let lessonWord = target == 1 ? "lesson" : "lessons"
        return "About \(weeks) \(weekWord) at \(target) \(lessonWord) a week"
    }

    private var recommendedRouteTitle: String {
        if let path = recommendedPath { return path.title }
        if let route = roleRoute { return route.title }
        return recommendedSessions.first?.title ?? "Your learning path"
    }

    private var recommendedRouteDescription: String {
        if let path = recommendedPath { return path.description }
        if let route = roleRoute { return route.description }
        return recommendedSessions.first?.description ?? ""
    }

    /// The recommended route card for a new learner: the role route
    /// for a chosen profile, otherwise the fundamentals path. The
    /// lesson count comes from the live catalogue and the weeks
    /// estimate from that count and the weekly target. Tapping the
    /// card opens the route detail.
    private var recommendedRouteSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFHomeSectionHeader(title: "Your recommended route", systemImage: "map.fill", accent: .royal)
            if contentService.searchIndex == nil && contentService.allLessons.isEmpty {
                PFHomeStripeCard(accent: .royal) {
                    Text("Your recommended route will appear here once the catalogue loads.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let path = recommendedPath {
                NavigationLink(destination: PathDetailView(path: path)) {
                    recommendedRouteCardContent
                }
                .buttonStyle(PFCardButtonStyle())
                .accessibilityLabel("Recommended route: \(recommendedRouteTitle)")
                .accessibilityHint("Opens the \(recommendedRouteTitle) path")
            } else if let session = recommendedSessions.first {
                NavigationLink(destination: GuidedPathDetailView(session: session)) {
                    recommendedRouteCardContent
                }
                .buttonStyle(PFCardButtonStyle())
                .accessibilityLabel("Recommended route: \(recommendedRouteTitle)")
                .accessibilityHint("Opens Session \(session.id), \(session.title)")
            } else {
                PFHomeStripeCard(accent: .royal) {
                    Text("Your recommended route will appear here once the catalogue loads.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var recommendedRouteCardContent: some View {
        PFHomeStripeCard(accent: .royal) {
            HStack(alignment: .top, spacing: PFSpacing.md) {
                PFIconTile(systemImage: "map.fill", size: 44)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(recommendedRouteTitle)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    if !recommendedRouteDescription.isEmpty {
                        Text(recommendedRouteDescription)
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if recommendedRouteLessons.count > 0 {
                        Text("\(recommendedRouteLessons.count) lessons")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let weeksText = recommendedRouteWeeksText {
                        Text(weeksText)
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let entry = recommendedRouteEntryLesson {
                        Text("Start with: \(entry.title)")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.pfSecondaryText)
                    .padding(.top, PFSpacing.xs)
            }
        }
    }

    // MARK: - Resume learning (returning learners)

    /// The lesson a returning learner resumes: the most recent
    /// unfinished lesson they opened, otherwise the next unfinished
    /// lesson in the guided path. It never points back at a lesson
    /// just finished unless that lesson is the only one recorded.
    private var resumeEntry: SearchEntry? {
        if let recent = recentUnfinishedLessons.first { return recent }
        if let next = continueEntry { return next }
        if let lastID = progressStore.lastLessonID {
            return contentService.allLessons.first(where: { $0.id == lastID })
        }
        return nil
    }

    /// The guided session holding the resume lesson, when it is in
    /// the guided path.
    private var resumeSession: GuidedSession? {
        guard let entry = resumeEntry else { return nil }
        return session(containing: entry.id)
    }

    /// Position of the resume lesson inside its session, 1-based.
    private var resumeLessonPosition: Int {
        guard let entry = resumeEntry, let session = resumeSession else { return 0 }
        let lessons = PFChapterHelper.lessons(forSession: session, in: contentService)
        return (lessons.firstIndex { $0.id == entry.id } ?? 0) + 1
    }

    /// Progress inside the resume lesson's session, from real
    /// completion data.
    private var resumeSessionProgress: (completed: Int, total: Int) {
        guard let session = resumeSession else { return (0, 0) }
        return guidedSessionProgress(for: session)
    }

    /// True when the resume lesson is one the learner already opened
    /// but did not finish, so the button reads Resume rather than
    /// Continue.
    private var isResumingOpenedLesson: Bool {
        guard let entry = resumeEntry else { return false }
        return recentUnfinishedLessons.first?.id == entry.id
    }

    /// The first card for a returning learner: the lesson to resume,
    /// with its session, position and session progress. This is the
    /// old "Up next" hero, moved first for returning learners and
    /// pointed at the most recent unfinished lesson when there is
    /// one.
    private var resumeLessonSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFHomeSectionHeader(title: "Resume learning", systemImage: "play.fill", accent: .gold)
            if let entry = resumeEntry {
                NavigationLink(destination: LessonView(entry: entry)) {
                    PFHomeTabCard(accent: .gold) {
                        VStack(alignment: .leading, spacing: PFSpacing.md) {
                            HStack(spacing: PFSpacing.md) {
                                PFIconTile(systemImage: "play.fill", size: 52)
                                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                    if let session = resumeSession {
                                        Text("Session \(session.id) of \(ContentService.guidedSessions.count): \(session.title)")
                                            .font(.pfCaptionBold)
                                            .foregroundColor(.pfRoyal)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Text(entry.title)
                                        .font(.pfCardTitle)
                                        .foregroundColor(.pfNavy)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(PFChapterHelper.chapterTitle(for: entry))
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .lineLimit(1)
                                    if resumeSessionProgress.total > 0 {
                                        Text("Lesson \(resumeLessonPosition) of \(resumeSessionProgress.total) in this session")
                                            .font(.pfCaptionBold)
                                            .foregroundColor(.pfRoyal)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if resumeSessionProgress.total > 0 {
                                PFProgressBar(progress: Double(resumeSessionProgress.completed) / Double(resumeSessionProgress.total))
                            }
                            Text(isResumingOpenedLesson ? "Resume lesson" : "Continue")
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
                .accessibilityLabel("Resume learning: \(entry.title)")
                .accessibilityHint("Opens the lesson to continue learning")
            } else {
                PFHomeTabCard(accent: .gold) {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("Your next lesson is on its way")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("The course catalogue is still loading. Once it appears, your next lesson will show here.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Continue the active path (returning learners)

    /// The learning path the returning learner is continuing: the
    /// active path when one is set, otherwise the path named by the
    /// learner's role route. Home only reads the active path;
    /// setting it happens on the paths screens.
    private var activeLearningPath: LearningPath? {
        if let activeID = activePathStore.activePathID,
           let path = LearningPath.all.first(where: { $0.id == activeID }) {
            return path
        }
        if let pathID = roleRoute?.pathID,
           let path = LearningPath.all.first(where: { $0.id == pathID }) {
            return path
        }
        return nil
    }

    /// The guided session the returning learner is continuing when
    /// no learning path resolves: the first route session with an
    /// unfinished lesson, otherwise the current guided session.
    private var activeGuidedSession: GuidedSession? {
        if activeLearningPath != nil { return nil }
        for session in recommendedSessions {
            let lessons = PFChapterHelper.lessons(forSession: session, in: contentService)
            if lessons.contains(where: { !progressStore.isLessonComplete($0.id) }) {
                return session
            }
        }
        return currentGuidedSession
    }

    /// The lessons of the active path or session, from the live
    /// catalogue. Empty while the catalogue is loading.
    private var activePathLessons: [SearchEntry] {
        if let path = activeLearningPath {
            return path.lessons(in: contentService)
        }
        guard let session = activeGuidedSession else { return [] }
        return PFChapterHelper.lessons(forSession: session, in: contentService)
    }

    private var activePathProgress: (completed: Int, total: Int) {
        let lessons = activePathLessons
        return (lessons.filter { progressStore.isLessonComplete($0.id) }.count, lessons.count)
    }

    private var activePathNextLesson: SearchEntry? {
        activePathLessons.first(where: { !progressStore.isLessonComplete($0.id) })
    }

    private var activePathTitle: String {
        if let path = activeLearningPath { return path.title }
        if let session = activeGuidedSession { return "Session \(session.id): \(session.title)" }
        return "Your learning path"
    }

    private var activePathPercentText: String {
        guard activePathProgress.total > 0 else { return "0%" }
        let fraction = Double(activePathProgress.completed) / Double(activePathProgress.total)
        return "\(Int((fraction * 100).rounded()))%"
    }

    /// The active path card for a returning learner: the path or
    /// session title, the next incomplete lesson, and the progress
    /// fraction from live data. The card opens the path detail; the
    /// button below it opens the next lesson directly.
    private var activePathSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFHomeSectionHeader(title: "Continue your path", systemImage: "arrow.right.circle.fill", accent: .royal)
            if contentService.searchIndex == nil && contentService.allLessons.isEmpty {
                PFHomeTopBarCard(accent: .royal) {
                    Text("Your path will appear here once the catalogue loads.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if activeLearningPath == nil && activeGuidedSession == nil {
                PFHomeTopBarCard(accent: .royal) {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("You have finished the guided path")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Revisit any lesson from Learn, or practise with the Payment Cases.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                activePathDetailCard
                if let next = activePathNextLesson {
                    NavigationLink(destination: LessonView(entry: next)) {
                        Text("Start next lesson: \(next.title)")
                            .font(.pfBody.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.pfRoyal)
                            .cornerRadius(PFSpacing.cornerRadius)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start next lesson: \(next.title)")
                    .accessibilityHint("Opens the next lesson on your path")
                }
            }
        }
    }

    /// The active path card, linking to the path or session detail.
    @ViewBuilder
    private var activePathDetailCard: some View {
        if let path = activeLearningPath {
            NavigationLink(destination: PathDetailView(path: path)) {
                activePathCardContent
            }
            .buttonStyle(PFCardButtonStyle())
            .accessibilityLabel("Continue your path: \(path.title)")
            .accessibilityHint("Opens the \(path.title) path")
        } else if let session = activeGuidedSession {
            NavigationLink(destination: GuidedPathDetailView(session: session)) {
                activePathCardContent
            }
            .buttonStyle(PFCardButtonStyle())
            .accessibilityLabel("Continue your path: Session \(session.id), \(session.title)")
            .accessibilityHint("Opens Session \(session.id), \(session.title)")
        } else {
            EmptyView()
        }
    }

    private var activePathCardContent: some View {
        PFHomeTopBarCard(accent: .royal) {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                HStack(alignment: .top, spacing: PFSpacing.md) {
                    PFIconTile(systemImage: "map.fill", size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text(activePathTitle)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        if activePathProgress.total > 0 {
                            Text("\(activePathProgress.completed) of \(activePathProgress.total) lessons complete")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.pfSecondaryText)
                        .padding(.top, PFSpacing.xs)
                }
                if activePathProgress.total > 0 {
                    HStack(spacing: PFSpacing.sm) {
                        PFProgressBar(progress: Double(activePathProgress.completed) / Double(activePathProgress.total), height: 6)
                        Text(activePathPercentText)
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfNavy)
                    }
                }
                if let next = activePathNextLesson {
                    Text("Next: \(next.title)")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else if activePathProgress.total > 0 {
                    Text("Every lesson on this path is complete.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Review weak areas (returning learners)

    /// The lowest scored competency dimension, from recorded
    /// assessments only. Nil when no assessment has been recorded.
    private var weakestDimension: (dimension: CompetencyStore.CompetencyDimension, score: Double)? {
        competencyStore.scores.min(by: { $0.value < $1.value })
            .map { (dimension: $0.key, score: $0.value) }
    }

    /// Lessons with the lowest average quiz scores, lowest first.
    /// Only lessons with a recorded quiz average and a catalogue
    /// entry appear. At most three. Raw quiz counts are never used
    /// on their own: without the total, a count says nothing about
    /// how well the learner did.
    private var weakestQuizLessons: [(lesson: SearchEntry, average: Double, attempts: Int)] {
        var scored: [(lesson: SearchEntry, average: Double, attempts: Int)] = []
        for lessonID in progressStore.quizScores.keys {
            guard let average = progressStore.averageQuizScore(for: lessonID),
                  let lesson = contentService.allLessons.first(where: { $0.id == lessonID }) else { continue }
            let attempts = progressStore.quizHistory[lessonID]?.count ?? 0
            scored.append((lesson: lesson, average: average, attempts: attempts))
        }
        scored.sort { $0.average < $1.average }
        return Array(scored.prefix(3))
    }

    /// Revision concepts the learner keeps getting wrong, resolved
    /// to lessons where possible. Only concepts not already listed
    /// as weakest quiz lessons appear, at most three.
    private var weakRevisionLessons: [SearchEntry] {
        let listed = Set(weakestQuizLessons.map { $0.lesson.id })
        var result: [SearchEntry] = []
        for concept in revisionService.weakConcepts {
            guard !listed.contains(concept.id) else { continue }
            guard let lesson = contentService.allLessons.first(where: { $0.id == concept.id }) else { continue }
            result.append(lesson)
            if result.count >= 3 { break }
        }
        return result
    }

    /// True when any real evidence of a weak area exists: a recorded
    /// competency score, a recorded quiz average, or a weak revision
    /// concept. Nothing is shown as weak without evidence.
    private var hasWeakAreaEvidence: Bool {
        weakestDimension != nil || !weakestQuizLessons.isEmpty || !revisionService.weakConcepts.isEmpty
    }

    /// Weak areas for a returning learner, from real evidence only:
    /// the lowest assessed dimension, the weakest quiz lessons, and
    /// the revision concepts the learner keeps getting wrong. With
    /// no evidence the section shows an honest empty state instead
    /// of inventing a weak area.
    private var reviewWeakAreasSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFHomeSectionHeader(title: "Review weak areas", systemImage: "arrow.clockwise", accent: .navy)
            if !hasWeakAreaEvidence {
                NavigationLink(destination: RevisionCentreView()) {
                    PFHomeTopBarCard(accent: .navy) {
                        HStack(spacing: PFSpacing.md) {
                            PFIconTile(systemImage: "arrow.clockwise", size: 44)
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                Text("No weak areas yet")
                                    .font(.pfCardTitle)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Finish a lesson quiz or an assessment and the areas to review will show here. You can schedule revision for finished lessons in the Revision Centre.")
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
                .accessibilityLabel("No weak areas yet. Open the Revision Centre")
                .accessibilityHint("Opens the Revision Centre")
            } else {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    if let weakest = weakestDimension {
                        NavigationLink(destination: AssessmentView(dimension: weakest.dimension)) {
                            PFHomeTopBarCard(accent: .navy) {
                                HStack(spacing: PFSpacing.md) {
                                    PFIconTile(systemImage: weakest.dimension.systemImage, size: 44)
                                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                        Text(weakest.dimension.rawValue)
                                            .font(.pfCardTitle)
                                            .foregroundColor(.pfNavy)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text("Lowest assessed area: \(Int(weakest.score.rounded()))% across your recorded assessments. Retake the assessment to improve it.")
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
                        .accessibilityLabel("Weakest area: \(weakest.dimension.rawValue), \(Int(weakest.score.rounded())) percent")
                        .accessibilityHint("Opens the assessment for \(weakest.dimension.rawValue)")
                    }
                    ForEach(weakestQuizLessons.indices, id: \.self) { index in
                        weakQuizLessonRow(
                            lesson: weakestQuizLessons[index].lesson,
                            average: weakestQuizLessons[index].average,
                            attempts: weakestQuizLessons[index].attempts
                        )
                    }
                    ForEach(weakRevisionLessons) { lesson in
                        NavigationLink(destination: LessonView(entry: lesson)) {
                            PFHomeTopBarCard(accent: .navy) {
                                HStack(spacing: PFSpacing.md) {
                                    PFIconTile(systemImage: "arrow.clockwise", size: 44)
                                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                        Text(lesson.title)
                                            .font(.pfCardTitle)
                                            .foregroundColor(.pfNavy)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text("This lesson keeps coming up wrong in revision. Revisit it, then review it again in the Revision Centre.")
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
                        .accessibilityLabel("Weak revision lesson: \(lesson.title)")
                        .accessibilityHint("Opens the lesson to review it")
                    }
                    if weakestDimension == nil && weakestQuizLessons.isEmpty && weakRevisionLessons.isEmpty && !revisionService.weakConcepts.isEmpty {
                        NavigationLink(destination: RevisionCentreView()) {
                            PFHomeTopBarCard(accent: .navy) {
                                HStack(spacing: PFSpacing.md) {
                                    PFIconTile(systemImage: "arrow.clockwise", size: 44)
                                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                        Text("Concepts to review")
                                            .font(.pfCardTitle)
                                            .foregroundColor(.pfNavy)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text("\(revisionService.weakConcepts.count) concepts you keep getting wrong are waiting in the Revision Centre.")
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
                        .accessibilityLabel("Concepts to review in the Revision Centre")
                        .accessibilityHint("Opens the Revision Centre")
                    }
                }
            }
        }
    }

    /// One weakest-quiz-lesson row, with the real average and the
    /// real attempt count. Kept as a function so the section does
    /// not need a key path into a tuple.
    private func weakQuizLessonRow(lesson: SearchEntry, average: Double, attempts: Int) -> some View {
        let percent = Int((average * 100).rounded())
        let attemptWord = attempts == 1 ? "attempt" : "attempts"
        return NavigationLink(destination: LessonView(entry: lesson)) {
            PFHomeTopBarCard(accent: .navy) {
                HStack(spacing: PFSpacing.md) {
                    PFIconTile(systemImage: "questionmark.circle.fill", size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text(lesson.title)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Quiz average \(percent)% over \(attempts) \(attemptWord). Revisit the lesson and retake the quiz.")
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
        .accessibilityLabel("Weak quiz lesson: \(lesson.title), quiz average \(percent) percent")
        .accessibilityHint("Opens the lesson to review it and retake the quiz")
    }

    // MARK: - Interview questions

    /// Situation-based interview questions for payments and BA
    /// roles, with a model answer for each. Placed near the
    /// learning plan and Continue sections so it is easy to find.
    private var interviewSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFHomeSectionHeader(title: "Interview Questions", systemImage: "briefcase.fill", accent: .navy)
            NavigationLink(destination: InterviewQuestionsView()) {
                PFCard {
                    HStack(spacing: PFSpacing.md) {
                        PFIconTile(systemImage: "briefcase.fill", size: 44)
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text("Interview Questions")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(ContentManifest.interviewQuestionCount) situation-based payments and BA interview questions, each with a model answer.")
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
            .accessibilityLabel("Interview Questions")
            .accessibilityHint("Opens \(ContentManifest.interviewQuestionCount) situation-based payments and BA interview questions")
        }
    }

    // MARK: - Daily Revision

    /// Concepts due for revision today, from the shared revision
    /// service. Zero means nothing is due, and the card says so.
    private var dueRevisionCount: Int {
        revisionService.dueToday.count
    }

    /// Accessibility hint for the Daily Revision card, with the real
    /// due count when anything is due.
    private var dailyRevisionHint: String {
        if dueRevisionCount > 0 {
            return "Opens the Revision Centre with \(dueRevisionCount) concepts due"
        }
        return "Opens the Revision Centre, nothing is due today"
    }

    private var dailyRevisionSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFHomeSectionHeader(title: "Daily Revision", systemImage: "arrow.triangle.2.circlepath", accent: .gold)
            NavigationLink(destination: RevisionCentreView()) {
                PFCard {
                    HStack(spacing: PFSpacing.md) {
                        PFIconTile(systemImage: "arrow.clockwise", size: 44)
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text("Daily Revision")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(dueRevisionCount > 0 ? "\(dueRevisionCount) concepts due" : "Nothing due today")
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
            .accessibilityLabel("Daily Revision")
            .accessibilityHint(dailyRevisionHint)
        }
    }

    // MARK: - Daily Challenge

    /// A fresh case every day. No challenge title is exposed by the
    /// challenge screen, so the card shows "Today's case" rather than
    /// inventing a title.
    private var dailyChallengeSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFHomeSectionHeader(title: "Daily Challenge", systemImage: "bolt.fill", accent: .gold)
            NavigationLink(destination: DailyChallengeView()) {
                PFHomeStripeCard(accent: .gold) {
                    HStack(spacing: PFSpacing.md) {
                        PFIconTile(systemImage: "bolt.fill", size: 44)
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text("Daily Challenge")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Today's case")
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
            .accessibilityLabel("Daily Challenge")
            .accessibilityHint("Opens today's challenge case")
        }
    }

    // MARK: - Practice experiences

    /// The four practice experiences: the Payment Simulator, the
    /// ISO 20022 Explorer, the Exception Lab and the BA/PO Studio.
    /// They live inside Explore for both new and returning
    /// learners, so every learner reaches them from one place, and
    /// they are not repeated anywhere else on Home. Each row opens
    /// its experience directly. No counts in the copy: the
    /// experiences carry no catalogue counts.
    private var practiceExperiencesSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFHomeSectionHeader(title: "Practice experiences", systemImage: "square.grid.2x2.fill", accent: .royal)
            NavigationLink(destination: PaymentLifecycleSimulatorView()) {
                practiceExperienceCard(
                    title: "Payment Simulator",
                    subtitle: "Follow a payment through its lifecycle, step by step",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .buttonStyle(PFCardButtonStyle())
            .accessibilityLabel("Payment Simulator")
            .accessibilityHint("Opens the Payment Simulator")
            NavigationLink(destination: ISO20022ExplorerView()) {
                practiceExperienceCard(
                    title: "ISO 20022 Explorer",
                    subtitle: "Look up ISO 20022 messages and their fields",
                    systemImage: "doc.text.magnifyingglass"
                )
            }
            .buttonStyle(PFCardButtonStyle())
            .accessibilityLabel("ISO 20022 Explorer")
            .accessibilityHint("Opens the ISO 20022 Explorer")
            NavigationLink(destination: ExceptionInvestigationLabView()) {
                practiceExperienceCard(
                    title: "Exception Lab",
                    subtitle: "Investigate payment exceptions and trace what went wrong",
                    systemImage: "exclamationmark.triangle.fill"
                )
            }
            .buttonStyle(PFCardButtonStyle())
            .accessibilityLabel("Exception Lab")
            .accessibilityHint("Opens the Exception Lab")
            NavigationLink(destination: BAProductStudioView()) {
                practiceExperienceCard(
                    title: "BA/PO Studio",
                    subtitle: "Draft BA and PO deliverables for payment work",
                    systemImage: "square.and.pencil"
                )
            }
            .buttonStyle(PFCardButtonStyle())
            .accessibilityLabel("BA/PO Studio")
            .accessibilityHint("Opens the BA/PO Studio")
        }
    }

    /// One practice experience row: icon tile, title, subtitle and
    /// chevron, matching the Interview Questions cards on this screen.
    private func practiceExperienceCard(title: String, subtitle: String, systemImage: String) -> some View {
        PFHomeStripeCard(accent: .royal) {
            HStack(spacing: PFSpacing.md) {
                PFIconTile(systemImage: systemImage, size: 44)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(title)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
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

    /// Circular avatar at the top right, matching the mockup: the
    /// signed-in user's initial on royal blue, or a generic person
    /// icon for guests. Tapping it opens Profile.
    private var avatarView: some View {
        Group {
            if authService.isSignedIn,
               let fullName = authService.currentUser?.displayName?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !fullName.isEmpty,
               let first = fullName.first {
                Text(String(first))
                    .font(.pfBody.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.pfRoyal)
                    .clipShape(Circle())
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.pfScreenTitle.weight(.regular))
                    .foregroundColor(.pfRoyal)
            }
        }
    }

    // MARK: - Continue helpers

    private var firstGuidedLesson: SearchEntry? {
        guard let session = ContentService.guidedSessions.first else { return nil }
        return PFChapterHelper.lessons(forSession: session, in: contentService).first
            ?? contentService.allLessons.first
    }

    /// The lesson the resume and recommendation cards fall back to:
    /// the next unfinished lesson in session order. Only when the
    /// whole guided path is complete does it fall back to the first
    /// lesson. It never points back at the lesson just finished.
    private var continueEntry: SearchEntry? {
        nextGuidedLesson ?? firstGuidedLesson
    }

    /// The guided session holding one lesson, when the lesson is in
    /// the guided path. Nil for lessons outside the path.
    private func session(containing lessonID: String) -> GuidedSession? {
        ContentService.guidedSessions.first { session in
            PFChapterHelper.lessons(forSession: session, in: contentService)
                .contains { $0.id == lessonID }
        }
    }

    // MARK: - Explore

    /// Everything that is not the dashboard's main flow, behind one
    /// "Explore" disclosure. The daily challenge and progress live
    /// above Explore now, so they are not repeated here. Practice
    /// Mode is included only for returning learners: new learners
    /// already see the practice exercise above, so repeating it here
    /// would duplicate the card. The practice experiences sit here
    /// for both new and returning learners, so every learner
    /// reaches them from one place.
    /// Certification stays here for both,
    /// so it is always one tap away. Nothing is deleted: the tab bar
    /// is the door to Learn, Search, Payment Cases and My Progress,
    /// so the old quick-link tiles that duplicated it are gone.
    private func exploreSection(includePractice: Bool) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: PFSpacing.xl) {
                learningPlanSection
                interviewSection
                dailyRevisionSection
                practiceExperiencesSection
                recentLessonsSection
                if includePractice {
                    practiceExerciseSection
                }
                certificationSection
            }
            .padding(.top, PFSpacing.md)
        } label: {
            HStack(spacing: PFSpacing.md) {
                Image(systemName: "compass.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.pfRoyal)
                    .frame(width: 32, height: 32)
                    .background(Color.pfRoyal.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: PFSpacing.smallRadius))
                    .accessibilityHidden(true)
                Text("Explore")
                Spacer()
            }
        }
        .font(.pfCardTitle)
        .foregroundColor(.pfNavy)
        .padding(PFSpacing.md)
        .background(Color.pfCard)
        .cornerRadius(PFSpacing.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                .stroke(Color.pfRoyal.opacity(0.35), lineWidth: 1)
        )
        .accessibilityHint("Expands to show guided sessions, interview questions, daily revision, practice experiences, recent lessons and certification")
    }

    // MARK: - Learning habit

    /// The learning habit cards: today's small goal, the weekly
    /// target, the question of the day, the weekly investigation
    /// challenge, revision reminders, weak-area recommendations
    /// and milestones. Placed between progress and Explore for
    /// both new and returning learners. The section reads its own
    /// stores and removes no existing destination. The soft panel
    /// groups its cards into one distinct block; the habit header
    /// itself lives in HabitViews.swift and is unchanged here.
    private var habitSection: some View {
        HabitSectionView()
            .padding(PFSpacing.md)
            .background(Color.pfNavySoft)
            .cornerRadius(PFSpacing.cardRadius)
    }

    // MARK: - Your Progress

    /// Progress in the current session, not the whole catalogue.
    /// The ring shows "Session X, A of B lessons", never a
    /// whole-catalogue fraction against ContentManifest.lessonCount
    /// with 0%. While the catalogue is still loading it says so instead
    /// of flashing 0%. A new user sees a neutral "No active streak"
    /// baseline, not a missing streak.
    private var yourProgressSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            if let tabBinding = selectedTab {
                PFHomeSectionHeader(
                    title: "Your Progress",
                    systemImage: "chart.bar.fill",
                    accent: .navy,
                    actionTitle: "My Progress",
                    action: { tabBinding.wrappedValue = 4 }
                )
            } else {
                PFHomeSectionHeader(title: "Your Progress", systemImage: "chart.bar.fill", accent: .navy)
            }
            PFHomeTopBarCard(accent: .navy) {
                if contentService.searchIndex == nil && contentService.allLessons.isEmpty {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("Your progress will appear here once the catalogue loads.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(spacing: PFSpacing.md) {
                        VStack(spacing: PFSpacing.sm) {
                            PFProgressRing(progress: sessionProgressFraction, size: 104, color: .pfRoyal)
                            Text(sessionProgressLabel)
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfNavy)
                            Text(sessionProgressDetail)
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: PFSpacing.sm) {
                            HStack(spacing: PFSpacing.sm) {
                                Image(systemName: "target")
                                    .font(.pfCardTitle.weight(.semibold))
                                    .foregroundColor(.pfRoyal)
                                Text("Learning Goal")
                                    .font(.pfCardTitle)
                                    .foregroundColor(.pfNavy)
                            }
                            Text("\(progressStore.lessonsCompletedThisWeek) of \(progressStore.weeklyGoal) lessons this week")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            PFProgressBar(progress: progressStore.weeklyProgress)
                            if progressStore.streakCount > 0 {
                                Label("\(progressStore.streakCount) day streak", systemImage: "flame.fill")
                                    .font(.pfCaptionBold)
                                    .foregroundColor(.pfSecondaryText)
                            } else {
                                Label("No active streak", systemImage: "flame")
                                    .font(.pfCaptionBold)
                                    .foregroundColor(.pfSecondaryText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// Progress in the current session as a fraction, for the ring.
    private var sessionProgressFraction: Double {
        guard let session = currentGuidedSession else { return 0 }
        let progress = guidedSessionProgress(for: session)
        guard progress.total > 0 else { return 0 }
        return Double(progress.completed) / Double(progress.total)
    }

    /// "Session 1" or "All sessions" for the ring label.
    private var sessionProgressLabel: String {
        if let session = currentGuidedSession {
            return "Session \(session.id) of \(ContentService.guidedSessions.count)"
        }
        return "Guided path complete"
    }

    /// "2 of 12 lessons" for the current session.
    private var sessionProgressDetail: String {
        guard let session = currentGuidedSession else {
            return "\(progressStore.totalLessonsCompleted) lessons complete"
        }
        let progress = guidedSessionProgress(for: session)
        return "\(progress.completed) of \(progress.total) lessons"
    }

    // MARK: - Pick up where you left off

    /// The top 3 most recently opened lessons that are not marked
    /// complete, most recent first. Only real catalogue entries,
    /// from the persisted recent-open list.
    @ObservedObject private var recentLessonsStore = RecentLessonsStore.shared

    private var recentUnfinishedLessons: [SearchEntry] {
        let entries = recentLessonsStore.lessonIDs.compactMap { id in
            contentService.allLessons.first(where: { $0.id == id })
        }
        return Array(entries.filter { !progressStore.isLessonComplete($0.id) }.prefix(3))
    }

    private var recentLessonsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFHomeSectionHeader(title: "Pick up where you left off", systemImage: "clock.fill", accent: .navy)
            if recentUnfinishedLessons.isEmpty {
                PFCard {
                    Text("Open a lesson and it will show up here so you can pick it up later.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(recentUnfinishedLessons) { lesson in
                    NavigationLink(destination: LessonView(entry: lesson)) {
                        LessonRow(entry: lesson)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PFCardButtonStyle())
                    .accessibilityLabel("Pick up: \(lesson.title)")
                    .accessibilityHint("Opens the lesson")
                }
            }
        }
    }

    // MARK: - Practice Mode and Certification

    /// All situations, full data first and search index fallback,
    /// so Practice Mode can draw its distractors from real takeaways.
    private var practiceSituations: [Situation] {
        if let full = contentService.fullSituations, !full.isEmpty {
            return full.map { situation(fromFull: $0) }
        }
        return contentService.allSituations.map { situation(from: $0) }
    }

    /// The first practice-eligible situation, or the first
    /// situation when none is eligible yet.
    private var firstPracticeSituation: Situation? {
        let all = practiceSituations
        return all.first { PracticeModeBuilder.isEligible($0, in: all) } ?? all.first
    }

    /// One practical exercise: the first practice-eligible
    /// situation, or the first situation when none is eligible yet.
    /// New learners see this above Explore; returning learners see
    /// it inside Explore. The card always opens Practice Mode with
    /// the full situation list, so distractors come from real
    /// takeaways. When no situation has loaded yet the section says
    /// so honestly instead of showing a card that goes nowhere.
    private var practiceExerciseSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFHomeSectionHeader(title: "Practise with a real case", systemImage: "flask.fill", accent: .royal)
            if let situation = firstPracticeSituation {
                NavigationLink(destination: PracticeModeView(situation: situation, allSituations: practiceSituations)) {
                    PFHomeTopBarCard(accent: .royal) {
                        HStack(spacing: PFSpacing.md) {
                            PFIconTile(systemImage: "flask.fill", size: 44)
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                Text("Practice Mode")
                                    .font(.pfCardTitle)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(situation.title)
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Test yourself on real payment scenarios")
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
                .buttonStyle(PFCardButtonStyle())
                .accessibilityLabel("Practice Mode: \(situation.title)")
                .accessibilityHint("Opens Practice Mode with this payment case")
            } else {
                PFHomeTopBarCard(accent: .royal) {
                    Text("Practice exercises will appear here once the catalogue loads.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Certification: pass a Final Assessment and earn a verified
    /// certificate. The card opens the certificates list. It lives
    /// inside Explore for both new and returning learners.
    private var certificationSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFHomeSectionHeader(title: "Certification", systemImage: "seal.fill", accent: .gold)
            NavigationLink(destination: CertificatesListView()) {
                highlightCard(
                    title: "Certification",
                    subtitle: "Pass a Final Assessment and earn a verified certificate",
                    systemImage: "seal.fill"
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PFCardButtonStyle())
            .accessibilityLabel("Certification")
            .accessibilityHint("Opens your certificates and Final Assessments")
        }
    }

    private func highlightCard(title: String, subtitle: String, systemImage: String) -> some View {
        PFHomeTabCard(accent: .gold) {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                PFIconTile(systemImage: systemImage, size: 44)
                Text(title)
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Home section headers and card treatments

/// The visual system that keeps Home sections differentiable.
/// Every section header pairs an icon tile with a short accent bar
/// and a full width hairline, and every dashboard card carries one
/// of three accent treatments: a tab on the top edge, a stripe on
/// the leading edge, or a bar inset from the top edge. Accents are
/// semantic, not decorative: gold marks the one lesson to start,
/// royal marks the journey and the tools, navy marks review and
/// progress. All colours come from the DesignSystem tokens; no new
/// colours are introduced here. Single link rows inside Explore
/// keep the plain PFCard so the dashboard cards read as primary.
private enum PFHomeSectionAccent {
    case gold
    case royal
    case navy

    /// The accent colour for the header bar and the card treatment.
    var accent: Color {
        switch self {
        case .gold: return .pfGold
        case .royal: return .pfRoyal
        case .navy: return .pfNavy
        }
    }

    /// The icon colour on the tinted tile. Gold uses the darker gold
    /// text token so the small icon stays legible on a light tile.
    var iconForeground: Color {
        switch self {
        case .gold: return .pfGoldText
        case .royal: return .pfRoyal
        case .navy: return .pfNavy
        }
    }

    /// The soft tint behind the header icon.
    var tint: Color {
        switch self {
        case .gold: return .pfGoldSoft
        case .royal: return Color.pfRoyal.opacity(0.10)
        case .navy: return .pfNavySoft
        }
    }

    /// The card border colour for this accent, drawn over the plain
    /// PFCard border so the card keeps its shape and shadow.
    var border: Color {
        switch self {
        case .gold: return Color.pfGold.opacity(0.55)
        case .royal: return Color.pfRoyal.opacity(0.45)
        case .navy: return Color.pfNavy.opacity(0.30)
        }
    }
}

/// A Home section header: an icon tile, the title, an optional
/// trailing action, and an accent bar over a hairline rule. The
/// icon and accent differ per section; the title text is unchanged.
private struct PFHomeSectionHeader: View {
    let title: String
    let systemImage: String
    let accent: PFHomeSectionAccent
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            HStack(spacing: PFSpacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(accent.iconForeground)
                    .frame(width: 32, height: 32)
                    .background(accent.tint)
                    .clipShape(RoundedRectangle(cornerRadius: PFSpacing.smallRadius))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.pfSectionTitle)
                    .foregroundColor(.pfNavy)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.pfCallout).fontWeight(.semibold)
                        .foregroundColor(.pfRoyal)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            HStack(spacing: 0) {
                Capsule()
                    .fill(accent.accent)
                    .frame(width: 36, height: 3)
                Rectangle()
                    .fill(Color.pfBorder)
                    .frame(height: 1)
            }
        }
    }
}

/// A card with a short accent tab straddling its top edge, for the
/// one lesson to start: the recommendation and the resume card.
/// Wraps PFCard, so padding, shape and shadow are unchanged.
private struct PFHomeTabCard<Content: View>: View {
    let accent: PFHomeSectionAccent
    let content: Content

    init(accent: PFHomeSectionAccent, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        PFCard { content }
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                    .stroke(accent.border, lineWidth: 1.5)
            )
            .overlay(alignment: .topLeading) {
                Capsule()
                    .fill(accent.accent)
                    .frame(width: 44, height: 5)
                    .padding(.leading, PFSpacing.lg)
                    .offset(y: -2)
            }
    }
}

/// A card with an accent stripe on its leading edge, for journey
/// and tool cards: the route, the daily challenge and the practice
/// experiences. Wraps PFCard, so padding, shape and shadow are
/// unchanged.
private struct PFHomeStripeCard<Content: View>: View {
    let accent: PFHomeSectionAccent
    let content: Content

    init(accent: PFHomeSectionAccent, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        PFCard { content }
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                    .stroke(accent.border, lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(accent.accent)
                    .frame(width: 5)
                    .padding(.vertical, PFSpacing.md)
                    .padding(.leading, 2)
            }
    }
}

/// A card with an accent bar inset from its top edge, for path,
/// review and progress cards. Wraps PFCard, so padding, shape and
/// shadow are unchanged.
private struct PFHomeTopBarCard<Content: View>: View {
    let accent: PFHomeSectionAccent
    let content: Content

    init(accent: PFHomeSectionAccent, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        PFCard { content }
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                    .stroke(accent.border, lineWidth: 1)
            )
            .overlay(alignment: .top) {
                Capsule()
                    .fill(accent.accent)
                    .frame(height: 3)
                    .padding(.horizontal, PFSpacing.lg)
                    .padding(.top, 2)
            }
    }
}

// MARK: - Guided session card (horizontal scroll)

/// A compact guided-session card for the Home horizontal scroll:
/// number, title, lesson count and a progress bar.
struct GuidedSessionCard: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    let session: GuidedSession

    private var lessons: [SearchEntry] {
        PFChapterHelper.lessons(forSession: session, in: contentService)
    }

    private var completedCount: Int {
        lessons.filter { progressStore.isLessonComplete($0.id) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            HStack(spacing: PFSpacing.sm) {
                Text("\(session.id)")
                    .font(.pfBody.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.pfRoyal)
                    .clipShape(Circle())
                Text("Session \(session.id)")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfRoyal)
                Spacer()
            }
            Text(session.title)
                .font(.pfCardTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Text(session.description)
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text("\(lessons.count) lessons")
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
            if !lessons.isEmpty {
                PFProgressBar(progress: Double(completedCount) / Double(lessons.count), height: 6)
            }
        }
        .frame(width: 250, alignment: .leading)
        .padding(PFSpacing.lg)
        .background(Color.pfCard)
        .cornerRadius(PFSpacing.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                .stroke(Color.pfBorder, lineWidth: 1)
        )
        .shadow(color: Color.pfNavy.opacity(0.08), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Home library card (horizontal scroll)

/// A compact Guides/Labs/Tests card for the Home horizontal scroll.
struct HomeLibraryCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            PFIconTile(systemImage: systemImage, size: 44)
            Text(title)
                .font(.pfCardTitle)
                .foregroundColor(.pfNavy)
            Text(subtitle)
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            HStack(spacing: PFSpacing.xs) {
                Text("Open")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfRoyal)
                Image(systemName: "chevron.right")
                    .font(.pfCaption.weight(.semibold))
                    .foregroundColor(.pfRoyal)
            }
        }
        .frame(width: 200, alignment: .leading)
        .padding(PFSpacing.lg)
        .background(Color.pfCard)
        .cornerRadius(PFSpacing.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                .stroke(Color.pfBorder, lineWidth: 1)
        )
        .shadow(color: Color.pfNavy.opacity(0.08), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Guided session row

struct GuidedSessionRow: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    let session: GuidedSession

    private var lessons: [SearchEntry] {
        PFChapterHelper.lessons(forSession: session, in: contentService)
    }

    var body: some View {
        PFCard {
            HStack(alignment: .top, spacing: PFSpacing.md) {
                Text("\(session.id)")
                    .font(.pfCardTitle.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.pfRoyal)
                    .clipShape(Circle())
                    .shadow(color: Color.pfRoyal.opacity(0.35), radius: 6, x: 0, y: 3)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(session.title)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(session.description)
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(session.chapterIDs.count) chapters, \(lessons.count) lessons")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                        .fixedSize(horizontal: false, vertical: true)
                    if !lessons.isEmpty {
                        PFProgressBar(
                            progress: Double(lessons.filter { progressStore.isLessonComplete($0.id) }.count) / Double(lessons.count),
                            height: 6
                        )
                        .padding(.top, PFSpacing.xs)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.pfSecondaryText)
                    .padding(.top, PFSpacing.xs)
            }
        }
    }
}

// MARK: - Guided path detail

/// Lists the lessons of one guided session, with completion checkmarks
/// and a Continue button for the next uncompleted lesson.
struct GuidedPathDetailView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    let session: GuidedSession

    @State private var visibleCount: Int = 20

    private static let pageSize = 20

    private var lessons: [SearchEntry] {
        PFChapterHelper.lessons(forSession: session, in: contentService)
    }

    private var visibleLessons: [SearchEntry] {
        Array(lessons.prefix(visibleCount))
    }

    private var completedCount: Int {
        lessons.filter { progressStore.isLessonComplete($0.id) }.count
    }

    /// The next lesson to continue with: the first uncompleted lesson,
    /// or the first lesson when the session is fully complete.
    private var nextLesson: SearchEntry? {
        lessons.first(where: { !progressStore.isLessonComplete($0.id) }) ?? lessons.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text(session.description)
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                    if !lessons.isEmpty {
                        Text("\(completedCount) of \(lessons.count) lessons complete")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                        PFProgressBar(progress: lessons.isEmpty ? 0 : Double(completedCount) / Double(lessons.count))
                    }
                }
                if let next = nextLesson {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("Up next")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                        Text(next.title)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        if let position = PFChapterHelper.readingPositionLabel(for: next, in: contentService) {
                            Text(position)
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                        }
                        NavigationLink(destination: LessonView(entry: next)) {
                            Text(completedCount == lessons.count ? "Review again" : "Continue")
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
                if contentService.isLoadingIndex && lessons.isEmpty {
                    ProgressView("Loading lessons...")
                } else if lessons.isEmpty {
                    Text("No lessons are available for this session yet. Check your connection and try again.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                }
                ForEach(visibleLessons) { lesson in
                    NavigationLink(destination: LessonView(entry: lesson)) {
                        LessonRow(entry: lesson)
                    }
                    .buttonStyle(PFCardButtonStyle())
                }
                if lessons.count > visibleLessons.count {
                    Text("Showing \(visibleLessons.count) of \(lessons.count) lessons")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PFSecondaryButton(title: "Load more lessons") {
                        visibleCount += Self.pageSize
                    }
                }
            }
            .padding(PFSpacing.lg)
            .id("guidedPathTop")
        }
        .pfScrollToTopOnAppear("guidedPathTop")
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .onChange(of: lessons) { _, _ in
            visibleCount = Self.pageSize
        }
        .navigationTitle("Session \(session.id): \(session.title)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Lesson row

struct LessonRow: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var storeManager: StoreManager
    let entry: SearchEntry
    /// True when the row sits in a chapter list and shows the
    /// lesson number inside the chapter ("Lesson 3"). Other
    /// callers leave it off: without chapter context the number
    /// alone would confuse.
    var showsLessonNumber: Bool = false

    /// True when this lesson's chapter is not unlocked: neither the
    /// part containing it nor the Integrated Course is owned.
    private var isLocked: Bool {
        guard let number = PFChapterHelper.chapterNumber(from: entry.id) else { return false }
        return !storeManager.isChapterUnlocked("ch\(number)")
    }

    /// True when this lesson is free without any purchase: the
    /// first lesson of its chapter, or one of its part's
    /// sequential free samples. Free with full content even when
    /// the chapter is locked.
    private var isFreeSample: Bool {
        PFChapterHelper.isFreeLesson(entry, in: contentService)
    }

    var body: some View {
        PFCard {
            HStack(spacing: PFSpacing.md) {
                ZStack {
                    PFIconTile(
                        systemImage: progressStore.isLessonComplete(entry.id) ? "checkmark" : "play.fill",
                        size: 44
                    )
                    if progressStore.isLessonComplete(entry.id) {
                        Circle()
                            .fill(Color.pfSuccess)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.pfCaption.weight(.bold))
                                    .foregroundColor(.white)
                            )
                            .offset(x: 16, y: -16)
                    }
                }
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    if showsLessonNumber, let position = PFBookModeReadingOrder.displayNumber(forLessonID: entry.id) ?? contentService.lessonPositionInChapter(for: entry) {
                        Text("Lesson \(position)")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                    }
                    Text(entry.title)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.preview)
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let duration = LessonDurations.label(for: entry.id) {
                        HStack(spacing: PFSpacing.xs) {
                            Image(systemName: "clock")
                                .font(.pfCaption.weight(.semibold))
                            Text(duration)
                                .font(.pfCaption)
                        }
                        .foregroundColor(.pfSecondaryText)
                    }
                    if isLocked && isFreeSample {
                        HStack(spacing: PFSpacing.xs) {
                            Image(systemName: "gift.fill")
                                .font(.pfCaption.weight(.semibold))
                            Text("Free sample")
                                .font(.pfCaptionBold)
                        }
                        .foregroundColor(.pfSuccess)
                    } else if isLocked {
                        HStack(spacing: PFSpacing.xs) {
                            Image(systemName: "lock.fill")
                                .font(.pfCaption.weight(.semibold))
                            Text("Premium")
                                .font(.pfCaptionBold)
                        }
                        .foregroundColor(.pfGold)
                    }
                    PFProgressBar(
                        progress: progressStore.isLessonComplete(entry.id) ? 1 : 0,
                        height: 6
                    )
                    .padding(.top, PFSpacing.xs)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.pfSecondaryText)
            }
        }
    }
}

