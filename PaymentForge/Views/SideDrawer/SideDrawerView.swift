// SideDrawerView.swift
// PaymentForge iOS - Side drawer menu, modelled on the Paytm Settings
// drawer the owner shared: a panel that slides in over the main content,
// with a title, option rows (icon, bold title, grey subtitle, chevron),
// a highlighted card at the bottom and the brand name below it.
// Uses the app design language: royal blue primary, gold sparingly,
// deep executive navy. No em dashes in any user-facing text.

import SwiftUI

// MARK: - Destinations

/// Where a drawer row leads. Handled by the container: tabs switch in place,
// sheets present over the app. Tab destinations (home, learn, search,
// paymentCases, myProgress) switch tabs only. Profile is a sheet
// destination, separate from My Progress: opening Profile never
// lands on My Progress and vice versa. myLearning is kept for the
// Keep Learning card at the bottom, and also switches to Learn.
enum DrawerDestination: String, Identifiable, Hashable {
    case home
    case learn
    case search
    case paymentCases
    case myProgress
    case chatAssistant
    case myLearning
    case myPurchases
    case profile
    case appearance
    case helpAndSupport
    case about

    var id: String { rawValue }
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

    /// The rows in the drawer, in display order: first the five tab
    /// destinations, then Profile as its own account destination,
    /// then purchases, appearance, help and about. Profile is listed
    /// explicitly so it is always one tap away, and it routes to the
    /// Profile sheet, never to the My Progress tab.
    /// Refer and Win is deliberately not listed: there is no referral
    /// offer for PaymentForge, and the brief says to leave the row out
    /// rather than invent one.
    private var rows: [DrawerRowModel] {
        [
            DrawerRowModel(
                id: .home,
                icon: "house.fill",
                title: "Home",
                subtitle: "Your personalised home and continue learning"
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
                id: .myProgress,
                icon: "chart.bar.fill",
                title: "My Progress",
                subtitle: "Your learning analytics, streak and quiz scores"
            ),
            DrawerRowModel(
                id: .chatAssistant,
                icon: "bubble.left.and.bubble.right.fill",
                title: "Chat Assistant",
                subtitle: "Ask the assistant anything about payments"
            ),
            DrawerRowModel(
                id: .profile,
                icon: "person.fill",
                title: "Profile",
                subtitle: "Your name, privacy, notifications and language"
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
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Deep navy gradient header with the PaymentForge logo:
            // a gold PF monogram tile, the white brand name and the
            // tagline. The panel ignores the safe area so it runs full
            // height, so the header is pushed below the status bar with
            // the real device inset instead of a fixed value.
            HStack(spacing: PFSpacing.md) {
                Text("PF")
                    .font(.pfSectionTitle.weight(.bold))
                    .foregroundColor(.pfNavy)
                    .frame(width: 48, height: 48)
                    .background(Color.pfGold)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Payments Training Hub")
                        .font(.pfSectionTitle.weight(.bold))
                        .foregroundColor(.white)
                    Text("Master the world of payments")
                        .font(.pfCaption.weight(.regular))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, PFWindowSafeArea.top + 12)
            .padding(.bottom, 20)
            .background(Color.pfHeroGradient)

            // Option rows.
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        DrawerRow(model: row) {
                            onSelect(row.id)
                        }
                        if row.id != rows.last?.id {
                            Divider()
                                .padding(.leading, 76)
                        }
                    }
                }
                .padding(.top, PFSpacing.sm)
            }

            Spacer(minLength: PFSpacing.lg)

            // Highlighted progress card, in the style of the Paytm
            // Security Shield card: icon, bold title, subtitle, pill button.
            KeepLearningCard {
                onSelect(.myLearning)
            }
            .padding(.horizontal, PFSpacing.lg)
            .padding(.bottom, PFSpacing.lg)

            // Brand name at the very bottom, kept above the home
            // indicator by the real device bottom inset.
            VStack(spacing: 2) {
                Text("Payments Training Hub")
                    .font(.pfSectionTitle.weight(.bold))
                    .foregroundColor(.pfNavy)
                Text("Payments, taught the way banks actually run them.")
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
/// Matches the Paytm row format exactly.
private struct DrawerRow: View {
    let model: DrawerRowModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: PFSpacing.lg) {
                Image(systemName: model.icon)
                    .font(.pfCardTitle.weight(.regular))
                    .foregroundColor(.pfNavy)
                    .frame(width: 36, height: 36, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.title)
                        .font(.pfBody.weight(.semibold))
                        .foregroundColor(.pfNavy)
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
                    .foregroundColor(.pfNavy.opacity(0.55))
            }
            .padding(.horizontal, PFSpacing.xl)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(PFDrawerRowStyle())
        .accessibilityLabel("\(model.title). \(model.subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}

/// A drawer row press style: a light-blue rounded background while
/// pressed, so the tapped row reads as the active one.
private struct PFDrawerRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? Color.pfRoyal.opacity(0.08)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, PFSpacing.sm)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Keep learning card

/// The highlighted card at the bottom of the drawer, in the style of the
/// Paytm Security Shield card. Shows the learner's streak and weekly
/// goal progress, with a button to continue learning.
private struct KeepLearningCard: View {
    @EnvironmentObject private var progressStore: ProgressStore
    let onContinue: () -> Void

    var body: some View {
        HStack(spacing: PFSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.pfGoldSoft)
                    .frame(width: 52, height: 52)
                Image(systemName: "flame.fill")
                    .font(.pfSectionTitle.weight(.regular))
                    .foregroundColor(.pfGold)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Keep learning")
                    .font(.pfBody.weight(.bold))
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(progressLine)
                    .font(.pfCaption.weight(.regular))
                    .foregroundColor(.pfSecondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                PFProgressBar(progress: progressStore.weeklyProgress, height: 6)
                    .padding(.top, 4)
            }

            Spacer(minLength: PFSpacing.sm)

            Button(action: onContinue) {
                Text("Continue")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.pfRoyal)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
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
                    Text("Dark mode applies across the whole app. Larger text increases the text size across the app. It takes effect when a screen is next opened.")
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
/// search index and the support contact.
struct HelpSupportView: View {
    @EnvironmentObject private var contentService: ContentService
    @Environment(\.dismiss) private var dismiss

    private var faqs: [SearchEntry] {
        contentService.searchIndex?.entries.filter { $0.type == .faq } ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                    .padding(.vertical, 4)
                    .listRowBackground(Color.pfCard)
                } header: {
                    Text("Contact")
                }

                Section {
                    if faqs.isEmpty {
                        Text("FAQs are loading. Check your connection and try again.")
                            .foregroundColor(.pfSecondaryText)
                            .listRowBackground(Color.pfCard)
                    } else {
                        ForEach(faqs.prefix(20)) { faq in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(faq.title)
                                    .font(.pfCardTitle)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(faq.preview)
                                    .font(.pfCallout)
                                    .foregroundColor(.pfSecondaryText)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.pfCard)
                        }
                    }
                } header: {
                    Text("Frequently asked questions")
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
        }
    }
}

// MARK: - About

/// About PaymentForge, the operator and the curriculum.
struct AboutPaymentForgeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.xl) {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("Payments Training Hub")
                            .font(.pfHeroTitle)
                            .foregroundColor(.pfNavy)
                        Text("Payments, taught the way banks actually run them.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                    }

                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("The curriculum")
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                        Text("100 chapters and 746 narrated lessons across 15 domains, with 45 long-form guides, 320 interview questions, 10 simulators, 124 scenarios and 564 Payment Situations. Every lesson is built for working payments professionals, with real examples and field-level detail.")
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                    }

                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("The operator")
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                        Text("Payments Training Hub is built and run by Debarghya Mondal, a Senior Business Analyst who has run payments transformation at NatWest in the UK since 2021, deployed through Capco in Bangalore.")
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                    }

                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("How it works")
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                        Text("Browse the catalogue freely, with no sign-in. Lessons unlock when you buy their course: 11 courses from Rs. 999 to Rs. 2,999, or the Integrated Course for Rs. 9,999, which unlocks everything. Payment Situations is a separate product, priced at Rs. 4,999, paid by UPI with manual verification. Progress is stored only on your device.")
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
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
