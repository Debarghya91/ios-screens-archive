// NotificationSettingsView.swift
// Payments Training Hub iOS - Notification settings.
//
// One screen for every notification choice: a master switch, one
// toggle per notification type, and the system permission status
// in plain words. All preferences live in LocalNotificationService
// and every toggle writes through updatePreferences. All
// notifications are local only. The habit reminders toggle also
// keeps the scheduled habit reminders in step through the existing
// habit code; it never reimplements the habit scheduler. When the
// system permission is denied, this screen only points to system
// Settings. It never asks again from inside the app.
// No em dashes in any user-facing text.

import SwiftUI
import UserNotifications

/// The notification settings screen, reached from Profile. The
/// master switch turns every type off at once while keeping the
/// per-type choices below, so turning it back on restores them.
struct NotificationSettingsView: View {
    @StateObject private var notificationService = LocalNotificationService.shared
    @ObservedObject private var habitStore = LearningHabitStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.xl) {
                aboutSection
                masterSection
                typesSection
                habitNote
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            notificationService.refreshIfNamespaceChanged()
            Task { await notificationService.refreshAuthorizationStatus() }
        }
    }

    // MARK: - About and system permission

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "About notifications")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    PFBodyText(text: "Payments Training Hub sends short notifications to help you keep learning. They remind you at a time you choose, tell you when new lessons arrive, and share offers. Choose which types you want below. You can change this any time.", textColor: .pfSecondaryText)
                    HStack {
                        Text("System permission")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                        Spacer()
                        Text(authorizationStatusText)
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                    }
                    if notificationService.authorizationStatus == .denied {
                        Text("Notifications are off in system Settings, so nothing below can reach you yet. Turn them on in Settings to receive them.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        PFSecondaryButton(title: "Open Settings") {
                            LocalNotificationService.openSystemSettings()
                        }
                    }
                }
            }
        }
    }

    /// The system permission in plain words: allowed, not allowed,
    /// or not asked yet. Provisional and ephemeral delivery both
    /// count as allowed, since notifications can reach the learner.
    private var authorizationStatusText: String {
        switch notificationService.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Allowed"
        case .denied:
            return "Not allowed"
        case .notDetermined:
            return "Not asked yet"
        @unknown default:
            return "Not asked yet"
        }
    }

    // MARK: - Master switch

    private var masterSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "All notifications")
            PFCard {
                preferenceToggle(
                    title: "All notifications",
                    explanation: "Turn every notification type on or off at once. Your choices below are kept when this is off.",
                    isOn: masterBinding
                )
            }
        }
    }

    // MARK: - Per-type toggles

    private var typesSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Notification types")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    preferenceToggle(
                        title: "Habit reminders",
                        explanation: "A gentle nudge at the time you chose.",
                        isOn: habitRemindersBinding
                    )
                    Divider()
                    preferenceToggle(
                        title: "Streak nudges",
                        explanation: "A short note about your learning streak.",
                        isOn: streakNudgesBinding
                    )
                    Divider()
                    preferenceToggle(
                        title: "Continue learning",
                        explanation: "A reminder to pick up where you left off.",
                        isOn: continueLearningBinding
                    )
                    Divider()
                    preferenceToggle(
                        title: "New lessons and cases",
                        explanation: "A note when new lessons or cases are added.",
                        isOn: newContentAlertsBinding
                    )
                    Divider()
                    preferenceToggle(
                        title: "Offers and announcements",
                        explanation: "Offers and news from Payments Training Hub.",
                        isOn: offersBinding
                    )
                }
            }
            .disabled(!notificationService.preferences.masterEnabled)
        }
    }

    /// Habit reminders follow the time and frequency set on
    /// Profile, under Learning reminders. This toggle only decides
    /// whether those reminders are sent.
    private var habitNote: some View {
        Text("Habit reminders use the time and frequency set under Learning reminders on your Profile.")
            .font(.pfBody)
            .foregroundColor(.pfSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Toggle rows and bindings

    /// One toggle row, matching the settings toggle in Learning
    /// Preferences: title, one line of explanation, royal switch.
    private func preferenceToggle(title: String, explanation: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(explanation)
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(.pfRoyal)
    }

    private var masterBinding: Binding<Bool> {
        Binding(
            get: { notificationService.preferences.masterEnabled },
            set: { newValue in
                var updated = notificationService.preferences
                updated.masterEnabled = newValue
                notificationService.updatePreferences(updated)
            }
        )
    }

    private var habitRemindersBinding: Binding<Bool> {
        Binding(
            get: { notificationService.preferences.habitReminders },
            set: { newValue in
                var updated = notificationService.preferences
                updated.habitReminders = newValue
                notificationService.updatePreferences(updated)
                applyHabitReminderChange(newValue)
            }
        )
    }

    private var streakNudgesBinding: Binding<Bool> {
        Binding(
            get: { notificationService.preferences.streakNudges },
            set: { newValue in
                var updated = notificationService.preferences
                updated.streakNudges = newValue
                notificationService.updatePreferences(updated)
            }
        )
    }

    private var continueLearningBinding: Binding<Bool> {
        Binding(
            get: { notificationService.preferences.continueLearning },
            set: { newValue in
                var updated = notificationService.preferences
                updated.continueLearning = newValue
                notificationService.updatePreferences(updated)
            }
        )
    }

    private var newContentAlertsBinding: Binding<Bool> {
        Binding(
            get: { notificationService.preferences.newContentAlerts },
            set: { newValue in
                var updated = notificationService.preferences
                updated.newContentAlerts = newValue
                notificationService.updatePreferences(updated)
            }
        )
    }

    private var offersBinding: Binding<Bool> {
        Binding(
            get: { notificationService.preferences.offers },
            set: { newValue in
                var updated = notificationService.preferences
                updated.offers = newValue
                notificationService.updatePreferences(updated)
            }
        )
    }

    // MARK: - Habit reminder wiring

    /// Keep the scheduled habit reminders in step with the habit
    /// reminders toggle, using only the existing habit code.
    /// Turning the toggle off cancels the scheduled requests but
    /// keeps the learner's saved frequency and time untouched, so
    /// turning it back on can restore them. Turning it on
    /// re-applies the saved settings through the store, which
    /// schedules only when reminders are on and the system allows
    /// delivery, and removes any stale request otherwise. This
    /// never calls disableReminders: that path overwrites the saved
    /// frequency with off, which would destroy the settings the
    /// on path needs to restore. It also never asks the system for
    /// permission: that prompt belongs to the opt-in path on
    /// Profile, under Learning reminders.
    private func applyHabitReminderChange(_ isOn: Bool) {
        if isOn {
            Task { await habitStore.applyCurrentSchedule() }
        } else {
            LearningHabitScheduler.cancelAll()
        }
    }
}
