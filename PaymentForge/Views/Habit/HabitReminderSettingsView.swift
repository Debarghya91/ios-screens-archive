// HabitReminderSettingsView.swift
// Payments Training Hub iOS - Learning reminder settings for Profile.
//
// Reminders are off by default and need explicit opt-in: turning
// them on asks the system for notification authorisation, and the
// choice is saved only when authorisation is granted. Frequency is
// daily, weekly (every Monday) or off, at a learner-chosen time.
// Reminders are local notifications only, encouraging and never
// shaming, and they can be turned off here at any time. Settings
// are stored per account through LearningHabitStore; guests can
// set them too, and they stay on this device.
// No em dashes in any user-facing text.

import SwiftUI

/// The reminder settings card shown in Profile, for signed-in
/// learners and guests alike.
struct HabitReminderSettingsView: View {
    @ObservedObject private var habitStore = LearningHabitStore.shared
    @ObservedObject private var notificationService = LocalNotificationService.shared

    @State private var selectedFrequency: LearningHabitReminderFrequency = .off
    @State private var selectedTime = Date()
    @State private var isWorking = false
    @State private var statusMessage: String?

    /// The chosen time as a short local time string, for status
    /// lines. Built from the stored settings, not the picker, so
    /// it always describes what is actually saved.
    private var savedTimeText: String {
        let settings = habitStore.reminderSettings
        let date = Calendar.current.date(
            bySettingHour: settings.hour,
            minute: settings.minute,
            second: 0,
            of: Date()
        ) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// The status line: what is on, or why reminders stay off.
    /// A denied system decision is stated plainly, with where to
    /// change it, and the stored choice stays off.
    private var statusText: String {
        if habitStore.remindersEnabled {
            if !notificationService.preferences.habitReminders {
                return "Reminders are set for \(habitStore.reminderSettings.frequency.scheduleText) at \(savedTimeText), but paused in Notification settings. Turn Habit reminders back on there to receive them."
            }
            return "Reminders on: \(habitStore.reminderSettings.frequency.scheduleText) at \(savedTimeText)."
        }
        if habitStore.notificationAuthorizationStatus == .denied {
            return "Notifications are turned off for Payments Training Hub in the Settings app, under Notifications. Reminders stay off until you turn them on there."
        }
        return "Reminders are off. Turn them on only if you want them."
    }

    var body: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Text("A gentle nudge at a time you choose. Reminders are off unless you turn them on, and you can turn them off here at any time. Nothing here tracks missed days.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Reminder frequency", selection: $selectedFrequency) {
                    ForEach(LearningHabitReminderFrequency.allCases, id: \.self) { frequency in
                        Text(frequency.displayTitle).tag(frequency)
                    }
                }
                .pickerStyle(.segmented)
                Text(selectedFrequency.explainer)
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                DatePicker(
                    "Reminder time",
                    selection: $selectedTime,
                    displayedComponents: .hourAndMinute
                )
                .font(.pfBody)
                .foregroundColor(.pfNavy)
                Text(statusText)
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let statusMessage {
                    Text(statusMessage)
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if habitStore.remindersEnabled {
                    PFPrimaryButton(title: "Save reminder settings") {
                        Task { await saveSettings() }
                    }
                    .disabled(isWorking)
                    .opacity(isWorking ? 0.5 : 1)
                    Button(role: .destructive) {
                        habitStore.disableReminders()
                        syncFromStore()
                        statusMessage = "Reminders turned off."
                    } label: {
                        Text("Turn off reminders")
                            .font(.pfBody.weight(.semibold))
                            .foregroundColor(.pfError)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                } else {
                    PFPrimaryButton(title: "Turn on reminders") {
                        Task { await saveSettings() }
                    }
                    .disabled(isWorking || selectedFrequency == .off)
                    .opacity((isWorking || selectedFrequency == .off) ? 0.5 : 1)
                }
            }
        }
        .onAppear {
            notificationService.refreshIfNamespaceChanged()
            syncFromStore()
            Task { await habitStore.refreshAuthorizationStatus() }
        }
    }

    /// Copy the stored settings into the picker and time control,
    /// so the controls always start from what is actually saved.
    private func syncFromStore() {
        let settings = habitStore.reminderSettings
        selectedFrequency = settings.frequency
        if let date = Calendar.current.date(
            bySettingHour: settings.hour,
            minute: settings.minute,
            second: 0,
            of: Date()
        ) {
            selectedTime = date
        }
    }

    /// Save the picked frequency and time through the opt-in path:
    /// authorisation is requested, and the choice is stored and
    /// scheduled only when it is granted. Picking off turns
    /// reminders off without asking for authorisation.
    private func saveSettings() async {
        isWorking = true
        defer { isWorking = false }
        let components = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        let hour = components.hour ?? LearningHabitReminderSettings.default.hour
        let minute = components.minute ?? LearningHabitReminderSettings.default.minute
        if selectedFrequency == .off {
            habitStore.disableReminders()
            statusMessage = "Reminders turned off."
            syncFromStore()
            return
        }
        let granted = await habitStore.enableReminders(
            frequency: selectedFrequency,
            hour: hour,
            minute: minute
        )
        if granted {
            statusMessage = "Reminders on."
        } else {
            statusMessage = "Notifications were not allowed, so reminders stay off. You can allow them in the Settings app, under Notifications."
        }
        syncFromStore()
    }
}
