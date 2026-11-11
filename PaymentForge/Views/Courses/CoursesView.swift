// CoursesView.swift
// PaymentForge iOS - Learn tab: learning pathways and all courses.
// Native SwiftUI only, no WebView. Uses the shared DesignSystem.
// No em dashes in any user-facing text.
//
// Adaptive layout: every screen here uses flexible stacks and frames
// (maxWidth: .infinity, no fixed widths), text that wraps instead of
// clipping, and safe-area aware ScrollViews. It is built to look right
// on an iPhone SE (320pt wide), a standard iPhone, a Plus, a Pro and a
// Pro Max, in portrait and in landscape.
//
// Pathways are the eight guided sessions from the live site, with
// lesson counts and completion % computed from the real catalogue
// and real progress. Chapters are gated by purchase: a chapter's
// lessons unlock when its bundle, or the Integrated Course, is owned.
// The catalogue stays browsable: locked chapters show a lock state
// and open to a lock screen, never a dead end.

import SwiftUI
import Foundation

// MARK: - Pathway levels

/// The level of a guided session. The catalogue carries no level
/// field for sessions, so this is a presentation grouping by position
/// in the guided path, stated here so it is never mistaken for
/// catalogue data: sessions 1 to 3 lay the foundations, sessions 4
/// to 6 go deeper, and sessions 7 and 8 are the most advanced.
/// The filter and the pill both use this one mapping.
enum PFPathwayLevel: String, CaseIterable {
    case foundation = "Foundation"
    case intermediate = "Intermediate"
    case advanced = "Advanced"

    static func level(for session: GuidedSession) -> PFPathwayLevel {
        switch session.id {
        case 1...3: return .foundation
        case 4...6: return .intermediate
        default: return .advanced
        }
    }
}

// MARK: - Courses

struct CoursesView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore

    /// Opens the side drawer. Passed in from the tab bar so the menu
    /// button can sit in this screen's navigation bar, and only here:
    /// pushed detail views have no menu button and keep a clean back button.
    @Binding var isDrawerOpen: Bool

    @State private var selectedLevel: PFPathwayLevel? = nil
    @State private var selectedSection: LearnSection = .learningPaths

    /// Chapters shown in the flat All chapters list. Ten at first;
    /// Load more adds ten. Reset when the catalogue reloads.
    @State private var visibleChapterCount: Int = 10
    private static let chapterPageSize = 10

    private enum LearnSection: String, CaseIterable {
        case learningPaths = "Learning Paths"
        case allCourses = "All Courses"
    }

    private var filteredSessions: [GuidedSession] {
        guard let selectedLevel else { return ContentService.guidedSessions }
        return ContentService.guidedSessions.filter { PFPathwayLevel.level(for: $0) == selectedLevel }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.xl) {
                    loadStateView

                    Picker("Learn section", selection: $selectedSection) {
                        ForEach(LearnSection.allCases, id: \.self) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Learn section")

                    tutorSection

                    interviewSection

                    if contentService.isLoadingIndex && contentService.searchIndex == nil {
                        VStack(alignment: .leading, spacing: PFSpacing.md) {
                            PFSkeletonView()
                            PFSkeletonView()
                            PFSkeletonView()
                        }
                    } else if selectedSection == .learningPaths {
                        guidedPathsSection
                        levelFilterSection
                        pathwaysSection
                    } else {
                        allChaptersSection
                        librarySection
                    }
                }
                .padding(PFSpacing.lg)
            }
            .background(Color.pfBackground)
            // Extra scrollable space at the bottom so the last card clears
            // the tab bar on every iPhone size.
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: PFSpacing.xl)
            }
            .navigationTitle("Learn")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    DrawerMenuButton(isDrawerOpen: $isDrawerOpen)
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
            PFErrorStateView(
                title: "Could not load the course catalogue",
                message: error,
                retryTitle: "Retry"
            ) {
                Task { await contentService.loadSearchIndex() }
            }
        } else if contentService.isLoadingIndex && contentService.searchIndex == nil {
            PFLoadingView(message: "Loading the course catalogue...")
        }
    }

    // MARK: - Chat Assistant

    /// Ask the Chat Assistant: a chat that answers only from the
    /// course content. Shown above both Learn sections so it is
    /// reachable without switching tabs. Guests can use it;
    /// sign-in is never forced.
    private var tutorSection: some View {
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

    // MARK: - Interview questions

    /// Situation-based interview questions for payments and BA
    /// roles. Shown above both Learn sections, next to the Chat
    /// Assistant card, so it is reachable without switching tabs.
    private var interviewSection: some View {
        NavigationLink(destination: InterviewQuestionsView()) {
            PFCard {
                HStack(spacing: PFSpacing.md) {
                    PFIconTile(systemImage: "briefcase.fill", size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        HStack(spacing: PFSpacing.sm) {
                            Text("Interview Questions")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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

    // MARK: - Guided learning paths

    /// The six guided learning paths, in the mockup's Courses card
    /// layout: icon tile left, title, two-line description,
    /// "Level • N lessons", progress bar with % at the right, bookmark
    /// top right. Counts and progress are real, from the catalogue and
    /// ProgressStore.
    private var guidedPathsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            Text("Guided Learning Paths")
                .font(.pfScreenTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Text("Six paths through the curriculum, each with real lessons, practice situations, an assessment checkpoint and a capstone situation.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(LearningPath.all) { path in
                NavigationLink(destination: PathDetailView(path: path)) {
                    GuidedPathCardView(path: path)
                }
                .buttonStyle(PFCardButtonStyle())
            }
        }
    }

    // MARK: - Level filter

    private var levelFilterSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            Text("Learning Pathways")
                .font(.pfScreenTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Text("Eight sessions that take you through the curriculum in order, from what a payment is to practice and interview preparation.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PFSpacing.sm) {
                    PFChip(text: "All Pathways", isSelected: selectedLevel == nil) {
                        selectedLevel = nil
                    }
                    ForEach(PFPathwayLevel.allCases, id: \.self) { level in
                        PFChip(text: level.rawValue, isSelected: selectedLevel == level) {
                            selectedLevel = level
                        }
                    }
                }
            }
        }
    }

    // MARK: - Pathways

    private var pathwaysSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            if filteredSessions.isEmpty {
                PFEmptyStateView(
                    systemImage: "book.fill",
                    title: "No pathways match this level yet",
                    message: "Try a different level filter to see more learning pathways.",
                    actionTitle: "Show all pathways",
                    action: { selectedLevel = nil }
                )
            }
            ForEach(filteredSessions) { session in
                NavigationLink(destination: GuidedPathDetailView(session: session)) {
                    PathwayCardView(session: session)
                }
                .buttonStyle(PFCardButtonStyle())
            }
        }
    }

    // MARK: - All chapters

    private var chapterNumbers: [Int] {
        PFChapterHelper.chapterNumbers(in: contentService)
    }

    /// Chapters shown so far in the flat list, in chapter-number
    /// order, ten at a time.
    private var visibleChapters: [Int] {
        Array(chapterNumbers.prefix(visibleChapterCount))
    }

    private var allChaptersSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "All chapters")
            if contentService.isLoadingIndex && chapterNumbers.isEmpty {
                ProgressView("Loading chapters...")
            } else if chapterNumbers.isEmpty {
                Text("Chapters will appear here once the course catalogue has loaded.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
            } else {
                Text("\(chapterNumbers.count) chapters in the catalogue. Open one to see its lessons.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(visibleChapters, id: \.self) { number in
                    NavigationLink(destination: ChapterDetailView(chapterNumber: number)) {
                        ChapterRow(chapterNumber: number)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PFCardButtonStyle())
                }
                if chapterNumbers.count > visibleChapters.count {
                    Text("Showing \(visibleChapters.count) of \(chapterNumbers.count) chapters")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PFSecondaryButton(title: "Load more chapters") {
                        visibleChapterCount += Self.chapterPageSize
                    }
                }
            }
        }
    }

    // MARK: - Guides, labs and tests

    /// Counts come from the loaded search index only. While it is
    /// still loading the subtitles carry no number rather than a
    /// made-up one.
    private func countSubtitle(count: Int?, singular: String, plural: String, suffix: String) -> String {
        if let count {
            return "\(count) \(count == 1 ? singular : plural) \(suffix)"
        }
        return "\(plural.capitalized) \(suffix)"
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Guides, labs and tests")
            NavigationLink(destination: GuideListView()) {
                LibraryRow(
                    title: "Guides",
                    subtitle: countSubtitle(
                        count: contentService.searchIndex?.counts.guide,
                        singular: "guide", plural: "guides",
                        suffix: "to read alongside the lessons"
                    ),
                    systemImage: "book"
                )
            }
            .buttonStyle(PFCardButtonStyle())
            NavigationLink(destination: LabListView()) {
                LibraryRow(
                    title: "Labs",
                    subtitle: countSubtitle(
                        count: contentService.searchIndex?.counts.lab,
                        singular: "lab", plural: "labs",
                        suffix: "to practise in"
                    ),
                    systemImage: "flask"
                )
            }
            .buttonStyle(PFCardButtonStyle())
            NavigationLink(destination: TestListView()) {
                LibraryRow(
                    title: "Tests",
                    subtitle: countSubtitle(
                        count: contentService.searchIndex?.counts.test,
                        singular: "test", plural: "tests",
                        suffix: "to check your understanding"
                    ),
                    systemImage: "checkmark.circle"
                )
            }
            .buttonStyle(PFCardButtonStyle())
        }
    }
}

// MARK: - Pathway card

/// One learning pathway card: number, title, level pill, the
/// session's own description, real lesson count and real completion
/// %. Nothing is gated, so there is no lock state on this card.
struct PathwayCardView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    let session: GuidedSession

    private var lessons: [SearchEntry] {
        PFChapterHelper.lessons(forSession: session, in: contentService)
    }

    private var completedCount: Int {
        lessons.filter { progressStore.isLessonComplete($0.id) }.count
    }

    private var progress: Double {
        guard !lessons.isEmpty else { return 0 }
        return Double(completedCount) / Double(lessons.count)
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
                    HStack(spacing: PFSpacing.sm) {
                        PFLevelPill(text: PFPathwayLevel.level(for: session).rawValue)
                        Text("Session \(session.id)")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                    }
                    Text(session.description)
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(lessons.count) lessons, \(completedCount) complete")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if !lessons.isEmpty {
                        PFProgressBar(progress: progress, height: 6)
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

// MARK: - Pathway list (in-stack destination)

/// The eight guided sessions as a plain list, for places that link
/// to Courses from inside another NavigationStack (for example the
/// Home quick links) where the Courses tab itself cannot be pushed.
struct GuidedPathwayListView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Text("Eight sessions that take you through the curriculum in order, from what a payment is to practice and interview preparation.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(ContentService.guidedSessions) { session in
                    NavigationLink(destination: GuidedPathDetailView(session: session)) {
                        PathwayCardView(session: session)
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
        .navigationTitle("Learning pathways")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Domain names

/// The 15 curriculum domains, exactly as listed on the live site.
/// No chapter-to-domain mapping is shown anywhere: that mapping is not
/// in the data, so domains are presented as an informational list only.
/// The list is currently not shown on the Courses screen; the types
/// stay for the drawer and future use.
enum PFDomainList {
    static let names: [String] = [
        "Foundations of Money and Payments",
        "Accounts, Ledger and Accounting",
        "Payment Lifecycle",
        "Messaging and Standards",
        "Domestic Payment Systems",
        "Cross-Border Payments",
        "Clearing, Settlement and Liquidity",
        "Cards and Alternative Payments",
        "Payment Architecture and Technology",
        "APIs and Integration",
        "Operations, Exceptions and Reconciliation",
        "Risk, Compliance and Regulation",
        "Payments Product and Business",
        "Business Analysis and Professional Practice",
        "Advanced and Emerging Payments"
    ]
}

// MARK: - Chapter row

struct ChapterRow: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var storeManager: StoreManager
    let chapterNumber: Int

    private var lessons: [SearchEntry] {
        PFChapterHelper.lessons(forChapter: chapterNumber, in: contentService)
    }

    private var completedCount: Int {
        lessons.filter { progressStore.isLessonComplete($0.id) }.count
    }

    /// True when neither the bundle containing this chapter nor the
    /// Integrated Course is owned.
    private var isLocked: Bool {
        !storeManager.isChapterUnlocked("ch\(chapterNumber)")
    }

    var body: some View {
        PFCard {
            HStack(alignment: .top, spacing: PFSpacing.md) {
                Text("\(chapterNumber)")
                    .font(.pfCardTitle.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.pfRoyal)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Color.pfRoyal.opacity(0.30), radius: 6, x: 0, y: 3)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text("Chapter \(chapterNumber)")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(PFChapterHelper.chapterTitle(for: lessons, number: chapterNumber))
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(lessons.count) lessons, \(completedCount) complete")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
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
                    if !lessons.isEmpty {
                        PFProgressBar(
                            progress: Double(completedCount) / Double(lessons.count),
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

// MARK: - Chapter detail

/// Lists one chapter's lessons, with completion checkmarks.
/// When the chapter is locked, a banner names the bundle that
/// unlocks it; the lessons stay listed and open to the lock screen.
struct ChapterDetailView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var storeManager: StoreManager
    let chapterNumber: Int

    @State private var showCheckout = false

    /// Lessons shown at first. Most chapters have fewer than ten
    /// lessons and show all of them; a longer chapter gets a
    /// Load more button instead of a very long list.
    @State private var visibleLessonCount = 10
    private static let lessonPageSize = 10

    private var lessons: [SearchEntry] {
        PFChapterHelper.lessons(forChapter: chapterNumber, in: contentService)
    }

    /// The lessons actually rendered: the first page(s) of the
    /// chapter's lessons.
    private var visibleLessons: [SearchEntry] {
        Array(lessons.prefix(visibleLessonCount))
    }

    private var completedCount: Int {
        lessons.filter { progressStore.isLessonComplete($0.id) }.count
    }

    /// True when neither the bundle containing this chapter nor the
    /// Integrated Course is owned.
    private var isLocked: Bool {
        !storeManager.isChapterUnlocked("ch\(chapterNumber)")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text(PFChapterHelper.chapterTitle(for: lessons, number: chapterNumber))
                        .font(.pfSectionTitle)
                        .foregroundColor(.pfNavy)
                    if !lessons.isEmpty {
                        Text("\(completedCount) of \(lessons.count) lessons complete")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                        PFProgressBar(progress: lessons.isEmpty ? 0 : Double(completedCount) / Double(lessons.count))
                    }
                }
                if contentService.isLoadingIndex && lessons.isEmpty {
                    ProgressView("Loading lessons...")
                } else if lessons.isEmpty {
                    Text("No lessons are available for this chapter yet. Check your connection and try again.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                }
                if isLocked {
                    lockBanner
                }
                ForEach(visibleLessons) { lesson in
                    NavigationLink(destination: LessonView(entry: lesson)) {
                        LessonRow(entry: lesson)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PFCardButtonStyle())
                }
                if lessons.count > visibleLessons.count {
                    Text("Showing \(visibleLessons.count) of \(lessons.count) lessons")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PFSecondaryButton(title: "Load more lessons") {
                        visibleLessonCount += Self.lessonPageSize
                    }
                }
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .navigationTitle("Chapter \(chapterNumber)")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Lock banner: names the bundle that unlocks this chapter and
    /// offers checkout. The lessons below stay listed and open to
    /// the lock screen, so browsing stays open.
    private var lockBanner: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.md) {
                    PFIconTile(systemImage: "lock.fill", size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Locked chapter")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        if let bundle = storeManager.unlockingProduct(for: "ch\(chapterNumber)") {
                            Text("Unlock this chapter with \(bundle.name) for \(storeManager.priceText(for: bundle.productID)).")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Unlock this chapter with The Integrated Course.")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                PFPrimaryButton(title: "See all courses") {
                    showCheckout = true
                }
            }
        }
        .sheet(isPresented: $showCheckout) {
            CheckoutView()
        }
    }
}

// MARK: - Library rows and lists

struct LibraryRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
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
}

struct GuideListView: View {
    @EnvironmentObject private var contentService: ContentService

    var body: some View {
        entryList(entries: contentService.allGuides, emptyText: "No guides are available yet. Check your connection and try again.", title: "Guides")
    }

    @ViewBuilder
    private func entryList(entries: [SearchEntry], emptyText: String, title: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                if contentService.isLoadingIndex && entries.isEmpty {
                    ProgressView("Loading...")
                } else if entries.isEmpty {
                    Text(emptyText)
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                }
                ForEach(entries) { entry in
                    NavigationLink(destination: EntryDetailView(entry: entry)) {
                        EntryRow(entry: entry)
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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LabListView: View {
    @EnvironmentObject private var contentService: ContentService

    private var labs: [SearchEntry] {
        contentService.searchIndex?.entries.filter { $0.type == .lab } ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                if contentService.isLoadingIndex && contentService.searchIndex == nil {
                    ProgressView("Loading...")
                } else if labs.isEmpty {
                    Text("No labs are available yet. Check your connection and try again.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                }
                ForEach(labs) { entry in
                    NavigationLink(destination: EntryDetailView(entry: entry)) {
                        EntryRow(entry: entry)
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
        .navigationTitle("Labs")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TestListView: View {
    @EnvironmentObject private var contentService: ContentService

    private var tests: [SearchEntry] {
        contentService.searchIndex?.entries.filter { $0.type == .test } ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                if contentService.isLoadingIndex && contentService.searchIndex == nil {
                    ProgressView("Loading...")
                } else if tests.isEmpty {
                    Text("No tests are available yet. Check your connection and try again.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                }
                ForEach(tests) { entry in
                    NavigationLink(destination: EntryDetailView(entry: entry)) {
                        EntryRow(entry: entry)
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
        .navigationTitle("Tests")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct EntryRow: View {
    let entry: SearchEntry

    private var systemImage: String {
        switch entry.type {
        case .lesson: return "play.fill"
        case .guide: return "book.fill"
        case .situation: return "briefcase.fill"
        case .lab: return "flask.fill"
        case .test: return "checkmark.circle.fill"
        case .faq: return "questionmark.circle.fill"
        }
    }

    var body: some View {
        PFCard {
            HStack(spacing: PFSpacing.md) {
                PFIconTile(systemImage: systemImage, size: 44)
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
}

// MARK: - Entry detail

/// Shows one guide, lab or test entry: title, type pill, full text.
struct EntryDetailView: View {
    let entry: SearchEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                PFPill(text: entry.type.displayName)
                Text(entry.title)
                    .font(.pfSectionTitle)
                    .foregroundColor(.pfNavy)
                Text(entry.text)
                    .font(.pfBody)
                    .foregroundColor(.pfNavy)
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .navigationTitle(entry.type.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Domain detail

/// A domain is informational only: its chapters are listed under
/// All chapters above, and no chapter mapping is invented.
struct DomainDetailView: View {
    let domainName: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Text(domainName)
                    .font(.pfSectionTitle)
                    .foregroundColor(.pfNavy)
                Text("Part of the Payments Training Hub curriculum.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                Text("The chapters for this domain are listed under All chapters above. Work through them in order, or follow the guided path from the start.")
                    .font(.pfBody)
                    .foregroundColor(.pfNavy)
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .navigationTitle("Domain")
        .navigationBarTitleDisplayMode(.inline)
    }
}
