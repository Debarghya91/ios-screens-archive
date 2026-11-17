// OnboardingFlowView.swift
// Payments Training Hub iOS - Swipeable first-run introduction:
// four pages the learner swipes through, answering why this app
// exists, who it is for, what it can do, and what is free. No
// Next button and no Back button: swipe moves between pages, the
// dots below jump straight to a page, and Skip is always visible
// in the top bar. A small looping swipe hint plays under the
// pages until the last one, where Get started takes its place
// and stays fixed and visible. No questions up front: the old
// seven-step flow asked about role, knowledge, objective,
// intensity and a diagnostic before the learner had seen
// anything, and new users dropped out. The profile models, the
// store, and the diagnostic view all stay in the codebase
// (Learning Preferences and the assessments still use them);
// only this flow stops asking.
//
// Get started records the skip (markSkipped: onboarding complete
// with no fabricated profile, weekly goal untouched) and calls
// onFinish, so the flow can be presented as a fullScreenCover
// with no other dependencies: the only init argument is
// onFinish. Onboarding runs after sign-in: the app gate shows
// the sign-in screen first, and this flow never promises that
// sign-in is optional.
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
import UIKit
import ImageIO

struct OnboardingFlowView: View {
    let onFinish: () -> Void

    @ObservedObject private var contentService = ContentService.shared
    @ObservedObject private var onboardingStore = OnboardingStore.shared

    @State private var currentPage = 0

    private static let pageCount = 4

    private var isLastPage: Bool {
        currentPage == Self.pageCount - 1
    }

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    whyPage
                        .tag(0)
                    whoPage
                        .tag(1)
                    capabilitiesPage
                        .tag(2)
                    freePage
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                footer
            }
            .background(Color.pfBackground)
            .navigationTitle("Get started")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Skip") {
                        getStarted()
                    }
                    .accessibilityLabel("Skip this introduction")
                    .accessibilityHint("Skips the introduction and opens the app.")
                }
            }
        }
    }

    // MARK: - Footer: swipe hint or Get started, plus dots

    /// The fixed footer: the looping swipe hint on every page
    /// except the last, where Get started takes its place so it
    /// is always visible without scrolling, and the tappable
    /// dots under both.
    private var footer: some View {
        VStack(spacing: PFSpacing.md) {
            if isLastPage {
                PFPrimaryButton(title: "Get started") {
                    getStarted()
                }
                .accessibilityLabel("Get started")
            } else {
                AnimatedGIFView(assetName: "SwipeNext")
                    .frame(width: 84, height: 28)
                    .accessibilityHidden(true)
            }
            dotsRow
        }
        .padding(.horizontal, PFSpacing.xl)
        .padding(.top, PFSpacing.md)
        .padding(.bottom, PFSpacing.lg)
        .background(Color.pfBackground)
    }

    /// Tappable dots: one per page, the current page in royal, so
    /// the length of the introduction is clear and any page is
    /// one tap away.
    private var dotsRow: some View {
        HStack(spacing: PFSpacing.sm) {
            ForEach(0..<Self.pageCount, id: \.self) { index in
                Button {
                    withAnimation {
                        currentPage = index
                    }
                } label: {
                    Circle()
                        .fill(index == currentPage ? Color.pfRoyal : Color.pfBorder)
                        .frame(width: index == currentPage ? 10 : 8, height: index == currentPage ? 10 : 8)
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .accessibilityLabel("Page \(index + 1) of \(Self.pageCount)")
            }
        }
    }

    // MARK: - Pages

    /// One pager page: a vertical scroll of content, so nothing
    /// is clipped on small phones. The footer below the pager
    /// stays fixed.
    private func pageScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                content()
            }
            .padding(PFSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One page heading. Each page has its own title and
    /// subtitle: a single shared headline on all four pages made
    /// them read as the same page.
    private func pageHeading(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text(title)
                .font(.pfScreenTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Page 1: why this app exists.
    private var whyPage: some View {
        pageScroll {
            pageHeading(title: "Learn payments, properly.", subtitle: "The full payments course: short lessons, real cases, and practice, in plain language.")
            PaymentJourneyAnimation()
            Text("Why this app")
                .font(.pfSectionTitle)
                .foregroundColor(.pfRoyal)
            Text("Payments move the world's money, but learning how they work is harder than it should be. The knowledge is scattered across bank documents, scheme rulebooks and long threads. This app gathers it into one complete course, in plain language, built from real bank work.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            explanationBlock(
                systemImage: "building.columns.fill",
                title: "Built from real work",
                body: "Every lesson comes from real payments work at a large UK bank: real message flows, real failures, and real fixes."
            )
            explanationBlock(
                systemImage: "book.fill",
                title: "One course, in order",
                body: "\(ContentManifest.lessonCount) short lessons across \(ProductCatalogue.partProducts.count) courses and \(ContentManifest.chapterCount) chapters, in reading order, so you always know what comes next."
            )
            explanationBlock(
                systemImage: "textformat",
                title: "Plain language",
                body: "No jargon without an explanation. Every term is explained where it first appears."
            )
        }
    }

    /// Page 2: who the app is built for.
    private var whoPage: some View {
        pageScroll {
            pageHeading(title: "Built for the people who move money.", subtitle: "From your first payments job to the most senior role, the course meets you where you are.")
            RoleHighlightAnimation()
            Text("Who it is for")
                .font(.pfSectionTitle)
                .foregroundColor(.pfRoyal)
            Text("Built for people who work in payments or want to, at any stage of their career.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            explanationBlock(
                systemImage: "person.fill",
                title: "Business analysts",
                body: "You gather requirements and shape how payments work. Learn the domain properly, so your documents hold up."
            )
            explanationBlock(
                systemImage: "person.2.fill",
                title: "Product owners and managers",
                body: "You own a payments product and decide what gets built. Understand the flows, the rules and the risks."
            )
            explanationBlock(
                systemImage: "graduationcap.fill",
                title: "Freshers starting out",
                body: "You are starting out and want the foundations first, in order, without guessing what to learn next."
            )
            explanationBlock(
                systemImage: "checkmark.seal.fill",
                title: "Testers and engineers",
                body: "You test or build payment systems. Understand the flows, the messages and the failure cases."
            )
            explanationBlock(
                systemImage: "lightbulb.fill",
                title: "Anyone who needs to understand money movement",
                body: "Payments touch every business. Learn how money actually moves, step by step."
            )
        }
    }

    /// Page 3: what the app can do.
    private var capabilitiesPage: some View {
        pageScroll {
            pageHeading(title: "Everything you need, in one place.", subtitle: "Lessons, cases, labs, simulators and interview prep, all in reading order.")
            Text("What it can do")
                .font(.pfSectionTitle)
                .foregroundColor(.pfRoyal)
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text("What you get")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    countRow(value: ProductCatalogue.partProducts.count, label: "courses, in reading order")
                    countRow(value: ContentManifest.chapterCount, label: "chapters")
                    countRow(value: ContentManifest.lessonCount, label: "lessons")
                    countRow(value: ContentManifest.situationCount, label: "Payment Cases")
                    countRow(value: ContentManifest.interviewQuestionCount, label: "interview questions")
                    countRow(value: ContentManifest.guideCount, label: "guides")
                    countRow(value: ContentManifest.labCount, label: "labs")
                    countRow(value: ContentManifest.testCount, label: "tests")
                    countRow(value: ContentManifest.simulatorCount, label: "simulators")
                    countRow(value: ContentManifest.faqCount, label: "FAQs")
                    countRow(value: ContentManifest.weeklyCaseCount, label: "weekly cases")
                }
            }
            explanationBlock(
                systemImage: "headphones",
                title: "Read or listen",
                body: "Every lesson has audio. Listen while you travel, read when you sit down."
            )
            explanationBlock(
                systemImage: "map.fill",
                title: "Follow a journey",
                body: "Pick a learning journey for one goal, or start at Course 1 and work in order. Home always shows your next lesson."
            )
            explanationBlock(
                systemImage: "briefcase.fill",
                title: "Practise real cases",
                body: "Work real payment problems step by step, the way a senior analyst handles them, with labs, simulators and tests."
            )
            explanationBlock(
                systemImage: "questionmark.circle.fill",
                title: "Prepare for interviews",
                body: "\(ContentManifest.interviewQuestionCount) interview questions with model answers, plus the situations banks ask about."
            )
            explanationBlock(
                systemImage: "arrow.triangle.2.circlepath",
                title: "Your progress follows you",
                body: "Finished lessons, streaks and certificates save to your account and sync across your devices."
            )
        }
    }

    /// Page 4: what is free, plus the first lesson and free case.
    /// Get started lives in the fixed footer, always visible.
    private var freePage: some View {
        pageScroll {
            pageHeading(title: "Start free, then unlock what you need.", subtitle: "Try the course free. Buy a course only when you want the full content, for 1 year.")
            FreeRingAnimation()
            Text("What is free")
                .font(.pfSectionTitle)
                .foregroundColor(.pfRoyal)
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text("What is free")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    freeRow("The first lesson of every chapter is free, with the full content.")
                    freeRow("A few Payment Cases are free to try.")
                    freeRow("You can browse the whole catalogue free.")
                    freeRow("Courses unlock when you buy them, for 1 year.")
                }
            }
            firstLessonCard
            freeCaseCard
            Text("You can explore first and come back to a journey later.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
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
            CountUpNumber(value: value)
            Text(label)
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    /// One "What is free" line: a checkmark and the promise, in
    /// plain words. Every line restates a claim the app already
    /// makes on its locked screens and catalogue copy.
    private func freeRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: PFSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.pfSuccess)
                .accessibilityHidden(true)
            Text(text)
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
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
            // Never a push from inside the cover: the card
            // requests the lesson, then finishes the
            // introduction, and MainTabView opens the lesson
            // through the lesson sheet once the cover is gone.
            Button {
                LessonSheetRouter.shared.requestAfterIntroduction(firstLesson)
                // Finish on the next turn: the request and the
                // completion flag in one transaction left the
                // cover stuck on screen in gate run 44171037785
                // (its onDismiss fired but the cover never
                // left), which dropped the lesson sheet behind
                // it. The request is already recorded, so the
                // dismissal still opens it.
                Task { @MainActor in getStarted() }
            } label: {
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
            // Same deferral as the first-lesson card: request
            // the case, finish the introduction, and MainTabView
            // opens the case sheet once the cover is gone. Never
            // a push from inside the cover.
            Button {
                LessonSheetRouter.shared.requestCaseAfterIntroduction(freeCase)
                // Same next-turn finish as the first-lesson card:
                // the request and the completion flag in one
                // transaction left the cover stuck in gate run
                // 44171037785.
                Task { @MainActor in getStarted() }
            } label: {
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

// MARK: - Animated GIF hint

/// Renders a looping GIF data asset (SwiftUI has no native GIF
/// animation). Frames and per-frame delays come from the GIF
/// itself through ImageIO, so the loop matches the asset. When
/// the asset is missing, a static chevron pair shows instead, so
/// the hint never renders empty.
private struct AnimatedGIFView: UIViewRepresentable {
    let assetName: String

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.image = Self.animatedImage(assetName: assetName)
        view.tintColor = UIColor(red: 0.09, green: 0.25, blue: 0.55, alpha: 1)
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {}

    private static func animatedImage(assetName: String) -> UIImage? {
        guard let asset = NSDataAsset(name: assetName),
              let source = CGImageSourceCreateWithData(asset.data as CFData, nil) else {
            return UIImage(systemName: "chevron.left.2")
        }
        let count = CGImageSourceGetCount(source)
        var images: [UIImage] = []
        var duration: TimeInterval = 0
        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            images.append(UIImage(cgImage: cgImage))
            duration += delayForFrame(at: index, in: source)
        }
        guard !images.isEmpty, duration > 0 else {
            return UIImage(systemName: "chevron.left.2")
        }
        return UIImage.animatedImage(with: images, duration: duration)
    }

    private static func delayForFrame(at index: Int, in source: CGImageSource) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }
        if let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval, unclamped > 0 {
            return unclamped
        }
        if let clamped = gif[kCGImagePropertyGIFDelayTime] as? TimeInterval, clamped > 0 {
            return clamped
        }
        return 0.1
    }
}

// MARK: - Page animations

/// Page 1: a payment travelling from sender to beneficiary
/// through five stages, looping. The gold dot is the payment;
/// the stages are labelled so the motion teaches the journey.
/// A new payment starts each loop.
private struct PaymentJourneyAnimation: View {
    private let stages = ["You", "Your bank", "Scheme", "Their bank", "Paid"]
    @State private var progress: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let nodeWidth = width / CGFloat(stages.count)
            let startX = nodeWidth / 2
            let track = width - nodeWidth
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.pfBorder)
                    .frame(width: track, height: 3)
                    .offset(x: startX, y: 11)
                Rectangle()
                    .fill(Color.pfRoyal)
                    .frame(width: CGFloat(progress) * track, height: 3)
                    .offset(x: startX, y: 11)
                HStack(spacing: 0) {
                    ForEach(stages, id: \.self) { stage in
                        VStack(spacing: 6) {
                            Circle()
                                .fill(Color.pfCard)
                                .frame(width: 24, height: 24)
                                .overlay(Circle().stroke(Color.pfRoyal, lineWidth: 2))
                            Text(stage)
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(width: nodeWidth)
                    }
                }
                Circle()
                    .fill(Color.pfGold)
                    .frame(width: 14, height: 14)
                    .offset(x: startX + CGFloat(progress) * track - 7, y: 5)
            }
        }
        .frame(height: 64)
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                progress = 1
            }
        }
    }
}

/// Page 2: the roles the course is built for, one at a time,
/// crossfading in a loop so the page keeps moving.
private struct RoleHighlightAnimation: View {
    private let roles = ["Business analysts", "Product owners", "Freshers", "Testers", "Engineers"]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.6)) { timeline in
            let index = Int(timeline.date.timeIntervalSinceReferenceDate / 1.6) % roles.count
            HStack(spacing: PFSpacing.sm) {
                Image(systemName: "person.fill")
                    .foregroundColor(.pfRoyal)
                Text("Built for \(roles[index])")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.pfNavy)
            }
            .padding(.horizontal, PFSpacing.md)
            .padding(.vertical, PFSpacing.sm)
            .background(Color.pfNavySoft)
            .cornerRadius(20)
            .id(index)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            .animation(.easeInOut(duration: 0.4), value: index)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 40)
    }
}

/// Page 3: a number that counts up from zero when it appears.
/// The Double state is what animates; the label shows its
/// whole part.
private struct CountUpNumber: View {
    let value: Int
    @State private var displayed: Double = 0

    var body: some View {
        Text("\(Int(displayed))")
            .font(.pfSectionTitle)
            .foregroundColor(.pfNavy)
            .onAppear {
                withAnimation(.easeOut(duration: 1.2)) {
                    displayed = Double(value)
                }
            }
    }
}

/// Page 4: a ring that fills, then a checkmark that pops in.
/// The ring is the free start; the checkmark is the first
/// lesson unlocked.
private struct FreeRingAnimation: View {
    @State private var progress: Double = 0
    @State private var checked = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.pfBorder, lineWidth: 6)
                .frame(width: 72, height: 72)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.pfSuccess, lineWidth: 6)
                .frame(width: 72, height: 72)
                .rotationEffect(.degrees(-90))
            Image(systemName: "checkmark")
                .font(.title2.weight(.bold))
                .foregroundColor(.pfSuccess)
                .scaleEffect(checked ? 1 : 0.3)
                .opacity(checked ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                progress = 1
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.8)) {
                checked = true
            }
        }
    }
}
