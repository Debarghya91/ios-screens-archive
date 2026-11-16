// BAProductStudioView.swift
// Payments Training Hub iOS - BA and Product Owner Studio.
//
// Teaching first. The Studio introduces and explains every BABOK
// item and teaches how to write each artifact and output, in
// Level 1 to Level 3 order: all 34 Chapter 2 key concepts, all
// 6 knowledge areas and 30 tasks, all 50 techniques, all 6
// competency groups and all 29 individual competencies, and all
// 5 perspectives, plus orientation lessons and career guides.
// Practice (scenarios, questions, the existing exercises, and the
// write-your-own workspace) follows the teaching, inside each
// lesson, clearly separated and labelled as practice.
//
// Content is authored as logical paragraphs in the data model
// (StudioExercises.swift) and rendered with breathing room by
// StudioParagraphsView. The Studio shows the no-IIBA-endorsement
// disclaimer. All prose is original Payments Training Hub authorship,
// working from BABOK names and structure only; no BABOK Guide
// text is used.
//
// Gating: teaching lessons and career guides are gated by BA/PO
// Studio through StudioGating. The first 2 teaching units and the
// first 2 career guides are free samples; the rest need Studio
// (or the Integrated Course). Headers and titles stay visible
// (discovery); the teaching content locks. The existing practice
// exercises keep their grounded gating: an exercise grounded in
// a free sample stays open, and a situation exercise needs
// Practice Experiences. Drafts stay on this device only, through
// StudioDraftStore, for exercises and for lesson write-your-own
// work alike.
// No em dashes in any user-facing text.

import SwiftUI

// MARK: - Gating helpers

/// The Studio gating rules. Exercise gating reads the existing
/// checks: lesson gating is PFChapterHelper plus
/// StoreManager.isChapterUnlocked, exactly as LessonView uses
/// them, and situation gating is isPracticeUnlocked, exactly as
/// SituationsView uses it. Teaching and guide gating is defined
/// here: the first 2 units and the first 2 guides are free
/// samples, and the rest need BA/PO Studio.
@MainActor
enum StudioGating {
    /// The catalogue entry for a lesson exercise, nil when the
    /// catalogue has not loaded or the lesson is not in it.
    static func lessonEntry(for exercise: StudioExercise, in contentService: ContentService) -> SearchEntry? {
        guard exercise.sourceKind == .lesson else { return nil }
        return contentService.allLessons.first { $0.id == exercise.sourceID }
    }

    /// True when the exercise is grounded in a free source: the
    /// first lesson of its chapter, or a free sample situation.
    /// False when the catalogue has not loaded, because the
    /// sample check cannot be run yet.
    static func isFreeSource(_ exercise: StudioExercise, in contentService: ContentService) -> Bool {
        switch exercise.sourceKind {
        case .situation:
            return ContentService.freeSampleIDs.contains(exercise.sourceID)
        case .lesson:
            guard let entry = lessonEntry(for: exercise, in: contentService) else { return false }
            return PFChapterHelper.isSampleLesson(entry, in: contentService)
        }
    }

    /// True when the exercise must stay locked. A lesson exercise
    /// whose entry is not loaded yet counts as locked, so the
    /// detail view shows the lock state rather than the brief
    /// until the catalogue loads and the check can run.
    static func isLocked(_ exercise: StudioExercise, contentService: ContentService, storeManager: StoreManager) -> Bool {
        switch exercise.sourceKind {
        case .situation:
            if ContentService.freeSampleIDs.contains(exercise.sourceID) { return false }
            return !storeManager.isPracticeUnlocked
        case .lesson:
            guard let entry = lessonEntry(for: exercise, in: contentService) else { return true }
            guard let number = PFChapterHelper.chapterNumber(from: entry.id) else { return false }
            if PFChapterHelper.isSampleLesson(entry, in: contentService) { return false }
            return !storeManager.isChapterUnlocked("ch\(number)")
        }
    }

    /// True when this teaching lesson is one of the 2 free samples:
    /// the first 2 units in StudioLesson.all order.
    static func isFreeTeachingSample(_ lesson: StudioLesson) -> Bool {
        StudioLesson.all.prefix(FreeSampleRules.studioFreeLessonCount).contains(lesson)
    }

    /// True when this career guide is one of the 2 free samples:
    /// the first 2 guides in StudioCareerGuide.all order.
    static func isFreeGuideSample(_ guide: StudioCareerGuide) -> Bool {
        StudioCareerGuide.all.prefix(FreeSampleRules.studioFreeGuideCount).contains(guide)
    }

    /// True when this teaching lesson's content must stay locked:
    /// no Studio entitlement and not a free sample.
    static func isTeachingLocked(_ lesson: StudioLesson, storeManager: StoreManager) -> Bool {
        !storeManager.isStudioUnlocked && !isFreeTeachingSample(lesson)
    }

    /// True when this career guide's content must stay locked:
    /// no Studio entitlement and not a free sample.
    static func isGuideLocked(_ guide: StudioCareerGuide, storeManager: StoreManager) -> Bool {
        !storeManager.isStudioUnlocked && !isFreeGuideSample(guide)
    }
}

// MARK: - Studio home: teaching first

/// The Studio home. Teaching comes first: lessons introduce and
/// explain every BABOK item and teach how to write each output,
/// in Level 1 to Level 3 order. Practice (the existing exercises,
/// the write-your-own workspace, scenarios and questions) follows
/// the teaching, inside each lesson and in the Practice Studio
/// section below. Teaching lessons and career guides are gated by
/// BA/PO Studio through StudioGating: the first 2 of each are
/// free samples. The existing exercises keep their grounded
/// gating through StudioGating.
struct BAProductStudioView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var storeManager: StoreManager
    @ObservedObject private var draftStore = StudioDraftStore.shared
    @State private var selectedKind: StudioLessonKind? = nil
    @State private var selectedType: StudioTaskType? = nil

    init() {}

    private var visibleLessons: [StudioLesson] {
        guard let selectedKind else { return StudioLesson.all }
        return StudioLesson.all.filter { $0.kind == selectedKind }
    }

    private func lessons(for level: StudioLevel) -> [StudioLesson] {
        visibleLessons.filter { $0.level == level }
    }

    private var visibleExercises: [StudioExercise] {
        guard let selectedType else { return StudioExercise.all }
        return StudioExercise.all.filter { $0.taskType == selectedType }
    }

    private var drafts: [StudioDraft] {
        draftStore.allDrafts()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                headerCard
                disclaimerCard

                if !drafts.isEmpty {
                    draftsSection
                }

                learnInOrderSection

                knowledgeAreaSection

                careerGuidesSection

                practiceStudioSection
            }
            .padding(PFSpacing.lg)
            .id("studioTop")
        }
        .pfScrollToTopOnAppear("studioTop", resetWhen: (selectedKind?.rawValue ?? "", selectedType?.rawValue ?? ""))
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle("BA and PO Studio")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await contentService.loadSearchIndex()
        }
    }

    // MARK: - Header and disclaimer

    private var headerCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                HStack(spacing: PFSpacing.md) {
                    PFIconTile(systemImage: "book.pages", size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Learn the craft, then practise it")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text("Every lesson introduces one item, explains what it is and why it matters, then teaches how to write its output, with one worked example.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Work through Level 1, then Level 2, then Level 3. The 34 key concepts, 30 tasks, 50 techniques, 6 competency groups with 29 individual competencies, and 5 perspectives are all here, in order. Practice comes after the teaching, inside each lesson.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your drafts stay on this device.")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfNavy)
            }
        }
    }

    private var disclaimerCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("About this Studio")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfNavy)
                Text(StudioDisclaimer.text)
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Drafts

    private var draftsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "My drafts")
            ForEach(drafts) { draft in
                draftRow(for: draft)
            }
            Text("Your drafts stay on this device.")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
        }
    }

    @ViewBuilder
    private func draftRow(for draft: StudioDraft) -> some View {
        if let exercise = StudioExercise.all.first(where: { $0.id == draft.exerciseID }) {
            NavigationLink(destination: StudioExerciseDetailView(exercise: exercise)) {
                PFCard {
                    HStack(spacing: PFSpacing.md) {
                        PFIconTile(systemImage: exercise.taskType.systemImage, size: 44)
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text(exercise.title)
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(draft.wordCount) words. Updated \(draft.updatedAt.formatted(date: .abbreviated, time: .shortened)).")
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.pfSecondaryText)
                            .pfDecorative()
                    }
                }
            }
            .buttonStyle(PFCardButtonStyle())
        } else if let lesson = StudioLesson.all.first(where: { $0.id == draft.exerciseID }) {
            NavigationLink(destination: StudioLessonDetailView(lesson: lesson)) {
                PFCard {
                    HStack(spacing: PFSpacing.md) {
                        PFIconTile(systemImage: lesson.kind.systemImage, size: 44)
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text("Write your own: \(lesson.outputName)")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Lesson: \(lesson.title). \(draft.wordCount) words. Updated \(draft.updatedAt.formatted(date: .abbreviated, time: .shortened)).")
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
            .buttonStyle(PFCardButtonStyle())
        }
    }

    // MARK: - Learn in order

    private var learnInOrderSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Learn in order")
            Text("Start at Level 1 and work down. Each lesson teaches before it asks you to practise.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("Filter by kind")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfNavy)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PFSpacing.sm) {
                        PFChip(text: "All", isSelected: selectedKind == nil) {
                            selectedKind = nil
                        }
                        ForEach(StudioLessonKind.allCases, id: \.self) { kind in
                            PFChip(text: kind.displayName, isSelected: selectedKind == kind) {
                                selectedKind = kind
                            }
                        }
                    }
                    .padding(.vertical, PFSpacing.xs)
                }
            }

            ForEach(StudioLevel.allCases) { level in
                if !lessons(for: level).isEmpty {
                    levelSection(level)
                }
            }
        }
    }

    private func levelSection(_ level: StudioLevel) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    HStack(spacing: PFSpacing.md) {
                        PFIconTile(systemImage: level.systemImage, size: 44)
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text(level.displayName)
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                            Text(level.blurb)
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("\(lessons(for: level).count) lessons")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfNavy)
                }
            }
            ForEach(lessons(for: level)) { lesson in
                NavigationLink(destination: StudioLessonDetailView(lesson: lesson)) {
                    lessonRow(lesson)
                }
                .buttonStyle(PFCardButtonStyle())
            }
        }
    }

    private func lessonRow(_ lesson: StudioLesson) -> some View {
        PFCard {
            HStack(spacing: PFSpacing.md) {
                PFIconTile(systemImage: lesson.kind.systemImage, size: 44)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(lesson.title)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(lesson.subtitle)
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: PFSpacing.sm) {
                        PFPill(text: lesson.kind.displayName)
                        PFPill(text: lesson.level.shortName)
                        if let reference = lesson.babokReference {
                            Text(reference)
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfSecondaryText)
                        }
                        if StudioGating.isFreeTeachingSample(lesson) {
                            PFPill(text: "Free", background: Color.pfGoldSoft, foreground: .pfGold)
                        }
                        if let draft = draftStore.draft(for: lesson.id) {
                            Text("Draft: \(draft.wordCount) words")
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfRoyal)
                        }
                    }
                }
                Spacer()
                if StudioGating.isTeachingLocked(lesson, storeManager: storeManager) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.pfSecondaryText)
                        .accessibilityLabel("Locked")
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.pfSecondaryText)
                    .pfDecorative()
            }
        }
    }

    // MARK: - Knowledge areas

    private var knowledgeAreaSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Browse by knowledge area")
            Text("The 30 tasks, grouped by their knowledge area. Each area opens with an introduction, then its tasks in order.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(StudioKnowledgeArea.allCases, id: \.self) { area in
                NavigationLink(destination: StudioKnowledgeAreaView(area: area)) {
                    PFCard {
                        HStack(spacing: PFSpacing.md) {
                            PFIconTile(systemImage: "folder", size: 44)
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                Text(area.displayName)
                                    .font(.pfCardTitle)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(StudioLesson.tasks(for: area).count) tasks")
                                    .font(.pfCaption)
                                    .foregroundColor(.pfSecondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.pfSecondaryText)
                                .pfDecorative()
                        }
                    }
                }
                .buttonStyle(PFCardButtonStyle())
            }
        }
    }

    // MARK: - Career guides

    private var careerGuidesSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Career guides")
            Text("Step by step routes into business analysis, product ownership, product management, and payments specialism, with the skills, tools, and portfolio evidence each route needs.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(StudioCareerGuide.all) { guide in
                NavigationLink(destination: StudioCareerGuideDetailView(guide: guide)) {
                    PFCard {
                        HStack(spacing: PFSpacing.md) {
                            PFIconTile(systemImage: "person.text.rectangle", size: 44)
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                Text(guide.title)
                                    .font(.pfCardTitle)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(guide.audience)
                                    .font(.pfCaption)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: PFSpacing.sm) {
                                    PFPill(text: guide.level.shortName)
                                    if StudioGating.isFreeGuideSample(guide) {
                                        PFPill(text: "Free", background: Color.pfGoldSoft, foreground: .pfGold)
                                    }
                                }
                            }
                            Spacer()
                            if StudioGating.isGuideLocked(guide, storeManager: storeManager) {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.pfSecondaryText)
                                    .accessibilityLabel("Locked")
                            }
                            Image(systemName: "chevron.right")
                                .foregroundColor(.pfSecondaryText)
                                .pfDecorative()
                        }
                    }
                }
                .buttonStyle(PFCardButtonStyle())
            }
        }
    }

    // MARK: - Practice studio

    private var practiceStudioSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Practice Studio")
            Text("Practice exercises grounded in real lessons and situations. Work through the teaching first, then use these exercises to practise the deliverables. Gating is unchanged: exercises grounded in free samples stay open.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("Filter by task type")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfNavy)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PFSpacing.sm) {
                        PFChip(text: "All", isSelected: selectedType == nil) {
                            selectedType = nil
                        }
                        ForEach(StudioTaskType.allCases) { type in
                            PFChip(text: type.displayName, isSelected: selectedType == type) {
                                selectedType = type
                            }
                        }
                    }
                    .padding(.vertical, PFSpacing.xs)
                }
            }

            ForEach(visibleExercises) { exercise in
                NavigationLink(destination: StudioExerciseDetailView(exercise: exercise)) {
                    exerciseRow(exercise)
                }
                .buttonStyle(PFCardButtonStyle())
            }
        }
    }

    private func exerciseRow(_ exercise: StudioExercise) -> some View {
        PFCard {
            HStack(spacing: PFSpacing.md) {
                PFIconTile(systemImage: exercise.taskType.systemImage, size: 44)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(exercise.title)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(exercise.sourceCitation)
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: PFSpacing.sm) {
                        PFPill(text: exercise.taskType.displayName)
                        if StudioGating.isFreeSource(exercise, in: contentService) {
                            PFPill(text: "Free sample", background: Color.pfGoldSoft, foreground: .pfGoldText)
                        }
                        if let draft = draftStore.draft(for: exercise.id) {
                            Text("Draft: \(draft.wordCount) words")
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfRoyal)
                        }
                    }
                }
                Spacer()
                Image(systemName: StudioGating.isLocked(exercise, contentService: contentService, storeManager: storeManager) ? "lock.fill" : "chevron.right")
                    .foregroundColor(.pfSecondaryText)
                    .pfDecorative()
            }
        }
    }
}


// MARK: - Exercise detail

private struct StudioExerciseDetailView: View {
    let exercise: StudioExercise

    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var storeManager: StoreManager
    @ObservedObject private var draftStore = StudioDraftStore.shared

    @State private var draftText = ""
    @State private var completedSections: Set<String> = []
    @State private var hasLoadedDraft = false
    @State private var savedAt: Date? = nil
    @State private var showDeleteConfirmation = false
    @State private var showCheckout = false
    @State private var rubricChecks: [StudioRubricCheck]? = nil
    @State private var reviewedDraftText: String? = nil

    @State private var lessonDetail: LessonDetail? = nil
    @State private var lessonDetailSource: LessonDetailSource? = nil
    @State private var isLoadingSource = false
    @State private var sourceLoadError: String? = nil
    @State private var situation: Situation? = nil
    @State private var situationIsFullText = false

    private var isLocked: Bool {
        StudioGating.isLocked(exercise, contentService: contentService, storeManager: storeManager)
    }

    private var wordCount: Int {
        StudioRubricReview.wordCount(draftText)
    }

    private var hasSavedDraft: Bool {
        draftStore.hasDraft(for: exercise.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                if isLocked {
                    lockCard
                } else {
                    sourceSection
                    briefCard
                    workedExampleCard
                    workspaceCard
                    rubricCard
                }
            }
            .padding(PFSpacing.lg)
            .id("studioExerciseTop")
        }
        .pfScrollToTopOnAppear("studioExerciseTop")
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle(exercise.taskType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDraftIfNeeded()
            await loadSourceIfNeeded()
        }
        .task(id: draftText) {
            // Autosave: typed text is saved 1 second after the
            // last keystroke, so a crash never loses it. The
            // keyed task cancels and restarts on every keystroke;
            // saveCurrentDraft itself refuses to run before the
            // stored draft has loaded.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            saveCurrentDraft()
        }
        .onDisappear {
            saveCurrentDraft()
        }
        .alert("Delete this draft?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteDraft()
            }
            Button("Keep draft", role: .cancel) {}
        } message: {
            Text("The draft is only on this device. Deleting it cannot be undone.")
        }
        .sheet(isPresented: $showCheckout) {
            CheckoutView()
        }
    }

    // MARK: - Locked

    private var lockCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.md) {
                    PFIconTile(systemImage: "lock.fill", size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text(exercise.title)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(exercise.sourceCitation)
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if exercise.sourceKind == .situation {
                    Text("This exercise is grounded in a Payment Situation that is part of the full set. Unlock Payment Situations to open the exercise. The Integrated Course includes all situations too.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("This exercise is grounded in a lesson in a locked chapter. The first lesson of each chapter is a free sample; this exercise uses a later lesson, so it unlocks with the chapter.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PFPrimaryButton(title: "Go to checkout") {
                    showCheckout = true
                }
                Text("Your drafts stay on this device.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
            }
        }
    }

    // MARK: - Source content

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            HStack(spacing: PFSpacing.sm) {
                PFPill(text: exercise.taskType.displayName)
                if StudioGating.isFreeSource(exercise, in: contentService) {
                    PFPill(text: "Free sample", background: Color.pfGoldSoft, foreground: .pfGoldText)
                }
            }
            Text(exercise.title)
                .font(.pfSectionTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Text(exercise.sourceCitation)
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
            Text(exercise.groundingNote)
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if isLoadingSource {
                PFLoadingView(message: "Loading the source content.")
            } else if let sourceLoadError {
                PFErrorStateView(
                    title: "The source content could not be loaded",
                    message: sourceLoadError,
                    retryTitle: "Try again"
                ) {
                    Task { await loadSourceIfNeeded(force: true) }
                }
            } else if exercise.sourceKind == .lesson {
                lessonSourceCard
            } else {
                situationSourceCard
            }
        }
    }

    @ViewBuilder
    private var lessonSourceCard: some View {
        if let lessonDetail {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text("From the lesson")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    if lessonDetailSource == .cached {
                        PFOfflineBanner()
                        Text("Showing a saved copy of this lesson.")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                    }
                    if !lessonDetail.takeaways.isEmpty {
                        sourceList(title: "Key takeaways", items: lessonDetail.takeaways)
                    }
                    if !lessonDetail.doThisAtWork.isEmpty {
                        sourceList(title: "Do this at work", items: lessonDetail.doThisAtWork)
                    }
                    if !lessonDetail.beats.isEmpty {
                        VStack(alignment: .leading, spacing: PFSpacing.sm) {
                            Text("Beat titles")
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfNavy)
                            ForEach(lessonDetail.beats) { beat in
                                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                    Text(beat.title)
                                        .font(.pfBody)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if !beat.note.isEmpty {
                                        Text(beat.note)
                                            .font(.pfCaption)
                                            .foregroundColor(.pfSecondaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var situationSourceCard: some View {
        if let situation {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text("From the situation")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    if !situationIsFullText {
                        Text("Situation summary from the course catalogue. The full situation text loads when the situations data is available.")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    PFBodyText(text: situation.explain)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text("Takeaway")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfNavy)
                        PFBodyText(text: situation.takeaway)
                    }
                }
            }
        }
    }

    private func sourceList(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text(title)
                .font(.pfCaptionBold)
                .foregroundColor(.pfNavy)
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: PFSpacing.sm) {
                    Text("•")
                        .font(.pfBody)
                        .foregroundColor(.pfRoyal)
                        .pfDecorative()
                    Text(items[index])
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Brief and worked example

    private var briefCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("Task brief")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                PFBodyText(text: exercise.brief)
            }
        }
    }

    private var workedExampleCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                HStack(spacing: PFSpacing.sm) {
                    PFPill(text: "Worked example", background: Color.pfGoldSoft, foreground: .pfGoldText)
                }
                Text(exercise.workedExampleTitle)
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                PFBodyText(text: exercise.workedExampleBody)
                Text("Example only. This is a structural example for a different but related task. It is not course content, and it states no scheme rule. Use its shape, not its words.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Workspace

    private var workspaceCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Text("Your workspace")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draftText)
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .frame(minHeight: 220)
                        .scrollContentBackground(.hidden)
                    if draftText.isEmpty {
                        Text("Write your draft here. Start with the first section in the checklist below, in your own words.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .padding(.top, PFSpacing.sm)
                            .padding(.leading, PFSpacing.xs)
                            .allowsHitTesting(false)
                    }
                }
                .padding(PFSpacing.sm)
                .background(Color.pfBackground)
                .cornerRadius(PFSpacing.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                        .stroke(Color.pfBorder, lineWidth: 1)
                )
                Text("\(wordCount) words. \(exercise.wordCountGuidance)")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfNavy)
                    .accessibilityLabel("\(wordCount) words. \(exercise.wordCountGuidance)")

                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text("Section checklist")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfNavy)
                    ForEach(exercise.requiredSections, id: \.title) { section in
                        Button {
                            toggleSection(section.title)
                        } label: {
                            HStack(spacing: PFSpacing.sm) {
                                Image(systemName: completedSections.contains(section.title) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(completedSections.contains(section.title) ? .pfRoyal : .pfSecondaryText)
                                Text(section.title)
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(section.title), \(completedSections.contains(section.title) ? "done" : "not done")")
                    }
                }

                PFPrimaryButton(title: "Save draft") {
                    saveCurrentDraft()
                }
                if let savedAt {
                    Text("Draft saved \(savedAt.formatted(date: .abbreviated, time: .shortened)).")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                }
                if hasSavedDraft {
                    Button("Delete draft", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .font(.pfBody).fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                Text("Your drafts stay on this device.")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfNavy)
            }
        }
    }

    // MARK: - Checklist review

    private var rubricCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Text("Checklist review, not AI")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                Text("This check only looks for section words, word count, list lines and Gherkin keywords in your draft. It does not judge quality, and it is not AI. Run it whenever you want a completeness check.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                PFSecondaryButton(title: "Run checklist review", action: runRubricReview, isEnabled: !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let rubricChecks {
                    if reviewedDraftText != draftText {
                        Text("The draft changed since this review ran. Run the checklist again for the current draft.")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(rubricChecks) { check in
                        HStack(alignment: .top, spacing: PFSpacing.sm) {
                            Image(systemName: check.passed ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(check.passed ? .pfSuccess : .pfSecondaryText)
                                .pfDecorative()
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                Text(check.label)
                                    .font(.pfBody).fontWeight(.semibold)
                                    .foregroundColor(.pfNavy)
                                Text(check.detail)
                                    .font(.pfCaption)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleSection(_ title: String) {
        if completedSections.contains(title) {
            completedSections.remove(title)
        } else {
            completedSections.insert(title)
        }
        saveCurrentDraft()
    }

    private func saveCurrentDraft() {
        guard hasLoadedDraft else { return }
        let stored = draftStore.draft(for: exercise.id)
        let sections = Array(completedSections)
        if stored?.text == draftText,
           Set(stored?.completedSections ?? []) == completedSections {
            return
        }
        draftStore.saveDraft(exerciseID: exercise.id, text: draftText, completedSections: sections)
        if draftStore.hasDraft(for: exercise.id) {
            savedAt = Date()
        }
    }

    private func deleteDraft() {
        draftStore.deleteDraft(for: exercise.id)
        draftText = ""
        completedSections = []
        rubricChecks = nil
        reviewedDraftText = nil
        savedAt = nil
    }

    private func runRubricReview() {
        rubricChecks = StudioRubricReview.checks(for: exercise, draft: draftText)
        reviewedDraftText = draftText
    }

    // MARK: - Loading

    private func loadDraftIfNeeded() async {
        guard !hasLoadedDraft else { return }
        if let draft = draftStore.draft(for: exercise.id) {
            draftText = draft.text
            completedSections = Set(draft.completedSections)
            savedAt = draft.updatedAt
        }
        hasLoadedDraft = true
    }

    private func loadSourceIfNeeded(force: Bool = false) async {
        if isLoadingSource { return }
        if !force, lessonDetail != nil || situation != nil { return }
        isLoadingSource = true
        sourceLoadError = nil
        await contentService.loadSearchIndex()
        if isLocked {
            isLoadingSource = false
            return
        }
        switch exercise.sourceKind {
        case .lesson:
            await loadLessonSource()
        case .situation:
            await loadSituationSource()
        }
        isLoadingSource = false
    }

    private func loadLessonSource() async {
        guard let entry = StudioGating.lessonEntry(for: exercise, in: contentService) else {
            sourceLoadError = "The course catalogue did not include this lesson. Check your connection and try again."
            return
        }
        if let loaded = await contentService.loadLessonDetailWithSource(entry: entry) {
            lessonDetail = loaded.detail
            lessonDetailSource = loaded.source
        } else {
            sourceLoadError = "This lesson could not be loaded. Check your connection and tap Try again."
        }
    }

    private func loadSituationSource() async {
        await contentService.loadFullSituations()
        if let full = contentService.fullSituations?.first(where: { $0.id == exercise.sourceID }) {
            situation = TrainingHub.situation(fromFull: full)
            situationIsFullText = true
            return
        }
        if let entry = contentService.allSituations.first(where: { $0.id == exercise.sourceID }) {
            situation = TrainingHub.situation(from: entry)
            situationIsFullText = false
            return
        }
        sourceLoadError = "This situation could not be loaded. Check your connection and tap Try again."
    }
}

// MARK: - Paragraph rendering

/// Renders an array of paragraph strings with breathing room: one
/// Text per paragraph, paragraph spacing from the design scale, and
/// comfortable line spacing. The content model stores paragraphs as
/// arrays; a later pass owns shared paragraph rendering across the
/// app. This view is the Studio's local rendering of that model,
/// using existing design tokens only.
struct StudioParagraphsView: View {
    let paragraphs: [String]
    var textColor: Color = .pfNavy

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            ForEach(paragraphs.indices, id: \.self) { index in
                Text(paragraphs[index])
                    .font(.pfBody)
                    .foregroundColor(textColor)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A bullet list of short items, using existing design tokens.
private struct StudioBulletListView: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: PFSpacing.sm) {
                    Text("•")
                        .font(.pfBody)
                        .foregroundColor(.pfRoyal)
                        .pfDecorative()
                    Text(items[index])
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Knowledge area

/// One knowledge area: its introduction, then its task lessons in
/// order. Teaching only; practice lives inside each lesson.
struct StudioKnowledgeAreaView: View {
    @EnvironmentObject private var storeManager: StoreManager
    let area: StudioKnowledgeArea

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text(area.displayName)
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        StudioParagraphsView(paragraphs: area.introduction)
                    }
                }
                PFSectionHeader(title: "Tasks in this area")
                ForEach(StudioLesson.tasks(for: area)) { lesson in
                    NavigationLink(destination: StudioLessonDetailView(lesson: lesson)) {
                        PFCard {
                            HStack(spacing: PFSpacing.md) {
                                PFIconTile(systemImage: lesson.kind.systemImage, size: 44)
                                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                    Text(lesson.title)
                                        .font(.pfCardTitle)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(lesson.subtitle)
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                    HStack(spacing: PFSpacing.sm) {
                                        PFPill(text: lesson.level.shortName)
                                        if let reference = lesson.babokReference {
                                            Text(reference)
                                                .font(.pfCaptionBold)
                                                .foregroundColor(.pfSecondaryText)
                                        }
                                        if StudioGating.isFreeTeachingSample(lesson) {
                                            PFPill(text: "Free", background: Color.pfGoldSoft, foreground: .pfGold)
                                        }
                                    }
                                }
                                Spacer()
                                if StudioGating.isTeachingLocked(lesson, storeManager: storeManager) {
                                    Image(systemName: "lock.fill")
                                        .foregroundColor(.pfSecondaryText)
                                        .accessibilityLabel("Locked")
                                }
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.pfSecondaryText)
                                    .pfDecorative()
                            }
                        }
                    }
                    .buttonStyle(PFCardButtonStyle())
                }
                Text(StudioDisclaimer.text)
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(PFSpacing.lg)
            .id("studioAreaTop")
        }
        .pfScrollToTopOnAppear("studioAreaTop")
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle("Knowledge area")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Lesson detail: teaching, then practice

/// One teaching lesson. Order is fixed: teaching first (what the
/// item is, how to write its output, one worked example), then a
/// clearly separated Practice section (scenarios, questions, linked
/// exercises, and the write-your-own workspace). Practice is never
/// mixed into the explanation.
struct StudioLessonDetailView: View {
    @EnvironmentObject private var storeManager: StoreManager
    let lesson: StudioLesson

    @State private var showCheckout = false

    /// True when this lesson's teaching content must stay locked:
    /// no Studio entitlement and not a free sample. The header
    /// stays visible (discovery) either way.
    private var isLocked: Bool {
        StudioGating.isTeachingLocked(lesson, storeManager: storeManager)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                lessonHeader
                if isLocked {
                    studioLockCard
                } else {
                    teachingHeader
                    explanationCard
                    howToWriteCard
                    workedExampleCard
                    practiceSection
                }
                Text(StudioDisclaimer.text)
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle(lesson.kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCheckout) {
            CheckoutView()
        }
    }

    /// The lock card shown in place of the teaching content. The
    /// buy prompt opens the Purchases screen.
    private var studioLockCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Label("Lesson locked", systemImage: "lock.fill")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfNavy)
                Text("This teaching lesson is part of BA/PO Studio: \(StudioLesson.all.count) BABOK teaching units and \(StudioCareerGuide.all.count) career guides\(storeManager.isPriceAvailable(for: ProductCatalogue.studioProductID) ? " for \(storeManager.priceText(for: ProductCatalogue.studioProductID))" : ""), with 1 year of access. The Integrated Course includes the Studio too.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                PFPrimaryButton(title: "View BA/PO Studio") {
                    showCheckout = true
                }
            }
        }
    }

    // MARK: - Header

    private var lessonHeader: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            HStack(spacing: PFSpacing.sm) {
                PFPill(text: lesson.kind.displayName)
                PFPill(text: lesson.level.displayName)
                if let reference = lesson.babokReference {
                    PFPill(text: "BABOK \(reference)")
                }
            }
            if let area = lesson.knowledgeArea {
                Text(area.displayName)
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfSecondaryText)
            }
            Text(lesson.title)
                .font(.pfSectionTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Text(lesson.subtitle)
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var teachingHeader: some View {
        HStack(spacing: PFSpacing.sm) {
            PFPill(text: "Teaching", background: Color.pfGoldSoft, foreground: .pfGoldText)
            Text("Read the teaching first. Practice follows below.")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Teaching

    private var explanationCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Text("What this is, and why it matters")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                StudioParagraphsView(paragraphs: lesson.explanation)
                if !lesson.keyPoints.isEmpty {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("Key points")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfNavy)
                        StudioBulletListView(items: lesson.keyPoints)
                    }
                }
            }
        }
    }

    private var howToWriteCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Text("How to write: \(lesson.outputName)")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text("What goes in, in order")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfNavy)
                    ForEach(lesson.outputStructure.indices, id: \.self) { index in
                        let section = lesson.outputStructure[index]
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text("\(index + 1). \(section.title)")
                                .font(.pfBody).fontWeight(.semibold)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(section.guidance)
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                StudioParagraphsView(paragraphs: lesson.howToWrite)
            }
        }
    }

    private var workedExampleCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.sm) {
                    PFPill(text: "Worked example", background: Color.pfGoldSoft, foreground: .pfGoldText)
                }
                Text(lesson.workedExampleTitle)
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                StudioParagraphsView(paragraphs: lesson.workedExample)
                Text("Example only. This is a fictional illustration written for this lesson. Use its shape, not its words, and check every rule and figure against the owning team before using it for real work.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Practice

    private var practiceSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                HStack(spacing: PFSpacing.sm) {
                    PFPill(text: "Practice")
                    Text("Supporting practice, after the teaching")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfNavy)
                }
                Text("The scenarios, questions, and exercises below practise what the teaching above explained. They are not part of the explanation. Work through them after reading the teaching.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !lesson.practiceScenarios.isEmpty {
                scenariosCard
            }
            if !lesson.practiceQuestions.isEmpty {
                questionsCard
            }
            if !lesson.linkedExerciseIDs.isEmpty {
                linkedExercisesCard
            }
            StudioLessonWorkspaceView(lesson: lesson)
        }
    }

    private var scenariosCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Text("Practice scenarios")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                Text("Read each scenario, decide what you would do, then compare your thinking with the takeaway. The takeaway is shown with the scenario, so read the story first.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(lesson.practiceScenarios) { scenario in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: PFSpacing.md) {
                            StudioParagraphsView(paragraphs: scenario.story)
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                Text("Takeaway")
                                    .font(.pfCaptionBold)
                                    .foregroundColor(.pfNavy)
                                Text(scenario.takeaway)
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.top, PFSpacing.sm)
                    } label: {
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text(scenario.title)
                                .font(.pfBody).fontWeight(.semibold)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(scenario.id)
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                        }
                    }
                }
            }
        }
    }

    private var questionsCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Text("Practice questions")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                Text("Answer each question in your own words before opening the model answer. The model answer is one good answer, not the only answer.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(lesson.practiceQuestions) { item in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: PFSpacing.sm) {
                            if item.answer.isEmpty {
                                Text("This is a reflection prompt. There is no model answer. Discuss your answer with a colleague or mentor, or write it in the workspace below.")
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text("Model answer")
                                    .font(.pfCaptionBold)
                                    .foregroundColor(.pfNavy)
                                StudioParagraphsView(paragraphs: item.answer)
                            }
                        }
                        .padding(.top, PFSpacing.sm)
                    } label: {
                        Text(item.question)
                            .font(.pfBody).fontWeight(.semibold)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var linkedExercisesCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Text("Linked practice exercises")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                Text("These Practice Studio exercises follow this teaching. Gating is unchanged: an exercise grounded in a locked chapter or situation stays locked until it unlocks.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(lesson.linkedExerciseIDs, id: \.self) { exerciseID in
                    if let exercise = StudioExercise.all.first(where: { $0.id == exerciseID }) {
                        NavigationLink(destination: StudioExerciseDetailView(exercise: exercise)) {
                            HStack(spacing: PFSpacing.md) {
                                PFIconTile(systemImage: exercise.taskType.systemImage, size: 44)
                                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                    Text(exercise.title)
                                        .font(.pfBody).fontWeight(.semibold)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(exercise.sourceCitation)
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.pfSecondaryText)
                                    .pfDecorative()
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Write your own workspace

/// The write-your-own workspace for one lesson: the learner writes
/// the output the lesson taught, following its structure, and saves
/// the draft on this device through StudioDraftStore, keyed by the
/// lesson id. The same store, the same device-only rule, and the
/// same AI-review sheet as the practice exercises. No rubric: the
/// checklist is the lesson's own output structure, ticked by the
/// learner as each section is covered.
private struct StudioLessonWorkspaceView: View {
    let lesson: StudioLesson

    @ObservedObject private var draftStore = StudioDraftStore.shared

    @State private var draftText = ""
    @State private var completedSections: Set<String> = []
    @State private var hasLoadedDraft = false
    @State private var savedAt: Date? = nil
    @State private var showDeleteConfirmation = false

    private var wordCount: Int {
        StudioRubricReview.wordCount(draftText)
    }

    private var hasSavedDraft: Bool {
        draftStore.hasDraft(for: lesson.id)
    }

    var body: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Text("Write your own: \(lesson.outputName)")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Write the output this lesson taught, following the structure above, in your own words. Use the checklist to tick each section as you cover it.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draftText)
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .frame(minHeight: 220)
                        .scrollContentBackground(.hidden)
                    if draftText.isEmpty {
                        Text("Write your draft here. Start with the first section in the checklist below, in your own words.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .padding(.top, PFSpacing.sm)
                            .padding(.leading, PFSpacing.xs)
                            .allowsHitTesting(false)
                    }
                }
                .padding(PFSpacing.sm)
                .background(Color.pfBackground)
                .cornerRadius(PFSpacing.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                        .stroke(Color.pfBorder, lineWidth: 1)
                )
                Text("\(wordCount) words. \(lesson.wordCountGuidance)")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfNavy)
                    .accessibilityLabel("\(wordCount) words. \(lesson.wordCountGuidance)")

                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text("Section checklist")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfNavy)
                    ForEach(lesson.outputStructure, id: \.title) { section in
                        Button {
                            toggleSection(section.title)
                        } label: {
                            HStack(spacing: PFSpacing.sm) {
                                Image(systemName: completedSections.contains(section.title) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(completedSections.contains(section.title) ? .pfRoyal : .pfSecondaryText)
                                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                    Text(section.title)
                                        .font(.pfBody)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(section.guidance)
                                        .font(.pfCaption)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(section.title), \(completedSections.contains(section.title) ? "done" : "not done")")
                    }
                }

                PFPrimaryButton(title: "Save draft") {
                    saveCurrentDraft()
                }
                if let savedAt {
                    Text("Draft saved \(savedAt.formatted(date: .abbreviated, time: .shortened)).")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                }
                if hasSavedDraft {
                    Button("Delete draft", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .font(.pfBody).fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                Text("Your drafts stay on this device.")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfNavy)
            }
        }
        .task {
            await loadDraftIfNeeded()
        }
        .task(id: draftText) {
            // Autosave: typed text is saved 1 second after the
            // last keystroke, so a crash never loses it. The
            // keyed task cancels and restarts on every keystroke;
            // saveCurrentDraft itself refuses to run before the
            // stored draft has loaded.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            saveCurrentDraft()
        }
        .onDisappear {
            saveCurrentDraft()
        }
        .alert("Delete this draft?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteDraft()
            }
            Button("Keep draft", role: .cancel) {}
        } message: {
            Text("The draft is only on this device. Deleting it cannot be undone.")
        }
    }

    private func toggleSection(_ title: String) {
        if completedSections.contains(title) {
            completedSections.remove(title)
        } else {
            completedSections.insert(title)
        }
        saveCurrentDraft()
    }

    private func saveCurrentDraft() {
        guard hasLoadedDraft else { return }
        let stored = draftStore.draft(for: lesson.id)
        let sections = Array(completedSections)
        if stored?.text == draftText,
           Set(stored?.completedSections ?? []) == completedSections {
            return
        }
        draftStore.saveDraft(exerciseID: lesson.id, text: draftText, completedSections: sections)
        if draftStore.hasDraft(for: lesson.id) {
            savedAt = Date()
        }
    }

    private func deleteDraft() {
        draftStore.deleteDraft(for: lesson.id)
        draftText = ""
        completedSections = []
        savedAt = nil
    }

    private func loadDraftIfNeeded() async {
        guard !hasLoadedDraft else { return }
        if let draft = draftStore.draft(for: lesson.id) {
            draftText = draft.text
            completedSections = Set(draft.completedSections)
            savedAt = draft.updatedAt
        }
        hasLoadedDraft = true
    }
}

// MARK: - Career guide detail

/// One career guide: paragraphed teaching sections with numbered
/// steps, then the skills, tools, certifications, portfolio
/// artifacts, and common mistakes. Certification names identify the
/// certifications only; the no-endorsement note is shown beside them.
struct StudioCareerGuideDetailView: View {
    @EnvironmentObject private var storeManager: StoreManager
    let guide: StudioCareerGuide

    @State private var showCheckout = false

    /// True when this guide's content must stay locked: no Studio
    /// entitlement and not a free sample. The header stays visible
    /// (discovery) either way.
    private var isLocked: Bool {
        StudioGating.isGuideLocked(guide, storeManager: storeManager)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    PFPill(text: guide.level.displayName)
                    Text(guide.title)
                        .font(.pfSectionTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    StudioParagraphsView(paragraphs: guide.description)
                    Text("For: \(guide.audience)")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if !guide.timeframe.isEmpty {
                        Text(guide.timeframe)
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if isLocked {
                    studioLockCard
                } else {
                ForEach(guide.sections.indices, id: \.self) { index in
                    let section = guide.sections[index]
                    PFCard {
                        VStack(alignment: .leading, spacing: PFSpacing.md) {
                            Text(section.heading)
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            StudioParagraphsView(paragraphs: section.paragraphs)
                            if !section.steps.isEmpty {
                                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                                    Text("Steps")
                                        .font(.pfCaptionBold)
                                        .foregroundColor(.pfNavy)
                                    ForEach(section.steps.indices, id: \.self) { stepIndex in
                                        let step = section.steps[stepIndex]
                                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                            Text("Step \(stepIndex + 1). \(step.title)")
                                                .font(.pfBody).fontWeight(.semibold)
                                                .foregroundColor(.pfNavy)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Text(step.action)
                                                .font(.pfBody)
                                                .foregroundColor(.pfNavy)
                                                .fixedSize(horizontal: false, vertical: true)
                                            if !step.timeframe.isEmpty {
                                                Text(step.timeframe)
                                                    .font(.pfCaptionBold)
                                                    .foregroundColor(.pfSecondaryText)
                                            }
                                        }
                                    }
                                }
                            }
                            if !section.keyPoints.isEmpty {
                                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                                    Text("Key points")
                                        .font(.pfCaptionBold)
                                        .foregroundColor(.pfNavy)
                                    StudioBulletListView(items: section.keyPoints)
                                }
                            }
                        }
                    }
                }

                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        Text("Skills to build")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        StudioBulletListView(items: guide.skills)
                    }
                }

                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        Text("Tools to learn")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        StudioBulletListView(items: guide.tools)
                    }
                }

                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        Text("Certifications")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        ForEach(guide.certifications.indices, id: \.self) { index in
                            let certification = guide.certifications[index]
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                Text("\(certification.name) (\(certification.body))")
                                    .font(.pfBody).fontWeight(.semibold)
                                    .foregroundColor(.pfNavy)
                                Text(certification.note)
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Text(StudioCareerGuide.certificationNote)
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        Text("Portfolio artifacts")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text("Build proof you can do the work. Each artifact below is evidence a reviewer can check.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        StudioBulletListView(items: guide.portfolio)
                    }
                }

                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        Text("Common mistakes")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        StudioBulletListView(items: guide.mistakes)
                    }
                }
                }
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle("Career guide")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCheckout) {
            CheckoutView()
        }
    }

    /// The lock card shown in place of the guide content. The buy
    /// prompt opens the Purchases screen.
    private var studioLockCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Label("Guide locked", systemImage: "lock.fill")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfNavy)
                Text("This career guide is part of BA/PO Studio: \(StudioLesson.all.count) BABOK teaching units and \(StudioCareerGuide.all.count) career guides\(storeManager.isPriceAvailable(for: ProductCatalogue.studioProductID) ? " for \(storeManager.priceText(for: ProductCatalogue.studioProductID))" : ""), with 1 year of access. The Integrated Course includes the Studio too.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                PFPrimaryButton(title: "View BA/PO Studio") {
                    showCheckout = true
                }
            }
        }
    }
}
