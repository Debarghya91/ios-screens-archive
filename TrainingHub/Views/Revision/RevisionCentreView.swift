// RevisionCentreView.swift
// Payments Training Hub iOS - Spaced repetition revision centre.
// White cards on the soft blue-grey background, royal blue primary,
// gold sparingly, matching the mockup's general language. All concepts
// are real completed lessons the learner scheduled; due dates and
// intervals come from RevisionService, never invented.
// No em dashes in any user-facing text.

import SwiftUI

struct RevisionCentreView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @ObservedObject private var revisionService = RevisionService.shared

    @State private var reviewingConcept: RevisionService.RevisionConcept? = nil
    @State private var showAddLesson = false
    @State private var selectedTab = 0
    @State private var currentPage = 1

    private static let dueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func dueText(for concept: RevisionService.RevisionConcept) -> String {
        let today = Calendar.current.startOfDay(for: Date())
        let dueDay = Calendar.current.startOfDay(for: concept.nextDue)
        if dueDay <= today { return "Due today" }
        return "Next due \(dueDateFormatter.string(from: concept.nextDue))"
    }

    private var totalConceptPages: Int {
        PFPagination.totalPages(totalCount: revisionService.allConcepts.count)
    }

    private var effectiveConceptPage: Int {
        PFPagination.clampedPage(currentPage, totalPages: totalConceptPages)
    }

    private var visibleAllConcepts: [RevisionService.RevisionConcept] {
        PFPagination.slice(revisionService.allConcepts, page: currentPage)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.xl) {
                headerSection
                Picker("Revision list", selection: $selectedTab) {
                    Text("Due today (\(revisionService.dueToday.count))").tag(0)
                    Text("Weak concepts (\(revisionService.weakConcepts.count))").tag(1)
                    Text("All (\(revisionService.allConcepts.count))").tag(2)
                }
                .pickerStyle(.segmented)
                if selectedTab == 0 {
                    dueSection
                } else if selectedTab == 1 {
                    weakSection
                } else {
                    allSection
                }
                addSection
            }
            .padding(PFSpacing.lg)
            .id("revisionTop")
        }
        .pfScrollToTopOnAppear("revisionTop", resetWhen: (selectedTab, currentPage))
        // Copy protection: revision content cannot be selected, a
        // faint identity watermark sits over it, and recording blurs
        // it out. The review and add-lesson sheets sit outside this
        // ScrollView, so they stay editable.
        .pfProtectedContent()
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle("Revision Centre")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reviewingConcept) { concept in
            ReviewSheet(concept: concept)
        }
        .sheet(isPresented: $showAddLesson) {
            AddLessonSheet()
        }
        .onChange(of: selectedTab) { _, _ in
            currentPage = 1
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text("Daily revision")
                .font(.pfScreenTitle)
                .foregroundColor(.pfNavy)
            Text("Recall each concept from memory, then mark yourself correct or incorrect. Correct recalls push the concept further out; incorrect ones bring it back to today.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Lists

    private var dueSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Due today")
            if revisionService.dueToday.isEmpty {
                PFCard {
                    Text("Nothing is due today. Complete a lesson and add it below, or come back when a concept falls due.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(revisionService.dueToday) { concept in
                    ConceptRow(concept: concept) {
                        reviewingConcept = concept
                    }
                }
            }
        }
    }

    private var weakSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Weak concepts")
            if revisionService.weakConcepts.isEmpty {
                PFCard {
                    Text("No weak concepts yet. A concept appears here when you have marked it incorrect more often than correct.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(revisionService.weakConcepts) { concept in
                    ConceptRow(concept: concept) {
                        reviewingConcept = concept
                    }
                }
            }
        }
    }

    private var allSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "All revision concepts")
            if revisionService.allConcepts.isEmpty {
                PFCard {
                    Text("No concepts scheduled yet. Add a completed lesson below to start revising it.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(visibleAllConcepts) { concept in
                    ConceptRow(concept: concept) {
                        reviewingConcept = concept
                    }
                }
                if totalConceptPages > 1 {
                    let bounds = PFPagination.rangeBounds(page: effectiveConceptPage, totalCount: revisionService.allConcepts.count)
                    Text("Showing \(bounds.first)-\(bounds.last) of \(revisionService.allConcepts.count) concepts")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PFPaginationBar(currentPage: effectiveConceptPage, totalPages: totalConceptPages) { page in
                        currentPage = page
                    }
                }
            }
        }
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Add a lesson to revision")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text("Pick any lesson you have completed. It is scheduled for revision today, then at day 1, day 3, day 7 and day 30 as you recall it correctly.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    PFSecondaryButton(title: "Choose a completed lesson") {
                        showAddLesson = true
                    }
                }
            }
        }
    }
}

// MARK: - Concept row

private struct ConceptRow: View {
    let concept: RevisionService.RevisionConcept
    let onReview: () -> Void

    var body: some View {
        PFCard {
            HStack(spacing: PFSpacing.md) {
                PFIconTile(systemImage: "arrow.clockwise", size: 44)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(concept.title)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(RevisionCentreView.dueText(for: concept))
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                    Text("Correct \(concept.correctCount) • Incorrect \(concept.incorrectCount) • Interval \(concept.intervalDays) \(concept.intervalDays == 1 ? "day" : "days")")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Review", action: onReview)
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.pfRoyal)
                    .cornerRadius(10)
                    .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Review sheet

/// The review flow: recall the concept first, then mark Correct or
/// Incorrect. The answer is recorded in RevisionService, which
/// advances or resets the interval.
private struct ReviewSheet: View {
    @EnvironmentObject private var contentService: ContentService
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var revisionService = RevisionService.shared
    let concept: RevisionService.RevisionConcept

    @State private var revealed = false
    @State private var recorded: Bool? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.lg) {
                    Text(concept.title)
                        .font(.pfSectionTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    PFCard {
                        VStack(alignment: .leading, spacing: PFSpacing.md) {
                            Text("Recall from memory")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                            Text("Before looking, try to recall the key points of this lesson: what it taught, why it matters at work, and where it can go wrong.")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            if revealed {
                                if let entry = contentService.allLessons.first(where: { $0.id == concept.id }) {
                                    Text(entry.preview)
                                        .font(.pfBody)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Button {
                                        LessonSheetRouter.shared.open(entry)
                                    } label: {
                                        Text("Open the lesson to check yourself")
                                            .font(.pfBody.weight(.semibold))
                                            .foregroundColor(.pfRoyal)
                                    }
                                } else {
                                    Text("This lesson is not in the loaded catalogue right now.")
                                        .font(.pfBody)
                                        .foregroundColor(.pfSecondaryText)
                                }
                            } else {
                                PFSecondaryButton(title: "I have recalled it, show me the summary") {
                                    revealed = true
                                }
                            }
                        }
                    }
                    if recorded == nil {
                        VStack(spacing: PFSpacing.md) {
                            PFPrimaryButton(title: "I recalled it correctly") {
                                revisionService.recordReview(conceptID: concept.id, correct: true)
                                recorded = true
                            }
                            PFSecondaryButton(title: "I did not recall it") {
                                revisionService.recordReview(conceptID: concept.id, correct: false)
                                recorded = false
                            }
                        }
                    } else {
                        PFCard {
                            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                                Text(recorded == true ? "Recorded as correct. The next review is pushed further out." : "Recorded as incorrect. This concept is due again today.")
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                PFPrimaryButton(title: "Done") {
                                    dismiss()
                                }
                            }
                        }
                    }
                }
                .padding(PFSpacing.lg)
                .id("reviewSheetTop")
            }
            .pfScrollToTopOnAppear("reviewSheetTop")
            .background(Color.pfBackground)
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Add lesson sheet

private struct AddLessonSheet: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var revisionService = RevisionService.shared

    @State private var currentPage = 1

    private var completedLessons: [SearchEntry] {
        contentService.allLessons.filter { progressStore.isLessonComplete($0.id) }
    }

    private var unscheduled: [SearchEntry] {
        completedLessons.filter { !revisionService.isScheduled(lessonID: $0.id) }
    }

    private var totalUnscheduledPages: Int {
        PFPagination.totalPages(totalCount: unscheduled.count)
    }

    private var effectiveUnscheduledPage: Int {
        PFPagination.clampedPage(currentPage, totalPages: totalUnscheduledPages)
    }

    private var visibleUnscheduled: [SearchEntry] {
        PFPagination.slice(unscheduled, page: currentPage)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    if unscheduled.isEmpty {
                        Text(completedLessons.isEmpty
                            ? "No completed lessons yet. Complete a lesson first, then add it here."
                            : "Every completed lesson is already scheduled for revision.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(visibleUnscheduled) { lesson in
                            Button {
                                revisionService.scheduleLessonForRevision(lessonID: lesson.id, title: lesson.title)
                                dismiss()
                            } label: {
                                PFCard {
                                    HStack(spacing: PFSpacing.md) {
                                        if lesson.thumbnail != nil {
                                            PFThumbnailView(thumbnailPath: lesson.thumbnail, size: 40, cornerRadius: 12)
                                        } else {
                                            PFIconTile(systemImage: "book.fill", size: 40)
                                        }
                                        Text(lesson.title)
                                            .font(.pfBody)
                                            .foregroundColor(.pfNavy)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer()
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.pfRoyal)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        if totalUnscheduledPages > 1 {
                            let bounds = PFPagination.rangeBounds(page: effectiveUnscheduledPage, totalCount: unscheduled.count)
                            Text("Showing \(bounds.first)-\(bounds.last) of \(unscheduled.count) lessons")
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            PFPaginationBar(currentPage: effectiveUnscheduledPage, totalPages: totalUnscheduledPages) { page in
                                currentPage = page
                            }
                        }
                    }
                }
                .padding(PFSpacing.lg)
                .id("addLessonTop")
            }
            .pfScrollToTopOnAppear("addLessonTop", resetWhen: currentPage)
            .background(Color.pfBackground)
            .navigationTitle("Add a lesson")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
