// OnboardingFlowView.swift
// Payments Training Hub iOS - Explanation-first first-run screen:
// one screen that says who the app is for, why it helps, and how
// the journey works, then a single Get started button. No
// questions up front: the old seven-step flow asked about role,
// knowledge, objective, intensity and a diagnostic before the
// learner had seen anything, and new users dropped out. The
// profile models, the store, and the diagnostic view all stay in
// the codebase (Learning Preferences and the assessments still
// use them); only this flow stops asking.
//
// Get started records the skip (markSkipped: onboarding complete
// with no fabricated profile, weekly goal untouched) and calls
// onFinish, so the flow can be presented as a fullScreenCover
// with no other dependencies: the only init argument is
// onFinish. Onboarding never forces sign-in and never gates
// browsing.
//
// Counts come from ContentManifest only. The first lesson and the
// free case come from the live catalogue, so nothing is shown
// before it is known. The first lesson is the first lesson of
// Course 1 in reading order, which the lesson screen opens free
// with full content (see LessonView: the first lesson of each
// chapter is never locked). The free case is the first free
// sample situation in ContentService.freeSampleIDs, which are
// ungated. No em dashes in any user-facing text.

import SwiftUI

struct OnboardingFlowView: View {
    let onFinish: () -> Void

    @ObservedObject private var contentService = ContentService.shared
    @ObservedObject private var onboardingStore = OnboardingStore.shared

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.lg) {
                    Text("Learn payments, properly.")
                        .font(.pfScreenTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)

                    explanationBlock(
                        systemImage: "person.2.fill",
                        title: "Who it is for",
                        body: "Built for people who work in payments or want to: business analysts, product owners, freshers starting out, and anyone who needs to understand how money moves."
                    )
                    explanationBlock(
                        systemImage: "lightbulb.fill",
                        title: "Why it helps",
                        body: "881 short narrated lessons across 10 courses, 564 real-world payment situations, practice labs, simulators, and interview preparation, all in one place, in plain language."
                    )
                    explanationBlock(
                        systemImage: "map.fill",
                        title: "Your journey",
                        body: "Start with Course 1 and work through in order, or pick the course that matches the gap you need to close. Your progress saves as you go."
                    )

                    PFCard {
                        VStack(spacing: PFSpacing.md) {
                            countRow(value: ContentManifest.chapterCount, label: "chapters")
                            countRow(value: ContentManifest.lessonCount, label: "lessons")
                            countRow(value: ContentManifest.situationCount, label: "Payment Cases")
                            countRow(value: ContentManifest.interviewQuestionCount, label: "interview questions")
                        }
                    }

                    firstLessonCard
                    freeCaseCard

                    PFPrimaryButton(title: "Get started") {
                        getStarted()
                    }
                    .accessibilityLabel("Get started")

                    Text("No sign-in needed. Nothing here locks browsing: you can explore first and come back to a route later.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(PFSpacing.lg)
                .id("onboardingTop")
            }
            .pfScrollToTopOnAppear("onboardingTop")
            .background(Color.pfBackground)
            .navigationTitle("Get started")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Explanation

    /// One explanation block: an icon tile, a heading, and the
    /// explanation copy. The copy is the shared onboarding copy,
    /// used verbatim across surfaces.
    private func explanationBlock(systemImage: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: PFSpacing.md) {
            PFIconTile(systemImage: systemImage, size: 44)
            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                Text(title)
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                Text(body)
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func countRow(value: Int, label: String) -> some View {
        HStack(spacing: PFSpacing.sm) {
            Text("\(value)")
                .font(.pfSectionTitle)
                .foregroundColor(.pfNavy)
            Text(label)
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    /// Get started: record onboarding as complete with no
    /// profile (nothing was asked, so nothing is invented), leave
    /// the weekly goal untouched, and finish.
    private func getStarted() {
        onboardingStore.markSkipped()
        onFinish()
    }

    // MARK: - Free value

    /// The first lesson of Course 1 in reading order. Nil while
    /// the catalogue is still loading: the card simply does not
    /// show, rather than promising a lesson that is not there yet.
    private var firstLesson: SearchEntry? {
        contentService.readingOrderLessons.first
    }

    /// The first free Payment Case, resolved from the live catalogue.
    /// Nil while the catalogue is still loading.
    private var freeCase: Situation? {
        guard let id = ContentService.freeSampleIDs.first else { return nil }
        return pfSituation(id: id, in: contentService)
    }

    /// The first lesson card. The first lesson of a chapter opens
    /// free with full content, and the card says so only when the
    /// catalogue confirms this lesson is that first lesson.
    @ViewBuilder
    private var firstLessonCard: some View {
        if let firstLesson {
            let isSample = PFChapterHelper.isSampleLesson(firstLesson, in: contentService)
            NavigationLink(destination: LessonView(entry: firstLesson)) {
                PFCard {
                    HStack(spacing: PFSpacing.md) {
                        if firstLesson.thumbnail != nil {
                            PFThumbnailView(thumbnailPath: firstLesson.thumbnail, size: 44, cornerRadius: 12)
                        } else {
                            PFIconTile(systemImage: "play.fill", size: 44)
                        }
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text("Start with the first lesson")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(isSample
                                ? "\(firstLesson.title). Free sample lesson: this lesson opens free, with the full content. The rest of its chapter unlocks with the course."
                                : "\(firstLesson.title). The lesson screen explains what unlocks it if it is locked.")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.pfSecondaryText)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start with the first lesson: \(firstLesson.title)")
        }
    }

    /// The free Payment Case card: free sample situations are
    /// ungated, so this always opens real content for free once the
    /// catalogue has loaded. While it loads, the card says so
    /// honestly instead of offering a case that is not there yet.
    @ViewBuilder
    private var freeCaseCard: some View {
        if let freeCase {
            NavigationLink(destination: SituationDetailView(situation: freeCase)) {
                PFCard {
                    HStack(spacing: PFSpacing.md) {
                        if freeCase.thumbnail != nil {
                            PFThumbnailView(thumbnailPath: freeCase.thumbnail, size: 44, cornerRadius: 12)
                        } else {
                            PFIconTile(systemImage: "briefcase.fill", size: 44)
                        }
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text("Explore a free Payment Case")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(freeCase.title). Free to open, no purchase needed. There are \(ContentService.freeSampleIDs.count) free cases in total.")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.pfSecondaryText)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Explore a free Payment Case: \(freeCase.title)")
        } else {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text("Explore a free Payment Case")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    Text("The free cases will appear here once the course list has loaded. There are \(ContentService.freeSampleIDs.count) free cases, and they stay free without a purchase.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityLabel("Free Payment Cases will appear once the course list has loaded.")
        }
    }
}
