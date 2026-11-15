// LocalNotificationService.swift
// PaymentForge iOS - General local notification system (v66).
//
// Local only. Nothing in this file uses APNs, device tokens, or
// entitlements, and nothing talks to a server. All requests are
// scheduled through UNUserNotificationCenter on this device, and
// the schedulers in NotificationSchedulers.swift build them from
// on-device progress and catalogue data.
//
// This service owns the shared plumbing: the learner's
// preferences, the system authorisation state, the one-time
// permission ask, the notification centre delegate, and the
// refresh entry point. The per-kind scheduling lives in
// NotificationSchedulers.refreshAll, which reads these
// preferences and replaces the pending requests for this system.
//
// Request identifiers for this system all start with "pf.notify.".
// The existing habit reminders use different identifiers
// ("pf.learningHabit.dailyReminder" and
// "pf.learningHabit.weeklyReminder") and are owned by
// LearningHabitScheduler; this file never adds, removes, or
// reschedules them. When this system clears its own requests it
// filters by the "pf.notify." prefix, so habit reminders are
// never touched.
//
// Preferences are namespaced per account through
// AccountScopedStorage, following the LearningHabitStore
// pattern: one Codable value, JSON encoded, suppress-save while
// loading, legacy adoption on load, reload clears in-memory
// state first. The permission-asked flag is different: it is
// install level, stored under a plain UserDefaults key with no
// account namespace, so the system prompt is shown at most once
// per install whatever account is signed in.
//
// Tapping a notification routes through the same mechanism as a
// tapped deep link: the notification carries a "route" userInfo
// value holding a deep-link URL string, this service parses it
// with PaymentForgeDeepLink, and hands it to the app's existing
// PaymentForgeDeepLinkRouter. There is no second router. The
// router is attached by MainTabView on appear; a tap that
// arrives before the attach is held and delivered on attach, so
// a cold-start tap is never lost. Routing itself, including the
// onboarding gate and the LessonView gate, stays in
// MainTabView.resolvePendingDeepLink, unchanged.
// No em dashes in any user-facing text.

import Foundation
import Combine
import UIKit
import UserNotifications

// MARK: - Preferences

/// The learner's notification choices. Every kind defaults to
/// on, and the master switch gates them all: when
/// masterEnabled is false, no request from this system is
/// scheduled, whatever the individual kinds say.
/// `habitReminders` is this system's own habit-reminder kind; it
/// does not control the separate LearningHabitStore reminders,
/// which keep their own opt-in settings and identifiers.
struct NotificationPreferences: Codable, Equatable {
    var masterEnabled: Bool = true
    var habitReminders: Bool = true
    var streakNudges: Bool = true
    var continueLearning: Bool = true
    var newContentAlerts: Bool = true
    var offers: Bool = true
}

// MARK: - Service

/// The shared local notification service: preferences,
/// authorisation, the one-time permission ask, the notification
/// centre delegate, and the scheduling refresh entry point.
/// MainActor isolated, like the other shared stores, because it
/// publishes state SwiftUI reads and touches UserDefaults keys
/// that follow account switches.
@MainActor final class LocalNotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = LocalNotificationService()

    /// Base key for the preferences value, namespaced per
    /// account by AccountScopedStorage.
    static let preferencesBaseKey = "pf.notifications.preferences.v1"

    /// Install-level permission-asked flag, used PLAIN with no
    /// account namespace: the system prompt is shown at most
    /// once per install. Never pass this key through
    /// AccountScopedStorage.
    static let permissionAskedKey = "pf.notifications.permissionAsked.v1"

    /// Request identifier prefix for this system. Every request
    /// scheduled by NotificationSchedulers must start with this
    /// prefix, so the clear path below can remove exactly this
    /// system's requests and nothing else.
    static let requestIdentifierPrefix = "pf.notify."

    /// The current account's notification choices. Defaults to
    /// every kind on. Written only through updatePreferences and
    /// reloadForCurrentAccount.
    @Published private(set) var preferences: NotificationPreferences = NotificationPreferences() {
        didSet { savePreferences() }
    }

    /// The system notification authorisation status, last read.
    /// Starts as not determined; refreshed by
    /// refreshAuthorizationStatus. Never persisted: the system
    /// is the source of truth.
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// The app's deep link router, attached by MainTabView on
    /// appear. Weak: PaymentForgeApp owns the router.
    private weak var deepLinkRouter: PaymentForgeDeepLinkRouter?

    /// A deep link from a tapped notification that arrived before
    /// the router was attached. Delivered on attach, then
    /// cleared, so a cold-start tap is never lost. At most one
    /// link is held: the newest tap wins, matching the router's
    /// own newest-wins rule.
    private var pendingDeepLink: PaymentForgeDeepLink?

    /// Suppresses savePreferences while loading, so a reload
    /// into an account with no stored preferences does not write
    /// a default value into that namespace (which would block
    /// guest migration for it).
    private var suppressSave = false

    /// The account namespace the in-memory preferences were
    /// loaded from. Compared on every write and schedule
    /// refresh so a namespace change (sign-in or sign-out)
    /// reloads the right account's preferences instead of
    /// writing one account's choices into another namespace.
    /// AuthService is not edited by this build, so no reload
    /// hook runs on identity transitions; the namespace is
    /// re-checked here instead.
    private var loadedNamespace: String = AccountScopedStorage.currentNamespace

    override init() {
        super.init()
        loadPreferences()
    }

    // MARK: - Permission asked flag

    /// True once the learner has been asked about notifications
    /// on this install, whether they allowed, declined in the
    /// in-app explanation, or were already decided when asked.
    /// Install level, not per account: signing in, signing out,
    /// or switching accounts never re-arms the ask.
    var hasAskedPermission: Bool {
        UserDefaults.standard.bool(forKey: Self.permissionAskedKey)
    }

    /// Record that the learner has been asked, without showing
    /// the system prompt. Used by the "Not now" answer in the
    /// in-app explanation, so declining never asks again.
    func markPermissionAsked() {
        UserDefaults.standard.set(true, forKey: Self.permissionAskedKey)
    }

    // MARK: - Deep link router

    /// Attach the app's deep link router, and deliver any
    /// notification link that arrived before the attach.
    /// Called by MainTabView on appear. Idempotent: attaching
    /// the same router again is a no-op once the pending link
    /// has been delivered.
    func attachDeepLinkRouter(_ router: PaymentForgeDeepLinkRouter) {
        deepLinkRouter = router
        if let pending = pendingDeepLink {
            pendingDeepLink = nil
            router.receive(pending)
        }
    }

    // MARK: - Authorisation

    /// True when the system will deliver notifications: granted,
    /// or provisionally granted. Matches the rule in
    /// LearningHabitStore.applyCurrentSchedule.
    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    /// Re-read the system authorisation status.
    func refreshAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Ask the system for notification authorisation, at most
    /// once per install. The centre is called only when the
    /// status is not determined; when it is already decided
    /// (granted, denied, or provisionally granted, including a
    /// decision made through the habit reminder opt-in) the
    /// stored decision is returned without prompting, so a
    /// denial is never re-prompted. The install-level asked
    /// flag is recorded in both cases. Only alert and sound
    /// are requested, matching the habit reminder request: no
    /// badge. When permission is granted, the schedule is
    /// refreshed at once so the first notifications are set up
    /// without waiting for the next app activation.
    func requestAuthorization() async -> Bool {
        await refreshAuthorizationStatus()
        guard authorizationStatus == .notDetermined else {
            markPermissionAsked()
            return isAuthorized
        }
        markPermissionAsked()
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshAuthorizationStatus()
        if granted {
            refreshScheduledNotifications()
        }
        return granted
    }

    // MARK: - Preferences and scheduling

    /// Save new preferences and make the schedule match them.
    /// The schedule refresh uses the last known authorisation
    /// status, which the app refreshes whenever it becomes
    /// active; see PaymentForgeApp.
    func updatePreferences(_ new: NotificationPreferences) {
        refreshIfNamespaceChanged()
        preferences = new
        refreshScheduledNotifications()
    }

    /// Reload preferences when the identity namespace has
    /// changed since the last load. A no-op when it has not,
    /// so calling it on every settings appearance costs
    /// nothing and never flickers the toggles.
    func refreshIfNamespaceChanged() {
        guard AccountScopedStorage.currentNamespace != loadedNamespace else { return }
        withoutSaving {
            preferences = NotificationPreferences()
        }
        loadPreferences()
    }

    /// Make the scheduled notifications match the current
    /// preferences and authorisation: when delivery is allowed
    /// and the master switch is on, the schedulers rebuild this
    /// system's requests from the current preferences and
    /// on-device state; otherwise every pending request with
    /// the "pf.notify." prefix is removed. Habit reminder
    /// requests are never touched: their identifiers carry a
    /// different prefix. Cheap and idempotent: safe to call on
    /// every app activation and every preference change.
    func refreshScheduledNotifications() {
        refreshIfNamespaceChanged()
        guard isAuthorized, preferences.masterEnabled else {
            removePendingLocalNotificationRequests()
            return
        }
        NotificationSchedulers.refreshAll()
    }

    /// Reload preferences for the current account namespace,
    /// clearing the previous account's preferences first, then
    /// refresh the schedule for the newly loaded preferences.
    /// The authorisation status is not reset: it belongs to the
    /// system, not to any account. Provided for the auth flow
    /// to call on identity transitions; AuthService itself is
    /// not edited by this file, so the coordinator wires the
    /// call and adds preferencesBaseKey to the guest migration
    /// list, or preferences will not follow account changes.
    func reloadForCurrentAccount() {
        withoutSaving {
            preferences = NotificationPreferences()
        }
        loadPreferences()
        Task {
            await refreshAuthorizationStatus()
            refreshScheduledNotifications()
        }
    }

    /// Open the system Settings page for this app, where the
    /// learner can turn notifications on or off after denying
    /// them. Used by the settings surface when the status is
    /// denied: the system prompt cannot be shown again.
    static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show a banner and play the sound for a notification that
    /// arrives while the app is in the foreground, instead of
    /// the default silent delivery. This applies to every local
    /// notification while this service is the delegate,
    /// including habit reminders, which previously arrived
    /// silently in the foreground because no delegate was set.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// A notification was tapped (or an action on it was used).
    /// Forwards to handleNotificationResponse, which routes a
    /// deep-link notification through the app's router. The
    /// completion handler is always called.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleNotificationResponse(response)
        completionHandler()
    }

    /// Route a tapped notification. The schedulers store the
    /// destination as a deep-link URL string under the "route"
    /// userInfo key; it is parsed with PaymentForgeDeepLink, so
    /// only the two real routes are accepted (a lesson link and
    /// the weekly-case link, on the com.paymentforge.app
    /// scheme), and the parsed link is handed to the app's
    /// existing router, exactly as PaymentForgeApp.onOpenURL
    /// does for a tapped link. Notifications without a route,
    /// including habit reminders, and routes that do not parse
    /// as deep links are ignored: tapping them simply opens the
    /// app. When the router is not attached yet, the link is
    /// held and delivered on attach.
    func handleNotificationResponse(_ response: UNNotificationResponse) {
        guard let routeString = response.notification.request.content.userInfo["route"] as? String,
              let url = URL(string: routeString),
              let link = PaymentForgeDeepLink(url: url) else { return }
        if let router = deepLinkRouter {
            router.receive(link)
        } else {
            pendingDeepLink = link
        }
    }

    // MARK: - Private

    /// Remove every pending request belonging to this system,
    /// by the "pf.notify." identifier prefix. Delivered
    /// notifications are left alone, and habit reminder
    /// requests are left alone: their identifiers do not carry
    /// this prefix.
    private func removePendingLocalNotificationRequests() {
        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            let identifiers = pending
                .map(\.identifier)
                .filter { $0.hasPrefix(Self.requestIdentifierPrefix) }
            guard !identifiers.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    private func withoutSaving(_ work: () -> Void) {
        let previous = suppressSave
        suppressSave = true
        defer { suppressSave = previous }
        work()
    }

    private func loadPreferences() {
        withoutSaving {
            AccountScopedStorage.adoptLegacyKey(Self.preferencesBaseKey)
            let defaults = UserDefaults.standard
            if let data = defaults.data(forKey: AccountScopedStorage.currentKey(Self.preferencesBaseKey)),
               let decoded = try? JSONDecoder().decode(NotificationPreferences.self, from: data) {
                preferences = decoded
            } else {
                preferences = NotificationPreferences()
            }
            loadedNamespace = AccountScopedStorage.currentNamespace
        }
    }

    private func savePreferences() {
        guard !suppressSave else { return }
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: AccountScopedStorage.currentKey(Self.preferencesBaseKey))
        }
    }
}
