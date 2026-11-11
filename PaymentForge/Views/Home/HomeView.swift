// HomeView.swift
// PaymentForge iOS - Home tab, personalised to the mockup.
// Native SwiftUI only, no WebView. Uses the shared DesignSystem.
// No em dashes in any user-facing text.
//
// Section order on this screen: greeting, Learning plan, Continue
// Learning, Daily Revision, Daily Challenge, then Explore (quick
// links, Your Progress, Recommended for You, Situations teaser).
// Guest is the default: the screen works fully as a guest and never
// blocks on sign-in. The greeting shows a name only when a user is
// actually signed in (AuthService.currentUser); as a guest it shows
// a generic time-based greeting with no name, never a fake one.

import SwiftUI
import Foundation

// MARK: - Shared chapter helpers

/// Helpers for deriving chapters from lesson entries.
/// Lesson IDs look like ch1s1 or ch27s9. The chapter number is the digits
/// between "ch" and "s". Filtering is done on the exact chapter number:
/// a plain prefix match on "ch1" would also catch ch10 to ch19.
enum PFChapterHelper {
    static func chapterNumber(from lessonID: String) -> Int? {
        guard lessonID.hasPrefix("ch") else { return nil }
        let digits = lessonID.dropFirst(2).prefix(while: { $0.isNumber })
        return Int(digits)
    }

    /// Lessons belonging to exactly one chapter number, in catalogue order.
    static func lessons(forChapter number: Int, in service: ContentService) -> [SearchEntry] {
        service.allLessons.filter { chapterNumber(from: $0.id) == number }
    }

    /// Lessons for a guided session, in session chapter order, deduped by id.
    static func lessons(forSession session: GuidedSession, in service: ContentService) -> [SearchEntry] {
        var seen: Set<String> = []
        var result: [SearchEntry] = []
        for chapterID in session.chapterIDs {
            guard let number = chapterNumber(from: chapterID + "s1") else { continue }
            for lesson in lessons(forChapter: number, in: service) {
                if seen.insert(lesson.id).inserted {
                    result.append(lesson)
                }
            }
        }
        return result
    }

    /// Chapter title: the second non-empty line of the first lesson's text.
    static func chapterTitle(for lessons: [SearchEntry], number: Int) -> String {
        guard let first = lessons.first else { return "Chapter \(number)" }
        return chapterTitle(for: first)
    }

    /// Chapter title for one lesson entry: the chapter name parsed
    /// from the single-line catalogue text
    /// (`<lesson title> <chapter name> Part N: <domain> <body>`).
    /// Falls back to "Chapter <number>", never to the app name.
    static func chapterTitle(for entry: SearchEntry) -> String {
        if let name = entry.chapterName { return name }
        if let number = entry.chapterNumber { return "Chapter \(number)" }
        return "Chapter"
    }

    /// All chapter numbers present in the loaded index, numeric order.
    static func chapterNumbers(in service: ContentService) -> [Int] {
        let numbers = Set(service.allLessons.compactMap { chapterNumber(from: $0.id) })
        return numbers.sorted()
    }

    /// The next lessons to recommend: the first lessons in catalogue
    /// order that the learner has not completed yet. Real catalogue
    /// entries only, never invented.
    static func recommendedLessons(in service: ContentService, progress: ProgressStore, limit: Int = 3) -> [SearchEntry] {
        Array(service.allLessons.filter { !progress.isLessonComplete($0.id) }.prefix(limit))
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore

    /// Concepts due for revision today, from the shared revision
    /// service. The count drives the Daily Revision card; when it is
    /// zero the card says so honestly instead of inventing a number.
    @ObservedObject private var revisionService = RevisionService.shared

    /// The same shared auth service the sign-in screens use. Nil
    /// currentUser means a guest; the greeting then shows no name.
    @StateObject private var authService = AuthService.shared

    /// Opens the side drawer. Passed in from the tab bar so the menu
    /// button can sit in this screen's navigation bar, and only here:
    /// pushed detail views have no menu button and keep a clean back button.
    @Binding var isDrawerOpen: Bool

    /// Optional tab selection, for the quick links row. MainTabView
    /// does not pass this yet, so it is nil and each tile falls back
    /// to an in-stack destination. Once MainTabView passes
    /// $selectedTab, the tiles switch tabs instead. Nothing here
    /// invents a tab switch: without the binding the tiles navigate
    /// inside this NavigationStack.
    var selectedTab: Binding<Int>?

    init(isDrawerOpen: Binding<Bool>, selectedTab: Binding<Int>? = nil) {
        self._isDrawerOpen = isDrawerOpen
        self.selectedTab = selectedTab
    }

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.xl) {
                    loadStateView

                    greetingSection

                    learningPlanSection

                    continueSection

                    interviewSection

                    dailyRevisionSection

                    dailyChallengeSection

                    tutorSection

                    quickLinksSection

                    yourProgressSection

                    recentLessonsSection

                    highlightsSection
                }
                .padding(20)
            }
            .background(Color.pfBackground)
            // Extra scrollable space at the bottom so the last card clears
            // the tab bar on every iPhone size.
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: PFSpacing.xl)
            }
            .navigationTitle("Payments Training Hub")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    DrawerMenuButton(isDrawerOpen: $isDrawerOpen)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: ProfileView()) {
                        avatarView
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open your profile").accessibilityHint("Opens your profile, separate from My Progress")
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
        if let error = contentService.indexError {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text("Could not load the course catalogue")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    Text(error)
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
    /// signed in and has a display name; guests get the greeting
    /// with no name at all.
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let base: String
        switch hour {
        case 5..<12: base = "Good morning"
        case 12..<17: base = "Good afternoon"
        default: base = "Good evening"
        }
        if authService.isSignedIn,
           let fullName = authService.currentUser?.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fullName.isEmpty,
           let firstName = fullName.split(separator: " ").first {
            return "\(base), \(firstName)"
        }
        return base
    }

    /// Hero card: deep navy gradient with the greeting in white,
    /// the date and tagline below, and a subtle bank illustration
    /// drawn from SF Symbols. The greeting shows a name only when a
    /// user is actually signed in; guests get the greeting alone.
    /// The avatar in the navigation bar (top right) opens Profile.
    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            Text(greetingText + " 👋")
                .font(.pfScreenTitle)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(greetingText)
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.pfBody)
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Text("Master the world of payments, one lesson at a time.")
                .font(.pfBody)
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
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
                Text("PF")
                    .font(.system(.title3, design: .default).weight(.bold))
                    .foregroundColor(.pfNavy)
                    .frame(width: 48, height: 48)
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

    /// One short line stating the current path and the next step, from
    /// real progress only. With no progress at all it says to start
    /// the first lesson; with the path complete it says so honestly.
    private var learningPlanSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Your learning plan")
            PFCard {
                if contentService.searchIndex == nil && contentService.allLessons.isEmpty {
                    Text("Your learning plan will appear here once the catalogue loads.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let next = nextGuidedLesson {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        HStack(spacing: PFSpacing.sm) {
                            if let session = currentGuidedSession {
                                PFPill(text: "Session \(session.id) of \(ContentService.guidedSessions.count): \(session.title)")
                            } else {
                                PFPill(text: "Guided path")
                            }
                            if progressStore.totalLessonsCompleted == 0 {
                                PFPill(text: "Start here", background: Color.pfGoldSoft, foreground: .pfNavy)
                            }
                        }
                        Text(progressStore.totalLessonsCompleted == 0 ? "Start your first lesson" : "Your next step")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(next.title)
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        NavigationLink(destination: LessonView(entry: next)) {
                            Text(progressStore.totalLessonsCompleted == 0 ? "Start your first lesson" : "Continue")
                                .font(.pfBody.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.pfRoyal)
                                .cornerRadius(PFSpacing.cornerRadius)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("You have finished the guided path")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Revisit any lesson from Learn, or practise with the Payment Cases below.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            // All eight sessions of the plan, each with its correct
            // sequential number and its own progress, so the plan
            // never reads as a single "Session 1". The current
            // session is marked; tapping any session opens it.
            if !contentService.allLessons.isEmpty {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        ForEach(ContentService.guidedSessions) { session in
                            NavigationLink(destination: GuidedPathDetailView(session: session)) {
                                learningPlanSessionRow(for: session)
                            }
                            .buttonStyle(.plain)
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

    // MARK: - Interview questions

    /// Situation-based interview questions for payments and BA
    /// roles, with a model answer for each. Placed near the
    /// learning plan and Continue sections so it is easy to find.
    private var interviewSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Interview Questions")
            NavigationLink(destination: InterviewQuestionsView()) {
                PFCard {
                    HStack(spacing: PFSpacing.md) {
                        PFIconTile(systemImage: "briefcase.fill", size: 44)
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text("Interview Questions")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("500 situation-based payments and BA interview questions, each with a model answer.")
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
            .accessibilityHint("Opens 500 situation-based payments and BA interview questions")
        }
    }

    // MARK: - Daily Revision

    /// Concepts due for revision today, from the shared revision
    /// service. Zero means nothing is due, and the card says so.
    private var dueRevisionCount: Int {
        revisionService.dueToday.count
    }

    private var dailyRevisionSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Daily Revision")
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
        }
    }

    // MARK: - Daily Challenge

    /// A fresh case every day. No challenge title is exposed by the
    /// challenge screen, so the card shows "Today's case" rather than
    /// inventing a title.
    private var dailyChallengeSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Daily Challenge")
            NavigationLink(destination: DailyChallengeView()) {
                PFCard {
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
        }
    }

    // MARK: - Chat Assistant

    /// Ask the Chat Assistant: a chat that answers only from the
    /// course content. Guests can use it; sign-in is never forced.
    private var tutorSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Chat Assistant")
            NavigationLink(destination: ChatAssistantView()) {
                PFCard {
                    HStack(spacing: PFSpacing.md) {
                        PFIconTile(systemImage: "bubble.left.and.bubble.right.fill", size: 44)
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            HStack(spacing: PFSpacing.sm) {
                                Text("Ask the Chat Assistant")
                                    .font(.pfCardTitle)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text("Ask anything about payments. Answers come only from your lessons, guides and Payment Cases.")
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
            .accessibilityLabel("Ask the Chat Assistant")
            .accessibilityHint("Opens a chat with the Chat Assistant")
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
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.pfScreenTitle.weight(.regular))
                    .foregroundColor(.pfRoyal)
            }
        }
    }

    // MARK: - Continue Learning

    /// Lessons of the Continue lesson's chapter, in catalogue order.
    private var continueChapterLessons: [SearchEntry] {
        guard let entry = continueEntry,
              let number = PFChapterHelper.chapterNumber(from: entry.id) else {
            return []
        }
        return PFChapterHelper.lessons(forChapter: number, in: contentService)
    }

    /// Position of the Continue lesson inside its chapter, 1-based.
    private var continueLessonPosition: Int {
        guard let entry = continueEntry else { return 0 }
        return (continueChapterLessons.firstIndex { $0.id == entry.id } ?? 0) + 1
    }

    /// Chapter progress as a whole percent, from real completion data.
    private var continueChapterPercent: Int {
        guard continueChapterProgress.total > 0 else { return 0 }
        return Int((Double(continueChapterProgress.completed) / Double(continueChapterProgress.total) * 100).rounded())
    }

    private var lastLessonEntry: SearchEntry? {
        guard let id = progressStore.lastLessonID else { return nil }
        return contentService.allLessons.first { $0.id == id }
    }

    private var firstGuidedLesson: SearchEntry? {
        guard let session = ContentService.guidedSessions.first else { return nil }
        return PFChapterHelper.lessons(forSession: session, in: contentService).first
            ?? contentService.allLessons.first
    }

    /// The lesson the Continue card points at: the last lesson when
    /// there is progress, otherwise the first lesson of the guided path.
    private var continueEntry: SearchEntry? {
        lastLessonEntry ?? firstGuidedLesson
    }

    /// Progress inside the chapter of the Continue lesson, from real
    /// completion data.
    private var continueChapterProgress: (completed: Int, total: Int) {
        guard let entry = continueEntry,
              let number = PFChapterHelper.chapterNumber(from: entry.id) else {
            return (0, 0)
        }
        let lessons = PFChapterHelper.lessons(forChapter: number, in: contentService)
        return (lessons.filter { progressStore.isLessonComplete($0.id) }.count, lessons.count)
    }

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Continue your learning")
            if let entry = continueEntry {
                NavigationLink(destination: LessonView(entry: entry)) {
                    PFCard {
                        VStack(alignment: .leading, spacing: PFSpacing.md) {
                            HStack(spacing: PFSpacing.md) {
                                PFIconTile(systemImage: "play.fill", size: 52)
                                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                    Text(entry.title)
                                        .font(.pfCardTitle)
                                        .foregroundColor(.pfNavy)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(PFChapterHelper.chapterTitle(for: entry))
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .lineLimit(1)
                                    if continueChapterProgress.total > 0 {
                                        Text("Lesson \(continueLessonPosition) of \(continueChapterProgress.total) • \(continueChapterPercent)% complete")
                                            .font(.pfCaptionBold)
                                            .foregroundColor(.pfRoyal)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    if progressStore.isLessonComplete(entry.id) {
                                        Label("Completed", systemImage: "checkmark.circle.fill")
                                            .font(.pfCaptionBold)
                                            .foregroundColor(.pfSuccess)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "play.fill")
                                    .font(.pfCardTitle.weight(.bold))
                                    .foregroundColor(.white)
                                    .frame(width: 56, height: 56)
                                    .background(Color.pfRoyal)
                                    .clipShape(Circle())
                                    .shadow(color: Color.pfRoyal.opacity(0.35), radius: 8, x: 0, y: 4)
                            }
                            if continueChapterProgress.total > 0 {
                                PFProgressBar(progress: Double(continueChapterProgress.completed) / Double(continueChapterProgress.total))
                            }
                        }
                    }
                }
                .buttonStyle(PFCardButtonStyle())
            } else {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("Your first lesson is on its way")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("The course catalogue is still loading. Once it appears, your first lesson from the guided path will show here.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Quick links

    private var quickLinksSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Explore")
            HStack(spacing: PFSpacing.sm) {
                quickLink(title: "Learn", systemImage: "book.fill", tab: 1, fallback: AnyView(GuidedPathwayListView()))
                quickLink(title: "Payment Cases", systemImage: "briefcase.fill", tab: 3, fallback: AnyView(FreeSamplesView()))
                quickLink(title: "Search", systemImage: "magnifyingglass", tab: 2, fallback: AnyView(QuickSearchView()))
                quickLink(title: "My Progress", systemImage: "chart.bar.fill", tab: 4, fallback: AnyView(YourProgressDetailView()))
            }
        }
    }

    private func quickLinkTile(title: String, systemImage: String) -> some View {
        VStack(spacing: PFSpacing.sm) {
            PFIconTile(systemImage: systemImage, size: 44)
            Text(title)
                .font(.pfCaption.weight(.semibold))
                .foregroundColor(.pfNavy)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PFSpacing.md)
        .background(Color.pfCard)
        .cornerRadius(PFSpacing.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                .stroke(Color.pfBorder, lineWidth: 1)
        )
        .shadow(color: Color.pfNavy.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    /// A quick link tile. When the tab binding is wired it switches
    /// tabs; otherwise it navigates to the in-stack fallback screen.
    @ViewBuilder
    private func quickLink(title: String, systemImage: String, tab: Int, fallback: AnyView) -> some View {
        if let tabBinding = selectedTab {
            Button {
                tabBinding.wrappedValue = tab
            } label: {
                quickLinkTile(title: title, systemImage: systemImage)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                fallback
            } label: {
                quickLinkTile(title: title, systemImage: systemImage)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Your Progress

    private var yourProgressSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            if let tabBinding = selectedTab {
                PFSectionHeader(
                    title: "Your Progress",
                    actionTitle: "My Progress",
                    action: { tabBinding.wrappedValue = 4 }
                )
            } else {
                PFSectionHeader(title: "Your Progress")
            }
            PFCard {
                if contentService.searchIndex == nil {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("Your progress will appear here once the catalogue loads.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(spacing: PFSpacing.md) {
                        VStack(spacing: PFSpacing.sm) {
                            PFProgressRing(progress: overallProgress, size: 104, color: .pfRoyal)
                            Text("Overall")
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfNavy)
                            Text("\(progressStore.totalLessonsCompleted) of \(totalLessonCount) lessons")
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
                                    .foregroundColor(.pfGold)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
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
            PFSectionHeader(title: "Pick up where you left off")
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

    /// Two prominent highlights in place of the old Recommendations
    /// and Payment Situations sections: Practice Mode opens the
    /// first practice-eligible situation; Certification opens the
    /// certificates list.
    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Practise and certify")
            HStack(alignment: .top, spacing: PFSpacing.md) {
                if let situation = firstPracticeSituation {
                    NavigationLink(destination: PracticeModeView(situation: situation, allSituations: practiceSituations)) {
                        highlightCard(
                            title: "Practice Mode",
                            subtitle: "Test yourself on real payment scenarios",
                            systemImage: "flask.fill"
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PFCardButtonStyle())
                } else {
                    highlightCard(
                        title: "Practice Mode",
                        subtitle: "Test yourself on real payment scenarios",
                        systemImage: "flask.fill"
                    )
                }
                NavigationLink(destination: CertificatesListView()) {
                    highlightCard(
                        title: "Certification",
                        subtitle: "Pass a Final Assessment and earn a verified certificate",
                        systemImage: "seal.fill"
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(PFCardButtonStyle())
            }
        }
    }

    private func highlightCard(title: String, subtitle: String, systemImage: String) -> some View {
        PFCard {
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

// MARK: - Quick search (in-stack fallback for the Search quick link)

/// A compact in-stack search screen, used only when the Search tab
/// cannot be switched to directly. It searches the same live index
/// as the Search tab and opens lessons and entries the same way.
struct QuickSearchView: View {
    @EnvironmentObject private var contentService: ContentService

    @State private var query = ""

    private let popularSearches = [
        "MT103", "pacs.008", "ISO 20022", "SEPA", "chargeback", "nostro"
    ]

    private var results: [SearchEntry] {
        contentService.search(query: query, limit: 30)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.pfSecondaryText)
                    TextField("Search lessons, guides and situations", text: $query)
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(PFSpacing.md)
                .background(Color.pfCard)
                .cornerRadius(PFSpacing.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                        .stroke(Color.pfBorder, lineWidth: 1)
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PFSpacing.sm) {
                        ForEach(popularSearches, id: \.self) { term in
                            PFChip(text: term, isSelected: query == term) {
                                query = term
                            }
                        }
                    }
                }
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Try a popular search above, or type a message name, scheme or topic.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else if results.isEmpty {
                    Text("No results for \"\(query)\". Check the spelling, or try a broader term.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(results) { entry in
                        NavigationLink(destination: searchDestination(for: entry)) {
                            EntryRow(entry: entry)
                        }
                        .buttonStyle(PFCardButtonStyle())
                    }
                }
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func searchDestination(for entry: SearchEntry) -> some View {
        if entry.isLesson {
            LessonView(entry: entry)
        } else {
            EntryDetailView(entry: entry)
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

    private var lessons: [SearchEntry] {
        PFChapterHelper.lessons(forSession: session, in: contentService)
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
                ForEach(lessons) { lesson in
                    NavigationLink(destination: LessonView(entry: lesson)) {
                        LessonRow(entry: lesson)
                    }
                    .buttonStyle(PFCardButtonStyle())
                }
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .navigationTitle("Session \(session.id): \(session.title)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Lesson row

struct LessonRow: View {
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var storeManager: StoreManager
    let entry: SearchEntry

    /// True when this lesson's chapter is not unlocked: neither the
    /// bundle containing it nor the Integrated Course is owned.
    private var isLocked: Bool {
        guard let number = PFChapterHelper.chapterNumber(from: entry.id) else { return false }
        return !storeManager.isChapterUnlocked("ch\(number)")
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
                    Text(entry.title)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.preview)
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if isLocked {
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

// MARK: - Free samples

/// The free Payment Situations samples, in the site's sample order.
struct FreeSamplesView: View {
    @EnvironmentObject private var contentService: ContentService

    private var samples: [SearchEntry] {
        ContentService.freeSampleIDs.compactMap { id in
            contentService.allSituations.first(where: { $0.id == id })
        }
    }

    private func situation(from entry: SearchEntry) -> Situation {
        Situation(
            id: entry.id,
            title: entry.title,
            stage: 1,
            stageName: "Stage 1",
            level: .core,
            explain: entry.text,
            takeaway: entry.preview,
            isFreeSample: true,
            visual: nil
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Text("\(ContentService.freeSampleIDs.count) free samples from the Payment Situations. Each one walks through a real-world situation and what to do about it.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                if contentService.isLoadingIndex && samples.isEmpty {
                    ProgressView("Loading samples...")
                }
                ForEach(samples) { entry in
                    NavigationLink(destination: FreeSampleDetailView(situation: situation(from: entry))) {
                        PFCard {
                            HStack(spacing: PFSpacing.md) {
                                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                    Text(entry.title)
                                        .font(.pfCardTitle)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(entry.preview)
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.pfSecondaryText)
                            }
                        }
                    }
                    .buttonStyle(PFCardButtonStyle())
                }
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .navigationTitle("Free samples")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Detail for one free sample situation.
struct FreeSampleDetailView: View {
    let situation: Situation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                HStack(spacing: PFSpacing.sm) {
                    PFPill(text: situation.stageName)
                    PFPill(text: situation.level.displayName)
                    PFPill(text: "Free sample", background: Color.pfGoldSoft, foreground: .pfNavy)
                }
                Text(situation.title)
                    .font(.pfSectionTitle)
                    .foregroundColor(.pfNavy)
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text("What happened")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    Text(situation.explain)
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                }
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text("Takeaway")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    Text(situation.takeaway)
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                }
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .navigationTitle("Situation")
        .navigationBarTitleDisplayMode(.inline)
    }
}
