// InterviewQuestionsView.swift
// Payments Training Hub iOS - Interview questions section.
//
// Situation-based interview questions for payments and BA roles,
// loaded from the bundled interview-questions.json only. No network,
// no backend. The section has a category list, a search across all
// questions, and expandable model answers. Tapping a question shows
// its answer; only one answer is open at a time, and the question
// scrolls into view so a long answer is not left below the fold.
// When the bundled bank cannot be loaded, the section shows a
// local-data error state with a Try again action instead of an
// empty list or a misleading zero-results message.

import SwiftUI

/// The interview questions section: categories, or search results
/// when a query is typed. Tapping a category opens its questions.
struct InterviewQuestionsView: View {
    @State private var searchText = ""
    /// Bumped by the Try again action so the view re-reads the
    /// bundled bank after InterviewQuestionStore.reload().
    @State private var loadAttempt = 0

    /// The bundled bank. Reading loadAttempt subscribes this view
    /// to the Try again action, so a successful reload re-renders.
    private var bank: InterviewQuestionBank? {
        _ = loadAttempt
        return InterviewQuestionStore.shared
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchResults: [InterviewQuestion] {
        InterviewQuestionStore.search(searchText)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.lg) {
                    searchField
                        .id("interviewTop")

                    if bank == nil {
                        unavailableSection
                    } else if isSearching {
                        searchResultsSection(proxy: proxy)
                    } else {
                        categoriesSection
                    }
                }
                .padding(PFSpacing.lg)
            }
            .background(Color.pfBackground)
            // Extra scrollable space at the bottom so the last card clears
            // the tab bar on every iPhone size.
            .pfTabBarClearance()
            .onAppear {
                // The scroll rule: Back lands at the top, never
                // at the restored offset.
                proxy.scrollTo("interviewTop", anchor: .top)
            }
            .onChange(of: isSearching) { _, _ in
                // Entering or leaving search swaps the list
                // content in place: the new content starts at
                // the top.
                proxy.scrollTo("interviewTop", anchor: .top)
            }
        }
        .navigationTitle("Interview Questions")
        .navigationBarTitleDisplayMode(.large)
    }

    /// Scroll an expanded question to the top of the visible area
    /// once its answer has finished opening, so a long answer is
    /// not left below the fold.
    private func scrollToQuestion(_ id: String, proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .top)
            }
        }
    }

    // MARK: - Unavailable bank

    /// Shown only when the bundled question bank could not be
    /// loaded. The questions live in the app itself, so this is a
    /// local-data problem, not a connection problem, and the copy
    /// says so. Try again re-reads the bundled file.
    private var unavailableSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            Text("Interview questions are not available")
                .font(.pfCardTitle)
                .foregroundColor(.pfNavy)
            Text("The interview questions are stored in the app itself and could not be loaded. This is not a connection problem. Try again, or reinstall the app if the problem continues.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            PFSecondaryButton(title: "Try again") {
                InterviewQuestionStore.reload()
                loadAttempt += 1
            }
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: PFSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.pfBody.weight(.semibold))
                .foregroundColor(.pfSecondaryText)
                .accessibilityHidden(true)
            TextField("Search interview questions", text: $searchText)
                .font(.pfBody)
                .foregroundColor(.pfNavy)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.pfBody.weight(.regular))
                        .foregroundColor(.pfSecondaryText)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(PFSpacing.md)
        .background(Color.pfCard)
        .cornerRadius(PFSpacing.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                .stroke(Color.pfBorder, lineWidth: 1)
        )
    }

    // MARK: - Categories

    /// The category list. A nil bank never reaches here: body shows
    /// unavailableSection instead, so the list below only renders
    /// when the bank loaded.
    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            if let bank {
                Text("\(bank.total) interview questions across \(bank.categories.count) categories. Open a category to practise, or search for a question.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(bank.categories) { category in
                    NavigationLink(destination: InterviewCategoryQuestionsView(category: category)) {
                        PFCard {
                            HStack(spacing: PFSpacing.md) {
                                PFIconTile(systemImage: "questionmark.circle.fill", size: 44)
                                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                    Text(category.title)
                                        .font(.pfCardTitle)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("\(category.questions.count) questions")
                                        .font(.pfCaptionBold)
                                        .foregroundColor(.pfSecondaryText)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.pfSecondaryText)
                            }
                        }
                    }
                    .buttonStyle(PFCardButtonStyle())
                    .accessibilityLabel("\(category.title), \(category.questions.count) questions")
                }
            }
        }
    }

    // MARK: - Search results

    /// Search results, in the same title-plus-guidance shape as the
    /// Search tab's empty state. This only renders when the bank
    /// loaded (body gates on nil), so an empty list here always
    /// means no matching questions, never a load failure.
    private func searchResultsSection(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Results")
            if searchResults.isEmpty {
                Text("No interview questions match that search")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Try a different word, for example sanctions, reconciliation or stakeholder.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                InterviewQuestionList(
                    questions: searchResults,
                    showCategory: true,
                    onExpand: { id in scrollToQuestion(id, proxy: proxy) }
                )
            }
        }
    }
}

/// The questions of one category, twenty at a time. Tapping a
/// question reveals its model answer; only one answer is open.
struct InterviewCategoryQuestionsView: View {
    let category: InterviewCategory

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.lg) {
                    Text("\(category.questions.count) situation-based questions. Tap one to see a model answer.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    InterviewQuestionList(
                        questions: category.questions,
                        showCategory: false,
                        onExpand: { id in scrollToQuestion(id, proxy: proxy) }
                    )
                }
                .padding(PFSpacing.lg)
            }
            .background(Color.pfBackground)
            .pfTabBarClearance()
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Scroll an expanded question to the top of the visible area
    /// once its answer has finished opening, so a long answer is
    /// not left below the fold.
    private func scrollToQuestion(_ id: String, proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .top)
            }
        }
    }
}

/// A paginated list of interview questions with expandable answers,
/// presented in the Situations case-study format (see questionRow).
/// Twenty at first; Load more adds twenty. The page resets whenever
/// the question set changes, so a new search or category starts
/// from the top, but an open answer stays open when its question is
/// still in the new set, so typing another letter does not close
/// the answer being read. Expanding a question reports its id
/// through onExpand so the parent can scroll it into view.
struct InterviewQuestionList: View {
    let questions: [InterviewQuestion]
    var showCategory: Bool = false
    var onExpand: ((String) -> Void)? = nil

    @State private var expandedQuestionID: String? = nil
    @State private var visibleCount: Int = 20

    private static let pageSize = 20

    private var visibleQuestions: [InterviewQuestion] {
        Array(questions.prefix(visibleCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            ForEach(Array(visibleQuestions.enumerated()), id: \.element.id) { index, question in
                questionRow(question, number: index + 1)
            }
            if questions.count > visibleQuestions.count {
                Text("Showing \(visibleQuestions.count) of \(questions.count) questions")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                PFSecondaryButton(title: "Load more questions") {
                    visibleCount += Self.pageSize
                }
            }
        }
        .onChange(of: questions) { _, newQuestions in
            visibleCount = Self.pageSize
            // Collapse the open answer only when its question left
            // the set. Typing another search letter refines the set
            // but must not close an answer that is still listed.
            if let openID = expandedQuestionID,
               !newQuestions.contains(where: { $0.id == openID }) {
                expandedQuestionID = nil
            }
        }
    }

    /// One question row, in the Situations case-study presentation:
    /// the number badge, gold leading accent and gold tile from the
    /// situation row, the question at card-title scale, the category
    /// as a pill below it, and, when expanded, the answer in the
    /// Situations detail shape: a read-time line and a labelled
    /// Model answer section in body text. Question and answer
    /// wording is unchanged; only the presentation mirrors the
    /// Situations format.
    private func questionRow(_ question: InterviewQuestion, number: Int) -> some View {
        let isExpanded = expandedQuestionID == question.id
        let categoryTitle: String? = showCategory
            ? InterviewQuestionStore.categoryTitle(for: question.id)
            : nil
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedQuestionID = isExpanded ? nil : question.id
            }
            if !isExpanded {
                onExpand?(question.id)
            }
        } label: {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    HStack(alignment: .top, spacing: PFSpacing.md) {
                        Text("\(number)")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                            .frame(width: 26, height: 26)
                            .background(Color.pfRoyal.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .accessibilityHidden(true)
                        Rectangle()
                            .fill(Color.pfGold)
                            .frame(width: 4)
                            .cornerRadius(2)
                            .accessibilityHidden(true)
                        Image(systemName: "questionmark.circle.fill")
                            .font(.pfCardTitle.weight(.semibold))
                            .foregroundColor(Color.pfGoldText)
                            .frame(width: 44, height: 44)
                            .background(Color.pfGoldSoft)
                            .clipShape(RoundedRectangle(cornerRadius: PFSpacing.smallRadius))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: PFSpacing.sm) {
                            Text(question.question)
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if let categoryTitle {
                                PFPill(text: categoryTitle)
                            }
                        }
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.pfBody.weight(.semibold))
                            .foregroundColor(.pfSecondaryText)
                    }
                    if isExpanded {
                        VStack(alignment: .leading, spacing: PFSpacing.lg) {
                            if let readLabel = ReadTime.label(for: question.question + " " + question.answer) {
                                Label(readLabel, systemImage: "clock")
                                    .font(.pfCaptionBold)
                                    .foregroundColor(.pfSecondaryText)
                            }
                            answerSection(title: "Model answer") {
                                bodyText(question.answer)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(PFCardButtonStyle())
        .id(question.id)
        .accessibilityLabel(categoryTitle.map { "\(question.question), in \($0)" } ?? question.question)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Hides the model answer" : "Shows the model answer")
    }

    /// One body-text paragraph, as in the Situations detail tabs.
    /// Rendered through the shared paragraph renderer, so a long
    /// model answer reads as logical paragraphs with breathing
    /// room instead of one wall of text.
    private func bodyText(_ text: String) -> some View {
        PFBodyText(text: text)
    }

    /// A labelled section inside the expanded answer, as in the
    /// Situations detail tabs: a navy caption-bold heading over the
    /// section content.
    private func answerSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text(title)
                .font(.pfCaptionBold)
                .foregroundColor(.pfNavy)
            content()
        }
    }
}
