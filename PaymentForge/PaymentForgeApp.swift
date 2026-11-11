// PaymentForgeApp.swift
// PaymentForge iOS - App entry point and main tab navigation.
// No em dashes in any user-facing text.

import SwiftUI

@main
struct PaymentForgeApp: App {
    @StateObject private var contentService = ContentService.shared
    @StateObject private var progressStore = ProgressStore.shared
    @StateObject private var storeManager = StoreManager()
    @StateObject private var authService = AuthService.shared
    @AppStorage("pf.appearance.darkMode") private var darkModeEnabled = false

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
                .preferredColorScheme(darkModeEnabled ? .dark : .light)
                .onOpenURL { url in
                    // Auth callback (Google PKCE code or magic-link token).
                    // handleAuthCallback returns false for non-auth URLs.
                    Task { _ = await authService.handleAuthCallback(url: url) }
                }
                .task {
                    await contentService.loadSearchIndex()
                    await contentService.loadFullSituations()
                    await storeManager.start()
                }
        }
    }
}

/// The main tab bar, exactly five tabs: Home (0), Learn (1),
/// Search (2), Payment Cases (3), My Progress (4). Learn hosts the
/// existing CoursesView, Payment Cases hosts the existing
/// SituationsView, My Progress hosts the existing DashboardView
/// rebuilt as a progress screen. There is no Chat tab: the chat
/// assistant floats instead, as a Clippy-style paperclip over
/// every tab. No tab is removed, only renamed:
/// Courses becomes Learn, Situations becomes Payment Cases,
/// Dashboard becomes My Progress. Profile is NOT a tab: it is
/// reached from the Home avatar and from the account drawer, and
/// opens as a sheet, so it can never be confused with My Progress.
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

    @State private var isDrawerOpen = false
    @State private var selectedTab = 0
    @State private var presentedSheet: DrawerDestination? = nil
    @State private var showSplash = true
    /// The Clippy-style floating chat assistant: hidden when the
    /// learner drags it to the bottom edge, and the chat sheet it
    /// opens. There is no Chat tab: the assistant floats instead.
    @State private var isChatAssistantHidden = false
    @State private var showChatAssistant = false

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
            DrawerContainer(isOpen: $isDrawerOpen, onSelect: handleDrawerSelection) {
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
                case .profile:
                    ProfileView()
                case .appearance:
                    AppearanceSettingsView()
                case .helpAndSupport:
                    HelpSupportView()
                case .about:
                    AboutPaymentForgeView()
                case .myLearning, .home, .learn, .search, .paymentCases, .myProgress, .chatAssistant:
                    EmptyView()
                }
            }

            // The floating chat assistant: a Clippy-style paperclip
            // that floats over every tab, bottom right above the tab
            // bar. No Chat tab: the assistant floats instead, like
            // the website assistant.
            FloatingChatAssistant(
                selectedTab: $selectedTab,
                isHidden: $isChatAssistantHidden,
                showChat: $showChatAssistant
            )
            .zIndex(2)

            // The chat as a small floating window inside the current
            // page, anchored above the mascot at the bottom right.
            // It is an overlay, not a sheet, so the learner never
            // leaves the page they were on.
            if showChatAssistant {
                ChatAssistantCard(isPresented: $showChatAssistant)
                    .zIndex(3)
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
        .task {
            // Keep the splash fast: about 1.2 seconds, then fade out.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeOut(duration: 0.3)) {
                showSplash = false
            }
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
        case .chatAssistant:
            // Bring the floating assistant back and open the chat.
            isChatAssistantHidden = false
            showChatAssistant = true
        case .myPurchases, .profile, .appearance, .helpAndSupport, .about:
            presentedSheet = destination
        }
    }
}
