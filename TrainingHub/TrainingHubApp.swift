// TrainingHubApp.swift
// Payments Training Hub iOS - App entry point and main tab navigation.
// No em dashes in any user-facing text.

import SwiftUI
import UIKit
import UserNotifications
import os

@main
struct TrainingHubApp: App {
    @StateObject private var contentService = ContentService.shared
    @StateObject private var progressStore = ProgressStore.shared
    @StateObject private var storeManager = StoreManager.shared
    @StateObject private var authService = AuthService.shared
    @StateObject private var deepLinkRouter = TrainingHubDeepLinkRouter()
    @AppStorage("pf.appearance.darkMode") private var darkModeEnabled = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Crash capture installs first, before anything else can
        // run: it arms the uncaught-exception handler and the
        // run marker, so a crash anywhere in the launch path is
        // still recorded for Diagnostics.
        CrashCapture.install()
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
            // The app opens to browsable content with no session:
            // no sign-in gate stands in front of the tabs. Content
            // stays locked unless purchased (free samples stay
            // free), and the sign-in prompt appears only when the
            // learner taps a Buy action while signed out.
            // AuthService restores a stored session synchronously
            // from the Keychain before the first frame, so a
            // signed-in learner's entitlements are in place from
            // the start. The onboarding introduction stays as the
            // first-launch experience, presented by MainTabView.
            MainTabView()
                .task {
                    // Load the catalogue, the agendas, the full situations
                    // and the store in parallel: they are independent, and
                    // running them in sequence delayed the store
                    // behind a slow catalogue load. Every load is
                    // guarded against re-entry, so signing out and
                    // back in never duplicates work.
                    async let index: Void = contentService.loadSearchIndex()
                    async let agendas: Void = contentService.loadAgendas()
                    async let situations: Void = contentService.loadFullSituations()
                    async let store: Void = storeManager.start()
                    _ = await (index, agendas, situations, store)
                }
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
                    // (com.paymentstraininghub.app), and
                    // handleAuthCallback treats every URL on that
                    // scheme as an auth callback, so forwarding a
                    // deep link there would show a spurious
                    // sign-in error. Only URLs that are not deep
                    // links reach the auth handler. See
                    // ReferralInvite.swift for the link formats.
                    // A deep link received before MainTabView can
                    // route it (cold start, splash, onboarding)
                    // stays pending in the router: MainTabView
                    // routes it once it appears. No sign-in stands
                    // in front of routing: content is browsable
                    // without a session, and purchase-gated
                    // content keeps its lock state.
                    if let link = TrainingHubDeepLink(url: url) {
                        Task { @MainActor in deepLinkRouter.receive(link) }
                        return
                    }
                    // Auth callback (Google PKCE code, magic-link
                    // token, or password reset link).
                    // handleAuthCallback returns false for non-auth URLs.
                    Task { _ = await authService.handleAuthCallback(url: url) }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        // On every activation, refresh the system
                        // authorisation state and make the scheduled
                        // local notifications match it and the current
                        // preferences. Both calls are cheap and
                        // idempotent, and the status refresh runs
                        // first so the schedule uses fresh state.
                        // Nothing here prompts: the one-time in-app
                        // explanation lives in MainTabView.
                        // The same activation refreshes purchase
                        // entitlements from the device and the
                        // server, so a purchase, renewal or refund
                        // made outside the app takes effect without
                        // a relaunch, and marks the run as a clean
                        // foreground entry for crash capture.
                        Task { @MainActor in
                            await LocalNotificationService.shared.refreshAuthorizationStatus()
                            LocalNotificationService.shared.refreshScheduledNotifications()
                            await storeManager.refreshEntitlement()
                            await storeManager.refreshEntitlementFromServer()
                            CrashCapture.markEnteredForeground()
                        }
                    case .background:
                        // A backgrounded run that never returns is a
                        // clean exit, not a crash: record it so the
                        // next launch does not report a false crash.
                        CrashCapture.markCleanExit()
                    default:
                        break
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

// MARK: - Lesson sheet router

/// Opens lessons the way a deep link does: one sheet, owned by
/// MainTabView, carrying its own NavigationStack and a Done
/// button, over whatever tab is showing. Every lesson tap in the
/// app routes through here instead of pushing through a
/// NavigationLink, after the v106 fault in which a lesson tap
/// recorded its breadcrumb but the lesson screen never started:
/// the push transition between the tap and LessonView never
/// completed. A sheet presentation has no push transition to
/// stick, and the deep-link sheet already proves the mechanism.
///
/// The router is a shared singleton, like the navigation
/// debouncer: any view opens a lesson with one call and no
/// environment plumbing. The debounce and the breadcrumb live
/// here, so every lesson tap gets the same guard and the same
/// trace: a second tap on the same lesson within half a second
/// is ignored, and a tap that passes the debounce records
/// "lesson tap <id>".
///
/// The introduction cards cannot open a sheet directly: the
/// introduction is a fullScreenCover, and a sheet presented
/// while the cover is up is unreliable, so the cards request
/// their content here and MainTabView opens it once the cover
/// is gone, the same deferral the deep-link router uses.
@MainActor
final class LessonSheetRouter: ObservableObject {
    static let shared = LessonSheetRouter()

    /// The lesson the sheet is showing, or nil when no lesson
    /// sheet is up. MainTabView presents the sheet from this.
    @Published var presentedEntry: SearchEntry? = nil
    /// The free Payment Case the sheet is showing, or nil when
    /// no case sheet is up. Only the introduction requests one.
    @Published var presentedCase: Situation? = nil

    /// The destination requested from the introduction, waiting
    /// for the cover to dismiss before it opens. Nil otherwise.
    /// Published, so MainTabView's presentation arbitration
    /// re-evaluates the moment a request lands or opens: while
    /// a destination is pending, no alert may take the
    /// hierarchy, and the pending open holds this value until
    /// the sheet actually presents, so the gate stays closed
    /// through the settle window.
    @Published private(set) var pendingDestination: PendingDestination? = nil

    /// True while a pending destination's deferred open is
    /// scheduled but has not fired yet. Stops a second
    /// openPendingAfterIntroduction call (every sheet
    /// re-triggers the arbitration on dismiss) from scheduling
    /// a second presentation of the same destination.
    private var isOpeningPending = false

    /// Open a lesson at once: the debounce guards the tap, the
    /// breadcrumb records it, and the sheet presents.
    func open(_ entry: SearchEntry) {
        guard PFNavigationDebouncer.shared.allow(key: entry.id) else { return }
        CrashBreadcrumbs.record("lesson tap \(entry.id)")
        presentedEntry = entry
        CrashBreadcrumbs.record("lesson sheet requested \(entry.id)") // GATE-DIAG TEMPORARY
    }

    /// Close the lesson sheet.
    func close() {
        presentedEntry = nil
    }

    /// Close the case sheet.
    func closeCase() {
        presentedCase = nil
    }

    /// Request a lesson from the introduction: the tap is
    /// debounced and recorded now, and the lesson opens once
    /// MainTabView reports the introduction gone.
    func requestAfterIntroduction(_ entry: SearchEntry) {
        guard PFNavigationDebouncer.shared.allow(key: entry.id) else { return }
        CrashBreadcrumbs.record("lesson tap \(entry.id)")
        pendingDestination = .lesson(entry)
    }

    /// Request a free case from the introduction, same deferral.
    func requestCaseAfterIntroduction(_ situation: Situation) {
        guard PFNavigationDebouncer.shared.allow(key: "case-\(situation.id)") else { return }
        CrashBreadcrumbs.record("case tap \(situation.id)")
        pendingDestination = .freeCase(situation)
    }

    /// Open whatever the introduction requested, now that its
    /// cover is gone. Called from MainTabView when onboarding
    /// completes, and re-run from every sheet dismissal, so a
    /// request deferred behind another sheet opens when that
    /// sheet closes. The presentation is deferred past a short
    /// settle delay: the cover's onDismiss fires while the
    /// hierarchy is still tearing the cover down, and a sheet
    /// presented synchronously from it is dropped (gate run
    /// 44124436974: the lesson sheet never appeared after the
    /// first-lesson card tap). The pending destination is held
    /// until the deferred presentation fires, so the
    /// arbitration gate stays closed through the window and no
    /// alert can take the hierarchy first. A second call while
    /// the open is scheduled is a no-op, so the destination
    /// can never present twice.
    func openPendingAfterIntroduction() {
        CrashBreadcrumbs.record("openPending called") // GATE-DIAG TEMPORARY
        guard let destination = pendingDestination, !isOpeningPending else { return }
        isOpeningPending = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            CrashBreadcrumbs.record("openPending firing") // GATE-DIAG TEMPORARY
            isOpeningPending = false
            pendingDestination = nil
            switch destination {
            case .lesson(let entry):
                presentedEntry = entry
            case .freeCase(let situation):
                presentedCase = situation
            }
        }
    }
}

/// One destination requested from the introduction, waiting for
/// its cover to dismiss before it opens. A single enum value
/// makes the two request kinds mutually exclusive by
/// construction: a lesson and a case can never both be pending,
/// so the cover's dismissal opens exactly one sheet.
enum PendingDestination {
    case lesson(SearchEntry)
    case freeCase(Situation)
}

/// The main tab bar, four tabs: Home (0), Search (1), Payment
/// Cases (2), My Progress (3). Home is the one place for browsing
/// and starting lessons: the courses, learning journeys and
/// catalogue live on Home, and there is no separate Learn tab.
/// Routes that used to open Learn (drawer entries, the Keep
/// Learning card, the tour's final step, My Progress actions)
/// switch to Home and land on the browsing section through
/// homeSectionTarget. Payment Cases hosts the existing
/// SituationsView, My Progress hosts the existing DashboardView
/// rebuilt as a progress screen. There is no chat or helper
/// feature: search returns links to lessons, and the lesson
/// quizzes explain every answer in the lesson itself.
/// Profile is NOT a tab: it is reached from the Home avatar and
/// from the account drawer, and opens as a sheet, so it can never
/// be confused with My Progress. Practice stays reachable as a
/// sheet from the drawer and Home, rather than as a fifth tab, so
/// the tab bar keeps one job per tab. The four practice
/// experiences (Payment Simulator, ISO 20022 Explorer, Exception
/// Lab, BA/PO Studio) are sheets too, reached from the drawer and
/// Home, never new tabs.
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
    @EnvironmentObject private var storeManager: StoreManager
    @EnvironmentObject private var deepLinkRouter: TrainingHubDeepLinkRouter

    /// Navigation log: every tab switch is recorded with its
    /// source (tab bar, drawer, tour, Home, Dashboard), so a
    /// wrong-landing report can be traced to the route that
    /// caused it.
    private let navLog = Logger(subsystem: "TrainingHub", category: "NAV")

    /// The onboarding store, built by the onboarding worker. Its
    /// hasCompletedOnboarding flag alone drives the onboarding
    /// cover below: the tabs are never blocked by any other state,
    /// and the onboarding flow always offers Skip. The flag is
    /// install level (plain UserDefaults key, no account
    /// namespace), so sign-in, sign-out, and relaunch never show
    /// onboarding again.
    @StateObject private var onboardingStore = OnboardingStore.shared

    /// The lesson sheet router: every lesson tap in the app
    /// opens its sheet through here. MainTabView owns the sheet
    /// presentation below; the router owns the state.
    @StateObject private var lessonSheetRouter = LessonSheetRouter.shared

    @State private var isDrawerOpen = false
    /// Opens the Privacy Policy and Terms of Service in the
    /// browser: the drawer rows link out to the live legal
    /// pages, they never present a sheet.
    // NOTE: do not read @Environment(\.openURL) here. Its value
    // identity changes on every evaluation, which re-invalidates
    // this view and loops the whole tab hierarchy (gate runs
    // 44165658277-44198996345; _printChanges named _openURL at
    // every sample). External links open via UIApplication.

    @State private var selectedTab = 0
    /// Bumped when the learner taps the tab they are already
    /// on. Each root view watches it and scrolls to its top.
    @State private var tabReselectTick = 0
    /// The sequence of the last deep link actually routed.
    /// A second routing attempt for the same sequence is
    /// rejected, so a link can never open twice.
    @State private var lastRoutedDeepLinkSequence = 0

    /// The tab bar's selection binding: a tap on the current
    /// tab bumps the reselect tick (the root scrolls to its
    /// top), and every switch goes through the centralised
    /// navigation, logged with its source. Programmatic
    /// switches write selectedTab through navigateToTab
    /// directly and never pass through this binding, so they
    /// never bump the tick.
    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab {
                    tabReselectTick += 1
                }
                navigateToTab(newValue, source: "tabBar")
            }
        )
    }

    /// Record a tab switch with its source. The tour calls this
    /// through its onTabWrite closure: the overlay already wrote
    /// the binding, so the tour path logs without writing again.
    private func logTabNavigation(_ index: Int, source: String) {
        navLog.info("Tab navigation to \(index, privacy: .public) source \(source, privacy: .public)")
    }

    /// The one programmatic tab switch: logs the source, then
    /// writes the selection. Every route in this view (drawer,
    /// tour finish, Home and Dashboard actions) goes through
    /// here, never through a direct selectedTab write, so tab
    /// identity stays in DrawerDestination.tabIndex and every
    /// switch is traceable.
    private func navigateToTab(_ index: Int, source: String) {
        logTabNavigation(index, source: source)
        selectedTab = index
    }
    /// The Home section an outside route wants to land on, set
    /// together with the tab switch by handleDrawerSelection,
    /// the tour's Keep Learning step and the Dashboard's Start
    /// learning action (through its closure). Home scrolls to
    /// it and clears it.
    @State private var homeSectionTarget: HomeSectionTarget? = nil
    @State private var presentedSheet: DrawerDestination? = nil
    @State private var showSplash = true
    /// The introduction cover flag, owned by this view: armed
    /// once the splash fades (if onboarding is incomplete) and
    /// cleared when the completion flag flips. A writable flag,
    /// not a computed binding: the old read-only binding (empty
    /// setter) left the cover stuck on screen after dismissal
    /// in gate runs 44171037785 and 44188117143.
    @State private var showOnboarding = false

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

    /// The local notification service. MainTabView attaches the
    /// deep link router to it on appear, so tapped notifications
    /// route through the same router as tapped links, and owns
    /// the one-time permission explanation below.
    @StateObject private var notificationService = LocalNotificationService.shared
    /// The one-time in-app explanation shown before the system
    /// notification prompt. Presented once, after onboarding has
    /// completed, and never again: both answers record the
    /// install-level asked flag.
    @State private var showNotificationPermissionPrompt = false
    /// True while a delayed notification-prompt check is
    /// scheduled but has not fired yet. Stops the dismissal
    /// and flag-change paths from queueing the same check
    /// twice behind one cover dismissal.
    @State private var isNotificationPromptCheckPending = false
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
    /// The anchor of the Search page's difficulty pill strip,
    /// for the tour's filter demo on the Search step.
    @State private var searchPillsAnchor: Anchor<CGRect>? = nil
    /// The anchor of the Home page's Continue learning block,
    /// for the tour's block demo on the Home step.
    @State private var continueLearningAnchor: Anchor<CGRect>? = nil
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

    /// The one sheet MainTabView can present: a deep-link
    /// lesson, a tapped lesson, or the introduction's free
    /// case. Three separate .sheet modifiers on this view
    /// shadowed each other (only one presentation modifier of
    /// a kind is honored per view), which is how every gate run
    /// lost the lesson sheet: the router recorded the request,
    /// the binding flipped, the sheet never presented, and no
    /// warning was logged. One sheet, one binding, one
    /// presentation. Priority is deep link first, then the
    /// tapped lesson, then the free case; in practice only one
    /// source is ever set, because the arbitration gate holds
    /// the others until the sheet closes.
    private enum MainTabSheet: Identifiable {
        case deepLink(SearchEntry)
        case lesson(SearchEntry)
        case freeCase(Situation)

        var id: String {
            switch self {
            case .deepLink(let entry): return "deepLink-\(entry.id)"
            case .lesson(let entry): return "lesson-\(entry.id)"
            case .freeCase(let situation): return "case-\(situation.id)"
            }
        }
    }

    /// The single sheet binding: whichever source holds a
    /// destination presents, and dismissing clears every
    /// source, so a queued destination can never strand the
    /// sheet open or present twice.
    private var mainTabSheetBinding: Binding<MainTabSheet?> {
        Binding(
            get: {
                if let entry = deepLinkLessonEntry { return .deepLink(entry) }
                if let entry = lessonSheetRouter.presentedEntry { return .lesson(entry) }
                if let situation = lessonSheetRouter.presentedCase { return .freeCase(situation) }
                return nil
            },
            set: { sheet in
                if sheet == nil {
                    CrashBreadcrumbs.record("sheet binding set to nil") // GATE-DIAG TEMPORARY
                    deepLinkLessonEntry = nil
                    lessonSheetRouter.presentedEntry = nil
                    lessonSheetRouter.presentedCase = nil
                }
            }
        )
    }

    /// GATE-DIAG TEMPORARY: record that SwiftUI requested the
    /// sheet content, then hand the item through. Distinguishes
    /// "content closure never requested" from "closure ran but
    /// the view never appeared". DELETE with the rest of
    /// GateDiag.
    private func logSheetRequest(_ sheet: MainTabSheet) -> MainTabSheet {
        CrashBreadcrumbs.record("sheet content requested \(sheet.id)")
        return sheet
    }

    /// The single sheet's content: a deep-link lesson, a tapped
    /// lesson, or the introduction's free case, each in its own
    /// NavigationStack with a Done button.
    @ViewBuilder
    private func mainTabSheetContent(for sheet: MainTabSheet) -> some View {
        switch sheet {
        case .deepLink(let entry):
            NavigationStack {
                LessonView(entry: entry)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { deepLinkLessonEntry = nil }
                                .accessibilityHint("Closes this lesson.")
                        }
                    }
            }
        case .lesson(let entry):
            NavigationStack {
                LessonView(entry: entry)
                    .onAppear { CrashBreadcrumbs.record("lesson sheet appeared") } // GATE-DIAG TEMPORARY
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { lessonSheetRouter.close() }
                                .accessibilityHint("Closes this lesson.")
                        }
                    }
            }
        case .freeCase(let situation):
            NavigationStack {
                SituationDetailLoaderView(situation: situation)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { lessonSheetRouter.closeCase() }
                                .accessibilityHint("Closes this Payment Case.")
                        }
                    }
            }
        }
    }

    /// True while any sheet owns the presentation hierarchy, or
    /// a sheet is queued behind the introduction cover. Every
    /// alert checks this before presenting, and deep-link
    /// routing waits while it holds: a second presentation
    /// started while one is active is dropped by SwiftUI, which
    /// is how gate runs lost the lesson sheet after the
    /// first-lesson card tap. A gated alert or link is not lost:
    /// its flag stays set and every sheet re-runs the
    /// arbitration on dismiss (see presentationDidDismiss), so
    /// it shows as soon as the hierarchy is free.
    private var hasActiveSheetPresentation: Bool {
        presentedSheet != nil
            || deepLinkLessonEntry != nil
            || lessonSheetRouter.presentedEntry != nil
            || lessonSheetRouter.presentedCase != nil
            || lessonSheetRouter.pendingDestination != nil
    }

    /// Re-run the presentation arbitration after a sheet or the
    /// introduction cover closes: a deep link deferred while a
    /// presentation was up routes now, an introduction request
    /// deferred behind another sheet opens now, and the one-time
    /// notification explanation shows if its guards pass. Each
    /// step is a no-op when nothing is waiting. The pending
    /// destination opens only when the deep-link routing above
    /// did not take the hierarchy; otherwise it waits for that
    /// sheet's dismissal, which re-runs this function.
    private func presentationDidDismiss() {
        CrashBreadcrumbs.record("arbitration ran") // GATE-DIAG TEMPORARY
        resolvePendingDeepLink()
        if deepLinkLessonEntry == nil, presentedSheet == nil {
            lessonSheetRouter.openPendingAfterIntroduction()
        }
        scheduleNotificationPromptCheck()
    }

    /// GATE-DIAG TEMPORARY: record the real UIKit presentation
    /// hierarchy at this moment: the root view controller, the
    /// chain of presented controllers, and whether each is
    /// mid-dismissal, mid-presentation, or stuck in a
    /// transition. SwiftUI state and the UIKit hierarchy
    /// diverged in gate runs 44171037785 and 44188117143 (the
    /// cover stayed visible after onDismiss), and only this
    /// probe shows which side is telling the truth. DELETE with
    /// the rest of GateDiag.
    private func probePresentationHierarchy(tag: String) {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        guard !windows.isEmpty else {
            CrashBreadcrumbs.record("PROBE \(tag): no window")
            return
        }
        // One short line per window: breadcrumb entries are
        // capped, and a combined line truncates the tail.
        for (index, window) in windows.enumerated() {
            let short: (UIViewController) -> String = { vc in
                String(String(describing: type(of: vc)).split(separator: "<").first ?? "?")
            }
            var parts = "root=\(window.rootViewController.map(short) ?? "nil")"
            var current = window.rootViewController?.presentedViewController
            var depth = 0
            while let presented = current, depth < 3 {
                parts += " | p=\(short(presented)) dis=\(presented.isBeingDismissed ? 1 : 0) pres=\(presented.isBeingPresented ? 1 : 0) coord=\(presented.transitionCoordinator != nil ? 1 : 0)"
                current = presented.presentedViewController
                depth += 1
            }
            CrashBreadcrumbs.record("PROBE \(tag) w\(index) key=\(window.isKeyWindow ? 1 : 0) L=\(window.windowLevel.rawValue) \(parts)")
        }
    }

    /// GATE-DIAG TEMPORARY (Test C): the cover's dismissal runs
    /// the UIKit probe sequence AND the restored arbitration.
    /// Test B (run 44193811851) proved the cover dismisses with
    /// a clean UIKit hierarchy, about 15 seconds late visually.
    /// Test C asks whether the pending presentation survives
    /// that delayed dismissal: the probe runs alongside the
    /// arbitration, so a collision and a delay stay
    /// distinguishable.
    private func coverDidDismiss() {
        CrashBreadcrumbs.record("cover onDismiss fired")
        probePresentationHierarchy(tag: "cover-onDismiss")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            probePresentationHierarchy(tag: "cover+100ms")
            try? await Task.sleep(nanoseconds: 900_000_000)
            probePresentationHierarchy(tag: "cover+1s")
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            probePresentationHierarchy(tag: "cover+5s")
        }
        presentationDidDismiss()
    }

    var body: some View {
        GateDiag.count("MainTabView") // GATE-DIAG TEMPORARY
        if GateDiag.printChangesSample("MainTabView") { let _ = Self._printChanges() } // GATE-DIAG TEMPORARY
        return ZStack {
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
                selectedTab: selectedTab
            ) {
                TabView(selection: tabSelection) {
                    HomeView(
                        isDrawerOpen: $isDrawerOpen,
                        onSelectTab: { index in navigateToTab(index, source: "home") },
                        tabReselectTick: tabReselectTick,
                        homeSectionTarget: $homeSectionTarget
                    )
                        .tag(0)
                        .tabItem {
                            tabLabel(title: "Home", systemImage: "house.fill", index: 0)
                        }
                        .accessibilityLabel("Home")

                    SearchView(isDrawerOpen: $isDrawerOpen, tabReselectTick: tabReselectTick)
                        .tag(1)
                        .tabItem {
                            tabLabel(title: "Search", systemImage: "magnifyingglass", index: 1)
                        }
                        .accessibilityLabel("Search")

                    SituationsView(isDrawerOpen: $isDrawerOpen, tabReselectTick: tabReselectTick)
                        .tag(2)
                        .tabItem {
                            tabLabel(title: "Payment Cases", systemImage: "briefcase.fill", index: 2)
                        }
                        .accessibilityLabel("Payment Cases")

                    DashboardView(
                        isDrawerOpen: $isDrawerOpen,
                        onStartLearning: {
                            navigateToTab(DrawerDestination.home.tabIndex ?? 0, source: "dashboard")
                            homeSectionTarget = .learn(.courses)
                        },
                        tabReselectTick: tabReselectTick
                    )
                        .tag(3)
                        .tabItem {
                            tabLabel(title: "My Progress", systemImage: "chart.bar.fill", index: 3)
                        }
                        .accessibilityLabel("My Progress")
                }
                .tint(.pfTint)
                .toolbarBackground(Color.pfCard, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
            }
            .sheet(item: $presentedSheet, onDismiss: { presentationDidDismiss() }) { destination in
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
                    HelpSupportView()
                case .about:
                    AboutTrainingHubView()
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
                case .certificates:
                    PracticeExperienceSheet {
                        CertificatesListView()
                    }
                case .learningHabit:
                    PracticeExperienceSheet {
                        HabitSheetView()
                    }
                case .notifications:
                    PracticeExperienceSheet {
                        NotificationSettingsView()
                    }
                case .diagnostics:
                    DiagnosticsView()
                case .myLearning, .home, .learn, .search, .paymentCases, .myProgress, .interviewQuestions, .privacyPolicy, .termsOfService:
                    EmptyView()
                }
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
        // Tour target geometry. Every handler below writes state
        // ONLY when the stored value actually changes. The
        // handlers used to assign unconditionally, and anchor
        // values are fresh objects on every layout pass (Anchor
        // has no value equality to dedupe on), so each delivery
        // scheduled a new transaction, which re-laid-out, which
        // re-delivered: the main thread never settled, the
        // screen sat pixel-static while the view graph spun, and
        // accessibility snapshots timed out, failing three gate
        // classes in run 44132116949. Anchors resolve against the
        // current layout when read, so capturing the first live
        // anchor per target is enough: re-storing a fresh one
        // buys nothing. Frames are concrete rects, so an
        // equality guard is the correct dedupe there. The tour
        // overlay itself is currently never shown; these values
        // are captured for it and cost nothing once settled.
        .onPreferenceChange(DrawerRowAnchorKey.self) { anchors in
            var merged = drawerRowAnchors
            var changed = false
            for (key, value) in anchors where merged[key] == nil {
                merged[key] = value
                changed = true
            }
            GateDiag.delivery("DrawerRowAnchors", changed: changed) // GATE-DIAG TEMPORARY
            if changed { drawerRowAnchors = merged }
        }
        .onPreferenceChange(DrawerRowFrameKey.self) { frames in
            GateDiag.delivery("DrawerRowFrames", changed: drawerRowFrames != frames) // GATE-DIAG TEMPORARY
            if drawerRowFrames != frames { drawerRowFrames = frames }
        }
        .onPreferenceChange(KeepLearningAnchorKey.self) { anchor in
            GateDiag.delivery("KeepLearningAnchor", changed: keepLearningAnchor == nil && anchor != nil) // GATE-DIAG TEMPORARY
            if keepLearningAnchor == nil, let anchor { keepLearningAnchor = anchor }
        }
        .onPreferenceChange(KeepLearningFrameKey.self) { frame in
            GateDiag.delivery("KeepLearningFrame", changed: keepLearningFrame != frame) // GATE-DIAG TEMPORARY
            if keepLearningFrame != frame { keepLearningFrame = frame }
        }
        .onPreferenceChange(SearchFieldAnchorKey.self) { anchor in
            GateDiag.delivery("SearchFieldAnchor", changed: searchFieldAnchor == nil && anchor != nil) // GATE-DIAG TEMPORARY
            if searchFieldAnchor == nil, let anchor { searchFieldAnchor = anchor }
        }
        .onPreferenceChange(SearchPillsAnchorKey.self) { anchor in
            GateDiag.delivery("SearchPillsAnchor", changed: searchPillsAnchor == nil && anchor != nil) // GATE-DIAG TEMPORARY
            if searchPillsAnchor == nil, let anchor { searchPillsAnchor = anchor }
        }
        .onPreferenceChange(ContinueLearningAnchorKey.self) { anchor in
            GateDiag.delivery("ContinueLearningAnchor", changed: continueLearningAnchor == nil && anchor != nil) // GATE-DIAG TEMPORARY
            if continueLearningAnchor == nil, let anchor { continueLearningAnchor = anchor }
        }
        .coordinateSpace(name: TourCoordinateSpace.name)
        // The one lesson/case sheet: a deep-link lesson, a
        // tapped lesson, or the introduction's free case, each
        // in its own NavigationStack with a Done button, over
        // any tab. No push transition is involved, so a tap can
        // never strand the learner on a list. One modifier
        // only: three .sheet modifiers on this view shadowed
        // each other and the lesson sheet never presented (see
        // MainTabSheet).
        .sheet(item: mainTabSheetBinding, onDismiss: { presentationDidDismiss() }) { sheet in
            mainTabSheetContent(for: logSheetRequest(sheet))
        }
        // Presentation arbitration: this alert shows only when
        // no sheet owns the hierarchy, onboarding and the splash
        // are done, and no purchase notice is waiting (the
        // purchase alert has priority). The flag stays set while
        // gated, so the alert shows as soon as the hierarchy is
        // free instead of being lost.
        .alert(
            "Lesson link not found",
            isPresented: Binding(
                get: {
                    showDeepLinkNotFound
                        && onboardingStore.hasCompletedOnboarding
                        && !showSplash
                        && !hasActiveSheetPresentation
                        && !showNotificationPermissionPrompt
                        && storeManager.statusMessage == nil
                },
                set: { isPresented in
                    if !isPresented { showDeepLinkNotFound = false }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That link did not match a lesson in the course catalogue.")
        }
        // The one purchase alert in the app: every purchase,
        // restore and verification notice from StoreManager
        // surfaces here, and nowhere else, so a notice can
        // never stack over a lesson or a checkout screen.
        // Presentation arbitration: the alert shows only when
        // no sheet owns the hierarchy, onboarding and the splash
        // are done, and the notification explanation is not up.
        // The message stays in the store while gated, so the
        // notice shows as soon as the hierarchy is free instead
        // of being lost. Dismissing clears the message; the
        // store writes purchase notices only, never load
        // failures.
        .alert(
            "Purchase",
            isPresented: Binding(
                get: {
                    storeManager.statusMessage != nil
                        && onboardingStore.hasCompletedOnboarding
                        && !showSplash
                        && !hasActiveSheetPresentation
                        && !showNotificationPermissionPrompt
                },
                set: { isPresented in
                    if !isPresented { storeManager.clearStatusMessage() }
                }
            )
        ) {
            Button("OK", role: .cancel) { storeManager.clearStatusMessage() }
        } message: {
            Text(storeManager.statusMessage ?? "")
        }
        // Gated like the other two alerts: the flag alone must
        // never present into an owned hierarchy. The flag stays
        // set while gated, so the explanation shows as soon as
        // the hierarchy is free instead of wedging it.
        .alert("Turn on reminders?", isPresented: Binding(
            get: { showNotificationPermissionPrompt && !hasActiveSheetPresentation },
            set: { isPresented in
                if !isPresented { showNotificationPermissionPrompt = false }
            }
        )) {
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
            // launch onboarding is already complete, so this is the
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
        // Onboarding, after the splash fades. The cover flag is
        // owned here, not computed from the store: the old
        // read-only computed binding (empty setter) left the
        // cover on screen after its onDismiss fired in gate runs
        // 44171037785 and 44188117143, wedging every later
        // presentation. The flag arms only once the splash is
        // gone, and clears when the completion flag flips (see
        // the onChange handlers below). The flow always offers
        // Skip, so the tabs are never blocked behind it.
        .fullScreenCover(
            isPresented: $showOnboarding,
            onDismiss: {
                coverDidDismiss()
            }
        ) {
            OnboardingFlowView(onFinish: {})
        }
        // Onboarding completing requests the cover dismissal:
        // the flag flip clears the cover flag, and the cover's
        // onDismiss runs the post-dismissal handling. The
        // completion event and the dismissal callback serve
        // different purposes and must not both trigger the
        // pending presentation.
        .onChange(of: onboardingStore.hasCompletedOnboarding) { _, completed in
            // GATE-DIAG TEMPORARY (Test B isolation): the flag
            // flip requests dismissal only, and the UIKit probe
            // records the hierarchy at that moment. The
            // notification check is disabled here for this run
            // so no other presentation competes with the cover
            // dismissal. Restore scheduleNotificationPromptCheck
            // here once the lifecycle failure is proven.
            probePresentationHierarchy(tag: "flag-flipped")
            if completed {
                showOnboarding = false
            }
        }
        .onChange(of: showSplash) { _, splashVisible in
            // Arm the cover once the splash is gone, only for a
            // learner who has not completed onboarding. The
            // cover must never compete with the splash.
            if !splashVisible, !onboardingStore.hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .onChange(of: lessonSheetRouter.presentedEntry) { _, entry in
            // GATE-DIAG TEMPORARY: probe the UIKit hierarchy
            // when a lesson sheet is requested, and after it,
            // to learn whether the sheet's view controller
            // exists (late render) or never materialises
            // (dropped presentation).
            guard entry != nil else { return }
            probePresentationHierarchy(tag: "sheet-requested")
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                probePresentationHierarchy(tag: "sheet+1s")
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                probePresentationHierarchy(tag: "sheet+5s")
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                probePresentationHierarchy(tag: "sheet+15s")
            }
        }
        .task {
            // GATE-DIAG TEMPORARY: count every objectWillChange fire
            // from each observed object, to catch @Published streams
            // the per-property counters do not cover.
            GateDiag.installTaps([
                ("ContentService", contentService.objectWillChange),
                ("ProgressStore", progressStore.objectWillChange),
                ("StoreManager", storeManager.objectWillChange),
                ("DeepLinkRouter", deepLinkRouter.objectWillChange),
                ("OnboardingStore", onboardingStore.objectWillChange),
                ("LessonSheetRouter", lessonSheetRouter.objectWillChange),
                ("NotificationService", notificationService.objectWillChange),
                ("BookmarkStore", PFBookmarkStore.shared.objectWillChange),
            ])
        }
        .task {
            // GATE-DIAG TEMPORARY: main-actor heartbeat, one
            // line every 2 seconds. Gaps in the heartbeat
            // timestamps mark main-thread stalls precisely.
            var tick = 0
            while !Task.isCancelled {
                tick += 1
                GateDiag.heartbeat(tick)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        .task {
            // Keep the splash fast: about 1.2 seconds, then fade out.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeOut(duration: 0.3)) {
                showSplash = false
            }
            // Check the permission explanation again shortly
            // after the splash, in case the first check ran
            // before onboarding completed.
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            maybeShowNotificationPermissionPrompt()
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
    /// tab, and My Progress never opens Profile. Learn entries land
    /// on Home's browsing section: there is no Learn tab any more,
    /// so the row switches to Home and sets the section target.
    private func handleDrawerSelection(_ destination: DrawerDestination) {
        switch destination {
        case .home:
            navigateToTab(DrawerDestination.home.tabIndex ?? 0, source: "drawer")
            homeSectionTarget = .top
        case .myLearning:
            // The Keep Learning card promises Continue/Start, so
            // it lands on the top of Home, where the Continue
            // learning block names the next lesson.
            navigateToTab(DrawerDestination.home.tabIndex ?? 0, source: "drawer")
            homeSectionTarget = .top
        case .learn:
            navigateToTab(DrawerDestination.home.tabIndex ?? 0, source: "drawer")
            homeSectionTarget = .learn(.courses)
        case .search:
            navigateToTab(DrawerDestination.search.tabIndex ?? 1, source: "drawer")
        case .paymentCases:
            navigateToTab(DrawerDestination.paymentCases.tabIndex ?? 2, source: "drawer")
        case .myProgress:
            navigateToTab(DrawerDestination.myProgress.tabIndex ?? 3, source: "drawer")
        case .interviewQuestions:
            // Interview Questions stays practice content: it
            // lands on Home's Practice tab, where the interview
            // section lives.
            navigateToTab(DrawerDestination.home.tabIndex ?? 0, source: "drawer")
            homeSectionTarget = .tab(.practice)
        case .certificates, .learningHabit, .notifications, .diagnostics:
            presentedSheet = destination
        case .privacyPolicy:
            UIApplication.shared.open(SupabaseConfig.privacyPolicyURL)
        case .termsOfService:
            UIApplication.shared.open(SupabaseConfig.termsURL)
        case .practice:
            // Practice Mode as a sheet, for the first
            // practice-eligible situation. See PracticeSheetView.
            presentedSheet = .practice
        case .myPurchases, .profile, .appearance, .helpAndSupport, .about, .simulator, .isoExplorer, .exceptionLab, .baStudio, .weeklyFreeCase, .communityChallenge:
            presentedSheet = destination
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
    /// before sign-in: this view mounts only behind the gate, so a
    /// link tapped while signed out waits in the router until the
    /// learner signs in. A link is never routed before onboarding
    /// finishes either, because the onboarding cover sits above
    /// the sheets; routing retries when the flag flips.
    /// Two guards stop stale routing: a link older than 30 minutes
    /// is dropped, and a link whose sequence was already routed is
    /// never routed again. Gating is unchanged throughout:
    /// LessonView applies its own gate, so only free sample lessons
    /// open with full content.
    private func resolvePendingDeepLink() {
        guard onboardingStore.hasCompletedOnboarding,
              let link = deepLinkRouter.pendingLink else { return }
        // A sheet already up (or queued behind the cover) owns
        // the hierarchy: routing now would present a second
        // sheet over it and lose the link. The link stays
        // pending and routes from the sheet's dismissal, which
        // re-runs this function through
        // presentationDidDismiss.
        guard !hasActiveSheetPresentation else { return }
        // TTL: a link tapped long ago (cold start, onboarding,
        // a slow catalogue) must not open content the learner no
        // longer expects. 30 minutes covers every real launch.
        if let receivedAt = deepLinkRouter.pendingReceivedAt,
           Date().timeIntervalSince(receivedAt) > 30 * 60 {
            deepLinkRouter.clear()
            return
        }
        // Duplicate sequence: this link was already routed. A
        // re-entrant call during routing must not open it twice.
        let sequence = deepLinkRouter.pendingSequence
        guard sequence != lastRoutedDeepLinkSequence else { return }
        switch link {
        case .weeklyFreeCase:
            lastRoutedDeepLinkSequence = sequence
            deepLinkRouter.clear()
            presentedSheet = .weeklyFreeCase
        case .lesson(let lessonID):
            guard let index = contentService.searchIndex else { return }
            lastRoutedDeepLinkSequence = sequence
            deepLinkRouter.clear()
            if let entry = index.entries.first(where: { $0.id == lessonID && $0.type == .lesson }) {
                deepLinkLessonEntry = entry
            } else {
                showDeepLinkNotFound = true
            }
        }
    }

    /// Schedule the one-time notification explanation past the
    /// cover dismissal. Checking synchronously from the
    /// dismissal or the completion flag presented the alert
    /// into the dismissing cover in gate run 44171037785: the
    /// alert ghosted mid-transition and the lesson sheet never
    /// presented after it. The one-second settle covers the
    /// dismissal animation even on a slow Debug simulator, and
    /// the guards are re-checked when the delay fires, so a
    /// sheet that opened in the meantime still gates the
    /// alert. Callsites with no dismissal in flight (a
    /// returning launch, the splash task) keep calling the
    /// check directly.
    private func scheduleNotificationPromptCheck() {
        guard !isNotificationPromptCheckPending else { return }
        isNotificationPromptCheckPending = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            isNotificationPromptCheckPending = false
            maybeShowNotificationPermissionPrompt()
        }
    }

    /// Show the one-time notification permission explanation,
    /// once, after onboarding has completed. Every guard must
    /// pass: onboarding complete (install-level flag
    /// pf.onboarding.completed.v1, read through
    /// OnboardingStore.hasCompletedOnboarding), the splash
    /// gone, the learner not yet asked (install-level flag
    /// pf.notifications.permissionAsked.v1), the system
    /// decision still not determined, no sheet pending or up
    /// (see hasActiveSheetPresentation), and no other alert
    /// waiting: presenting the alert while a sheet presents (or
    /// the reverse) wedges the presentation hierarchy, which is
    /// how gate run 44089979766 lost the app after the
    /// first-lesson card tap. A deferred check is not lost:
    /// every sheet re-checks on dismiss, so the explanation
    /// shows as soon as the sheet closes. Both answers in the
    /// alert record the asked flag, so the explanation can
    /// never nag.
    private func maybeShowNotificationPermissionPrompt() {
        guard onboardingStore.hasCompletedOnboarding,
              !showSplash,
              !showNotificationPermissionPrompt,
              !notificationService.hasAskedPermission,
              notificationService.authorizationStatus == .notDetermined,
              !hasActiveSheetPresentation,
              !showDeepLinkNotFound,
              storeManager.statusMessage == nil
        else { return }
        showNotificationPermissionPrompt = true
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

/// The Learning habit sheet: the habit section (daily goal,
/// streak, weekly target, revision) in a scroll view, presented
/// from the drawer's "Everything inside" section.
private struct HabitSheetView: View {
    var body: some View {
        ScrollView {
            HabitSectionView()
                .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .navigationTitle("Learning habit")
        .navigationBarTitleDisplayMode(.inline)
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
                } else if let error = contentService.indexError, contentService.searchIndex == nil {
                    PFErrorStateView(
                        title: "Could not load the course catalogue",
                        message: error,
                        retryTitle: "Retry"
                    ) {
                        Task { await contentService.loadSearchIndex() }
                    }
                    .padding(PFSpacing.xl)
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
