// CoursesView.swift
// Payments Training Hub iOS - Learn tab: the courses index, learning pathways and the catalogue.
// Native SwiftUI only, no WebView. Uses the shared DesignSystem.
// No em dashes in any user-facing text.
//
// Adaptive layout: every screen here uses flexible stacks and frames
// (maxWidth: .infinity, no fixed widths), text that wraps instead of
// clipping, and safe-area aware ScrollViews. It is built to look right
// on an iPhone SE (320pt wide), a standard iPhone, a Plus, a Pro and a
// Pro Max, in portrait and in landscape.
//
// The three Learn sections do different jobs. Courses is the default:
// the course index, ten courses in reading order, each opening into
// its chapters and lessons like a navigation pane, with chapters
// numbered 1 to 99 and lessons one after another with prev/next, and
// nothing else on screen. No course starts open: every course is a
// row, and tapping it opens its chapter list. Learning Paths is the
// guided journey: six role paths filterable by level, then the eight
// guided sessions from the live site in order. Catalogue is the
// structured table of every chapter grouped by course, with guides,
// labs and tests below. Lesson counts and completion come from the
// real catalogue and real progress, and the section content sits
// directly under the section picker, so switching sections visibly
// changes the first screen. The shared interview and practice cards
// sit below the section content on the Learning Paths and Catalogue
// sections only: the Courses section stays uncluttered. Chapters are
// gated by purchase: a chapter's lessons unlock when its course, or
// the Integrated Course, is owned.
// The catalogue stays browsable: locked chapters show a lock state
// and open to a lock screen, never a dead end. Display numbers are
// course numbers from PFBookModeReadingOrder: internal chapter IDs
// are never shown.

import SwiftUI
import Foundation

// MARK: - Courses

struct CoursesView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var storeManager: StoreManager

    /// Opens the side drawer. Passed in from the tab bar so the menu
    /// button can sit in this screen's navigation bar, and only here:
    /// pushed detail views have no menu button and keep a clean back button.
    @Binding var isDrawerOpen: Bool

    @State private var selectedSection: LearnSection = .courses

    /// The level filter for the guided paths on the Learning Paths
    /// section only. It never filters the sessions or the Catalogue
    /// section. The level strings match LearningPath.level exactly.
    @State private var selectedPathLevel: PathLevelFilter = .all

    private enum LearnSection: String, CaseIterable {
        case courses = "Courses"
        case learningPaths = "Learning Paths"
        case catalogue = "Catalogue"
    }

    private enum PathLevelFilter: String, CaseIterable {
        case all = "All"
        case foundation = "Foundation"
        case intermediate = "Intermediate"
        case advanced = "Advanced"
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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
                        .id("learnTop")

                        // The section content comes first, directly
                        // under the picker, so switching sections
                        // visibly changes the first screen. The
                        // shared interview and practice cards below
                        // it appear on the Learning Paths and
                        // Catalogue sections only: the Courses
                        // section stays uncluttered, with nothing
                        // on screen but the course index itself.
                        if contentService.isLoadingIndex && contentService.searchIndex == nil {
                            VStack(alignment: .leading, spacing: PFSpacing.md) {
                                PFSkeletonView()
                                PFSkeletonView()
                                PFSkeletonView()
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Loading chapters")
                        } else if selectedSection == .courses {
                            coursesSection
                        } else if selectedSection == .learningPaths {
                            learningPathsIntroSection
                            levelFilterSection
                            guidedPathsSection
                            pathwaysSection
                        } else {
                            catalogueSection
                            librarySection
                        }

                        if selectedSection != .courses {
                            interviewSection

                            practiceSection

                            practiceExperiencesSection
                        }
                    }
                    .padding(PFSpacing.lg)
                }
                .background(Color.pfBackground)
                // Extra scrollable space at the bottom so the last card clears
                // the tab bar on every iPhone size.
                .pfTabBarClearance()
                .onChange(of: selectedSection) { _, _ in
                    // Switching sections returns to the top, so the
                    // new section's content is visible at once
                    // instead of hidden below the previous scroll
                    // position. The Dashboard segment picker uses
                    // the same scroll-to-top pattern.
                    withAnimation {
                        proxy.scrollTo("learnTop", anchor: .top)
                    }
                }
                .onAppear {
                    // The scroll rule: Back and tab switches land
                    // at the top, never at the restored offset.
                    proxy.scrollTo("learnTop", anchor: .top)
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

    // MARK: - Interview questions

    /// Situation-based interview questions for payments and BA
    /// roles. Shown below the Learning Paths and All Courses
    /// sections, so it is reachable without switching tabs.
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
                        Text("\(ContentManifest.interviewQuestionCount) situation-based payments and BA interview questions, each with a model answer.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.pfSecondaryText)
                        .pfDecorative()
                }
            }
        }
        .buttonStyle(PFCardButtonStyle())
        .accessibilityLabel("Interview Questions")
        .accessibilityHint("Opens \(ContentManifest.interviewQuestionCount) situation-based payments and BA interview questions")
    }

    // MARK: - Practice Mode

    /// All situations, full data first and search index fallback,
    /// so Practice Mode can draw its distractors from real takeaways.
    /// The same rule as the Home highlight: one definition of
    /// "first practice-eligible situation" in each place that
    /// offers Practice Mode.
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

    /// Practice Mode, shown below the Learning Paths and All
    /// Courses sections next to the Interview Questions card, so
    /// Practice is reachable from Learn as well as from Home and
    /// the drawer.
    /// Opens the first practice-eligible situation, exactly as the
    /// Home highlight does. While no situation has loaded yet, the
    /// card shows without navigating, so it never leads to an
    /// empty practice screen. Chapter browsing below is unchanged.
    private var practiceSection: some View {
        Group {
            if let situation = firstPracticeSituation {
                NavigationLink(destination: PracticeModeView(situation: situation, allSituations: practiceSituations)) {
                    practiceCard(showsChevron: true)
                }
                .buttonStyle(PFCardButtonStyle())
                .accessibilityLabel("Practice Mode")
                .accessibilityHint("Opens Practice Mode for a real payment scenario")
            } else {
                practiceCard(showsChevron: false)
                    .accessibilityLabel("Practice Mode. Payment Cases are still loading.")
            }
        }
    }

    /// The Practice card. The chevron only shows when the card
    /// navigates: while no situation has loaded, the card does not
    /// navigate and must not promise that it does.
    private func practiceCard(showsChevron: Bool) -> some View {
        PFCard {
            HStack(spacing: PFSpacing.md) {
                PFIconTile(systemImage: "flask.fill", size: 44)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text("Practice Mode")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Test yourself on real payment scenarios")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.pfSecondaryText)
                        .pfDecorative()
                }
            }
        }
    }

    // MARK: - Practice experiences

    /// The four practice experiences, shown below the Learning
    /// Paths and All Courses sections next to the Interview
    /// Questions and Practice Mode cards, so they are reachable
    /// from Learn as well as from Home and the drawer. Each row
    /// opens its experience directly. No counts in the copy: the
    /// experiences carry no catalogue counts.
    private var practiceExperiencesSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Practice experiences")
            NavigationLink(destination: PaymentLifecycleSimulatorView()) {
                LibraryRow(
                    title: "Payment Simulator",
                    subtitle: "Follow a payment through its lifecycle, step by step",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .buttonStyle(PFCardButtonStyle())
            .accessibilityLabel("Payment Simulator")
            .accessibilityHint("Opens the Payment Simulator")
            NavigationLink(destination: ISO20022ExplorerView()) {
                LibraryRow(
                    title: "ISO 20022 Explorer",
                    subtitle: "Look up ISO 20022 messages and their fields",
                    systemImage: "doc.text.magnifyingglass"
                )
            }
            .buttonStyle(PFCardButtonStyle())
            .accessibilityLabel("ISO 20022 Explorer")
            .accessibilityHint("Opens the ISO 20022 Explorer")
            NavigationLink(destination: ExceptionInvestigationLabView()) {
                LibraryRow(
                    title: "Exception Lab",
                    subtitle: "Investigate payment exceptions and trace what went wrong",
                    systemImage: "exclamationmark.triangle.fill"
                )
            }
            .buttonStyle(PFCardButtonStyle())
            .accessibilityLabel("Exception Lab")
            .accessibilityHint("Opens the Exception Lab")
            NavigationLink(destination: BAProductStudioView()) {
                LibraryRow(
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

    // MARK: - Learning Paths section

    /// The Learning Paths intro: the purpose of this section, stated
    /// directly under the picker so it reads differently from the
    /// All Courses section at once. This section is a journey:
    /// paths by role and level, then sessions in order. It uses the
    /// same lessons as All Courses, arranged as a journey instead
    /// of a catalogue.
    private var learningPathsIntroSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            Text("Guided paths and sessions")
                .font(.pfScreenTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Text("Follow a guided path for one role, or work through the eight sessions in order. Pick a path or a session to see its lessons and practice situations.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The guided paths matching the selected level, in catalogue
    /// order. All shows every path. The filter raw values are the
    /// LearningPath level strings, so every path matches exactly
    /// one level filter.
    private var filteredPaths: [LearningPath] {
        guard selectedPathLevel != .all else { return LearningPath.all }
        return LearningPath.all.filter { $0.level == selectedPathLevel.rawValue }
    }

    // MARK: - Level filter

    /// The level filter for the guided paths only, as always-visible
    /// chips in the Search difficulty-pills pattern: one tap picks
    /// a level, tapping All clears it. Sessions below are never
    /// filtered: they have no level, and they run in a fixed order.
    private var levelFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PFSpacing.sm) {
                Text("Level")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfSecondaryText)
                    .accessibilityHidden(true)
                ForEach(PathLevelFilter.allCases, id: \.self) { filter in
                    PFChip(text: filter.rawValue, isSelected: selectedPathLevel == filter) {
                        selectedPathLevel = filter
                    }
                    .pfMinimumTouchTarget()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Level filter")
    }

    // MARK: - Guided learning paths

    /// The guided learning paths matching the level filter, in the
    /// mockup's Courses card layout: icon tile left, title, two-line
    /// description, "Level • N lessons", progress bar with % at the
    /// right, bookmark top right. Counts and progress are real,
    /// from the catalogue and ProgressStore. Tapping a card opens
    /// the same PathDetailView as before.
    private var guidedPathsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Guided paths")
            Text("Showing \(filteredPaths.count) of \(LearningPath.all.count) paths")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            if filteredPaths.isEmpty {
                Text("No paths at this level yet.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                PFSecondaryButton(title: "Show all paths") {
                    selectedPathLevel = .all
                }
            } else {
                ForEach(filteredPaths) { path in
                    NavigationLink(destination: PathDetailView(path: path)) {
                        GuidedPathCardView(path: path)
                    }
                    .buttonStyle(PFCardButtonStyle())
                }
            }
        }
    }

    // MARK: - Courses section

    /// The first lesson in reading order the learner has not
    /// completed yet, or nil when every lesson is complete.
    private var nextLessonToRead: SearchEntry? {
        contentService.readingOrderLessons.first { !progressStore.isLessonComplete($0.id) }
    }

    /// The courses index: ten courses in reading order, chapters
    /// numbered 1 to 99, then the chapter held outside the main
    /// reading path. The index behaves like a navigation pane:
    /// every course is a row, no course starts open, and tapping
    /// a course opens its chapter list. A Continue reading card
    /// sits above the courses. Nothing else shares this screen:
    /// no interview, practice or experience cards, so the index
    /// reads like an index.
    private var coursesSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            Text("Courses")
                .font(.pfScreenTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Text("Ten courses in reading order, 99 chapters, each lesson following the last. Open a course to see its chapters, then open a chapter to read its lessons.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if contentService.isLoadingIndex && chapterNumbers.isEmpty {
                ProgressView("Loading chapters...")
            } else if chapterNumbers.isEmpty {
                Text("Chapters will appear here once the course catalogue has loaded.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
            } else {
                continueReadingCard
                ForEach(Array(ProductCatalogue.partProducts.enumerated()), id: \.element.id) { index, product in
                    NavigationLink(destination: CourseDetailView(product: product, courseNumber: index + 1, chapterNumbers: PFChapterHelper.readingOrderChapterNumbers(for: product))) {
                        CourseIndexRow(product: product, courseNumber: index + 1, chapterNumbers: PFChapterHelper.readingOrderChapterNumbers(for: product))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PFCardButtonStyle())
                }
                heldOutSection
            }
        }
    }

    /// Continue reading: the next unread lesson in reading order,
    /// with its chapter and lesson numbers. When every lesson is
    /// complete, a finished note instead of a dead card.
    private var continueReadingCard: some View {
        Group {
            if let lesson = nextLessonToRead {
                NavigationLink(destination: LessonView(entry: lesson)) {
                    PFCard {
                        HStack(spacing: PFSpacing.md) {
                            PFIconTile(systemImage: "book.fill", size: 44)
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                Text("Continue reading")
                                    .font(.pfCaptionBold)
                                    .foregroundColor(.pfRoyal)
                                Text(lesson.title)
                                    .font(.pfCardTitle)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let position = PFChapterHelper.readingPositionLabel(for: lesson, in: contentService) {
                                    Text(position)
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.pfSecondaryText)
                                .pfDecorative()
                        }
                    }
                }
                .buttonStyle(PFCardButtonStyle())
                .accessibilityLabel("Continue reading: \(lesson.title)")
            } else {
                PFCard {
                    HStack(spacing: PFSpacing.md) {
                        PFIconTile(systemImage: "checkmark.seal.fill", size: 44)
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text("You have finished the full course")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                            Text("Every lesson is complete. Revisit any chapter, or try the tests and practice experiences.")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    /// Chapters held outside the main reading path, listed after
    /// the parts by title, with no book number. Hidden while the
    /// catalogue has no lessons for them.
    private var heldOutSection: some View {
        let heldOut = PFBookModeReadingOrder.heldOutInternalNumbers.sorted().filter { chapterNumbers.contains($0) }
        return Group {
            if !heldOut.isEmpty {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    PFSectionHeader(title: "Outside the main reading path")
                    Text("Extra reading, outside the numbered chapters. Read it any time; it is not part of the sequence.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(heldOut, id: \.self) { number in
                        NavigationLink(destination: ChapterDetailView(chapterNumber: number)) {
                            ChapterRow(chapterNumber: number)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PFCardButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: - Pathways

    /// The eight guided sessions in order, under their own heading.
    /// Sessions are never level-filtered. Tapping a card opens the
    /// same GuidedPathDetailView as before.
    private var pathwaysSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Sessions in order")
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
    }

    // MARK: - Catalogue section, as a table grouped by course

    private var chapterNumbers: [Int] {
        PFChapterHelper.chapterNumbers(in: contentService)
    }

    /// The ten courses in catalogue order: every product with
    /// chapters except The Integrated Course (which contains every
    /// chapter). The standalone products contain no chapters and
    /// are excluded by the chapterIDs check. The ten courses
    /// partition the 99 in-course chapters exactly: no chapter in
    /// two courses, no in-course chapter missing, as the entitlement
    /// tests assert. The held-out ch37 sits in no course and stays
    /// reachable without purchase. Grouping by course therefore
    /// reaches every chapter the old flat list reached, with no
    /// chapter lost and none repeated.
    private var chapterBundles: [CourseProduct] {
        ProductCatalogue.products.filter { product in
            product.productID != ProductCatalogue.fullCourseProductID
                && !product.chapterIDs.isEmpty
        }
    }

    /// The catalogue as a structured table: one row per chapter,
    /// grouped under its course, with columns for the chapter
    /// number, the chapter title, the lesson count, and access.
    /// Course bands head each group. Rows alternate white and
    /// off-white with hairline dividers, and every row opens the
    /// same ChapterDetailView the old chapter list opened, with
    /// the same lock state. No chapter is paginated away. Colours
    /// are the fixed pf palette, identical in light and dark mode:
    /// navy band with white text, navy titles, secondary captions,
    /// success check for unlocked chapters, secondary lock for
    /// locked ones. Ownership is read only, through
    /// StoreManager.isProductUnlocked: no gating rule changes here.
    private var catalogueSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            Text("Catalogue")
                .font(.pfScreenTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Text("Every chapter grouped by the course that unlocks it. Open a chapter to see its lessons.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if contentService.isLoadingIndex && chapterNumbers.isEmpty {
                ProgressView("Loading chapters...")
            } else if chapterNumbers.isEmpty {
                Text("Chapters will appear here once the course catalogue has loaded.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
            } else {
                Text("\(chapterBundles.count) courses, \(chapterNumbers.count) chapters in the catalogue.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A course shows Owned when you own it or The Integrated Course.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                catalogueTable
            }
        }
    }

    /// The catalogue table: a header row, then one navy course band
    /// and its chapter rows per course. The whole table sits in one
    /// bordered container so the columns read as a table, not as
    /// loose cards.
    private var catalogueTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: PFSpacing.sm) {
                Text("Ch.")
                    .frame(width: 36, alignment: .leading)
                Text("Chapter")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Lessons")
                    .frame(width: 52, alignment: .trailing)
                Text("Access")
                    .frame(width: 44, alignment: .trailing)
            }
            .font(.pfCaptionBold)
            .foregroundColor(.white)
            .padding(.horizontal, PFSpacing.md)
            .padding(.vertical, PFSpacing.sm)
            .background(Color.pfNavy)
            ForEach(chapterBundles) { product in
                catalogueCourseBand(product: product)
                ForEach(Array(PFChapterHelper.readingOrderChapterNumbers(for: product).enumerated()), id: \.element) { index, number in
                    NavigationLink(destination: ChapterDetailView(chapterNumber: number)) {
                        CatalogueChapterRow(chapterNumber: number, isAlternate: index % 2 == 1)
                    }
                    .buttonStyle(PFCardButtonStyle())
                }
            }
        }
        .background(Color.pfCard)
        .cornerRadius(PFSpacing.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                .stroke(Color.pfBorder, lineWidth: 1)
        )
        .shadow(color: Color.pfNavy.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    /// One navy course band inside the catalogue table: the course
    /// name, its chapter and lesson counts, and its Owned or Locked
    /// state. Read only: ownership comes from StoreManager.
    private func catalogueCourseBand(product: CourseProduct) -> some View {
        HStack(spacing: PFSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(.pfCaptionBold)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(PFChapterHelper.readingOrderChapterNumbers(for: product).count) chapters")
                    .font(.pfCaption)
                    .foregroundColor(.white.opacity(0.8))
            }
            Spacer()
            // Owned/Locked pill: white text on the royal band for
            // both states (9.79:1, AAA), told apart by the icon
            // and the word, never by colour alone. Gold text on
            // royal measured 4.09:1, below AA for caption text.
            HStack(spacing: 4) {
                Image(systemName: storeManager.isProductUnlocked(product.productID) ? "checkmark.circle.fill" : "lock.fill")
                    .font(.pfCaption.weight(.semibold))
                    .accessibilityHidden(true)
                Text(storeManager.isProductUnlocked(product.productID) ? "Owned" : "Locked")
                    .font(.pfCaptionBold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.14))
            .clipShape(Capsule())
        }
        .padding(.horizontal, PFSpacing.md)
        .padding(.vertical, PFSpacing.sm)
        .background(Color.pfRoyal)
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
                        suffix: "to read"
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
                        suffix: "to take, with questions, scores and explanations"
                    ),
                    systemImage: "checkmark.circle"
                )
            }
            .buttonStyle(PFCardButtonStyle())
        }
    }
}

// MARK: - Pathway card

/// One learning pathway card: number, title, the session's own
/// description, real lesson count and real completion %. Nothing is
/// gated, so there is no lock state on this card.
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

    /// "69 lessons, 12 complete · About 6 hrs 10 min", or without
    /// the estimate when no durations are known. When nothing is
    /// complete yet the ", 0 complete" tail is omitted: a fresh
    /// user never sees a zero counter.
    private var summaryLine: String {
        let base = completedCount > 0
            ? "\(lessons.count) lessons, \(completedCount) complete"
            : "\(lessons.count) lessons"
        guard let total = LessonDurations.totalLabel(for: lessons) else { return base }
        return base + " · " + total
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
                    Text("Session \(session.id)")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                    Text(session.description)
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(summaryLine)
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if !lessons.isEmpty && completedCount > 0 {
                        PFProgressBar(progress: progress, height: 6)
                            .padding(.top, PFSpacing.xs)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.pfSecondaryText)
                    .padding(.top, PFSpacing.xs)
                    .pfDecorative()
            }
        }
    }
}

// MARK: - Course index row

/// One course in the Courses index: a row that opens the course
/// detail, never an expanding group. The thumbnail of the course's
/// first lesson with one sits beside the title when the website
/// exposes thumbnails; otherwise the course number badge shows.
/// Lesson counts, completion and the Owned state are real: lessons
/// from the catalogue, completion from ProgressStore, ownership
/// read only through StoreManager.isProductUnlocked, which counts
/// The Integrated Course as unlocking every course. No price is
/// shown here and no gating rule changes.
struct CourseIndexRow: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var storeManager: StoreManager
    let product: CourseProduct
    let courseNumber: Int
    let chapterNumbers: [Int]

    /// Every lesson of every chapter in this course, in reading
    /// order, deduped by id. Courses never share a chapter, so no
    /// lesson repeats; the dedupe guards the count if the
    /// catalogue ever overlaps.
    private var lessons: [SearchEntry] {
        var seen: Set<String> = []
        var result: [SearchEntry] = []
        for number in chapterNumbers {
            for lesson in PFChapterHelper.lessons(forChapter: number, in: contentService) {
                if seen.insert(lesson.id).inserted {
                    result.append(lesson)
                }
            }
        }
        return result
    }

    private var completedCount: Int {
        lessons.filter { progressStore.isLessonComplete($0.id) }.count
    }

    /// "7 chapters, 48 lessons, 12 complete", plus the total
    /// duration estimate when durations are known. When nothing is
    /// complete yet the ", 0 complete" tail is omitted: a fresh
    /// user never sees a zero counter.
    private var summaryLine: String {
        let chapterWord = chapterNumbers.count == 1 ? "chapter" : "chapters"
        let base = completedCount > 0
            ? "\(chapterNumbers.count) \(chapterWord), \(lessons.count) lessons, \(completedCount) complete"
            : "\(chapterNumbers.count) \(chapterWord), \(lessons.count) lessons"
        guard let total = LessonDurations.totalLabel(for: lessons) else { return base }
        return base + " · " + total
    }

    private var progress: Double {
        guard !lessons.isEmpty else { return 0 }
        return Double(completedCount) / Double(lessons.count)
    }

    /// True when this course is owned outright, or The Integrated
    /// Course is owned. Read only: this view never changes any
    /// entitlement, it only labels the existing state.
    private var isUnlocked: Bool {
        storeManager.isProductUnlocked(product.productID)
    }

    private var thumbnailPath: String? {
        PFChapterHelper.courseThumbnailPath(chapterNumbers: chapterNumbers, in: contentService)
    }

    var body: some View {
        PFCard {
            HStack(alignment: .top, spacing: PFSpacing.md) {
                if thumbnailPath != nil {
                    PFThumbnailView(thumbnailPath: thumbnailPath, size: 44, cornerRadius: 12)
                } else {
                    Text("\(courseNumber)")
                        .font(.pfCardTitle.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.pfRoyal)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: Color.pfRoyal.opacity(0.30), radius: 6, x: 0, y: 3)
                }
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text("Course \(courseNumber)")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(product.name)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(product.tagline)
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(summaryLine)
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if isUnlocked {
                        PFPill(
                            text: "Owned",
                            background: Color.pfSuccess.opacity(0.12),
                            foreground: .pfSuccess
                        )
                    } else {
                        PFPill(
                            text: "Locked",
                            background: Color.pfGoldSoft,
                            foreground: Color.pfGoldText
                        )
                    }
                    if !lessons.isEmpty && completedCount > 0 {
                        PFProgressBar(progress: progress, height: 6)
                            .padding(.top, PFSpacing.xs)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.pfSecondaryText)
                    .padding(.top, PFSpacing.xs)
                    .pfDecorative()
            }
        }
    }
}

// MARK: - Course detail

/// One course opened from the index: its thumbnail beside the
/// title, the highlighted agenda block (the course description:
/// why take this course), its Owned or Locked state, and its
/// chapters in reading order, each opening ChapterDetailView.
/// Prev/next course links at the foot keep the courses reading one
/// after another. Gating is unchanged: each chapter applies its
/// own lock state, and the lock card below names the price through
/// StoreManager, like the chapter lock banner.
struct CourseDetailView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var storeManager: StoreManager
    let product: CourseProduct
    let courseNumber: Int
    let chapterNumbers: [Int]

    @State private var showCheckout = false

    private var lessons: [SearchEntry] {
        var seen: Set<String> = []
        var result: [SearchEntry] = []
        for number in chapterNumbers {
            for lesson in PFChapterHelper.lessons(forChapter: number, in: contentService) {
                if seen.insert(lesson.id).inserted {
                    result.append(lesson)
                }
            }
        }
        return result
    }

    private var completedCount: Int {
        lessons.filter { progressStore.isLessonComplete($0.id) }.count
    }

    private var isUnlocked: Bool {
        storeManager.isProductUnlocked(product.productID)
    }

    private var thumbnailPath: String? {
        PFChapterHelper.courseThumbnailPath(chapterNumbers: chapterNumbers, in: contentService)
    }

    private var courseIndex: Int {
        courseNumber - 1
    }

    private var previousCourse: CourseProduct? {
        let courses = ProductCatalogue.partProducts
        guard courseIndex > 0, courses.indices.contains(courseIndex - 1) else { return nil }
        return courses[courseIndex - 1]
    }

    private var nextCourse: CourseProduct? {
        let courses = ProductCatalogue.partProducts
        guard courses.indices.contains(courseIndex + 1) else { return nil }
        return courses[courseIndex + 1]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                HStack(alignment: .top, spacing: PFSpacing.md) {
                    if thumbnailPath != nil {
                        PFThumbnailView(thumbnailPath: thumbnailPath, size: 72, cornerRadius: 14)
                    }
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Course \(courseNumber) of \(ProductCatalogue.partProducts.count)")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                        Text(product.name)
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(product.tagline)
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                PFAgendaBlock(title: "Why take this course", agenda: product.description)
                HStack(spacing: PFSpacing.sm) {
                    if isUnlocked {
                        PFPill(
                            text: "Owned",
                            background: Color.pfSuccess.opacity(0.12),
                            foreground: .pfSuccess
                        )
                    } else {
                        PFPill(
                            text: "Locked",
                            background: Color.pfGoldSoft,
                            foreground: Color.pfGoldText
                        )
                    }
                    Text("\(chapterNumbers.count) chapters, \(lessons.count) lessons")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                }
                if completedCount > 0 {
                    Text("\(completedCount) of \(lessons.count) lessons complete")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                    PFProgressBar(progress: lessons.isEmpty ? 0 : Double(completedCount) / Double(lessons.count))
                }
                if !isUnlocked {
                    lockCard
                }
                PFSectionHeader(title: "Chapters")
                if contentService.isLoadingIndex && lessons.isEmpty {
                    ProgressView("Loading chapters...")
                } else if chapterNumbers.isEmpty {
                    Text("Chapters will appear here once the course catalogue has loaded.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                } else {
                    ForEach(chapterNumbers, id: \.self) { number in
                        NavigationLink(destination: ChapterDetailView(chapterNumber: number)) {
                            ChapterRow(chapterNumber: number)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PFCardButtonStyle())
                    }
                }
                courseNavFooter
            }
            .padding(PFSpacing.lg)
            .id("courseTop")
        }
        .pfScrollToTopOnAppear("courseTop")
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle("Course \(courseNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCheckout) {
            CheckoutView()
        }
    }

    /// Lock card: names the price and offers checkout. Chapters
    /// below stay listed and open to their own lock states, so
    /// browsing stays open.
    private var lockCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.md) {
                    PFIconTile(systemImage: "lock.fill", size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Locked course")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text("Unlock this course with \(product.name) for \(storeManager.priceText(for: product.productID)), with 1 year of access. The Integrated Course unlocks every course too.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                PFPrimaryButton(title: "See purchase options") {
                    showCheckout = true
                }
            }
        }
    }

    /// Prev/next course footer in reading order, so courses read
    /// one after another. The first course has no previous, the
    /// last has no next.
    private var courseNavFooter: some View {
        HStack(spacing: PFSpacing.md) {
            if let previous = previousCourse {
                NavigationLink(destination: CourseDetailView(product: previous, courseNumber: courseNumber - 1, chapterNumbers: PFChapterHelper.readingOrderChapterNumbers(for: previous))) {
                    courseNavLabel(product: previous, number: courseNumber - 1, direction: "Previous course")
                }
                .buttonStyle(PFCardButtonStyle())
            }
            Spacer()
            if let next = nextCourse {
                NavigationLink(destination: CourseDetailView(product: next, courseNumber: courseNumber + 1, chapterNumbers: PFChapterHelper.readingOrderChapterNumbers(for: next))) {
                    courseNavLabel(product: next, number: courseNumber + 1, direction: "Next course")
                }
                .buttonStyle(PFCardButtonStyle())
            }
        }
    }

    private func courseNavLabel(product: CourseProduct, number: Int, direction: String) -> some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                Text(direction)
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfRoyal)
                Text("Course \(number)")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.pfNavy)
                Text(product.name)
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Catalogue chapter row

/// One chapter row inside the catalogue table: the chapter number
/// (or the chapter thumbnail when the website exposes one), the
/// chapter title, the lesson count, and the access icon. Columns
/// align with the table header in catalogueTable: 36pt number,
/// flexible title, 52pt lesson count, 44pt access. Alternate rows
/// carry the off-white tint. Colours are the fixed pf palette,
/// identical in light and dark mode.
struct CatalogueChapterRow: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var storeManager: StoreManager
    let chapterNumber: Int
    let isAlternate: Bool

    private var lessons: [SearchEntry] {
        PFChapterHelper.lessons(forChapter: chapterNumber, in: contentService)
    }

    private var bookNumber: Int? {
        PFBookModeReadingOrder.bookNumber(forInternalNumber: chapterNumber)
    }

    private var isLocked: Bool {
        !storeManager.isChapterUnlocked("ch\(chapterNumber)")
    }

    private var thumbnailPath: String? {
        PFChapterHelper.chapterThumbnailPath(forChapter: chapterNumber, in: contentService)
    }

    var body: some View {
        HStack(spacing: PFSpacing.sm) {
            if thumbnailPath != nil {
                PFThumbnailView(thumbnailPath: thumbnailPath, size: 36, cornerRadius: 8)
            } else {
                Text(bookNumber.map(String.init) ?? "•")
                    .font(.pfCaptionBold)
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.pfRoyal)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                if let bookNumber {
                    Text("Chapter \(bookNumber)")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                }
                Text(PFChapterHelper.chapterTitle(for: lessons, number: chapterNumber))
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.pfNavy)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(lessons.count)")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .frame(width: 52, alignment: .trailing)
            Image(systemName: isLocked ? "lock.fill" : "checkmark.circle.fill")
                .font(.pfBody.weight(.semibold))
                .foregroundColor(isLocked ? .pfSecondaryText : .pfSuccess)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, PFSpacing.md)
        .padding(.vertical, PFSpacing.sm)
        .background(isAlternate ? Color.pfBackground : Color.pfCard)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.pfBorder)
                .frame(height: 1)
        }
        .contentShape(Rectangle())
    }
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

    /// "8 lessons, 3 complete · About 1 hr 20 min", or without the
    /// estimate when no durations are known. When nothing is
    /// complete yet the ", 0 complete" tail is omitted: a fresh
    /// user never sees a zero counter.
    private var summaryLine: String {
        let base = completedCount > 0
            ? "\(lessons.count) lessons, \(completedCount) complete"
            : "\(lessons.count) lessons"
        guard let total = LessonDurations.totalLabel(for: lessons) else { return base }
        return base + " · " + total
    }

    /// True when neither the course containing this chapter nor the
    /// Integrated Course is owned.
    private var isLocked: Bool {
        !storeManager.isChapterUnlocked("ch\(chapterNumber)")
    }

    /// The book chapter number shown on the badge and caption, or
    /// nil for a chapter held outside the main reading path: the
    /// internal chapter number is never shown.
    private var bookNumber: Int? {
        PFBookModeReadingOrder.bookNumber(forInternalNumber: chapterNumber)
    }

    /// The chapter thumbnail, when the website exposes one for a
    /// lesson in this chapter. The thumbnail replaces the number
    /// badge; the caption below still names the chapter number.
    private var thumbnailPath: String? {
        PFChapterHelper.chapterThumbnailPath(forChapter: chapterNumber, in: contentService)
    }

    var body: some View {
        PFCard {
            HStack(alignment: .top, spacing: PFSpacing.md) {
                if thumbnailPath != nil {
                    PFThumbnailView(thumbnailPath: thumbnailPath, size: 44, cornerRadius: 12)
                } else {
                    Text(bookNumber.map(String.init) ?? "•")
                        .font(.pfCardTitle.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.pfRoyal)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: Color.pfRoyal.opacity(0.30), radius: 6, x: 0, y: 3)
                }
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    if let bookNumber {
                        Text("Chapter \(bookNumber)")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Outside the main reading path")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(PFChapterHelper.chapterTitle(for: lessons, number: chapterNumber))
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(summaryLine)
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if isLocked {
                        HStack(spacing: PFSpacing.xs) {
                            Image(systemName: "lock.fill")
                                .font(.pfCaption.weight(.semibold))
                                .pfDecorative()
                            Text("Premium")
                                .font(.pfCaptionBold)
                        }
                        .foregroundColor(.pfGold)
                    }
                    if !lessons.isEmpty && completedCount > 0 {
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
                    .pfDecorative()
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

    /// "About 1 hr 20 min in total, 45 min left", or just the
    /// total when the chapter is finished. Nil when no durations
    /// are known.
    private var timeLine: String? {
        guard let total = LessonDurations.totalLabel(for: lessons) else { return nil }
        let remaining = lessons.filter { !progressStore.isLessonComplete($0.id) }
            .reduce(0) { $0 + (LessonDurations.seconds(for: $1.id) ?? 0) }
        guard remaining > 0 else { return total + " in total" }
        return total + " in total, " + LessonDurations.durationText(remaining) + " left"
    }

    /// True when neither the course containing this chapter nor the
    /// Integrated Course is owned.
    private var isLocked: Bool {
        !storeManager.isChapterUnlocked("ch\(chapterNumber)")
    }

    /// The chapter agenda, from the chapter's opening lesson (see
    /// PFChapterHelper.chapterAgenda). Nil when the website
    /// exposes no agenda for the chapter: no agenda block shows.
    private var chapterAgenda: String? {
        PFChapterHelper.chapterAgenda(forChapter: chapterNumber, in: contentService)
    }

    /// The chapter thumbnail, when the website exposes one. It
    /// sits beside the chapter title.
    private var thumbnailPath: String? {
        PFChapterHelper.chapterThumbnailPath(forChapter: chapterNumber, in: contentService)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                HStack(alignment: .top, spacing: PFSpacing.md) {
                    if thumbnailPath != nil {
                        PFThumbnailView(thumbnailPath: thumbnailPath, size: 64, cornerRadius: 14)
                    }
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text(PFChapterHelper.chapterTitle(for: lessons, number: chapterNumber))
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                        if !lessons.isEmpty {
                            if completedCount > 0 {
                                Text("\(completedCount) of \(lessons.count) lessons complete")
                                    .font(.pfCaptionBold)
                                    .foregroundColor(.pfRoyal)
                            } else {
                                Text("\(lessons.count) lessons")
                                    .font(.pfCaptionBold)
                                    .foregroundColor(.pfSecondaryText)
                            }
                            if let timeLine {
                                Text(timeLine)
                                    .font(.pfCaption)
                                    .foregroundColor(.pfSecondaryText)
                            }
                            if completedCount > 0 {
                                PFProgressBar(progress: Double(completedCount) / Double(lessons.count))
                            }
                        }
                    }
                }
                if let chapterAgenda {
                    PFAgendaBlock(title: "Why take this chapter", agenda: chapterAgenda)
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
                    // A locked lesson never navigates into LessonView:
                    // tapping it opens checkout, where the price and
                    // the Buy button live. Free lessons (the first
                    // lesson of the chapter, or a sequential sample)
                    // and unlocked lessons navigate normally. Rows
                    // show the lesson number inside the chapter.
                    if isLocked && !PFChapterHelper.isFreeLesson(lesson, in: contentService) {
                        Button {
                            showCheckout = true
                        } label: {
                            LessonRow(entry: lesson, showsLessonNumber: true)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PFCardButtonStyle())
                        .accessibilityLabel("\(lesson.title), locked. Tap to see the price.")
                    } else {
                        NavigationLink(destination: LessonView(entry: lesson)) {
                            LessonRow(entry: lesson, showsLessonNumber: true)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PFCardButtonStyle())
                    }
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
                chapterNavFooter
            }
            .padding(PFSpacing.lg)
            .id("chapterTop")
        }
        .pfScrollToTopOnAppear("chapterTop")
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle(PFBookModeReadingOrder.chapterLabel(forInternalNumber: chapterNumber) ?? PFChapterHelper.chapterTitle(for: lessons, number: chapterNumber))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Prev/next chapter footer in reading order, so chapters read
    /// one after another. The first course chapter has
    /// no previous, the last has no next, and a held-out chapter
    /// has neither. Gating is unchanged: the destination chapter
    /// applies its own lock state.
    private var chapterNavFooter: some View {
        let adjacent = PFBookModeReadingOrder.adjacentChapters(forInternalNumber: chapterNumber)
        return HStack(spacing: PFSpacing.md) {
            if let previous = adjacent.previous {
                NavigationLink(destination: ChapterDetailView(chapterNumber: previous)) {
                    chapterNavLabel(number: previous, direction: "Previous chapter")
                }
                .buttonStyle(PFCardButtonStyle())
            }
            Spacer()
            if let next = adjacent.next {
                NavigationLink(destination: ChapterDetailView(chapterNumber: next)) {
                    chapterNavLabel(number: next, direction: "Next chapter")
                }
                .buttonStyle(PFCardButtonStyle())
            }
        }
    }

    /// One prev/next chapter link: the direction, the book chapter
    /// label and the chapter title.
    private func chapterNavLabel(number: Int, direction: String) -> some View {
        let title = PFChapterHelper.chapterTitle(
            for: PFChapterHelper.lessons(forChapter: number, in: contentService),
            number: number
        )
        let label = PFBookModeReadingOrder.chapterLabel(forInternalNumber: number) ?? title
        return PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                Text(direction)
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfRoyal)
                Text(label)
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.pfNavy)
                Text(title)
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Lock banner: names the course that unlocks this chapter and
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
                        if let part = storeManager.unlockingProduct(for: "ch\(chapterNumber)") {
                            Text("Unlock this chapter with \(part.name) for \(storeManager.priceText(for: part.productID)), with 1 year of access.")
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
                PFPrimaryButton(title: "See purchase options") {
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
                    .pfDecorative()
            }
        }
    }
}

struct GuideListView: View {
    @EnvironmentObject private var contentService: ContentService

    @State private var visibleCount: Int = 20

    private static let pageSize = 20

    var body: some View {
        entryList(entries: contentService.allGuides, emptyText: "No guides are available yet. Check your connection and try again.", title: "Guides")
    }

    @ViewBuilder
    private func entryList(entries: [SearchEntry], emptyText: String, title: String) -> some View {
        let visibleEntries = Array(entries.prefix(visibleCount))
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                if contentService.isLoadingIndex && entries.isEmpty {
                    ProgressView("Loading...")
                } else if entries.isEmpty {
                    Text(emptyText)
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                }
                ForEach(visibleEntries) { entry in
                    NavigationLink(destination: EntryDetailView(entry: entry)) {
                        EntryRow(entry: entry)
                    }
                    .buttonStyle(PFCardButtonStyle())
                }
                if entries.count > visibleEntries.count {
                    Text("Showing \(visibleEntries.count) of \(entries.count) guides")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PFSecondaryButton(title: "Load more guides") {
                        visibleCount += Self.pageSize
                    }
                }
            }
            .padding(PFSpacing.lg)
            .id("guidesTop")
        }
        .pfScrollToTopOnAppear("guidesTop")
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .onChange(of: entries) { _, _ in
            visibleCount = Self.pageSize
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LabListView: View {
    @EnvironmentObject private var contentService: ContentService

    @State private var visibleCount: Int = 20

    private static let pageSize = 20

    private var labs: [SearchEntry] {
        contentService.searchIndex?.entries.filter { $0.type == .lab } ?? []
    }

    private var visibleLabs: [SearchEntry] {
        Array(labs.prefix(visibleCount))
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
                ForEach(visibleLabs) { entry in
                    NavigationLink(destination: EntryDetailView(entry: entry)) {
                        EntryRow(entry: entry)
                    }
                    .buttonStyle(PFCardButtonStyle())
                }
                if labs.count > visibleLabs.count {
                    Text("Showing \(visibleLabs.count) of \(labs.count) labs")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PFSecondaryButton(title: "Load more labs") {
                        visibleCount += Self.pageSize
                    }
                }
            }
            .padding(PFSpacing.lg)
            .id("labsTop")
        }
        .pfScrollToTopOnAppear("labsTop")
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .onChange(of: labs) { _, _ in
            visibleCount = Self.pageSize
        }
        .navigationTitle("Labs")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TestListView: View {
    @EnvironmentObject private var contentService: ContentService

    @State private var visibleCount: Int = 20

    private static let pageSize = 20

    private var tests: [SearchEntry] {
        contentService.searchIndex?.entries.filter { $0.type == .test } ?? []
    }

    private var visibleTests: [SearchEntry] {
        Array(tests.prefix(visibleCount))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Text("Each test asks real questions from the course and shows your score with explanations. Open a test to take it.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if contentService.isLoadingIndex && contentService.searchIndex == nil {
                    ProgressView("Loading...")
                } else if tests.isEmpty {
                    Text("No tests are available yet. Check your connection and try again.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                }
                ForEach(visibleTests) { entry in
                    NavigationLink(destination: TestQuizView(entry: entry)) {
                        TestRow(entry: entry)
                    }
                    .buttonStyle(PFCardButtonStyle())
                }
                if tests.count > visibleTests.count {
                    Text("Showing \(visibleTests.count) of \(tests.count) tests")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PFSecondaryButton(title: "Load more tests") {
                        visibleCount += Self.pageSize
                    }
                }
            }
            .padding(PFSpacing.lg)
            .id("testsTop")
        }
        .pfScrollToTopOnAppear("testsTop")
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .onChange(of: tests) { _, _ in
            visibleCount = Self.pageSize
        }
        .navigationTitle("Tests")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Tests: catalogue info, rows and the test quiz
//
// The Tests section exists so a learner can sit a real test on one
// area of the course and see a score with explanations, instead of
// reading about the area. Each row is one test from the search index
// (type .test). The index entry carries only a title, a domain label
// and a question count in its text; the questions themselves live on
// the test page (entry.url), embedded as TEST_DATA JSON together with
// the duration and the pass mark. TestQuizView fetches that page and
// runs the quiz from those real questions only. Nothing here invents
// a question, an option or a correct answer, and no score is saved:
// answers stay in memory for the attempt and are gone when the view
// goes away. Tests stay open to every learner, as they were when the
// rows opened the shared reading view: no gating is added here.
// AssessmentView and FinalAssessmentView were not reused: they run
// lesson quiz questions, record competency results or certificates,
// and need a dimension or a course bundle, none of which a test has.
// Practice Mode and the Daily Challenge build one decision from
// situation takeaways, not a bank of questions with answers. The
// interview bank carries open questions with model answers and no
// options, so it cannot be scored either.

// MARK: - Test catalogue info

/// The question count and domain label parsed from a test entry's
/// catalogue text, for example "Foundations Test Payment Foundations
/// foundations 10 questions". The count is the number before the
/// word "questions"; the domain label is the text between the title
/// and the trailing "<slug> <number> questions". Nil when the text
/// carries no count, never a guessed number.
struct TestEntryInfo {
    let questionCount: Int?
    let domainLabel: String?

    init(entry: SearchEntry) {
        let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var remainder = text
        if !title.isEmpty, remainder.hasPrefix(title) {
            remainder = String(remainder.dropFirst(title.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let words = remainder.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var count: Int? = nil
        var countWordIndex: Int? = nil
        for (index, word) in words.enumerated() {
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters).lowercased()
            guard cleaned == "question" || cleaned == "questions" else { continue }
            guard index >= 1, let number = Int(words[index - 1]), number > 0 else { continue }
            count = number
            countWordIndex = index
            break
        }
        questionCount = count
        if let countWordIndex, countWordIndex >= 3 {
            let domainWords = words[0..<(countWordIndex - 2)]
            let label = domainWords.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            domainLabel = label.isEmpty ? nil : label
        } else {
            domainLabel = nil
        }
    }

    /// Honest duration estimate for the row: one minute per
    /// question, the same 60 seconds per question the assessment
    /// session allows, and the same duration the test pages
    /// themselves carry (duration_minutes equals the question
    /// count on every test page). The quiz view replaces this
    /// estimate with the page's own duration once it has loaded.
    var estimatedMinutes: Int? {
        questionCount
    }

    /// "10 questions · About 10 min", or a plain statement when the
    /// catalogue text carries no count. Never a read time: a test
    /// is taken, not read.
    var rowMetaText: String {
        guard let count = questionCount else {
            return "No questions listed in the catalogue"
        }
        let questionWord = count == 1 ? "question" : "questions"
        return "\(count) \(questionWord) · About \(count) min"
    }
}

// MARK: - Test row

/// One test row: title, domain label, question count and duration
/// estimate. Test-specific on purpose: the shared EntryRow shows a
/// read time computed from the entry text, which is wrong for a
/// test (the catalogue text is a few words, so every test showed a
/// one minute read time). A test with no count in the catalogue says
/// so plainly here; tapping it still opens the quiz view, which
/// loads the test page and reports what it finds.
struct TestRow: View {
    let entry: SearchEntry

    private var info: TestEntryInfo {
        TestEntryInfo(entry: entry)
    }

    var body: some View {
        PFCard {
            HStack(spacing: PFSpacing.md) {
                PFIconTile(systemImage: "checkmark.circle.fill", size: 44)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(entry.title)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    if let domainLabel = info.domainLabel {
                        Text(domainLabel)
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: PFSpacing.xs) {
                        Image(systemName: "clock")
                            .font(.pfCaption.weight(.semibold))
                            .accessibilityHidden(true)
                        Text(info.rowMetaText)
                            .font(.pfCaption)
                    }
                    .foregroundColor(.pfSecondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.pfSecondaryText)
                    .pfDecorative()
            }
        }
        .accessibilityLabel("\(entry.title), \(info.rowMetaText)")
    }
}

// MARK: - Test page data (TEST_DATA JSON)

// The test page embeds its questions as:
// var TEST_DATA = {"mode": "test", "test": {"id", "title",
// "duration_minutes", "pass_mark_percent"}, "questions": [{"id",
// "domain", "chapter", "question", "options", "answer",
// "explanation", "why_wrong", ...}]}.
// Every field is optional in the raw decode, so one malformed item
// can be skipped without losing the whole test. Validation happens
// in TestPageLoader.validQuestions, never here.
struct TestPagePayload: Decodable {
    let test: TestPageInfo?
    let questions: [TestPageRawQuestion]?
}

struct TestPageInfo: Decodable {
    let id: String?
    let title: String?
    let durationMinutes: Int?
    let passMarkPercent: Int?

    enum CodingKeys: String, CodingKey {
        case id, title
        case durationMinutes = "duration_minutes"
        case passMarkPercent = "pass_mark_percent"
    }
}

struct TestPageRawQuestion: Decodable {
    let id: String?
    let chapter: String?
    let question: String?
    let options: [String]?
    let answer: Int?
    let explanation: String?
    let whyWrong: [String]?
    let scenario: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case id, chapter, question, options, answer, explanation, scenario, source
        case whyWrong = "why_wrong"
    }
}

/// One validated test question, ready to ask. Built only from the
/// test page's own questions: a question with no text, fewer than
/// two options, or an answer index outside its options is skipped
/// by the loader instead of being repaired or invented.
struct TestQuizQuestion: Identifiable, Hashable {
    let id: String
    let question: String
    let options: [String]
    let correctOptionIndex: Int
    let explanation: String
    let whyWrong: [String]
    let chapterID: String?
    let scenario: String?
    let source: String?
}

/// Why a test page could not be turned into a quiz, in words the
/// learner can act on.
enum TestPageError: Error, Equatable {
    case badResponse
    case noTestData
    case undecodable

    var message: String {
        switch self {
        case .badResponse:
            return "The test page could not be loaded. Check your connection and try again."
        case .noTestData:
            return "The test page loaded, but it carried no test questions to run."
        case .undecodable:
            return "The test page loaded, but its questions could not be read."
        }
    }
}

// MARK: - Test page loader

/// Fetches one test page from the course website and reads its
/// TEST_DATA questions. The fetch mirrors the lesson detail fetch:
/// the page URL is the entry's own url under the site base, with
/// bounded retry (3 attempts, exponential backoff) for network
/// failures. A page that loads but carries no usable test data is
/// reported at once and never retried, because retrying cannot fix
/// it. No other file loads test pages: there is no test loader in
/// ContentService, and none is added there by this change.
enum TestPageLoader {
    static func load(entry: SearchEntry) async throws -> (info: TestPageInfo?, questions: [TestQuizQuestion]) {
        let pageURL = ContentService.siteBase.appendingPathComponent(entry.url)
        var lastError: Error = TestPageError.badResponse
        for attempt in 0..<3 {
            do {
                let (data, response) = try await URLSession.shared.data(from: pageURL)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let html = String(data: data, encoding: .utf8) else {
                    throw TestPageError.badResponse
                }
                return try parse(html: html)
            } catch {
                if let testError = error as? TestPageError, testError != .badResponse {
                    throw testError
                }
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(500_000_000 * (1 << attempt)))
                }
            }
        }
        throw lastError
    }

    private static func parse(html: String) throws -> (info: TestPageInfo?, questions: [TestQuizQuestion]) {
        guard let jsonData = extractTestDataJSON(html) else {
            throw TestPageError.noTestData
        }
        guard let payload = try? JSONDecoder().decode(TestPagePayload.self, from: jsonData) else {
            throw TestPageError.undecodable
        }
        return (payload.test, validQuestions(from: payload.questions))
    }

    /// Find the TEST_DATA JSON object inside "var TEST_DATA = {...};"
    /// and return its bytes. The scan respects JSON strings and
    /// escapes, so braces inside quoted question text cannot end
    /// the object early. The same approach the lesson parser uses
    /// for its studio JSON blob.
    private static func extractTestDataJSON(_ html: String) -> Data? {
        guard let marker = html.range(of: "var TEST_DATA = ") else { return nil }
        guard let braceIndex = html[marker.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = braceIndex
        while index < html.endIndex {
            let ch = html[index]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else if ch == "\"" {
                inString = true
            } else if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    let jsonText = String(html[braceIndex...index])
                    return jsonText.data(using: .utf8)
                }
            }
            index = html.index(after: index)
        }
        return nil
    }

    /// Keep only questions that can honestly be asked: non-empty
    /// question text, at least two options, and an answer index
    /// inside the options. Anything else is skipped, never repaired.
    private static func validQuestions(from raw: [TestPageRawQuestion]?) -> [TestQuizQuestion] {
        guard let raw else { return [] }
        var questions: [TestQuizQuestion] = []
        for (index, item) in raw.enumerated() {
            guard let question = nonEmpty(item.question),
                  let options = item.options, options.count >= 2,
                  let correct = item.answer, correct >= 0, correct < options.count else { continue }
            questions.append(TestQuizQuestion(
                id: nonEmpty(item.id) ?? "question-\(index + 1)",
                question: question,
                options: options,
                correctOptionIndex: correct,
                explanation: nonEmpty(item.explanation) ?? "",
                whyWrong: item.whyWrong ?? [],
                chapterID: nonEmpty(item.chapter),
                scenario: nonEmpty(item.scenario),
                source: nonEmpty(item.source)
            ))
        }
        return questions
    }

    /// Trimmed text, or nil when there is nothing to show.
    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

// MARK: - Test quiz

/// Runs one test: loads the test page's own questions, asks them one
/// at a time, scores the attempt, and reviews every answer with the
/// page's explanations. Untimed in the app: the page's duration is
/// shown as the time to allow, and the time used is shown on the
/// results, but no countdown ends the attempt early. Questions stay
/// in the page's own order, so a retake asks the same questions in
/// the same order. A test with no readable questions says so
/// plainly instead of showing an empty quiz, and a page that fails
/// to load offers Retry. Scores are not saved anywhere: the attempt
/// lives only while this view is on screen.
struct TestQuizView: View {
    let entry: SearchEntry

    @State private var isLoading = true
    @State private var loadError: String? = nil
    @State private var didAttemptLoad = false
    @State private var loadedInfo: TestPageInfo? = nil
    @State private var loadedQuestions: [TestQuizQuestion] = []
    @State private var isStarted = false
    @State private var isFinished = false
    @State private var currentIndex = 0
    @State private var answers: [String: Int] = [:]
    @State private var selectedOption: Int? = nil
    @State private var startedAt: Date? = nil
    @State private var finishedAt: Date? = nil
    /// True once this attempt's score has been persisted, so a
    /// re-render can never record the same attempt twice.
    @State private var didRecordResult = false

    private var catalogueInfo: TestEntryInfo {
        TestEntryInfo(entry: entry)
    }

    private var currentQuestion: TestQuizQuestion? {
        guard currentIndex < loadedQuestions.count else { return nil }
        return loadedQuestions[currentIndex]
    }

    private var correctCount: Int {
        loadedQuestions.filter { answers[$0.id] == $0.correctOptionIndex }.count
    }

    private var scorePercent: Int {
        guard !loadedQuestions.isEmpty else { return 0 }
        return Int((Double(correctCount) / Double(loadedQuestions.count) * 100).rounded())
    }

    /// Pass or fail against the page's own pass mark, or nil when
    /// the page carries no pass mark: no verdict is invented then.
    private var passed: Bool? {
        guard let passMark = loadedInfo?.passMarkPercent else { return nil }
        return scorePercent >= passMark
    }

    /// The page's own duration when it loaded, else the catalogue
    /// estimate of one minute per question.
    private var durationMinutes: Int? {
        loadedInfo?.durationMinutes ?? catalogueInfo.estimatedMinutes
    }

    private var elapsedText: String? {
        guard let start = startedAt, let end = finishedAt else { return nil }
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return AssessmentSession.format(seconds: seconds)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                if isLoading {
                    HStack(spacing: PFSpacing.sm) {
                        ProgressView()
                        Text("Loading the test questions...")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let loadError {
                    PFErrorStateView(
                        title: "Could not load this test",
                        message: loadError,
                        retryTitle: "Retry"
                    ) {
                        retryLoad()
                    }
                } else if loadedQuestions.isEmpty {
                    emptyView
                } else if isFinished {
                    resultsView
                } else if !isStarted {
                    introView
                } else {
                    questionView
                }
            }
            .padding(PFSpacing.lg)
            .id("testQuizTop")
        }
        .pfScrollToTopOnAppear("testQuizTop", resetWhen: (currentIndex, isFinished))
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
    }

    // MARK: - Loading

    private func load() async {
        if didAttemptLoad { return }
        didAttemptLoad = true
        isLoading = true
        loadError = nil
        do {
            let result = try await TestPageLoader.load(entry: entry)
            loadedInfo = result.info
            loadedQuestions = result.questions
        } catch let error as TestPageError {
            loadError = error.message
        } catch {
            loadError = TestPageError.badResponse.message
        }
        isLoading = false
    }

    private func retryLoad() {
        didAttemptLoad = false
        loadedInfo = nil
        loadedQuestions = []
        Task { await load() }
    }

    // MARK: - Empty state

    private var emptyView: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("This test has no questions yet")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                Text(emptyMessage)
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                PFPrimaryButton(title: "Retry") {
                    retryLoad()
                }
            }
        }
    }

    private var emptyMessage: String {
        if let count = catalogueInfo.questionCount {
            let questionWord = count == 1 ? "question" : "questions"
            return "The catalogue lists \(count) \(questionWord) for this test, but no questions could be read from the test page. The page may have changed, or the connection may have dropped part of it. Try again, or come back later."
        }
        return "No questions could be read from the test page. Try again, or come back later."
    }

    // MARK: - Intro

    private var introView: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    HStack(spacing: PFSpacing.sm) {
                        PFPill(text: "Test")
                        Spacer()
                        Text("\(loadedQuestions.count) \(loadedQuestions.count == 1 ? "question" : "questions")")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                    }
                    Text(entry.title)
                        .font(.pfSectionTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    if let domainLabel = catalogueInfo.domainLabel {
                        Text(domainLabel)
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let minutes = durationMinutes {
                        Text("Allow about \(minutes) \(minutes == 1 ? "minute" : "minutes").")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let passMark = loadedInfo?.passMarkPercent {
                        Text("Pass mark: \(passMark)%.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                    }
                    if let bestScoreText {
                        Text(bestScoreText)
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                    }
                    Text("Questions come from this test on the course website. Answer every question to see your score and the explanations. Your answers stay on this device for this attempt; only your score is saved to your progress.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            PFPrimaryButton(title: "Start test") {
                startTest()
            }
        }
    }

    // MARK: - Questions

    private var questionView: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    HStack(spacing: PFSpacing.sm) {
                        PFPill(text: "Test")
                        if let question = currentQuestion, let number = chapterNumber(for: question),
                           let label = PFBookModeReadingOrder.chapterLabel(forInternalNumber: number) {
                            Text(label)
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfSecondaryText)
                        }
                        Spacer()
                        Text("Question \(currentIndex + 1) of \(loadedQuestions.count)")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                    }
                    PFProgressBar(progress: Double(currentIndex) / Double(max(loadedQuestions.count, 1)), height: 6)
                    if let question = currentQuestion {
                        if let scenario = question.scenario {
                            PFBodyText(text: scenario, textColor: .pfSecondaryText)
                        }
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
            PFPrimaryButton(title: currentIndex == loadedQuestions.count - 1 ? "See my score" : "Next question") {
                answerAndAdvance()
            }
            .disabled(selectedOption == nil)
            .opacity(selectedOption == nil ? 0.5 : 1)
            Text("Questions come from this test on the course website.")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Results and review

    private var resultsView: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    HStack(spacing: PFSpacing.lg) {
                        PFProgressRing(progress: Double(scorePercent) / 100, size: 110, color: .pfRoyal)
                        VStack(alignment: .leading, spacing: PFSpacing.sm) {
                            Text("\(correctCount) of \(loadedQuestions.count) correct")
                                .font(.pfSectionTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(scorePercent)% on \(entry.title)")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            if let passMark = loadedInfo?.passMarkPercent {
                                Text("Pass mark: \(passMark)%.")
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                            }
                            if let passed {
                                Text(passed ? "Passed. Well done." : "Not passed yet. Read the review below and try again.")
                                    .font(.pfBody)
                                    .foregroundColor(passed ? .pfSuccess : .pfError)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let elapsedText {
                                Text("Time used: \(elapsedText)")
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                            }
                            Text("This score is saved to your progress.")
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            if let bestScoreText {
                                Text(bestScoreText)
                                    .font(.pfCaption)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            Text("Review")
                .font(.pfSectionTitle)
                .foregroundColor(.pfNavy)
            ForEach(loadedQuestions) { question in
                reviewCard(for: question)
            }
            PFPrimaryButton(title: "Retake test") {
                startTest()
            }
        }
    }

    private func reviewCard(for question: TestQuizQuestion) -> some View {
        let chosen = answers[question.id]
        let wasCorrect = chosen == question.correctOptionIndex
        return PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                HStack(spacing: PFSpacing.sm) {
                    Image(systemName: wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(wasCorrect ? .pfSuccess : .pfError)
                    Text(wasCorrect ? "Correct" : "Not correct")
                        .font(.pfCaptionBold)
                        .foregroundColor(wasCorrect ? .pfSuccess : .pfError)
                    Spacer()
                    if let number = chapterNumber(for: question),
                       let label = PFBookModeReadingOrder.chapterLabel(forInternalNumber: number) {
                        Text(label)
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                    }
                }
                if let scenario = question.scenario {
                    PFBodyText(text: scenario, textColor: .pfSecondaryText)
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
                    if chosen < question.options.count {
                        Text("Your answer: \(question.options[chosen])")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let why = whyWrongText(for: question, chosen: chosen) {
                        PFBodyText(text: why, textColor: .pfSecondaryText)
                    }
                }
                if !question.explanation.isEmpty {
                    PFBodyText(text: question.explanation, textColor: .pfSecondaryText)
                }
                if let source = question.source {
                    Text("Source: \(source)")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let number = chapterNumber(for: question) {
                    NavigationLink(destination: ChapterDetailView(chapterNumber: number)) {
                        Text(PFBookModeReadingOrder.chapterLabel(forInternalNumber: number).map { "Open \($0)" } ?? "Open chapter")
                            .font(.pfBody.weight(.semibold))
                            .foregroundColor(.pfRoyal)
                    }
                }
            }
        }
    }

    /// The page's own note for the option the learner picked, when
    /// the page supplies one for that option. Empty for the correct
    /// option on every page checked, so it only ever explains a
    /// wrong pick.
    private func whyWrongText(for question: TestQuizQuestion, chosen: Int) -> String? {
        guard chosen < question.whyWrong.count else { return nil }
        let text = question.whyWrong[chosen].trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// The best recorded score on this test, as display text, or
    /// nil when the test has never been taken. Reads the persisted
    /// score history, so a retake shows the standing best.
    private var bestScoreText: String? {
        guard let best = ProgressStore.shared.quizScore(for: "test-\(entry.id)"),
              !loadedQuestions.isEmpty else { return nil }
        return "Best score on this test: \(best) of \(loadedQuestions.count) correct."
    }

    /// The chapter number from a question's chapter id ("ch39" to
    /// 39), or nil when the question carries no usable chapter.
    private func chapterNumber(for question: TestQuizQuestion) -> Int? {
        guard let chapterID = question.chapterID else { return nil }
        return PFChapterHelper.chapterNumber(from: chapterID)
    }

    // MARK: - Attempt flow

    private func startTest() {
        answers = [:]
        currentIndex = 0
        selectedOption = nil
        isFinished = false
        startedAt = Date()
        finishedAt = nil
        didRecordResult = false
        isStarted = true
    }

    /// Persist this attempt's score once, so Tests feed progress
    /// like lesson quizzes do: the attempt is appended to the
    /// test's score history in ProgressStore (keyed "test-<id>",
    /// the same synthetic-key pattern Practice Mode uses) and a
    /// quiz-completed event is recorded. Scores are never written
    /// to CompetencyStore: a test spans chapters, and inventing a
    /// single competency dimension for it would misstate the
    /// result.
    private func recordResultIfNeeded() {
        guard !didRecordResult, !loadedQuestions.isEmpty else { return }
        didRecordResult = true
        ProgressStore.shared.recordQuizScore(
            lessonID: "test-\(entry.id)",
            correct: correctCount,
            total: loadedQuestions.count
        )
    }

    /// Record the selected answer and move on. The Next button is
    /// disabled until an option is selected, so every question is
    /// answered by the time the results show: there is no
    /// unanswered state to handle.
    private func answerAndAdvance() {
        guard let selectedOption, let question = currentQuestion else { return }
        answers[question.id] = selectedOption
        self.selectedOption = nil
        if currentIndex >= loadedQuestions.count - 1 {
            finishedAt = Date()
            isFinished = true
            recordResultIfNeeded()
        } else {
            currentIndex += 1
        }
    }
}
