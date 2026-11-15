// HomeView.swift
// Payments Training Hub iOS - Home: the one place for browsing and
// starting lessons. Native SwiftUI only, no WebView. Uses the shared
// DesignSystem. No em dashes in any user-facing text.
//
// Section order on this screen: greeting, then the Continue learning
// block (where you left off plus your next lesson, one tap to
// continue), then the full course browsing (courses, learning
// journeys, catalogue), then Everything inside (the depth of the
// course and every capability, each linked). A returning learner
// then sees the daily challenge, weak areas from real evidence,
// progress and the learning habit; a new learner sees the progress
// starter state. Both end with one collapsed "Explore" disclosure.
// There is no separate Learn page: browsing lives here, and every
// route that used to open Learn lands on the browsing section below
// through HomeSectionTarget. The "path" abstraction is gone
// user-facing: journeys are called learning journeys, the chosen
// one is "Your journey", and the primary affordance names no
// concept at all, just the next lesson. Home never overwhelms: the
// dashboard is the next lesson, browsing is one scroll away.
// Guest is the default: the screen works fully as a guest and never
// blocks on sign-in. The greeting shows a name only when a user is
// actually signed in (AuthService.currentUser); as a guest it says
// "Learner".

import SwiftUI
import Foundation

// MARK: - Home section target

/// A Home section a route can land on. Drawer entries, the My
/// Progress "Start learning" actions, the tour's final step and the
/// Keep Learning card all route through MainTabView, which sets this
/// target and switches to the Home tab; Home scrolls to the section
/// and clears the target. `.learn` also selects the browsing
/// section, so "Choose your journey" lands on Learning Journeys.
/// User-facing wording only: code identifiers stay unchanged.
enum HomeSectionTarget: Equatable {
    case top
    case learn(LearnSection)
}

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

    /// The learner's chosen journey, when one is chosen. Home only
    /// reads it; the journey screens set it.
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

    /// The Home section an outside route wants to land on, set by
    /// MainTabView together with the tab switch. Home scrolls to it
    /// and clears it. Nil when no route is landing.
    var homeSectionTarget: Binding<HomeSectionTarget?>?

    /// Replays the guided tour, passed in from MainTabView. Home
    /// passes it to the Help sheet so Replay tour works from the
    /// capabilities list exactly as it does from the drawer.
    var onReplayTour: (() -> Void)?

    /// The browsing section selected in the embedded course
    /// browsing below. Owned here so capability rows, the journey
    /// buttons and outside routes can land on a chosen section.
    @State private var learnSection: LearnSection = .courses

    /// A scroll request raised inside Home (capability rows, journey
    /// buttons, section switches). The body observes it next to the
    /// ScrollViewReader proxy, scrolls, and clears it, so no view
    /// below the body ever holds a proxy.
    @State private var pendingScrollTarget: HomeSectionTarget?

    /// The capability sheet currently presented, if any: the
    /// destinations that own their own NavigationStack and so must
    /// be sheets, never pushes. Profile keeps its own bool below.
    @State private var capabilitySheet: CapabilitySheet?

    init(
        isDrawerOpen: Binding<Bool>,
        selectedTab: Binding<Int>? = nil,
        homeSectionTarget: Binding<HomeSectionTarget?>? = nil,
        onReplayTour: (() -> Void)? = nil
    ) {
        self._isDrawerOpen = isDrawerOpen
        self.selectedTab = selectedTab
        self.homeSectionTarget = homeSectionTarget
        self.onReplayTour = onReplayTour
    }

    /// The Home section an outside route asked for, flattened from
    /// the optional binding for onChange observation.
    private var externalTarget: HomeSectionTarget? {
        homeSectionTarget?.wrappedValue ?? nil
    }

    /// Scroll to a Home section through the reader proxy, deferred
    /// one runloop turn like PFScrollToTopModifier so the layout
    /// for a just-selected browsing section exists first.
    private func scrollToTarget(_ target: HomeSectionTarget, proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            switch target {
            case .top:
                proxy.scrollTo("homeTop", anchor: .top)
            case .learn:
                proxy.scrollTo("learnTop", anchor: .top)
            }
        }
    }

    /// Apply a landing target: select its browsing section when it
    /// names one, then scroll. Used for both outside routes and
    /// inside-Home requests, so every landing behaves the same.
    private func applyTarget(_ target: HomeSectionTarget, proxy: ScrollViewProxy) {
        if case .learn(let section) = target {
            learnSection = section
        }
        scrollToTarget(target, proxy: proxy)
    }

    /// Request a landing from inside Home: a capability row, a
    /// journey button, or the browse button. The body observes the
    /// pending target and scrolls to it.
    private func requestHomeSection(_ target: HomeSectionTarget) {
        pendingScrollTarget = target
    }

    /// Capability destinations that own their own NavigationStack
    /// and so present as sheets from Home, never as pushes.
    private enum CapabilitySheet: String, Identifiable {
        case checkout
        case appearance
        case about
        case help

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: PFSpacing.xxl) {
                        loadStateView

                        greetingSection

                        // One Home for every learner: the next lesson
                        // first, then browsing, then everything
                        // inside. Returning learners add challenge,
                        // weak areas, progress and habit below;
                        // newcomers get the progress starter state.
                        // No branch shows a second "next lesson"
                        // pointer: the Continue learning block is
                        // the only one.
                        continueLearningSection

                        browseSection

                        everythingInsideSection

                        if isReturningLearner {
                            dailyChallengeSection

                            reviewWeakAreasSection

                            yourProgressSection

                            habitSection

                            exploreSection(includePractice: true)
                        } else {
                            yourProgressSection

                            exploreSection(includePractice: false)
                        }
                    }
                    .padding(20)
                    .id("homeTop")
                }
                .background(Color.pfBackground)
                // Extra scrollable space at the bottom so the last card clears
                // the tab bar on every iPhone size.
                .pfTabBarClearance()
                .onAppear {
                    // The scroll rule: every entry opens at the top,
                    // unless an outside route asked for a section,
                    // in which case the landing wins over the top.
                    if let target = externalTarget {
                        applyTarget(target, proxy: proxy)
                        homeSectionTarget?.wrappedValue = nil
                    } else {
                        scrollToTarget(.top, proxy: proxy)
                    }
                }
                .onChange(of: externalTarget) { _, newTarget in
                    guard let newTarget else { return }
                    applyTarget(newTarget, proxy: proxy)
                    homeSectionTarget?.wrappedValue = nil
                }
                .onChange(of: pendingScrollTarget) { _, newTarget in
                    guard let newTarget else { return }
                    applyTarget(newTarget, proxy: proxy)
                    pendingScrollTarget = nil
                }
                .onChange(of: learnSection) { _, _ in
                    // Switching browsing sections returns to the
                    // browsing anchor, so the new section's content
                    // is visible at once instead of hidden below the
                    // previous scroll position.
                    scrollToTarget(.learn(learnSection), proxy: proxy)
                }
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
                .sheet(item: $capabilitySheet) { sheet in
                    switch sheet {
                    case .checkout:
                        CheckoutView()
                    case .appearance:
                        AppearanceSettingsView()
                    case .about:
                        AboutPaymentForgeView()
                    case .help:
                        HelpSupportView(onReplayTour: onReplayTour)
                    }
                }
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
    /// Continue learning block above, so this section is the
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
                        Text("You have finished the guided sessions")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Revisit any lesson in the browsing above, or practise with the Payment Cases.")
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
    /// progress fraction so progress is never colour-only. A
    /// session with nothing complete says so in words, not as a
    /// "0 of N" counter.
    private func learningPlanAccessibilityLabel(for session: GuidedSession) -> String {
        let progress = guidedSessionProgress(for: session)
        if progress.total > 0 && progress.completed > 0 {
            return "Session \(session.id): \(session.title), \(progress.completed) of \(progress.total) lessons complete"
        }
        if progress.total > 0 {
            return "Session \(session.id): \(session.title), not started yet"
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
                    if progress.completed > 0 {
                        Text("\(progress.completed) of \(progress.total) lessons complete")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        PFProgressBar(progress: Double(progress.completed) / Double(progress.total), height: 6)
                    } else {
                        Text("\(progress.total) lessons · Not started yet")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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

    // MARK: - Continue learning (every learner)

    /// The one next lesson for every learner, from a single
    /// authority: the journey order's next unfinished lesson when a
    /// journey resolves (the chosen journey, else the role route's
    /// journey, else the current guided session), then the most
    /// recent unfinished lesson, then the guided head. One pointer
    /// only: nothing else on Home names a next lesson, so a
    /// recommendation and the journey can never disagree.
    private var continueNextLesson: SearchEntry? {
        if let next = activePathNextLesson { return next }
        if let entry = resumeEntry { return entry }
        return continueEntry
    }

    /// The lesson the learner left unfinished, shown only when it
    /// differs from the next lesson, so "where you left off" and
    /// "your next lesson" never name the same lesson twice.
    private var leftOffLesson: SearchEntry? {
        guard let recent = recentUnfinishedLessons.first,
              recent.id != continueNextLesson?.id else { return nil }
        return recent
    }

    /// The journey the learner chose, when one is chosen. Home only
    /// reads it; choosing happens in the journey detail.
    private var chosenJourney: LearningPath? {
        activePathStore.activePath
    }

    /// The line under the next lesson, naming the authority in plain
    /// words: the chosen journey when one is chosen, the role
    /// journey when the onboarding role picked one, the first
    /// lesson for a newcomer, and the guided sessions otherwise.
    /// Never a bare recommendation with no reason.
    private var continueReason: String {
        if let journey = chosenJourney {
            return "Next in your journey: \(journey.title). Work through it in order."
        }
        if let journey = activeLearningPath {
            return "Next in the \(journey.title) journey, chosen for your role. Work through it in order."
        }
        if isNewLearner {
            return "Start here: the first lesson. Work through in order. Your progress saves as you go."
        }
        return "Next in the guided sessions, in order."
    }

    /// The single Continue learning block: where you left off plus
    /// your next lesson, one tap to continue, with the journey
    /// choice secondary underneath. It replaces the old separate
    /// recommendation, resume and path cards: one block, one next
    /// lesson, no competing pointers. When the lesson is locked,
    /// the lesson screen's own lock handling applies and nothing
    /// here bypasses it.
    private var continueLearningSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFHomeSectionHeader(title: "Continue learning", systemImage: "play.fill", accent: .gold)
            if contentService.searchIndex == nil && contentService.allLessons.isEmpty {
                PFHomeTabCard(accent: .gold) {
                    Text("Your next lesson will appear here once the catalogue loads.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let next = continueNextLesson {
                PFHomeTabCard(accent: .gold) {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        if let leftOff = leftOffLesson {
                            NavigationLink(destination: LessonView(entry: leftOff)) {
                                HStack(spacing: PFSpacing.md) {
                                    if leftOff.thumbnail != nil {
                                        PFThumbnailView(thumbnailPath: leftOff.thumbnail, size: 44, cornerRadius: 12)
                                    } else {
                                        PFIconTile(systemImage: "clock.fill", size: 44)
                                    }
                                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                        Text("Where you left off")
                                            .font(.pfCaptionBold)
                                            .foregroundColor(.pfRoyal)
                                        Text(leftOff.title)
                                            .font(.pfCardTitle)
                                            .foregroundColor(.pfNavy)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(PFChapterHelper.chapterTitle(for: leftOff))
                                            .font(.pfCaption)
                                            .foregroundColor(.pfSecondaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.pfSecondaryText)
                                        .pfDecorative()
                                }
                            }
                            .buttonStyle(PFCardButtonStyle())
                            .accessibilityLabel("Where you left off: \(leftOff.title)")
                            .accessibilityHint("Opens the lesson you left off")
                        }
                        HStack(spacing: PFSpacing.md) {
                            if next.thumbnail != nil {
                                PFThumbnailView(thumbnailPath: next.thumbnail, size: 52, cornerRadius: 12)
                            } else {
                                PFIconTile(systemImage: "play.fill", size: 52)
                            }
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                Text("Your next lesson")
                                    .font(.pfCaptionBold)
                                    .foregroundColor(.pfRoyal)
                                Text(next.title)
                                    .font(.pfCardTitle)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(PFChapterHelper.chapterTitle(for: next))
                                    .font(.pfCaption)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let duration = LessonDurations.listenLabel(for: next.id) {
                                    Text(duration)
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text(continueReason)
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        NavigationLink(destination: LessonView(entry: next)) {
                            Text(isNewLearner ? "Start this lesson" : "Continue")
                                .font(.pfBody.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.pfRoyal)
                                .cornerRadius(PFSpacing.cornerRadius)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(isNewLearner ? "Start this lesson" : "Continue"): \(next.title)")
                        .accessibilityHint("Opens your next lesson")
                        journeyRow
                    }
                }
            } else {
                PFHomeTabCard(accent: .gold) {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("You have finished your journey")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Revisit any lesson in the browsing below, or practise with the Payment Cases.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        PFSecondaryButton(title: "Browse the full course") {
                            requestHomeSection(.learn(.courses))
                        }
                    }
                }
            }
        }
    }

    /// The journey line inside the Continue block, secondary to the
    /// next lesson: the chosen journey with Change journey, or
    /// Choose your journey with a one-line explanation of what a
    /// journey is. Both land on Learning Journeys below.
    private var journeyRow: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            if let journey = chosenJourney {
                HStack(spacing: PFSpacing.sm) {
                    Text("Your journey: \(journey.title)")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Change journey") { requestHomeSection(.learn(.learningPaths)) }
                        .font(.pfBody.weight(.semibold))
                        .foregroundColor(.pfRoyal)
                        .accessibilityLabel("Change journey")
                        .accessibilityHint("Opens Learning Journeys to choose a different journey")
                }
            } else {
                Text("A learning journey is a set order of chapters for one goal. Choose one and this block shows its next lesson first.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Choose your journey") { requestHomeSection(.learn(.learningPaths)) }
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.pfRoyal)
                    .accessibilityLabel("Choose your journey")
                    .accessibilityHint("Opens Learning Journeys")
            }
        }
    }

    // MARK: - Browse the full course

    /// The course browsing embedded in Home: courses, learning
    /// journeys and the catalogue, with the learnTop anchor on the
    /// wrapper so outside routes and capability rows land with the
    /// header visible. No separate Learn page exists any more.
    private var browseSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFHomeSectionHeader(title: "Browse the full course", systemImage: "book.fill", accent: .royal)
            LearnSectionsView(selectedSection: $learnSection)
        }
        .id("learnTop")
    }

    // MARK: - Everything inside

    /// One depth stat: a real catalogue count and its label. Counts
    /// come from ContentManifest, never hardcoded here.
    private func depthStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.pfScreenTitle)
                .foregroundColor(.pfNavy)
            Text(label)
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The depth of the course, stated once with real counts, plus
    /// the mastery arc: courses in order, then Final Assessments
    /// and certificates, with narration called out as part of the
    /// lesson experience rather than a separate product.
    private var depthStatsCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.lg) {
                    depthStat(value: "\(ProductCatalogue.partProducts.count)", label: "courses")
                    depthStat(value: "\(ContentManifest.chapterCount)", label: "chapters")
                    depthStat(value: "\(ContentManifest.lessonCount)", label: "lessons")
                }
                HStack(spacing: PFSpacing.lg) {
                    depthStat(value: "\(ContentManifest.situationCount)", label: "payment cases")
                    depthStat(value: "\(ContentManifest.interviewQuestionCount)", label: "interview questions")
                    depthStat(value: "\(ContentManifest.faqCount)", label: "FAQs")
                }
                Text("Work from Course 1 to Course 10, then prove it with Final Assessments and certificates. Many lessons have narration: tap Play in a lesson to listen as you read, and download lessons to listen offline.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Everything inside: the depth card plus the complete,
    /// structured list of every capability that exists, each linked
    /// to where the user reaches it. Nothing is listed that does
    /// not exist: no video lessons, no chat assistant, no
    /// bookmarks list, no referral offer. Push destinations use
    /// NavigationLink, tabs switch tabs, Home sections scroll to
    /// the browsing below, and stack-owning destinations present
    /// as sheets. The tour is not listed here: replaying it needs
    /// MainTabView, and it stays reachable from Help and Support.
    private var everythingInsideSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFHomeSectionHeader(title: "Everything inside", systemImage: "square.grid.2x2.fill", accent: .navy)
            Text("The full course in one place. Start with the next lesson at the top of this page; everything below is here when you need it.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            depthStatsCard
            capabilityGroup(title: "Learn") {
                capabilityActionRow(icon: "book.fill", title: "Courses", detail: "10 courses, 100 chapters, 881 lessons, in reading order.") {
                    requestHomeSection(.learn(.courses))
                }
                capabilityActionRow(icon: "map.fill", title: "Learning journeys", detail: "Set orders of chapters for one goal, plus the eight guided sessions. Choose your journey.") {
                    requestHomeSection(.learn(.learningPaths))
                }
                capabilityActionRow(icon: "list.bullet", title: "Catalogue", detail: "Every chapter in one table, with guides, labs and tests.") {
                    requestHomeSection(.learn(.catalogue))
                }
                if let tabBinding = selectedTab {
                    capabilityActionRow(icon: "magnifyingglass", title: "Search", detail: "Find any lesson, case, guide or answer.") {
                        tabBinding.wrappedValue = 1
                    }
                    capabilityActionRow(icon: "briefcase.fill", title: "Payment Cases", detail: "564 real payment problems, in six stages, with free samples.") {
                        tabBinding.wrappedValue = 2
                    }
                }
                capabilityPushRow(icon: "questionmark.bubble.fill", title: "Interview Questions", detail: "500 situation-based questions, each with a model answer.") {
                    InterviewQuestionsView()
                }
                capabilityPushRow(icon: "arrow.clockwise", title: "Revision Centre", detail: "Daily revision and the concepts you keep getting wrong.") {
                    RevisionCentreView()
                }
                capabilityPushRow(icon: "note.text", title: "My Notes", detail: "Your notes, kept on this device.") {
                    NotesView()
                }
                capabilityActionRow(icon: "headphones", title: "Audio lessons", detail: "Narration on many lessons. Tap Play in a lesson to listen, and download lessons to listen offline.") {
                    requestHomeSection(.learn(.courses))
                }
            }
            capabilityGroup(title: "Practise") {
                if let situation = firstPracticeSituation {
                    capabilityPushRow(icon: "checklist", title: "Practice Mode", detail: "Practise payment cases as questions.") {
                        PracticeModeView(situation: situation, allSituations: practiceSituations)
                    }
                }
                capabilityPushRow(icon: "arrow.triangle.2.circlepath", title: "Payment Simulator", detail: "Follow a payment through its lifecycle, step by step.") {
                    PaymentLifecycleSimulatorView()
                }
                capabilityPushRow(icon: "doc.text.magnifyingglass", title: "ISO 20022 Explorer", detail: "Look up ISO 20022 messages and their fields.") {
                    ISO20022ExplorerView()
                }
                capabilityPushRow(icon: "exclamationmark.triangle.fill", title: "Exception Lab", detail: "Investigate payment exceptions and trace what went wrong, with the Investigation Experience.") {
                    ExceptionInvestigationLabView()
                }
                capabilityPushRow(icon: "square.and.pencil", title: "BA/PO Studio", detail: "Draft BA and PO deliverables for payment work.") {
                    BAProductStudioView()
                }
                capabilityPushRow(icon: "bolt.fill", title: "Daily Challenge", detail: "One question a day.") {
                    DailyChallengeView()
                }
                capabilityPushRow(icon: "trophy.fill", title: "Weekly Challenge", detail: "The weekly community challenge.") {
                    CommunityChallengeView()
                }
                capabilityPushRow(icon: "gift.fill", title: "Free Case of the Week", detail: "One free payment case a week.") {
                    WeeklyFreeCaseView()
                }
                capabilityPushRow(icon: "doc.text.fill", title: "Guides", detail: "Step-by-step guides for payment work.") {
                    GuideListView()
                }
                capabilityPushRow(icon: "flask.fill", title: "Labs", detail: "Hands-on lab exercises.") {
                    LabListView()
                }
                capabilityPushRow(icon: "checkmark.circle.fill", title: "Tests", detail: "Tests that check what you learned.") {
                    TestListView()
                }
                capabilityPushRow(icon: "checkmark.seal.fill", title: "Certificates", detail: "Certificates you have earned, and Final Assessments.") {
                    CertificatesListView()
                }
            }
            capabilityGroup(title: "Your progress and account") {
                if let tabBinding = selectedTab {
                    capabilityActionRow(icon: "chart.bar.fill", title: "My Progress", detail: "Progress, streaks, scores and activity.") {
                        tabBinding.wrappedValue = 3
                    }
                }
                capabilityActionRow(icon: "bag.fill", title: "My Purchases", detail: "Buy a course or the full academy. 1 year of access.") {
                    capabilitySheet = .checkout
                }
                capabilityActionRow(icon: "person.crop.circle.fill", title: "Profile", detail: "Sign in, cloud sync, reminders and preferences.") {
                    showProfileSheet = true
                }
                capabilityActionRow(icon: "moon.fill", title: "Appearance", detail: "Dark mode and larger text.") {
                    capabilitySheet = .appearance
                }
                capabilityActionRow(icon: "questionmark.circle.fill", title: "Help and FAQs", detail: "320 FAQs, email support, and replay the tour.") {
                    capabilitySheet = .help
                }
                capabilityActionRow(icon: "info.circle.fill", title: "About", detail: "About Payments Training Hub.") {
                    capabilitySheet = .about
                }
            }
        }
    }

    /// One capability group: a header plus its rows.
    private func capabilityGroup<Content: View>(title: String, @ViewBuilder rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: title)
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                rows()
            }
        }
    }

    /// One capability row: icon tile, title, detail and chevron.
    private func capabilityRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: PFSpacing.md) {
            PFIconTile(systemImage: icon, size: 44)
            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                Text(title)
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.pfSecondaryText)
                .pfDecorative()
        }
        .contentShape(Rectangle())
    }

    /// A capability row that pushes a destination on Home's stack.
    /// Only destinations without their own NavigationStack use this.
    private func capabilityPushRow<Destination: View>(icon: String, title: String, detail: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            capabilityRow(icon: icon, title: title, detail: detail)
        }
        .buttonStyle(PFCardButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    /// A capability row that runs an action: a tab switch, a scroll
    /// to the browsing below, or a sheet.
    private func capabilityActionRow(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            capabilityRow(icon: icon, title: title, detail: detail)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    // MARK: - Continue helpers: resume and journey order

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

    // MARK: - Continue helpers: journey and session order

    /// The onboarding role's route, when the learner chose a
    /// profile. Its journey is the fallback order when no journey
    /// has been chosen.
    private var roleRoute: RoleRoute? {
        guard let profile = effectiveProfile else { return nil }
        return RoleRouteCatalogue.route(for: profile.role)
    }

    /// The guided sessions the role route names, otherwise the
    /// first guided session. The fallback order when no journey
    /// resolves.
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
        return "Your journey"
    }

    private var activePathPercentText: String {
        guard activePathProgress.total > 0 else { return "0%" }
        let fraction = Double(activePathProgress.completed) / Double(activePathProgress.total)
        return "\(Int((fraction * 100).rounded()))%"
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
                                    if lesson.thumbnail != nil {
                                        PFThumbnailView(thumbnailPath: lesson.thumbnail, size: 44, cornerRadius: 12)
                                    } else {
                                        PFIconTile(systemImage: "arrow.clockwise", size: 44)
                                    }
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
                    if lesson.thumbnail != nil {
                        PFThumbnailView(thumbnailPath: lesson.thumbnail, size: 44, cornerRadius: 12)
                    } else {
                        PFIconTile(systemImage: "questionmark.circle.fill", size: 44)
                    }
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
    /// baseline, not a missing streak. And until the first whole
    /// chapter is complete, the whole section is a starter state:
    /// a fresh user never sees a ring at 0% or a "0 of N" counter.
    private var yourProgressSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            if let tabBinding = selectedTab {
                PFHomeSectionHeader(
                    title: "Your Progress",
                    systemImage: "chart.bar.fill",
                    accent: .navy,
                    actionTitle: "My Progress",
                    action: { tabBinding.wrappedValue = 3 }
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
                } else if !hasMeaningfulProgress {
                    progressStarterCard
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
                            if progressStore.lessonsCompletedThisWeek > 0 {
                                Text("\(progressStore.lessonsCompletedThisWeek) of \(progressStore.weeklyGoal) lessons this week")
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                PFProgressBar(progress: progressStore.weeklyProgress)
                            } else {
                                Text("No lessons completed this week yet.")
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
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

    /// True once the learner has finished a whole chapter:
    /// the point where progress UI may appear. Before that, the
    /// progress section shows the starter state instead.
    private var hasMeaningfulProgress: Bool {
        ProgressVisibility.hasMeaningfulProgress(
            completedIDs: progressStore.completedLessonIDs,
            lessonEntries: contentService.allLessons
        )
    }

    /// The starter state shown instead of the progress ring and
    /// counters until the first chapter is complete: what will
    /// appear here, and a link to the first lesson to start with.
    /// No zero counter, no empty ring.
    private var progressStarterCard: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text("Your progress will show here once you finish your first chapter.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let firstLesson = continueNextLesson ?? contentService.readingOrderLessons.first {
                NavigationLink(destination: LessonView(entry: firstLesson)) {
                    Text("Start with the first lesson")
                        .font(.pfBody.weight(.semibold))
                        .foregroundColor(.pfRoyal)
                }
                .accessibilityLabel("Start with the first lesson: \(firstLesson.title)")
                .accessibilityHint("Opens the first lesson")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        return "All sessions complete"
    }

    /// "2 of 12 lessons" for the current session, or "Not
    /// started yet" when nothing in the session is complete: no
    /// "0 of 12" counter.
    private var sessionProgressDetail: String {
        guard let session = currentGuidedSession else {
            return "\(progressStore.totalLessonsCompleted) lessons complete"
        }
        let progress = guidedSessionProgress(for: session)
        guard progress.completed > 0 else { return "Not started yet" }
        return "\(progress.completed) of \(progress.total) lessons"
    }

    // MARK: - Recent lessons

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
            PFHomeSectionHeader(title: "Recent lessons", systemImage: "clock.fill", accent: .navy)
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

    /// The session thumbnail: the first lesson in the session
    /// that carries one. Nil keeps the header text on its own.
    private var thumbnailPath: String? {
        lessons.compactMap(\.thumbnail).first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                HStack(alignment: .top, spacing: PFSpacing.md) {
                    if thumbnailPath != nil {
                        PFThumbnailView(thumbnailPath: thumbnailPath, size: 56, cornerRadius: 12)
                    }
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text(session.description)
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                        if !lessons.isEmpty {
                            if completedCount > 0 {
                                Text("\(completedCount) of \(lessons.count) lessons complete")
                                    .font(.pfCaptionBold)
                                    .foregroundColor(.pfRoyal)
                                PFProgressBar(progress: Double(completedCount) / Double(lessons.count))
                            } else {
                                Text("\(lessons.count) lessons · Not started yet")
                                    .font(.pfCaptionBold)
                                    .foregroundColor(.pfSecondaryText)
                            }
                        }
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
    /// course containing it nor the Integrated Course is owned.
    private var isLocked: Bool {
        guard let number = PFChapterHelper.chapterNumber(from: entry.id) else { return false }
        return !storeManager.isChapterUnlocked("ch\(number)")
    }

    /// True when this lesson is free without any purchase: the
    /// first lesson of its chapter, or one of its course's
    /// sequential free samples. Free with full content even when
    /// the chapter is locked.
    private var isFreeSample: Bool {
        PFChapterHelper.isFreeLesson(entry, in: contentService)
    }

    var body: some View {
        PFCard {
            HStack(spacing: PFSpacing.md) {
                // The thumbnail sits beside the title when the
                // website exposes one; the play/check tile
                // otherwise, with the completed badge on top.
                if entry.thumbnail != nil {
                    ZStack(alignment: .topTrailing) {
                        PFThumbnailView(thumbnailPath: entry.thumbnail, size: 44, cornerRadius: 12)
                        if progressStore.isLessonComplete(entry.id) {
                            Circle()
                                .fill(Color.pfSuccess)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.pfCaption.weight(.bold))
                                        .foregroundColor(.white)
                                )
                                .offset(x: 6, y: -6)
                        }
                    }
                } else {
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
                    if let duration = LessonDurations.listenLabel(for: entry.id) {
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
                    // The progress bar shows only for a completed
                    // lesson: an empty bar under every unfinished
                    // lesson reads as a zero counter.
                    if progressStore.isLessonComplete(entry.id) {
                        PFProgressBar(progress: 1, height: 6)
                            .padding(.top, PFSpacing.xs)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.pfSecondaryText)
            }
        }
    }
}

