// LearningPreferencesView.swift
// PaymentForge iOS - Learning preferences: experience level, areas of
// interest, weekly target and audio preference.
// Guests keep these on the device in UserDefaults. Signed-in users
// also sync them to user_preferences in Supabase through SyncService.
// No em dashes in any user-facing text.

import SwiftUI

/// The Learning Preferences screen, reached from Profile.
struct LearningPreferencesView: View {
    @StateObject private var authService = AuthService.shared

    @State private var experienceLevel: String?
    @State private var selectedInterests: Set<String> = []
    @State private var weeklyTarget: Int = 5
    @State private var includeAudio = true
    @State private var savedMessage: String?
    @State private var didLoad = false

    /// Weekly target range. No low cap: the most a learner can
    /// aim for in a week is the whole catalogue (746 lessons).
    private let weeklyRange = 1...746
    @State private var weeklyTargetText = "5"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.xl) {
                experienceSection
                interestsSection
                targetSection
                audioSection
                saveButton
                if let savedMessage {
                    Text(savedMessage)
                        .font(.pfBody)
                        .foregroundColor(.pfSuccess)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if authService.isSignedIn {
                    Text("Saved to your account and synced across your devices.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Saved on this device. Sign in to sync these preferences across devices.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .navigationTitle("Learning Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !didLoad {
                didLoad = true
                Task { await load() }
            }
        }
    }

    // MARK: - Experience level

    private var experienceSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Experience Level")
            Text("How much experience do you have in banking or payments?")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: PFSpacing.sm) {
                ForEach(ExperienceLevel.allCases, id: \.rawValue) { level in
                    let selected = experienceLevel == level.rawValue
                    Button {
                        experienceLevel = level.rawValue
                    } label: {
                        Text(level.rawValue)
                            .font(.pfBody.weight(.semibold))
                            .foregroundColor(selected ? .white : .pfNavy)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(selected ? Color.pfRoyal : Color.pfCard)
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(selected ? Color.pfRoyal : Color.pfBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Interests

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Areas of Interest")
            Text("Pick the areas you want to focus on. You can pick more than one.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: PFSpacing.sm) {
                ForEach(InterestArea.allCases, id: \.rawValue) { area in
                    let selected = selectedInterests.contains(area.rawValue)
                    Button {
                        if selected {
                            selectedInterests.remove(area.rawValue)
                        } else {
                            selectedInterests.insert(area.rawValue)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.pfCaption.weight(.bold))
                            }
                            Text(area.rawValue)
                                .font(.pfBody.weight(.semibold))
                        }
                        .foregroundColor(selected ? .white : .pfNavy)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(selected ? Color.pfRoyal : Color.pfCard)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(selected ? Color.pfRoyal : Color.pfBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Weekly target

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Weekly Learning Target")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text("How many lessons do you want to finish each week?")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: PFSpacing.md) {
                        TextField("5", text: $weeklyTargetText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .frame(width: 84)
                            .padding(PFSpacing.sm)
                            .background(Color.pfBackground)
                            .cornerRadius(PFSpacing.sm)
                            .onChange(of: weeklyTargetText) { newValue in
                                let digits = newValue.filter { $0.isNumber }
                                if digits != newValue { weeklyTargetText = digits }
                                if let value = Int(digits), weeklyRange.contains(value) {
                                    weeklyTarget = value
                                }
                            }
                        Text("lessons per week")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Spacer()
                        Stepper("", value: $weeklyTarget, in: weeklyRange)
                            .labelsHidden()
                            .onChange(of: weeklyTarget) { newValue in
                                weeklyTargetText = "\(newValue)"
                            }
                    }
                }
            }
        }
    }

    // MARK: - Audio

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Learning Preference")
            PFCard {
                Toggle(isOn: $includeAudio) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include audio narration")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text("Play the narrated audio with every lesson.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(.pfRoyal)
            }
        }
    }

    // MARK: - Save

    private var saveButton: some View {
        PFPrimaryButton(title: "Save preferences") {
            Task { await save() }
        }
    }

    /// Load preferences: the device copy first, always, so a
    /// saved value shows at once. The server row is only used when
    /// this device never saved preferences (a fresh device or a new
    /// sign-in): then it restores the account's values. Once the
    /// user has saved on this device, local is authoritative and a
    /// stale server row can never overwrite it.
    private func load() async {
        let local = LearningPreferences.loadLocal()
        apply(local)
        weeklyTargetText = "\(local.weeklyTarget)"
        guard authService.isSignedIn, !LearningPreferences.hasSavedLocally,
              let server = await SyncService.shared.fetchPreferences() else {
            return
        }
        apply(server)
        weeklyTargetText = "\(server.weeklyTarget)"
    }

    private func apply(_ prefs: LearningPreferences) {
        experienceLevel = prefs.experienceLevel
        selectedInterests = Set(prefs.domainInterests)
        weeklyTarget = prefs.weeklyTarget
        includeAudio = prefs.includeAudio
    }

    /// Save locally always, then push to user_preferences when
    /// signed in. The message says honestly whether the account
    /// write worked: a failed push leaves the preferences saved on
    /// the device with a sync pending, and never claims they synced.
    private func save() async {
        let prefs = LearningPreferences(
            userID: authService.currentUser?.id,
            experienceLevel: experienceLevel,
            domainInterests: Array(selectedInterests).sorted(),
            weeklyTarget: weeklyTarget,
            includeAudio: includeAudio,
            updatedAt: nil
        )
        prefs.saveLocal()
        weeklyTargetText = "\(weeklyTarget)"
        // Keep the Dashboard weekly goal in step with the target here.
        ProgressStore.shared.weeklyGoal = weeklyTarget
        if authService.isSignedIn {
            let pushed = await SyncService.shared.pushPreferences(prefs)
            savedMessage = pushed
                ? "Preferences saved to your account."
                : "Preferences saved on this device. They will sync when you are back online."
        } else {
            savedMessage = "Preferences saved."
        }
    }
}

// MARK: - Flow layout

/// A simple wrapping layout for chips and pills, so rows wrap instead
/// of clipping on narrow iPhones.
private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        // A flexible wrap without a custom Layout type: the chips are
        // laid out in a LazyVGrid with adaptive columns, which wraps
        // cleanly on every iPhone width.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110), spacing: spacing)],
            alignment: .leading,
            spacing: spacing
        ) {
            content
        }
    }
}
