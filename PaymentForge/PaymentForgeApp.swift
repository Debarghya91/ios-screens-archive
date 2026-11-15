// PaymentForgeApp.swift
// Payments Training Hub iOS - App entry point and main tab navigation.
// No em dashes in any user-facing text.

import SwiftUI
import UserNotifications

@main
struct PaymentForgeApp: App {
    @StateObject private var contentService = ContentService.shared
    @StateObject private var progressStore = ProgressStore.shared
    @StateObject private var storeManager = StoreManager.shared
    @StateObject private var authService = AuthService.shared
    @StateObject private var deepLinkRouter = PaymentForgeDeepLinkRouter()
    @AppStorage("pf.appearance.darkMode") private var darkModeEnabled = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The local notification service is the notification
        // centre delegate from launch, so tapped notifications
        // route even on a cold start. No other code sets the
        // delegate. Local only: no APNs, no device tokens.
        UNUserNotificationCenter.current().delegate = LocalNotificationService.shared
    }

    /// Binding for the set-new-password cover: shown while a
    /// password reset link's recovery session is waiting for a new
    /// password. Dismissing it clears the flag; the cover's own
    /// Cancel button also signs out the recovery session.
    private var passwordResetBinding: Binding<Bool> {
        Binding(
            get: { authService.showPasswordReset },
            set: { isPresented in
                if !isPresented { authService.dismissPasswordReset() }
            }
        )
    }

    var body: some Scene {
        WindowGroup {
            // Guest is the default: the app opens straight into the main
            // tabs with no forced sign-in. Auth is an upgrade path
            // (Profile / drawer "Sign in" opens WelcomeView), never a gate.
            MainTabView()
                .environmentObject(contentService)
                .environmentObject(progressStore)
                .environmentObject(storeManager)
                .environmentObject(authService)
                .environmentObject(deepLinkRouter)
                .fullScreenCover(isPresented: passwordResetBinding) {
                    ResetPasswordView()
                }
                .preferredColorScheme(darkModeEnabled ? .dark : .light)
                .onOpenURL { url in
                    // Deep links first: a lesson or weekly-case link
                    // shares the auth scheme
                    // (com.paymentforge.app), and
                    // handleAuthCallback treats every URL on that
                    // scheme as an auth callback, so forwarding a
                    // deep link there would show a spurious
                    // sign-in error. Only URLs that are not deep
                    // links reach the auth handler. See
                    // ReferralInvite.swift for the link formats.
                    if let link = PaymentForgeDeepLink(url: url) {
                        Task { @MainActor in deepLinkRouter.receive(link) }
                        return
                    }
                    // Auth callback (Google PKCE code, magic-link
                    // token, or password reset link).
                    // handleAuthCallback returns false for non-auth URLs.
                    Task { _ = await authService.handleAuthCallback(url: url) }
                }
                .task {
                    // Load the catalogue, the full situations and the
                    // store in parallel: they are independent, and
                    // running them in sequence delayed the store
                    // behind a slow catalogue load.
                    async let index: Void = contentService.loadSearchIndex()
                    async let situations: Void = contentService.loadFullSituations()
                    async let store: Void = storeManager.start()
                    _ = await (index, situations, store)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // On every activation, refresh the system
                    // authorisation state and make the scheduled
                    // local notifications match it and the current
                    // preferences. Both calls are cheap and
                    // idempotent, and the status refresh runs
                    // first so the schedule uses fresh state.
                    // Nothing here prompts: the one-time in-app
                    // explanation lives in MainTabView.
                    guard newPhase == .active else { return }
                    Task { @MainActor in
                        await LocalNotificationService.shared.refreshAuthorizationStatus()
                        LocalNotificationService.shared.refreshScheduledNotifications()
                    }
                }
                .onChange(of: authService.currentUser) { _, _ in
                    // Identity changed (sign-in or sign-out):
                    // reload notification preferences for the
                    // new namespace. On sign-in the namespace
                    // is already switched when currentUser
                    // publishes; on sign-out the service also
                    // re-checks the namespace on every write
                    // and schedule refresh, so no stale
                    // preferences can leak across accounts.
                    LocalNotificationService.shared.reloadForCurrentAccount()
                }
        }
    }
}

/// The main tab bar, exactly five tabs: Home (0), Learn (1),
/// Search (2), Payment Cases (3), My Progress (4). Learn hosts the
/// existing CoursesView, Payment Cases hosts the existing
/// SituationsView, My Progress hosts the existing DashboardView
/// rebuilt as a progress screen. There is no chat or helper
/// feature: search returns links to lessons, and the lesson
/// quizzes explain every answer in the lesson itself.
/// No tab is removed, only renamed:
/// Courses becomes Learn, Situations becomes Payment Cases,
/// Dashboard becomes My Progress. Profile is NOT a tab: it is
/// reached from the Home avatar and from the account drawer, and
/// opens as a sheet, so it can never be confused with My Progress.
/// The navigation review kept these five tabs unchanged: the
/// brief bars a radical navigation change without a demonstrably
/// better structure, and none was found. The tabs match the design
/// reference and the guided tour, each tab names one job the
/// learner already understands, and Practice stays reachable as a
/// sheet from the drawer, Learn and Home rather than as a sixth
/// tab, so the tab bar keeps one job per tab. The four practice
/// experiences (Payment Simulator, ISO 20022 Explorer, Exception
/// Lab, BA/PO Studio) are sheets too, reached from the drawer,
/// Home Explore and Learn, never new tabs.
/// Wrapped in the side drawer container: a menu button in the
/// navigation bar of each root tab screen, or a swipe right from
/// the left edge, opens the drawer, which slides in over the tabs.
/// Drawer rows switch tabs or present sheets. The menu button lives
/// in the root screens' navigation bars only, never on pushed
/// detail views, so it can never overlap a back button or a
/// navigation title.
struct MainTabView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var deepLinkRouter: PaymentForgeDeepLinkRouter

    /// The onboarding store, built by the onboarding worker. Its
    /// hasCompletedOnboarding flag alone drives the onboarding
    /// cover below: the tabs are never blocked by any other state,
    /// and the onboarding flow always offers Skip. The flag is
    /// install level (plain UserDefaults key, no account
    /// namespace), so sign-in, sign-out, and relaunch never show
    /// onboarding again.
    @StateObject private var onboardingStore = OnboardingStore.shared

    @State private var isDrawerOpen = false
    @State private var selectedTab = 0
    @State private var presentedSheet: DrawerDestination? = nil
    /// Guards delayed tour destination opens: bumped on every
    /// tour destination request, so a stale delayed open can
    /// never fire after the tour moved on or finished.
    @State private var tourDestinationGeneration = 0
    @State private var showSplash = true

    /// A lesson opened from a deep link, shown as a sheet so the
    /// link works from any tab without disturbing tab state.
    /// LessonView applies its existing gate inside the sheet, so
    /// a link to a gated lesson shows the locked state: deep
    /// links never bypass gating.
    @State private var deepLinkLessonEntry: SearchEntry? = nil
    /// True when a deep link named a lesson the loaded catalogue
    /// does not contain. Set only after the catalogue has loaded,
    /// so a slow load never shows a false not-found alert.
    @State private var showDeepLinkNotFound = false

    /// The guided tour, shown once on first launch, after the
    /// splash. Replayable from Help and Support. Guest mode stays:
    /// the tour never forces sign-in. tourDone is the tour's own
    /// install-level flag, separate from the onboarding flag: the
    /// tour fires once after the first onboarding completion (see
    /// startTourIfNeeded) and never again, except on replay.
    @AppStorage("pf.tour.done") private var tourDone = false
    @State private var showTour = false
    /// The local notification service. MainTabView attaches the
    /// deep link router to it on appear, so tapped notifications
    /// route through the same router as tapped links, and owns
    /// the one-time permission explanation below.
    @StateObject private var notificationService = LocalNotificationService.shared
    /// The one-time in-app explanation shown before the system
    /// notification prompt. Presented once, after onboarding and
    /// the welcome tour have completed, and never again: both
    /// answers record the install-level asked flag.
    @State private var showNotificationPermissionPrompt = false
    /// The measured tab bar geometry, reported by the frame
    /// reader for the tour spotlight. Empty until the first
    /// report arrives.
    @State private var tabBarGeometry: TabBarGeometry = TabBarGeometry(buttonRects: [], barFrame: .zero)
    /// The anchor of the Keep Learning card at the bottom of
    /// the drawer, for the tour's final step.
    @State private var keepLearningAnchor: Anchor<CGRect>? = nil
    /// The live frames of the drawer rows, in the tour
    /// coordinate space, for the tour spotlight. Refreshed on
    /// every scroll and slide; the overlay prefers these over
    /// the anchors.
    @State private var drawerRowFrames: [DrawerDestination: CGRect] = [:]
    /// The live frame of the Keep Learning card, same space
    /// and contract, for the tour's final step.
    @State private var keepLearningFrame: CGRect? = nil
    /// The anchor of the Search page's search field, for the
    /// tour's typing demo on the Search step.
    @State private var searchFieldAnchor: Anchor<CGRect>? = nil
    /// The drawer row the tour wants scrolled into view, if any.
    /// Passed through the drawer container to the drawer list.
    @State private var tourScrollTarget: DrawerDestination? = nil
    /// Drawer row anchors, read at this ZStack (the common
    /// ancestor of the drawer and the tour overlay) and passed
    /// down to the overlay, which resolves them against its own
    /// full-screen GeometryReader. Preferences only flow up, never
    /// down into a sibling subtree, so the overlay cannot read
    /// them itself.
    @State private var drawerRowAnchors: [DrawerDestination: Anchor<CGRect>] = [:]

    init() {
        // Unselected tab icons and labels in muted slate grey; the
        // selected tab is royal blue via the TabView tint.
        UITabBar.appearance().unselectedItemTintColor = UIColor(
            red: 0.39, green: 0.45, blue: 0.55, alpha: 1
        )
    }

    /// One tab label. The selected tab gets a small rounded
    /// light-blue background behind its icon.
    @ViewBuilder
    private func tabLabel(title: String, systemImage: String, index: Int) -> some View {
        if selectedTab == index {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(.title3, design: .default).weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(Color.pfRoyal.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(title)
                    .font(.pfCaptionBold)
            }
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    var body: some View {
        ZStack {
            // Invisible tab bar frame reader: measures the real
            // tab bar geometry in window coordinates for the
            // tour spotlight. It draws nothing, takes no
            // touches, and fills the same ZStack the overlay
            // measures. The overlay translates the reported
            // geometry into its own space.
            TabBarFrameReader { geometry in
                tabBarGeometry = geometry
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)

            DrawerContainer(
                isOpen: $isDrawerOpen,
                onSelect: handleDrawerSelection,
                selectedTab: selectedTab,
                tourScrollTarget: tourScrollTarget
            ) {
                TabView(selection: $selectedTab) {
                    HomeView(isDrawerOpen: $isDrawerOpen, selectedTab: $selectedTab)
                        .tag(0)
                        .tabItem {
                            tabLabel(title: "Home", systemImage: "house.fill", index: 0)
                        }
                        .accessibilityLabel("Home")

                    CoursesView(isDrawerOpen: $isDrawerOpen)
                        .tag(1)
                        .tabItem {
                            tabLabel(title: "Learn", systemImage: "book.fill", index: 1)
                        }
                        .accessibilityLabel("Learn")

                    SearchView(isDrawerOpen: $isDrawerOpen)
                        .tag(2)
                        .tabItem {
                            tabLabel(title: "Search", systemImage: "magnifyingglass", index: 2)
                        }
                        .accessibilityLabel("Search")

                    SituationsView(isDrawerOpen: $isDrawerOpen)
                        .tag(3)
                        .tabItem {
                            tabLabel(title: "Payment Cases", systemImage: "briefcase.fill", index: 3)
                        }
                        .accessibilityLabel("Payment Cases")

                    DashboardView(isDrawerOpen: $isDrawerOpen, selectedTab: $selectedTab)
                        .tag(4)
                        .tabItem {
                            tabLabel(title: "My Progress", systemImage: "chart.bar.fill", index: 4)
                        }
                        .accessibilityLabel("My Progress")
                }
                .tint(.pfRoyal)
                .toolbarBackground(Color.pfCard, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
            }
            .sheet(item: $presentedSheet) { destination in
                switch destination {
                case .myPurchases:
                    CheckoutView()
                case .practice:
                    PracticeSheetView()
                case .profile:
                    ProfileView()
                case .appearance:
                    AppearanceSettingsView()
                case .helpAndSupport:
                    HelpSupportView(onReplayTour: replayTour)
                case .about:
                    AboutPaymentForgeView()
                case .simulator:
                    PracticeExperienceSheet {
                        PaymentLifecycleSimulatorView()
                    }
                case .isoExplorer:
                    PracticeExperienceSheet {
                        ISO20022ExplorerView()
                    }
                case .exceptionLab:
                    PracticeExperienceSheet {
                        ExceptionInvestigationLabView()
                    }
                case .baStudio:
                    PracticeExperienceSheet {
                        BAProductStudioView()
                    }
                case .weeklyFreeCase:
                    PracticeExperienceSheet {
                        WeeklyFreeCaseView()
                    }
                case .communityChallenge:
                    PracticeExperienceSheet {
                        CommunityChallengeView()
                    }
                case .myLearning, .home, .learn, .search, .paymentCases, .myProgress, .startTour:
                    EmptyView()
                }
            }
            .onAppear {
                // The tour only starts once onboarding has finished:
                // startTourIfNeeded also requires onboarding complete,
                // so a first-run learner sees onboarding first.
                startTourIfNeeded()
            }

            // The guided tour, above the drawer and the tabs. On
            // first launch it appears once the splash has faded;
            // on replay the splash is long gone, so it appears
            // immediately.
            if showTour && !showSplash {
                NavigationTourOverlay(
                    selectedTab: $selectedTab,
                    isDrawerOpen: $isDrawerOpen,
                    drawerScrollTarget: $tourScrollTarget,
                    drawerRowAnchors: drawerRowAnchors,
                    drawerRowFrames: drawerRowFrames,
                    tabBarGeometry: tabBarGeometry,
                    keepLearningAnchor: keepLearningAnchor,
                    keepLearningFrame: keepLearningFrame,
                    searchFieldAnchor: searchFieldAnchor,
                    onOpenDestination: openDestinationFromTour,
                    onOpenKeepLearning: openKeepLearningFromTour,
                    onFinish: finishTour
                )
                .zIndex(2)
            }

            // Splash: brief, then the tabs take over. It is an
            // overlay, never a gate: even if the delay is skipped the
            // tabs are already underneath.
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onPreferenceChange(DrawerRowAnchorKey.self) { anchors in
            drawerRowAnchors = anchors
        }
        .onPreferenceChange(DrawerRowFrameKey.self) { frames in
            drawerRowFrames = frames
        }
        .onPreferenceChange(KeepLearningAnchorKey.self) { anchor in
            keepLearningAnchor = anchor
        }
        .onPreferenceChange(KeepLearningFrameKey.self) { frame in
            keepLearningFrame = frame
        }
        .onPreferenceChange(SearchFieldAnchorKey.self) { anchor in
            searchFieldAnchor = anchor
        }
        .coordinateSpace(name: TourCoordinateSpace.name)
        // Deep-link lesson sheet: a lesson link opens here, in its
        // own NavigationStack with a Done button, over any tab.
        .sheet(item: $deepLinkLessonEntry) { entry in
            NavigationStack {
                LessonView(entry: entry)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { deepLinkLessonEntry = nil }
                                .accessibilityHint("Closes this lesson.")
                        }
                    }
            }
        }
        .alert("Lesson link not found", isPresented: $showDeepLinkNotFound) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That link did not match a lesson in the course catalogue.")
        }
        .alert("Turn on reminders?", isPresented: $showNotificationPermissionPrompt) {
            Button("Allow notifications") {
                Task { @MainActor in
                    _ = await notificationService.requestAuthorization()
                }
            }
            Button("Not now", role: .cancel) {
                notificationService.markPermissionAsked()
            }
        } message: {
            Text("Payments Training Hub can send short reminders about your streak, picking up where you left off, and new lessons, plus occasional offers. You can change this later in Settings.")
        }
        .onAppear {
            // A link tapped before this view appeared (cold start)
            // is already pending in the router: route it now.
            resolvePendingDeepLink()
        }
        .onAppear {
            // Tapped notifications route through the same router
            // as tapped links: attach it, and deliver any link
            // that arrived before this view appeared. Then check
            // the one-time permission explanation: on a returning
            // launch the tour is already done, so this is the
            // moment it appears.
            notificationService.attachDeepLinkRouter(deepLinkRouter)
            maybeShowNotificationPermissionPrompt()
        }
        .onChange(of: deepLinkRouter.pendingLink) { _, _ in
            resolvePendingDeepLink()
        }
        .onChange(of: contentService.searchIndex?.counts.total ?? 0) { _, _ in
            // The catalogue arrived: a lesson link that was
            // waiting for it can resolve now.
            resolvePendingDeepLink()
        }
        // Onboarding, after the splash fades and before the guided
        // tour. The cover is driven solely by
        // hasCompletedOnboarding plus the splash gate: when the
        // flow saves or skips itself, the flag flips and the cover
        // dismisses. The set side is intentionally empty: nothing
        // else may dismiss onboarding, and the flow always offers
        // Skip, so the tabs are never blocked behind it.
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingStore.hasCompletedOnboarding && !showSplash },
            set: { _ in }
        )) {
            OnboardingFlowView(onFinish: {
                startTourIfNeeded()
            })
        }
        // The tour starts when onboarding completes, even if the
        // completion lands through the store rather than onFinish:
        // both paths call the same guarded starter, which also
        // requires the tour to be unfinished.
        .onChange(of: onboardingStore.hasCompletedOnboarding) { _, _ in
            startTourIfNeeded()
            // A deep link that arrived during onboarding routes
            // now that the cover is gone.
            resolvePendingDeepLink()
            // Onboarding completing with the tour already done
            // (a returning install) arms the permission check.
            maybeShowNotificationPermissionPrompt()
        }
        .onChange(of: tourDone) { _, _ in
            // The tour finishing arms the permission check; the
            // delayed check in finishTour retries it once the
            // tour overlay has gone.
            maybeShowNotificationPermissionPrompt()
        }
        .task {
            // Keep the splash fast: about 1.2 seconds, then fade out.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeOut(duration: 0.3)) {
                showSplash = false
            }
            // Fallback for the permission explanation: if the tour
            // never started, the tour-done flag can never arm the
            // check, so check again shortly after the splash, with
            // the fallback allowed. On a normal first launch the
            // tour is showing by now, so this check does nothing.
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            maybeShowNotificationPermissionPrompt(allowTourFallback: true)
        }
        .task {
            // Refresh the reading-order map from the website in
            // the background. This task never blocks the splash:
            // the bundled map is already loaded, and a refreshed
            // copy takes effect on the next launch. Every failure
            // is silent, the bundled map always applies.
            await contentService.refreshReadingOrderIfNeeded()
        }
    }

    /// Route a drawer row tap to a tab switch or a sheet.
    /// Profile is a separate destination from My Progress: it opens
    /// ProfileView as a sheet, it never switches to the My Progress
    /// tab, and My Progress never opens Profile.
    private func handleDrawerSelection(_ destination: DrawerDestination) {
        switch destination {
        case .home:
            selectedTab = 0
        case .myLearning, .learn:
            selectedTab = 1
        case .search:
            selectedTab = 2
        case .paymentCases:
            selectedTab = 3
        case .myProgress:
            selectedTab = 4
        case .practice:
            // Practice Mode as a sheet, for the first
            // practice-eligible situation. See PracticeSheetView.
            presentedSheet = .practice
        case .myPurchases, .profile, .appearance, .helpAndSupport, .about, .simulator, .isoExplorer, .exceptionLab, .baStudio, .weeklyFreeCase, .communityChallenge:
            presentedSheet = destination
        case .startTour:
            // The drawer has already closed by the time this
            // runs (DrawerContainer waits for the close
            // animation), so the tour start card shows at once.
            showTour = true
        }
    }

    /// Route a pending deep link (see ReferralInvite.swift for the
    /// formats). Lesson links resolve against the loaded catalogue:
    /// while the catalogue is still loading the link stays pending
    /// and this runs again when the catalogue arrives, and a lesson
    /// id the loaded catalogue does not contain clears the link and
    /// shows the not-found alert. Only entries of type lesson open:
    /// a lesson link carrying some other catalogue id never opens
    /// that content. Weekly-case links open the weekly sheet at
    /// once: the view loads its own data. A link is never routed
    /// before onboarding finishes, because the onboarding cover
    /// sits above the sheets; routing retries when the flag flips.
    /// Gating is unchanged throughout: LessonView applies its own
    /// gate, so only free sample lessons open with full content.
    private func resolvePendingDeepLink() {
        guard onboardingStore.hasCompletedOnboarding,
              let link = deepLinkRouter.pendingLink else { return }
        switch link {
        case .weeklyFreeCase:
            deepLinkRouter.clear()
            presentedSheet = .weeklyFreeCase
        case .lesson(let lessonID):
            guard let index = contentService.searchIndex else { return }
            deepLinkRouter.clear()
            if let entry = index.entries.first(where: { $0.id == lessonID && $0.type == .lesson }) {
                deepLinkLessonEntry = entry
            } else {
                showDeepLinkNotFound = true
            }
        }
    }

    /// Open a drawer destination from a tour step, or close any
    /// destination the tour opened when passed nil. Opening
    /// closes the drawer first and routes through
    /// handleDrawerSelection once the close animation finishes,
    /// exactly as a real drawer tap does. The generation guards
    /// the delayed routing: a fast Next or Back bumps it, so a
    /// stale delayed open can never fire after the tour moved
    /// on or finished.
    private func openDestinationFromTour(_ destination: DrawerDestination?) {
        tourDestinationGeneration += 1
        let generation = tourDestinationGeneration
        guard let destination else {
            presentedSheet = nil
            return
        }
        isDrawerOpen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard generation == tourDestinationGeneration, showTour else { return }
            handleDrawerSelection(destination)
        }
    }

    /// Open the Keep Learning card's target from the tour's final
    /// step: close the drawer and land on the Learn tab, the same
    /// routing as tapping the card itself.
    private func openKeepLearningFromTour() {
        isDrawerOpen = false
        selectedTab = 1
    }

    /// Show the guided tour only when onboarding has finished and
    /// the tour itself is unfinished. Called on appear (returning
    /// learners, onboarding already complete), from the onboarding
    /// flow's onFinish, and when the onboarding flag flips. The
    /// tour overlay still waits for the splash to fade.
    private func startTourIfNeeded() {
        guard !tourDone, onboardingStore.hasCompletedOnboarding else { return }
        showTour = true
    }

    /// The tour finished, completed or skipped: mark it done and
    /// land on Home with the drawer closed and no destination
    /// sheet open: a sheet opened by a tour step must not
    /// survive the tour.
    private func finishTour() {
        tourDone = true
        showTour = false
        tourScrollTarget = nil
        isDrawerOpen = false
        presentedSheet = nil
        selectedTab = 0
        // The permission explanation follows the tour, once the
        // overlay has gone. The delayed check re-reads every
        // guard, so it stays silent if anything changed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            maybeShowNotificationPermissionPrompt()
        }
    }

    /// Show the one-time notification permission explanation,
    /// once, after onboarding and the welcome tour have
    /// completed. Every guard must pass: onboarding complete
    /// (install-level flag pf.onboarding.completed.v1, read
    /// through OnboardingStore.hasCompletedOnboarding), the
    /// splash and the tour overlay gone, the tour done
    /// (install-level flag pf.tour.done) unless the caller
    /// allows the fallback, the learner not yet asked
    /// (install-level flag pf.notifications.permissionAsked.v1),
    /// and the system decision still not determined. Both
    /// answers in the alert record the asked flag, so the
    /// explanation can never nag. The fallback covers a tour
    /// that never runs: the post-splash check passes it, and
    /// the tour-showing guard keeps it silent while the tour
    /// is actually running.
    private func maybeShowNotificationPermissionPrompt(allowTourFallback: Bool = false) {
        guard onboardingStore.hasCompletedOnboarding,
              !showSplash,
              !showTour,
              !showNotificationPermissionPrompt,
              tourDone || allowTourFallback,
              !notificationService.hasAskedPermission,
              notificationService.authorizationStatus == .notDetermined
        else { return }
        showNotificationPermissionPrompt = true
    }

    /// Replay the tour from Help and Support: dismiss the sheet,
    /// then show the tour start card.
    private func replayTour() {
        presentedSheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            showTour = true
        }
    }
}

// MARK: - Practice sheet (drawer entry point)

/// Practice Mode presented as a sheet from the drawer. PracticeModeView
/// needs one situation plus the full list for its distractors, so
/// this sheet picks the first practice-eligible situation exactly
/// the way the Home highlight does: full situations data first,
/// search index fallback, first eligible situation, or the first
/// situation when none is eligible yet (PracticeModeView then shows
/// its honest not-eligible state). The sheet adds the NavigationStack
/// and Done button PracticeModeView does not carry itself, so the
/// sheet can always be dismissed. While the catalogue is still
/// loading, the sheet says so instead of showing an empty practice
/// screen; when the data arrives, the view recomputes and the
/// practice screen appears.
/// A sheet wrapper for the four practice experiences. They
/// carry no NavigationStack of their own (the host stack provides
/// navigation when pushed from Home or Learn), so the drawer sheet
/// supplies one plus a Done button, the PracticeSheetView pattern.
/// The wrapped view sets its own navigation title.
private struct PracticeExperienceSheet<Content: View>: View {
    let content: Content

    @Environment(\.dismiss) private var dismiss

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityHint("Closes this experience.")
                    }
                }
        }
    }
}

private struct PracticeSheetView: View {
    @EnvironmentObject private var contentService: ContentService
    @Environment(\.dismiss) private var dismiss

    /// All situations, full data first and search index fallback,
    /// so Practice Mode can draw its distractors from real takeaways.
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

    var body: some View {
        NavigationStack {
            Group {
                if let situation = firstPracticeSituation {
                    PracticeModeView(situation: situation, allSituations: practiceSituations)
                } else if contentService.isLoadingIndex && contentService.searchIndex == nil {
                    VStack(spacing: PFSpacing.md) {
                        ProgressView()
                        Text("Loading the Payment Cases...")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: PFSpacing.md) {
                        Text("No Payment Cases are available yet")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .multilineTextAlignment(.center)
                        Text("Check your connection and try again. Your progress is saved on this device.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(PFSpacing.xl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Practice Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityHint("Closes Practice Mode.")
                }
            }
        }
    }
}
