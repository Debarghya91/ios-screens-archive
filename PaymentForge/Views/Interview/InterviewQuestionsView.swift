// InterviewQuestionsView.swift
// PaymentForge iOS - Interview questions section.
//
// Situation-based interview questions for payments and BA roles,
// loaded from the bundled interview-questions.json only. No network,
// no backend. The section has a category list, a search across all
// questions, and expandable model answers. Tapping a question shows
// its answer; only one answer is open at a time.

import SwiftUI

/// The interview questions section: categories, or search results
/// when a query is typed. Tapping a category opens its questions.
struct InterviewQuestionsView: View {
    @State private var searchText = ""

    private var bank: InterviewQuestionBank? { InterviewQuestionStore.shared }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchResults: [InterviewQuestion] {
        InterviewQuestionStore.search(searchText)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                searchField

                if isSearching {
                    searchResultsSection
                } else {
                    categoriesSection
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
        .navigationTitle("Interview Questions")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: PFSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.pfBody.weight(.semibold))
                .foregroundColor(.pfSecondaryText)
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

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            if let bank {
                Text("\(bank.total) interview questions across \(bank.categories.count) topics. Open a topic to practise, or search for a situation.")
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
                                        .font(.pfBody)
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
            } else {
                Text("Interview questions are not available right now. Please try again later.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Search results

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Results")
            if searchResults.isEmpty {
                Text("No interview questions match that search. Try a different word, for example sanctions, reconciliation or stakeholder.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                InterviewQuestionList(
                    questions: searchResults,
                    showCategory: true
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
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                Text("\(category.questions.count) situation-based questions. Tap one to see a model answer.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                InterviewQuestionList(
                    questions: category.questions,
                    showCategory: false
                )
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A paginated list of interview questions with expandable answers.
/// Twenty at first; Load more adds twenty. The page resets whenever
/// the question set changes, so a new search or category starts
/// from the top.
struct InterviewQuestionList: View {
    let questions: [InterviewQuestion]
    var showCategory: Bool = false

    @State private var expandedQuestionID: String? = nil
    @State private var visibleCount: Int = 20

    private static let pageSize = 20

    private var visibleQuestions: [InterviewQuestion] {
        Array(questions.prefix(visibleCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            ForEach(visibleQuestions) { question in
                questionRow(question)
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
        .onChange(of: questions) { _, _ in
            visibleCount = Self.pageSize
            expandedQuestionID = nil
        }
    }

    private func questionRow(_ question: InterviewQuestion) -> some View {
        let isExpanded = expandedQuestionID == question.id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedQuestionID = isExpanded ? nil : question.id
            }
        } label: {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    HStack(alignment: .top, spacing: PFSpacing.sm) {
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            if showCategory,
                               let categoryTitle = InterviewQuestionStore.categoryTitle(for: question.id) {
                                Text(categoryTitle)
                                    .font(.pfCaptionBold)
                                    .foregroundColor(.pfRoyal)
                            }
                            Text(question.question)
                                .font(.pfBody)
                                .fontWeight(.semibold)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.pfBody.weight(.semibold))
                            .foregroundColor(.pfSecondaryText)
                    }
                    if isExpanded {
                        Divider()
                        Text("Model answer")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                        Text(question.answer)
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .lineSpacing(7)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .buttonStyle(PFCardButtonStyle())
        .accessibilityLabel(question.question)
        .accessibilityHint(isExpanded ? "Hides the model answer" : "Shows the model answer")
    }
}
