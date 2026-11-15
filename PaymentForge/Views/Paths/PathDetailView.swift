// PathDetailView.swift
// Payments Training Hub iOS - Guided learning path detail.
// Layout follows the mockup Courses screen: icon tile left, title,
// two-line description, "Level • N lessons", progress bar with % at
// the right, bookmark top right. All numbers are real: lesson counts
// from the catalogue, progress from ProgressStore. No mockup numbers.
// No em dashes in any user-facing text.

import SwiftUI

// MARK: - Guided path card (mockup layout)

/// One guided path card, in the mockup's Courses layout.
struct GuidedPathCardView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @ObservedObject private var bookmarks = PathBookmarkStore.shared
    @ObservedObject private var activePathStore = ActivePathStore.shared
    let path: LearningPath

    private var lessons: [SearchEntry] {
        path.lessons(in: contentService)
    }

    private var completedCount: Int {
        lessons.filter { progressStore.isLessonComplete($0.id) }.count
    }

    private var progress: Double {
        guard !lessons.isEmpty else { return 0 }
        return Double(completedCount) / Double(lessons.count)
    }

    /// The path thumbnail: the first lesson in the path that
    /// carries one. The icon tile shows when no lesson in the
    /// path has a thumbnail yet.
    private var thumbnailPath: String? {
        lessons.compactMap(\.thumbnail).first
    }

    var body: some View {
        PFCard {
            HStack(alignment: .top, spacing: PFSpacing.md) {
                if thumbnailPath != nil {
                    PFThumbnailView(thumbnailPath: thumbnailPath, size: 48, cornerRadius: 12)
                } else {
                    PFIconTile(systemImage: path.systemImage, size: 48)
                }
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(path.title)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(path.description)
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(path.level) • \(lessons.count) lessons")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                        .fixedSize(horizontal: false, vertical: true)
                    if activePathStore.activePathID == path.id {
                        PFPill(
                            text: "Your journey",
                            background: Color.pfRoyal.opacity(0.10),
                            foreground: .pfRoyal
                        )
                    }
                    if completedCount > 0 {
                        HStack(spacing: PFSpacing.sm) {
                            PFProgressBar(progress: progress, height: 6)
                            Text("\(Int((progress * 100).rounded()))%")
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.top, PFSpacing.xs)
                        Text("\(completedCount) of \(lessons.count) lessons complete")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Not started yet")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, PFSpacing.xs)
                    }
                }
                Button {
                    let wasBookmarked = bookmarks.isBookmarked(path.id)
                    bookmarks.toggle(path.id)
                    if !wasBookmarked {
                        progressStore.recordBookmark(pathID: path.id)
                    }
                } label: {
                    Image(systemName: bookmarks.isBookmarked(path.id) ? "bookmark.fill" : "bookmark")
                        .foregroundColor(bookmarks.isBookmarked(path.id) ? .pfGold : .pfSecondaryText)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(bookmarks.isBookmarked(path.id) ? "Remove bookmark" : "Bookmark this journey")
            }
        }
    }
}

// MARK: - Path detail

struct PathDetailView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @ObservedObject private var competencyStore = CompetencyStore.shared
    @ObservedObject private var activePathStore = ActivePathStore.shared
    let path: LearningPath

    private var lessons: [SearchEntry] {
        path.lessons(in: contentService)
    }

    private var completedCount: Int {
        lessons.filter { progressStore.isLessonComplete($0.id) }.count
    }

    private var progress: Double {
        guard !lessons.isEmpty else { return 0 }
        return Double(completedCount) / Double(lessons.count)
    }

    private var isComplete: Bool {
        path.isComplete(in: progressStore, service: contentService)
    }

    private var isActivePath: Bool {
        activePathStore.activePathID == path.id
    }

    /// The choose button reads "Choose your journey" before any
    /// journey is chosen and "Change journey" once one is: the
    /// action is the same select, only the wording names the
    /// learner's situation.
    private var chooseButtonTitle: String {
        activePathStore.activePathID == nil ? "Choose your journey" : "Change journey"
    }

    private var chooseButtonAccessibilityLabel: String {
        activePathStore.activePathID == nil
            ? "Choose \(path.title) as your journey"
            : "Change your journey to \(path.title)"
    }

    private var chapterBlocks: [(number: Int, title: String)] {
        path.chapterTitles(in: contentService)
    }

    private var labs: [SearchEntry] {
        path.labs(in: contentService)
    }

    private var estimatedWeeks: Int? {
        LearningPath.estimatedWeeks(totalLessons: lessons.count, weeklyTarget: progressStore.weeklyGoal)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.xl) {
                headerSection
                activePathSection
                entryExpectationsSection
                objectivesSection
                lessonsSection
                labsSection
                checkpointsSection
                situationsSection
                capstoneSection
                completionCriteriaSection
                certificateSection
            }
            .padding(PFSpacing.lg)
            .id("pathTop")
        }
        .pfScrollToTopOnAppear("pathTop")
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle(path.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.sm) {
                    PFLevelPill(text: path.level)
                    PFPill(text: "\(lessons.count) lessons")
                    Spacer()
                    if isComplete {
                        PFPill(text: "Complete", background: Color.pfSuccess.opacity(0.12), foreground: .pfSuccess)
                    }
                }
                HStack(alignment: .top, spacing: PFSpacing.md) {
                    if let thumbnailPath = lessons.compactMap(\.thumbnail).first {
                        PFThumbnailView(thumbnailPath: thumbnailPath, size: 56, cornerRadius: 12)
                    }
                    PFBodyText(text: path.description, textColor: .pfSecondaryText)
                }
                if completedCount > 0 {
                    HStack(spacing: PFSpacing.sm) {
                        PFProgressBar(progress: progress)
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    Text("\(completedCount) of \(lessons.count) lessons complete")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Not started yet")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Your journey

    private var activePathSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Your journey")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text("A learning journey is a set order of chapters for one goal. Your journey decides which lesson Home shows next in the Continue learning block, so you always know what to do next. You can follow only one journey at a time.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if isActivePath {
                        Label("This is your journey.", systemImage: "checkmark.circle.fill")
                            .font(.pfBody.weight(.semibold))
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("This is your journey.")
                        Text("Changing journeys never loses completed-lesson progress. Progress is kept per lesson, so everything you have completed stays complete.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        PFSecondaryButton(title: "Remove as my journey") {
                            activePathStore.select(nil)
                        }
                        .accessibilityLabel("Remove \(path.title) as my journey")
                    } else {
                        Text("Choose this journey, and Home will show its next lesson first in the Continue learning block.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Changing journeys never loses completed-lesson progress. Progress is kept per lesson, so everything you have completed stays complete.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        PFPrimaryButton(title: chooseButtonTitle) {
                            activePathStore.select(path.id)
                        }
                        .accessibilityLabel(chooseButtonAccessibilityLabel)
                    }
                }
            }
        }
    }

    // MARK: - Entry expectations

    private var entryExpectationsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Before you start")
            PFCard {
                Text(path.entryExpectations)
                    .font(.pfBody)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Objectives

    private var objectivesSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "What you will learn")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    ForEach(path.objectives, id: \.self) { objective in
                        HStack(alignment: .top, spacing: PFSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.pfSuccess)
                                .padding(.top, 2)
                            Text(objective)
                                .font(.pfBody)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Lessons

    private var lessonsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Lessons")
            if contentService.isLoadingIndex && lessons.isEmpty {
                ProgressView("Loading lessons...")
            } else if lessons.isEmpty {
                Text("Lessons will appear here once the course catalogue has loaded.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
            } else {
                ForEach(Array(chapterBlocks.enumerated()), id: \.element.number) { (index, chapter) in
                    // Book numbers only; a held-out chapter has no
                    // book number, so the chapter title stands in.
                    let chapterLabel = PFBookModeReadingOrder.bookNumber(forInternalNumber: chapter.number)
                        .map { "Chapter \($0)" } ?? chapter.title
                    let chapterThumbnail = PFChapterHelper.chapterThumbnailPath(forChapter: chapter.number, in: contentService)
                    HStack(alignment: .top, spacing: PFSpacing.md) {
                        if chapterThumbnail != nil {
                            PFThumbnailView(thumbnailPath: chapterThumbnail, size: 44, cornerRadius: 12)
                        }
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text("Step \(index + 1) of \(chapterBlocks.count): \(chapter.title)")
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfRoyal)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(chapterLabel) in the \(path.title) sequence, step \(index + 1) of \(chapterBlocks.count) in this path.")
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, PFSpacing.sm)
                    let chapterLessons = lessons.filter {
                        PFChapterHelper.chapterNumber(from: $0.id) == chapter.number
                    }
                    ForEach(chapterLessons) { lesson in
                        NavigationLink(destination: LessonView(entry: lesson)) {
                            LessonRow(entry: lesson)
                        }
                        .buttonStyle(PFCardButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: - Simulator exercises

    private var labsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Simulator exercises")
            if contentService.isLoadingIndex && labs.isEmpty {
                ProgressView("Loading exercises...")
            } else if labs.isEmpty {
                PFCard {
                    Text("No simulator exercises are listed for this path in the course catalogue.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(labs) { lab in
                    NavigationLink(destination: EntryDetailView(entry: lab)) {
                        EntryRow(entry: lab)
                    }
                    .buttonStyle(PFCardButtonStyle())
                }
            }
        }
    }

    // MARK: - Checkpoints

    private var checkpointsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Assessment checkpoints")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text("A 5-question quiz drawn from the real lesson quizzes in this path, scored against \(path.assessmentDimension.rawValue).")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let score = competencyStore.score(for: path.assessmentDimension) {
                        Text("Your recorded score: \(Int(score.rounded()))%")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                    } else {
                        Text("Not assessed yet for this dimension.")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                    }
                    Text("Checkpoints are optional practice. Completing this path does not require them.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    NavigationLink(destination: AssessmentView(path: path)) {
                        Text("Take the checkpoint assessment")
                            .font(.pfBody.weight(.semibold))
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

    // MARK: - Situations

    private var situationsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Practice situations")
            let situations = path.situations(in: contentService)
            if situations.isEmpty {
                Text("Situations will appear here once the catalogue has loaded.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
            } else {
                ForEach(situations) { situation in
                    NavigationLink(destination: SituationDetailView(situation: situation)) {
                        SituationRow(situation: situation)
                    }
                    .buttonStyle(PFCardButtonStyle())
                }
            }
        }
    }

    // MARK: - Capstone

    private var capstoneSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Capstone")
            if let capstone = path.capstone(in: contentService) {
                NavigationLink(destination: SituationDetailView(situation: capstone)) {
                    PFCard {
                        VStack(alignment: .leading, spacing: PFSpacing.sm) {
                            HStack(spacing: PFSpacing.sm) {
                                PFIconTile(systemImage: "flag.fill", size: 44)
                                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                    Text("Capstone situation")
                                        .font(.pfCaptionBold)
                                        .foregroundColor(.pfGold)
                                    Text(capstone.title)
                                        .font(.pfCardTitle)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.pfSecondaryText)
                            }
                            Text("Work this real situation end to end. It is the final check for this path.")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .buttonStyle(PFCardButtonStyle())
            } else {
                Text("The capstone will appear here once the catalogue has loaded.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
            }
        }
    }

    // MARK: - Completion criteria

    private var completionCriteriaSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "How to complete this path")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text(path.completionCriteria)
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    if let weeks = estimatedWeeks {
                        Text("At your weekly goal of \(progressStore.weeklyGoal) \(progressStore.weeklyGoal == 1 ? "lesson" : "lessons") a week, the \(lessons.count) lessons in this path take \(weeks) \(weeks == 1 ? "week" : "weeks").")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Certificate

    private var certificateSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Certificate")
            if path.certificateTitle == nil {
                PFCard {
                    Text("This path has no certificate. It prepares you for interviews; the five certificate paths are listed under Certificates on the Dashboard.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if isComplete {
                NavigationLink(destination: CertificateView(path: path)) {
                    PFCard {
                        HStack(spacing: PFSpacing.md) {
                            PFIconTile(systemImage: "seal.fill", size: 44)
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                Text("Certificate earned")
                                    .font(.pfCardTitle)
                                    .foregroundColor(.pfNavy)
                                Text("View and share your \(path.certificateTitle ?? "") certificate.")
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
            } else {
                PFCard {
                    Text("Complete all \(lessons.count) lessons in this path to earn the \(path.certificateTitle ?? "") certificate.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Situation row

/// A compact situation row: icon tile, title, stage and level pills.
struct SituationRow: View {
    let situation: Situation

    var body: some View {
        PFCard {
            HStack(spacing: PFSpacing.md) {
                // The thumbnail sits beside the title when the
                // website exposes one; the briefcase tile otherwise.
                if situation.thumbnail != nil {
                    PFThumbnailView(thumbnailPath: situation.thumbnail, size: 44, cornerRadius: 12)
                } else {
                    PFIconTile(systemImage: "briefcase.fill", size: 44)
                }
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(situation.title)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: PFSpacing.sm) {
                        PFPill(text: situation.stageName)
                        PFPill(
                            text: situation.level.displayName,
                            background: Color.pfGoldSoft,
                            foreground: Color.pfGoldText
                        )
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.pfSecondaryText)
            }
        }
    }
}
