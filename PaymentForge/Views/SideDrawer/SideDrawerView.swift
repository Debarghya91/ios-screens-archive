// SideDrawerView.swift
// Payments Training Hub iOS - Side drawer menu, modelled on a settings drawer
// design: a panel that slides in over the main content,
// with a title, option rows (icon, bold title, grey subtitle, chevron),
// a highlighted card at the bottom and the brand name below it.
// Uses the app design language: royal blue primary, gold sparingly,
// deep executive navy. No em dashes in any user-facing text.

import SwiftUI
import UIKit

/// Opens the mail app addressed to support. Used by Help and Support
/// and by About, so the address lives in one place.
private func openSupportEmail() {
    if let url = URL(string: "mailto:support@paymentstraininghub.com") {
        UIApplication.shared.open(url)
    }
}

// MARK: - Destinations

/// Where a drawer row leads. Handled by the container: tabs switch in place,
// sheets present over the app. Tab destinations (home, learn, search,
// paymentCases, myProgress) switch tabs only. Profile is a sheet
// destination, separate from My Progress: opening Profile never
// lands on My Progress and vice versa. Practice is a sheet
// destination too: it opens Practice Mode for the first
// practice-eligible situation. The four practice experiences
// (simulator, isoExplorer, exceptionLab, baStudio) are sheet
// destinations as well: they never become tabs. weeklyFreeCase
// is a sheet destination too: it opens the Free Case of the
// Week, one free payment case a week, never a tab.
// communityChallenge is a sheet destination too: it opens the
// weekly community challenge, never a tab. myLearning is kept
// for the Keep Learning card at the bottom, and also switches to Learn.
enum DrawerDestination: String, Identifiable, Hashable {
    case home
    case learn
    case search
    case paymentCases
    case practice
    case weeklyFreeCase
    case communityChallenge
    case myProgress
    case simulator
    case isoExplorer
    case exceptionLab
    case baStudio
    case myLearning
    case myPurchases
    case profile
    case appearance
    case helpAndSupport
    case about
    case startTour

    var id: String { rawValue }

    /// The tab index this destination switches to, if it is a tab
    /// destination. Home 0, Learn 1, Search 2, Payment Cases 3,
    /// My Progress 4. Sheet destinations return nil: they are never
    /// the current tab, so they never show the active row state.
    var tabIndex: Int? {
        switch self {
        case .home:
            return 0
        case .learn, .myLearning:
            return 1
        case .search:
            return 2
        case .paymentCases:
            return 3
        case .myProgress:
            return 4
        case .practice, .weeklyFreeCase, .communityChallenge, .simulator, .isoExplorer, .exceptionLab, .baStudio, .myPurchases, .profile, .appearance, .helpAndSupport, .about, .startTour:
            return nil
        }
    }
}

// MARK: - Drawer row model

private struct DrawerRowModel: Identifiable {
    let id: DrawerDestination
    let icon: String
    let title: String
    let subtitle: String
}

// MARK: - The drawer

/// The side drawer panel. Slides in from the left over the main content.
/// The container (DrawerContainer) handles the animation, dimming and
/// gestures; this view is the panel content only.
struct SideDrawerView: View {
    @EnvironmentObject private var progressStore: ProgressStore

    /// Called when a row is tapped. The container closes the drawer and
    /// then performs the navigation.
    var onSelect: (DrawerDestination) -> Void

    /// The currently selected tab, when the container knows it. The
    /// row for the current tab shows the active state, so the drawer
    /// says where the learner already is. Nil means no row is active.
    var selectedTab: Int? = nil

    /// The drawer row the guided tour wants scrolled into view,
    /// if any. Nil when the tour is not running or is on a tab
    /// step: the list never scrolls on its own outside the
    /// tour, and the tour's drawer steps only ever bring the
    /// highlighted row into view, with no showcase scroll.
    var tourScrollTarget: DrawerDestination? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Scrolls the drawer list to a row, animated at a medium
    /// human pace unless Reduce Motion is on, so the scroll
    /// itself is visible rather than a jump.
    private func scrollToRow(_ target: DrawerDestination, proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeInOut(duration: 0.6)) {
                proxy.scrollTo(target, anchor: .center)
            }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    /// The rows in the drawer, in display order: first the five tab
    /// destinations, Practice, the Free Case of the Week and the
    /// Weekly Challenge, then the four
    /// practice experiences (Payment Simulator, ISO 20022 Explorer,
    /// Exception Lab, BA/PO Studio),
    /// then Profile as its own account destination, then purchases,
    /// appearance, help and about, and Start Tour last. Practice sits directly after
    /// Payment Cases, the cases it practises, and before My
    /// Progress. The Free Case of the Week sits after Practice: it
    /// is one free case a week, and it opens as a sheet, never a
    /// tab. The guided tour addresses drawer rows by
    /// destination through their anchors and scrolls by row id, so
    /// the extra rows move no tour spotlight: each tour step still
    /// resolves its own row, and the new rows have no tour step.
    /// Profile is listed explicitly so
    /// it is always one tap away, and it routes to the Profile
    /// sheet, never to the My Progress tab.
    /// Refer and Win is deliberately not listed: there is no referral
    /// offer for Payments Training Hub, and the brief says to leave the row out
    /// rather than invent one. Referral invites (ReferralInvite)
    /// are local-only text and links with no reward, shared from
    /// the weekly free case screen and the share sheets, and they
    /// get no drawer row either.
    private var rows: [DrawerRowModel] {
        [
            DrawerRowModel(
                id: .home,
                icon: "house.fill",
                title: "Home",
                subtitle: "Your personalised home for continuing to learn"
            ),
            DrawerRowModel(
                id: .learn,
                icon: "book.fill",
                title: "Learn",
                subtitle: "Learning paths, courses and all chapters"
            ),
            DrawerRowModel(
                id: .search,
                icon: "magnifyingglass",
                title: "Search",
                subtitle: "Search lessons, guides, cases and questions"
            ),
            DrawerRowModel(
                id: .paymentCases,
                icon: "briefcase.fill",
                title: "Payment Cases",
                subtitle: "Real-world payment situations to practise"
            ),
            DrawerRowModel(
                id: .practice,
                icon: "flask.fill",
                title: "Practice",
                subtitle: "Test yourself on real payment scenarios"
            ),
            DrawerRowModel(
                id: .weeklyFreeCase,
                icon: "calendar.badge.clock",
                title: "Free Case of the Week",
                subtitle: "One real payment case, free every week"
            ),
            DrawerRowModel(
                id: .communityChallenge,
                icon: "trophy.fill",
                title: "Weekly Challenge",
                subtitle: "One case a week, scored on investigation quality"
            ),
            DrawerRowModel(
                id: .myProgress,
                icon: "chart.bar.fill",
                title: "My Progress",
                subtitle: "Your learning analytics, streak and quiz scores"
            ),
            DrawerRowModel(
                id: .simulator,
                icon: "arrow.triangle.2.circlepath",
                title: "Payment Simulator",
                subtitle: "Follow a payment through its lifecycle"
            ),
            DrawerRowModel(
                id: .isoExplorer,
                icon: "doc.text.magnifyingglass",
                title: "ISO 20022 Explorer",
                subtitle: "Look up ISO 20022 messages and fields"
            ),
            DrawerRowModel(
                id: .exceptionLab,
                icon: "exclamationmark.triangle.fill",
                title: "Exception Lab",
                subtitle: "Investigate payment exceptions"
            ),
            DrawerRowModel(
                id: .baStudio,
                icon: "square.and.pencil",
                title: "BA/PO Studio",
                subtitle: "Draft BA and PO deliverables"
            ),
            DrawerRowModel(
                id: .profile,
                icon: "person.fill",
                title: "Profile",
                subtitle: "Your name, privacy and account settings"
            ),
            DrawerRowModel(
                id: .myPurchases,
                icon: "bag.fill",
                title: "My Purchases",
                subtitle: "Your bundles and Payment Situations, payment and access status"
            ),
            DrawerRowModel(
                id: .appearance,
                icon: "circle.lefthalf.filled",
                title: "Appearance",
                subtitle: "Dark mode and display options"
            ),
            DrawerRowModel(
                id: .helpAndSupport,
                icon: "questionmark.circle.fill",
                title: "Help and Support",
                subtitle: "Customer support, your queries and FAQs"
            ),
            DrawerRowModel(
                id: .about,
                icon: "info.circle.fill",
                title: "About",
                subtitle: "About Payments Training Hub, the operator and the curriculum"
            ),
            DrawerRowModel(
                id: .startTour,
                icon: "play.circle.fill",
                title: "Start Tour",
                subtitle: "A quick guided tour of the key areas of the app"
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Deep navy gradient header with the brand mark: the
            // white brand name and the tagline. The panel ignores the safe area so it runs full
            // height, so the header is pushed below the status bar with
            // the real device inset instead of a fixed value.
            VStack(alignment: .leading, spacing: 2) {
                Text("Payments Training Hub")
                    .font(.pfSectionTitle.weight(.bold))
                    .foregroundColor(.white)
                Text("Master the world of payments")
                    .font(.pfCaption.weight(.regular))
                    .foregroundColor(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, PFWindowSafeArea.top + 12)
            .padding(.bottom, 20)
            .background(Color.pfHeroGradient)

            // Option rows. The scroll indicators stay visible: the
            // list is taller than most screens, and the indicator is
            // the cue that more rows sit below the fold.
            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            // Account and settings rows sit under their own
                            // heading, so a settings row does not read as
                            // just another navigation destination.
                            if row.id == .profile {
                                Text("Account and settings")
                                    .font(.pfCaptionBold)
                                    .foregroundColor(.pfSecondaryText)
                                    .padding(.leading, PFSpacing.xl)
                                    .padding(.top, PFSpacing.md)
                                    .padding(.bottom, PFSpacing.xs)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            DrawerRow(model: row, isActive: row.id.tabIndex != nil && row.id.tabIndex == selectedTab) {
                                onSelect(row.id)
                            }
                            .id(row.id)
                            // Reports the row frame for the tour
                            // spotlight, two ways. The anchor is
                            // resolved by the overlay as a
                            // fallback. The frame below is the
                            // primary source: a concrete rect in
                            // the tour coordinate space, pushed
                            // up on every move, so the overlay
                            // tracks the row while the list
                            // scrolls and the drawer slides. The
                            // rows themselves do not change
                            // appearance or behaviour.
                            .anchorPreference(key: DrawerRowAnchorKey.self, value: .bounds) { [row.id: $0] }
                            .background(
                                GeometryReader { rowProxy in
                                    Color.clear.preference(
                                        key: DrawerRowFrameKey.self,
                                        value: [row.id: rowProxy.frame(in: .named(TourCoordinateSpace.name))]
                                    )
                                }
                            )
                            if row.id != rows.last?.id {
                                Divider()
                                    .padding(.leading, 80)
                            }
                        }
                    }
                    .padding(.top, PFSpacing.sm)
                }
                .task(id: tourScrollTarget) {
                    // The tour asked for a row: bring it into
                    // view so the spotlight has a visible
                    // target. Nothing else scrolls: no
                    // showcase scroll through the list, no
                    // glide back to the top. Scroll at once,
                    // then three more passes spread over the
                    // drawer slide and the first scrolls: a
                    // scroll issued while the drawer is still
                    // closed or still sliding can be dropped,
                    // and the later passes land the row for
                    // certain. The task cancels when the
                    // target changes, so a stale re-scroll
                    // never fights the next step.
                    let animated = !reduceMotion
                    guard let target = tourScrollTarget else { return }
                    scrollToRow(target, proxy: scrollProxy, animated: animated)
                    for delay: UInt64 in [450_000_000, 450_000_000, 500_000_000] {
                        try? await Task.sleep(nanoseconds: delay)
                        guard !Task.isCancelled else { return }
                        scrollToRow(target, proxy: scrollProxy, animated: animated)
                    }
                }
            }

            Spacer(minLength: PFSpacing.lg)

            // Highlighted progress card, in the style of the Paytm
            // Security Shield card: icon, bold title, subtitle, pill button.
            KeepLearningCard {
                onSelect(.myLearning)
            }
            // Reports the card frame for the tour spotlight,
            // two ways: the anchor as fallback, and the live
            // frame below as the primary source, a concrete
            // rect in the tour coordinate space. The parent
            // passes both to the tour overlay; the card itself
            // does not change appearance or behaviour.
            .anchorPreference(key: KeepLearningAnchorKey.self, value: .bounds) { $0 }
            .background(
                GeometryReader { cardProxy in
                    Color.clear.preference(
                        key: KeepLearningFrameKey.self,
                        value: cardProxy.frame(in: .named(TourCoordinateSpace.name))
                    )
                }
            )
            .padding(.horizontal, PFSpacing.lg)
            .padding(.bottom, PFSpacing.lg)

            // Brand name at the very bottom, kept above the home
            // indicator by the real device bottom inset.
            VStack(spacing: 2) {
                Text("Payments Training Hub")
                    .font(.pfSectionTitle.weight(.bold))
                    .foregroundColor(.pfNavy)
                Text("Payments, taught the way banks actually process them.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, PFWindowSafeArea.bottom + PFSpacing.lg)
        }
        .background(Color.pfCard)
    }
}

// MARK: - One option row

/// One drawer row: icon on the left, bold title, grey subtitle, chevron.
/// Matches the Paytm row format exactly. The row is tappable across
/// its full width, and the row for the current tab shows the active
/// state: royal icon and title over a light royal background.
private struct DrawerRow: View {
    let model: DrawerRowModel
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: PFSpacing.lg) {
                Image(systemName: model.icon)
                    .font(.pfCardTitle.weight(.regular))
                    .foregroundColor(isActive ? .pfRoyal : .pfNavy)
                    .frame(width: 40, height: 40, alignment: .center)
                    .pfDecorative()

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.title)
                        .font(.pfBody.weight(.semibold))
                        .foregroundColor(isActive ? .pfRoyal : .pfNavy)
                        .multilineTextAlignment(.leading)
                    Text(model.subtitle)
                        .font(.pfCaption.weight(.regular))
                        .foregroundColor(.pfSecondaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(isActive ? .pfRoyal.opacity(0.8) : .pfNavy.opacity(0.55))
                    .pfDecorative()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PFSpacing.xl)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(PFDrawerRowStyle(isActive: isActive))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(accessibilityHintText)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : [.isButton])
    }

    /// One spoken item: title, subtitle, and the current-section
    /// note when this row is the tab the learner is already on.
    private var accessibilityText: String {
        if isActive {
            return "\(model.title). \(model.subtitle). Current section."
        }
        return "\(model.title). \(model.subtitle)"
    }

    /// What tapping the row does. The row for the current tab says
    /// so instead of promising a move that does not happen.
    private var accessibilityHintText: String {
        if isActive {
            return "You are already in this section."
        }
        return "Opens \(model.title)."
    }
}

/// A drawer row press style: a light-blue rounded background while
/// pressed, so the tapped row reads as the active one. The row for
/// the current tab keeps a lighter tint when it is not pressed.
private struct PFDrawerRowStyle: ButtonStyle {
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                DrawerRowPressBackground(isPressed: configuration.isPressed, isActive: isActive)
            )
            .clipShape(RoundedRectangle(cornerRadius: PFSpacing.smallRadius))
            .padding(.horizontal, PFSpacing.sm)
    }
}

/// The row background, as a view so it can read the Reduce Motion
/// setting, which a button style cannot read directly. The tint
/// change is instant when Reduce Motion is on.
private struct DrawerRowPressBackground: View {
    let isPressed: Bool
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        backgroundColor
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isPressed)
    }

    private var backgroundColor: Color {
        if isPressed {
            return Color.pfRoyal.opacity(0.16)
        }
        if isActive {
            return Color.pfRoyal.opacity(0.08)
        }
        return Color.clear
    }
}

// MARK: - Keep learning card

/// The highlighted card at the bottom of the drawer, in the style of the
/// Paytm Security Shield card. Shows the learner's streak and weekly
/// goal progress, with a button to continue learning. A learner who
/// has not completed a lesson yet sees "Start learning" instead of
/// "Keep learning": there is nothing to resume yet.
private struct KeepLearningCard: View {
    @EnvironmentObject private var progressStore: ProgressStore
    let onContinue: () -> Void

    /// True once the learner has completed at least one lesson.
    private var hasCompletedLesson: Bool {
        !progressStore.completedLessonIDs.isEmpty
    }

    var body: some View {
        HStack(spacing: PFSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.pfGoldSoft)
                    .frame(width: 52, height: 52)
                Image(systemName: "flame.fill")
                    .font(.pfSectionTitle.weight(.regular))
                    .foregroundColor(.pfGold)
                    .pfDecorative()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(hasCompletedLesson ? "Keep learning" : "Start learning")
                    .font(.pfBody.weight(.bold))
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(progressLine)
                    .font(.pfCaption.weight(.regular))
                    .foregroundColor(.pfSecondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                PFProgressBar(progress: progressStore.weeklyProgress, height: 6)
                    // The progress line above already states the streak
                    // and the weekly count, so the bar itself stays
                    // silent for VoiceOver instead of announcing the
                    // same progress a second time.
                    .accessibilityHidden(true)
                    .padding(.top, 4)
            }

            Spacer(minLength: PFSpacing.sm)

            Button(action: onContinue) {
                // Short button label on purpose: the drawer is narrow,
                // and the card title already says "Start learning".
                Text(hasCompletedLesson ? "Continue" : "Start")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.pfRoyal)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .background(Color.pfRoyal.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.pfRoyal.opacity(0.35), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(PFSpacing.lg)
        .background(Color.pfBackground)
        .cornerRadius(PFSpacing.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                .stroke(Color.pfBorder, lineWidth: 1)
        )
    }

    private var progressLine: String {
        let streak = progressStore.streakCount
        let done = progressStore.lessonsCompletedThisWeek
        let goal = progressStore.weeklyGoal
        if streak > 0 {
            return "\(streak) day streak. \(done) of \(goal) lessons this week."
        }
        return "\(done) of \(goal) lessons this week. Start your streak today."
    }
}

// MARK: - Appearance settings

/// Appearance options presented from the drawer: dark mode and display.
/// Dark mode is stored on device and applied app-wide.
struct AppearanceSettingsView: View {
    @AppStorage("pf.appearance.darkMode") private var darkModeEnabled = false
    @AppStorage("pf.appearance.largerText") private var largerTextEnabled = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Dark mode", isOn: $darkModeEnabled)
                    Toggle("Larger text", isOn: $largerTextEnabled)
                } header: {
                    Text("Display")
                } footer: {
                    Text("Dark mode changes the system appearance. Cards and lesson pages stay light so text stays readable. Larger text increases the text size across the app. It takes effect when a screen is next opened.")
                }
                .listRowBackground(Color.pfCard)

                Section {
                    HStack {
                        Text("Theme")
                        Spacer()
                        Text("Royal blue and gold")
                            .foregroundColor(.pfSecondaryText)
                    }
                } header: {
                    Text("Colour")
                } footer: {
                    Text("Payments Training Hub uses royal blue as the primary colour, with gold for the main call to action.")
                }
                .listRowBackground(Color.pfCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.pfBackground)
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: largerTextEnabled) { _, _ in
                // Tell any observer the setting changed. The fonts in
                // DesignSystem read this same key on every body
                // evaluation, so screens rebuilt after this point show
                // the new size. A screen already open may need reopening:
                // see the footer note above.
                NotificationCenter.default.post(name: .pfLargerTextChanged, object: nil)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: { dismiss() })
                }
            }
        }
    }
}

// MARK: - Help and support

/// Help and support presented from the drawer: FAQs from the live
/// search index and the support contact. Tapping a question expands
/// it to the full answer; tapping it again collapses it. The email
/// row opens the mail app, and the Copy button puts the address on
/// the clipboard.
struct HelpSupportView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var storeManager: StoreManager
    @Environment(\.dismiss) private var dismiss

    /// Called when the learner taps Replay tour. The parent
    /// dismisses this sheet and presents the tour.
    var onReplayTour: (() -> Void)? = nil

    /// The FAQ currently expanded to its full answer, if any.
    @State private var expandedFAQID: String? = nil
    /// False shows the first 20 FAQs; true shows every FAQ.
    @State private var showAllFAQs = false
    /// True after the support address has been copied.
    @State private var emailCopied = false
    /// True while the Purchases sheet is open from a locked FAQ.
    @State private var showCheckout = false

    private var faqs: [SearchEntry] {
        contentService.allFAQs
    }

    private var displayedFAQs: [SearchEntry] {
        showAllFAQs ? faqs : Array(faqs.prefix(20))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: PFSpacing.md) {
                        Button(action: openSupportEmail) {
                            HStack(spacing: PFSpacing.md) {
                                Image(systemName: "envelope.fill")
                                    .foregroundColor(.pfRoyal)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Email support")
                                        .font(.pfCardTitle)
                                        .foregroundColor(.pfNavy)
                                    Text("support@paymentstraininghub.com")
                                        .font(.pfCallout)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Email support, support@paymentstraininghub.com")
                        .accessibilityHint("Opens your mail app to write to support.")

                        Spacer()

                        Button {
                            UIPasteboard.general.string = "support@paymentstraininghub.com"
                            emailCopied = true
                        } label: {
                            Text(emailCopied ? "Copied" : "Copy")
                                .font(.pfCallout.weight(.semibold))
                                .foregroundColor(.pfRoyal)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(minHeight: 44)
                                .background(Color.pfRoyal.opacity(0.10))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(emailCopied ? "Support email address copied" : "Copy support email address")
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.pfCard)
                } header: {
                    Text("Contact")
                }

                Section {
                    Button(action: { onReplayTour?() }) {
                        HStack(spacing: PFSpacing.md) {
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(.pfRoyal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Replay tour")
                                    .font(.pfCardTitle)
                                    .foregroundColor(.pfNavy)
                                Text("See the guided tour of the app again.")
                                    .font(.pfCallout)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.pfCallout.weight(.semibold))
                                .foregroundColor(.pfSecondaryText)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Replay tour")
                    .accessibilityHint("Shows the guided tour of the app again.")
                    .listRowBackground(Color.pfCard)
                } header: {
                    Text("Guided tour")
                }

                Section {
                    if faqs.isEmpty {
                        Text("FAQs are loading. Check your connection and try again.")
                            .foregroundColor(.pfSecondaryText)
                            .listRowBackground(Color.pfCard)
                    } else {
                        ForEach(displayedFAQs) { faq in
                            let isExpanded = expandedFAQID == faq.id
                            // FAQ answers belong to Interview Ready:
                            // the first 5 in catalogue order are free
                            // samples. A locked FAQ shows its title
                            // only: no preview text leaks the answer.
                            let isLocked = EntryAccessRules.isLocked(
                                faq,
                                indexInType: faqs.firstIndex(of: faq),
                                isPracticeUnlocked: storeManager.isPracticeUnlocked,
                                isInterviewUnlocked: storeManager.isInterviewUnlocked,
                                isChapterUnlocked: true
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Button {
                                    expandedFAQID = isExpanded ? nil : faq.id
                                } label: {
                                    HStack(alignment: .top, spacing: PFSpacing.sm) {
                                        Text(faq.title)
                                            .font(.pfCardTitle)
                                            .foregroundColor(.pfNavy)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer()
                                        if isLocked {
                                            Image(systemName: "lock.fill")
                                                .font(.pfCallout.weight(.semibold))
                                                .foregroundColor(.pfSecondaryText)
                                                .accessibilityLabel("Answer locked")
                                        }
                                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                            .font(.pfCallout.weight(.semibold))
                                            .foregroundColor(.pfSecondaryText)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(faq.title)
                                .accessibilityHint(isLocked
                                    ? "Shows how to unlock this answer."
                                    : (isExpanded ? "Tap to collapse this answer." : "Tap to read the full answer."))
                                if isExpanded {
                                    if isLocked {
                                        VStack(alignment: .leading, spacing: PFSpacing.sm) {
                                            Text("This FAQ answer is part of Interview Ready: \(ContentManifest.faqCount) FAQ answers and \(ContentManifest.interviewQuestionCount) interview questions\(storeManager.isPriceAvailable(for: ProductCatalogue.interviewProductID) ? " for \(storeManager.priceText(for: ProductCatalogue.interviewProductID))" : ""), with 1 year of access. The Integrated Course includes Interview Ready too.")
                                                .font(.pfCallout)
                                                .foregroundColor(.pfSecondaryText)
                                                .fixedSize(horizontal: false, vertical: true)
                                            PFPrimaryButton(title: "View Interview Ready") {
                                                showCheckout = true
                                            }
                                        }
                                    } else {
                                        PFBodyText(text: faq.text, font: .pfCallout, textColor: .pfSecondaryText)
                                    }
                                } else if !isLocked {
                                    Text(faq.preview)
                                        .font(.pfCallout)
                                        .foregroundColor(.pfSecondaryText)
                                        .lineLimit(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.pfCard)
                        }
                        if faqs.count > 20 {
                            Button(showAllFAQs ? "Show fewer questions" : "Show all \(faqs.count) questions") {
                                showAllFAQs.toggle()
                            }
                            .font(.pfBody.weight(.semibold))
                            .foregroundColor(.pfRoyal)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.pfCard)
                        }
                    }
                } header: {
                    Text("Frequently asked questions")
                } footer: {
                    Text("For more answers, search the Search tab. It searches the full FAQ list.")
                }
            }
            // Rows stay on the card colour in both light and dark mode:
            // a default dark-mode row would make the navy row text
            // invisible.
            .scrollContentBackground(.hidden)
            .background(Color.pfBackground)
            .navigationTitle("Help and Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: { dismiss() })
                }
            }
            .sheet(isPresented: $showCheckout) {
                CheckoutView()
            }
        }
    }
}

// MARK: - About

/// About Payments Training Hub, the operator and the curriculum.
struct AboutPaymentForgeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentService: ContentService

    /// The app version from the bundle, for example "Version 1.0 (3)".
    /// Nil when the bundle carries no version, in which case the
    /// version line is not shown.
    private var appVersionText: String? {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty else {
            return nil
        }
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !build.isEmpty {
            return "Version \(version) (\(build))"
        }
        return "Version \(version)"
    }

    /// Curriculum numbers from the loaded search index and the
    /// bundled question bank, with the verified catalogue counts as
    /// fallback while the index loads. Never a stale hardcoded
    /// number, and never simulators: the app has no simulators.
    private var curriculumText: String {
        let counts = contentService.searchIndex?.counts
        let lessons = counts?.lesson ?? ContentManifest.lessonCount
        let guides = counts?.guide ?? ContentManifest.guideCount
        let situations = counts?.situation ?? ContentManifest.situationCount
        let questions = InterviewQuestionStore.totalCount
        return "\(ContentManifest.chapterCount) chapters and \(lessons) narrated lessons across \(ContentManifest.domainCount) domains, with \(guides) long-form guides, \(questions) interview questions and \(situations) Payment Situations. Every lesson is built for working payments professionals, with real examples and field-level detail."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.xl) {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("Payments Training Hub")
                            .font(.pfHeroTitle)
                            .foregroundColor(.pfNavy)
                        Text("Payments, taught the way banks actually process them.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                    }

                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("The curriculum")
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                        PFBodyText(text: curriculumText)
                    }

                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("The operator")
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                        PFBodyText(text: "Payments Training Hub is built and run by a Senior Business Analyst who has run payments transformation at NatWest in the UK since 2021, deployed through Capco in Bangalore.")
                    }

                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("How it works")
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                        PFBodyText(text: "Browse the catalogue freely, with no sign-in. The first lesson of every chapter is free. Courses unlock when you buy them, or buy the Integrated Course to unlock all chapters, lessons and Payment Situations. Payment Situations is also available on its own, paid by In-App Purchase. Progress syncs to your account when you sign in, and stays on your device when you do not.")
                    }

                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("About this app")
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                        if let appVersionText {
                            Text(appVersionText)
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                        }
                        Button(action: openSupportEmail) {
                            Text("Contact support: support@paymentstraininghub.com")
                                .font(.pfBody)
                                .foregroundColor(.pfRoyal)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityLabel("Contact support by email")
                        .accessibilityHint("Opens your mail app to write to support.")
                    }
                }
                .padding(PFSpacing.xl)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: PFSpacing.xl)
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: { dismiss() })
                }
            }
        }
    }
}
