// NotificationSchedulers.swift
// Payments Training Hub iOS - Local notification schedulers for
// streak nudges, continue learning, new content alerts and offers.
//
// Local only: UNUserNotificationCenter only. No entitlements, no
// APNs, no device token code, no network. This file edits no other
// file and hooks into no store: it only reads the existing stores
// and asks the notification centre to replace one pending request
// per type. Another worker wires refreshAll() to run on foreground.
//
// Contract: enum NotificationSchedulers { static func refreshAll() }.
// The enum is MainActor isolated because StoreManager is MainActor
// isolated and the offer checks must read it synchronously. Call
// refreshAll() from the main actor (SwiftUI foreground wiring
// satisfies this). It reads LocalNotificationService.shared, which
// another worker creates, against this contract: preferences with
// Bool fields masterEnabled, habitReminders, streakNudges,
// continueLearning, newContentAlerts and offers, plus
// authorizationStatus. Habit reminders are NOT scheduled here:
// they belong to LearningHabitStore and LearningHabitScheduler.
//
// Gates: refreshAll() schedules nothing unless the system status
// is authorized, provisional or ephemeral AND masterEnabled is
// true. When that gate fails, the four pending requests below are
// removed, so a stale nudge can never outlive its permission.
// Each type is then gated by its own toggle, and a type whose
// toggle is off has its pending request removed.
//
// One pending request per type, identifiers prefixed "pf.notify.".
// Scheduling a type always removes its existing request first, so
// a refresh replaces rather than stacks. The offers type is the
// one exception to remove-then-add on every refresh: see the
// weekly cadence note in refreshOffers. All fire times fall
// between 09:00 and 20:00 local time. Every request carries
// content.userInfo ["route": <deep link URL string>] for tap
// handling. No badge is set on any request.
//
// Routes (verified against the deep link type in ReferralInvite
// and the router in the app entry point; the scheme is
// SupabaseConfig.authRedirectScheme, "com.paymentforge.app").
// Only TWO routes exist in this build:
//   lesson:      com.paymentforge.app://lesson?id=<lesson id>
//   weekly case: com.paymentforge.app://weekly-case
// There is NO route for progress/streak and NO route for
// checkout/purchases: unknown hosts are ignored by the deep link
// parser, so inventing such a host would open nothing. Every
// scheduler below therefore uses only the two real routes:
// streak and continue learning open a real lesson link, new
// content opens the new lesson when one exists (weekly case
// otherwise), and offers open a locked lesson in the offered
// part, whose lock screen is the existing purchase path, or
// the weekly case for Practice Experiences. If a future build adds
// progress and purchases routes, the route helpers here are the
// one place to point the streak and offer requests at them.
//
// Copy: plain spoken language, short, no salesy advertising tone,
// no em dashes. The only brand name used is Payments Training Hub.
// Offer copy never states a price: the only purchase price is the
// StoreKit display price, shown by the store, never hardcoded.

import Foundation
import UserNotifications

@MainActor
enum NotificationSchedulers {

    // MARK: - Request identifiers

    static let streakRequestIdentifier = "pf.notify.streak"
    static let continueRequestIdentifier = "pf.notify.continue"
    static let newContentRequestIdentifier = "pf.notify.newcontent"
    static let offerRequestIdentifier = "pf.notify.offer"

    static let allRequestIdentifiers = [
        streakRequestIdentifier,
        continueRequestIdentifier,
        newContentRequestIdentifier,
        offerRequestIdentifier
    ]

    // MARK: - Stored state (base keys, namespaced per account)

    /// The seen-content marker: "v1" plus every catalogue entry id
    /// on screen at the last live refresh, one per line. Compared
    /// against the live catalogue to find genuinely new entries.
    /// See refreshNewContent for the format and its limits.
    private static let contentMarkerBaseKey = "pf.notifications.lastSeenContentMarker.v1"

    /// When an offer request was last scheduled, for the weekly
    /// cadence. A Date, stored under the current account namespace.
    private static let lastOfferScheduledBaseKey = "pf.notifications.lastOfferScheduledAt.v1"

    /// The product id of the last scheduled offer, so a pending
    /// offer for a product the learner has since unlocked can be
    /// dropped instead of firing.
    private static let lastOfferProductBaseKey = "pf.notifications.lastOfferProductID.v1"

    // MARK: - Thresholds

    /// Continue learning fires only when nothing in progress was
    /// touched for this long, and no activity of any kind was
    /// recorded for this long. 48 hours: a learner who was active
    /// yesterday is not nagged about a lesson from last week.
    private static let continueStaleInterval: TimeInterval = 48 * 3600

    /// Offers schedule at most once per week.
    private static let offerCadence: TimeInterval = 7 * 24 * 3600

    /// A scheduled fire time must be at least this far in the
    /// future, so a refresh never schedules a notification for a
    /// moment that has already passed.
    private static let minimumLeadTime: TimeInterval = 15 * 60

    // MARK: - Entry point

    /// Reconcile all four notification types with the current
    /// preferences, authorisation and recorded progress. Safe to
    /// call on every foreground: each type ends with at most one
    /// pending request, or none when its gate or condition fails.
    static func refreshAll() {
        let center = UNUserNotificationCenter.current()
        let service = LocalNotificationService.shared
        let status = service.authorizationStatus
        let deliveryAllowed = status == .authorized
            || status == .provisional
            || status == .ephemeral
        let preferences = service.preferences
        guard deliveryAllowed, preferences.masterEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: allRequestIdentifiers)
            return
        }
        refreshStreakNudge(isEnabled: preferences.streakNudges, center: center)
        refreshContinueLearning(isEnabled: preferences.continueLearning, center: center)
        refreshNewContent(isEnabled: preferences.newContentAlerts, center: center)
        refreshOffers(isEnabled: preferences.offers, center: center)
    }

    // MARK: - Streak nudge

    /// Schedule one evening nudge when a streak exists and the
    /// learner has no recorded activity today. Signal:
    /// ProgressStore.streakCount (consecutive active days ending
    /// today or yesterday, computed from LearningEvents) greater
    /// than zero, and ProgressStore.dailyActivity(on: today) equal
    /// to zero. Both are real store APIs, so no fixed daily nudge
    /// fallback is needed. Fire time: today 19:00, or tomorrow
    /// 19:00 when today is too soon. Route: the lesson to resume,
    /// or the weekly case when no lesson can be picked.
    private static func refreshStreakNudge(isEnabled: Bool, center: UNUserNotificationCenter) {
        guard isEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: [streakRequestIdentifier])
            return
        }
        let progress = ProgressStore.shared
        let streak = progress.streakCount
        let hasActivityToday = progress.dailyActivity(on: Date()) > 0
        guard streak > 0, !hasActivityToday else {
            center.removePendingNotificationRequests(withIdentifiers: [streakRequestIdentifier])
            return
        }
        let body: String
        if streak == 1 {
            body = "You have a 1 day streak. One short lesson keeps it going."
        } else {
            body = "You are on a \(streak) day streak. One short lesson keeps it going."
        }
        schedule(
            identifier: streakRequestIdentifier,
            body: body,
            route: resumeRoute(progress: progress),
            fireDate: nextDaytimeSlot(hour: 19, minute: 0),
            center: center
        )
    }

    // MARK: - Continue learning

    /// Schedule one nudge when an in-progress lesson or pathway
    /// exists that the learner has not returned to recently.
    /// Signal: the most recently touched started-but-incomplete
    /// lesson (latest lessonStarted, lessonDuration, audioListened
    /// or quiz event for a lesson id that is not complete), or,
    /// when no such lesson exists, the active path's first
    /// incomplete lesson when the path is genuinely in progress
    /// (at least one required lesson complete, at least one still
    /// open). The nudge fires only when that item was last touched
    /// at least 48 hours ago AND no activity of any kind was
    /// recorded in the last 48 hours (ProgressStore
    /// lastActivityDate). Bookmarks do not count as touches: they
    /// record saving, not learning. Fire time: today 18:00, or
    /// tomorrow 18:00 when today is too soon. Route: the lesson
    /// link for the item itself.
    private static func refreshContinueLearning(isEnabled: Bool, center: UNUserNotificationCenter) {
        guard isEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: [continueRequestIdentifier])
            return
        }
        let progress = ProgressStore.shared
        let candidate = mostRecentIncompleteLesson(progress: progress)
            ?? staleActivePathCandidate(progress: progress)
        let lastActivity = progress.lastActivityDate
        let now = Date()
        guard let candidate,
              now.timeIntervalSince(candidate.lastTouched) >= continueStaleInterval,
              let lastActivity,
              now.timeIntervalSince(lastActivity) >= continueStaleInterval,
              let url = PaymentForgeDeepLink.lessonURL(lessonID: candidate.lessonID) else {
            center.removePendingNotificationRequests(withIdentifiers: [continueRequestIdentifier])
            return
        }
        schedule(
            identifier: continueRequestIdentifier,
            body: "Your next lesson is ready when you are. Pick it up when you have a few minutes.",
            route: url.absoluteString,
            fireDate: nextDaytimeSlot(hour: 18, minute: 0),
            center: center
        )
    }

    // MARK: - New content

    /// Schedule one alert when the live catalogue contains entries
    /// the learner has not seen. Freshness signal: the set of
    /// catalogue entry ids. SearchIndex and SearchEntry carry no
    /// date, version or ordering field (verified: id, title, url,
    /// type and text only), so there is no "newer than" timestamp
    /// to compare. The marker therefore stores the full set of ids
    /// seen at the last live refresh, and an alert fires only when
    /// the live set contains ids the marker does not. Catalogue
    /// reorder, removal or rename alone never fires: only net new
    /// ids fire, and content edits that keep the same id never
    /// fire. The first refresh with no marker records the baseline
    /// silently and schedules nothing, so the whole catalogue is
    /// never announced as new. The marker advances to the current
    /// live set on every live refresh, including when the alert is
    /// scheduled, so one batch alerts at most once. Refreshes that
    /// only have a stale disk cache (isShowingCachedContent) never
    /// move the marker and never schedule. Fire time: today 12:00,
    /// or tomorrow 12:00 when today is too soon. Route: the first
    /// new lesson in catalogue order, the weekly case when the new
    /// entries are situations, or the first incomplete lesson when
    /// the new entries are only guides, labs, tests or FAQs.
    private static func refreshNewContent(isEnabled: Bool, center: UNUserNotificationCenter) {
        guard isEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: [newContentRequestIdentifier])
            return
        }
        let service = ContentService.shared
        guard let index = service.searchIndex, !service.isShowingCachedContent else {
            return
        }
        let defaults = UserDefaults.standard
        let markerKey = AccountScopedStorage.currentKey(contentMarkerBaseKey)
        let currentIDs = Set(index.entries.map(\.id))
        guard let stored = defaults.string(forKey: markerKey),
              let seenIDs = seenIDs(from: stored) else {
            defaults.set(contentMarkerValue(for: currentIDs), forKey: markerKey)
            center.removePendingNotificationRequests(withIdentifiers: [newContentRequestIdentifier])
            return
        }
        let newIDs = currentIDs.subtracting(seenIDs)
        defaults.set(contentMarkerValue(for: currentIDs), forKey: markerKey)
        guard !newIDs.isEmpty else {
            center.removePendingNotificationRequests(withIdentifiers: [newContentRequestIdentifier])
            return
        }
        let newEntries = index.entries.filter { newIDs.contains($0.id) }
        let body: String
        let route: String
        if let lesson = newEntries.first(where: { $0.type == .lesson }),
           let url = PaymentForgeDeepLink.lessonURL(lessonID: lesson.id) {
            body = "New lessons have been added. Have a look when you have a few minutes."
            route = url.absoluteString
        } else if newEntries.contains(where: { $0.type == .situation }) {
            body = "New payment cases have been added. Have a look when you have a few minutes."
            route = PaymentForgeDeepLink.weeklyCaseURL().absoluteString
        } else if let lessonID = firstIncompleteLessonID(progress: ProgressStore.shared, service: service),
                  let url = PaymentForgeDeepLink.lessonURL(lessonID: lessonID) {
            body = "New learning material has been added. Have a look when you have a few minutes."
            route = url.absoluteString
        } else {
            body = "New learning material has been added. Have a look when you have a few minutes."
            route = PaymentForgeDeepLink.weeklyCaseURL().absoluteString
        }
        schedule(
            identifier: newContentRequestIdentifier,
            body: body,
            route: route,
            fireDate: nextDaytimeSlot(hour: 12, minute: 0),
            center: center
        )
    }

    /// The marker value for a set of ids: a version line, then one
    /// id per line, sorted. Catalogue ids are single tokens with
    /// no newline, so one id per line parses back exactly.
    private static func contentMarkerValue(for ids: Set<String>) -> String {
        "v1\n" + ids.sorted().joined(separator: "\n")
    }

    /// The ids stored in a marker, or nil when the stored value is
    /// missing, unversioned or empty, which means "no usable
    /// baseline yet" and the caller records one silently.
    private static func seenIDs(from stored: String) -> Set<String>? {
        let lines = stored.components(separatedBy: "\n")
        guard lines.first == "v1" else { return nil }
        let ids = Set(lines.dropFirst().filter { !$0.isEmpty })
        guard !ids.isEmpty else { return nil }
        return ids
    }

    // MARK: - Offers

    /// One tasteful offer about a paid product, at most weekly.
    /// Catalogue (at most 3 messages, all read-only against the
    /// store, and only for products StoreManager reports NOT
    /// unlocked: isProductUnlocked for parts, and
    /// isPracticeUnlocked for Practice Experiences):
    ///   1. The Integrated Course, when the full course is locked.
    ///   2. Practice Experiences, when Practice is locked. The
    ///      Integrated Course includes Practice Experiences,
    ///      so full course owners already have Practice
    ///      unlocked and never receive this message. It goes
    ///      only to learners who hold neither product.
    ///   3. The book part for the chapter the learner most
    ///      recently worked in, via unlockingProduct(for:), when
    ///      that chapter is locked and maps to a part.
    /// When every eligible product is unlocked, nothing schedules.
    /// Choice rotates by ISO week number over the eligible
    /// messages, so the same message does not repeat every week
    /// while more than one product is locked. Cadence: an offer is
    /// scheduled only when none was scheduled in the last 7 days;
    /// the pending request is then left untouched until the week
    /// passes, because removing and re-adding it on every
    /// foreground would push its fire date out forever. The fire
    /// date is 7 days out at 11:00. Fully covered by the offers
    /// toggle: off removes the pending request. No prices, no
    /// gating changes, no purchase code: the route opens a locked
    /// lesson in the part, whose lock screen is the existing
    /// purchase path, or the weekly case for Practice, because
    /// no purchases route exists in this build.
    private static func refreshOffers(isEnabled: Bool, center: UNUserNotificationCenter) {
        let storeManager = StoreManager.shared
        guard isEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: [offerRequestIdentifier])
            return
        }
        let eligible = eligibleOffers(storeManager: storeManager)
        guard !eligible.isEmpty else {
            center.removePendingNotificationRequests(withIdentifiers: [offerRequestIdentifier])
            clearOfferState()
            return
        }
        let defaults = UserDefaults.standard
        let scheduledKey = AccountScopedStorage.currentKey(lastOfferScheduledBaseKey)
        let productKey = AccountScopedStorage.currentKey(lastOfferProductBaseKey)
        if let lastProductID = defaults.string(forKey: productKey),
           storeManager.isProductUnlocked(lastProductID) {
            center.removePendingNotificationRequests(withIdentifiers: [offerRequestIdentifier])
            clearOfferState()
        }
        if let lastScheduled = defaults.object(forKey: scheduledKey) as? Date,
           Date().timeIntervalSince(lastScheduled) < offerCadence {
            return
        }
        let week = Calendar(identifier: .iso8601).component(.weekOfYear, from: Date())
        let offer = eligible[week % eligible.count]
        schedule(
            identifier: offerRequestIdentifier,
            body: offer.body,
            route: offer.route,
            fireDate: offerFireDate(),
            center: center
        )
        defaults.set(Date(), forKey: scheduledKey)
        defaults.set(offer.productID, forKey: productKey)
    }

    /// One offer message: the product it is about, its copy, and
    /// the deep link route its tap opens.
    private struct OfferMessage {
        let productID: String
        let body: String
        let route: String
    }

    /// The offer messages whose product is currently locked, in
    /// catalogue order: full course, Practice Experiences, recent
    /// chapter part. Practice uses isPracticeUnlocked, so full
    /// course owners never see a Practice offer. Read-only
    /// store checks only.
    private static func eligibleOffers(storeManager: StoreManager) -> [OfferMessage] {
        var offers: [OfferMessage] = []
        let fullCourseID = ProductCatalogue.fullCourseProductID
        if !storeManager.isProductUnlocked(fullCourseID) {
            offers.append(OfferMessage(
                productID: fullCourseID,
                body: "The full course is there when you want every chapter in one place.",
                route: lockedLessonRoute(storeManager: storeManager)
                    ?? fallbackLessonRoute()
                    ?? PaymentForgeDeepLink.weeklyCaseURL().absoluteString
            ))
        }
        let practiceID = ProductCatalogue.practiceProductID
        // Practice entitlement, not the standalone product
        // alone: the Integrated Course includes Practice.
        if !storeManager.isPracticeUnlocked {
            offers.append(OfferMessage(
                productID: practiceID,
                body: "The full set of payment cases is there when you want to work through real situations.",
                route: PaymentForgeDeepLink.weeklyCaseURL().absoluteString
            ))
        }
        if let part = bundleForRecentChapter(storeManager: storeManager),
           !storeManager.isProductUnlocked(part.productID) {
            offers.append(OfferMessage(
                productID: part.productID,
                body: "\(part.name) is there when you want the full set of lessons on that topic.",
                route: lockedLessonRoute(storeManager: storeManager, onlyChapterIDs: part.chapterIDs)
                    ?? fallbackLessonRoute()
                    ?? PaymentForgeDeepLink.weeklyCaseURL().absoluteString
            ))
        }
        return offers
    }

    /// The part that unlocks the chapter the learner most
    /// recently worked in, from the most recent incomplete lesson,
    /// the last lesson, or the active path's next lesson, in that
    /// order. Nil when every chapter tried is unlocked or maps to
    /// no part.
    private static func bundleForRecentChapter(storeManager: StoreManager) -> CourseProduct? {
        let progress = ProgressStore.shared
        var chapterIDs: [String] = []
        if let recent = mostRecentIncompleteLesson(progress: progress),
           let number = PFChapterHelper.chapterNumber(from: recent.lessonID) {
            chapterIDs.append("ch\(number)")
        }
        if let lastID = progress.lastLessonID,
           let number = PFChapterHelper.chapterNumber(from: lastID) {
            chapterIDs.append("ch\(number)")
        }
        if let pathLessonID = activePathFirstIncompleteLessonID(progress: progress),
           let number = PFChapterHelper.chapterNumber(from: pathLessonID) {
            chapterIDs.append("ch\(number)")
        }
        for chapterID in chapterIDs {
            if let part = storeManager.unlockingProduct(for: chapterID) {
                return part
            }
        }
        return nil
    }

    /// Clear the stored offer schedule state, for example when
    /// every product is unlocked or the offered product was bought.
    private static func clearOfferState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AccountScopedStorage.currentKey(lastOfferScheduledBaseKey))
        defaults.removeObject(forKey: AccountScopedStorage.currentKey(lastOfferProductBaseKey))
    }

    /// The offer fire date: 7 days from now at 11:00 local, always
    /// in the future and always in daytime hours.
    private static func offerFireDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let target = calendar.date(byAdding: .day, value: 7, to: now)
            ?? now.addingTimeInterval(offerCadence)
        return calendar.date(bySettingHour: 11, minute: 0, second: 0, of: target) ?? target
    }

    // MARK: - Lesson resolution

    /// Event types that count as touching a lesson. Bookmarks are
    /// excluded: saving is not learning. Path progress events
    /// carry no lesson id and are handled by the path candidate.
    private static let lessonTouchTypes: Set<LearningEventType> = [
        .lessonStarted, .lessonCompleted, .lessonDuration,
        .audioListened, .quizAttempted, .quizCompleted
    ]

    /// The latest touch per lesson id, from recorded events.
    private static func lastTouchByLesson(progress: ProgressStore) -> [String: Date] {
        var result: [String: Date] = [:]
        for event in progress.events {
            guard lessonTouchTypes.contains(event.type),
                  let lessonID = event.lessonID else { continue }
            if let existing = result[lessonID] {
                if event.timestamp > existing {
                    result[lessonID] = event.timestamp
                }
            } else {
                result[lessonID] = event.timestamp
            }
        }
        return result
    }

    /// The most recently touched lesson that is not complete, with
    /// its last touch time. Nil when every touched lesson is
    /// complete, or when no lesson was ever touched. Needs no
    /// catalogue: the id alone builds the lesson link, and the
    /// router resolves it against the catalogue when tapped.
    private static func mostRecentIncompleteLesson(progress: ProgressStore) -> (lessonID: String, lastTouched: Date)? {
        lastTouchByLesson(progress: progress)
            .filter { !progress.isLessonComplete($0.key) }
            .max(by: { $0.value < $1.value })
            .map { (lessonID: $0.key, lastTouched: $0.value) }
    }

    /// The active path's first incomplete lesson with the path's
    /// last touch time, when the path is genuinely in progress:
    /// at least one required lesson complete and at least one
    /// still open. Last touch is the latest pathProgress event
    /// for the path, or the latest touch of any required lesson.
    /// Nil when there is no active path, the catalogue is still
    /// loading, the path is untouched or finished, or nothing
    /// touching the path was ever recorded.
    private static func staleActivePathCandidate(progress: ProgressStore) -> (lessonID: String, lastTouched: Date)? {
        guard let path = ActivePathStore.shared.activePath else { return nil }
        let service = ContentService.shared
        let lessons = path.lessons(in: service)
        guard !lessons.isEmpty else { return nil }
        let completed = lessons.filter { progress.isLessonComplete($0.id) }.count
        guard completed > 0, completed < lessons.count else { return nil }
        guard let next = path.firstIncompleteLesson(in: progress, service: service) else { return nil }
        let lessonIDs = Set(lessons.map(\.id))
        var touches: [Date] = []
        for event in progress.events {
            if event.type == .pathProgress, event.pathID == path.id {
                touches.append(event.timestamp)
            } else if lessonTouchTypes.contains(event.type),
                      let lessonID = event.lessonID,
                      lessonIDs.contains(lessonID) {
                touches.append(event.timestamp)
            }
        }
        guard let lastTouched = touches.max() else { return nil }
        return (lessonID: next.id, lastTouched: lastTouched)
    }

    /// The active path's first incomplete lesson id, or nil when
    /// there is no active path or the catalogue is still loading.
    /// Used as a resume fallback where any next lesson will do.
    private static func activePathFirstIncompleteLessonID(progress: ProgressStore) -> String? {
        guard let path = ActivePathStore.shared.activePath else { return nil }
        return path.firstIncompleteLesson(in: progress, service: ContentService.shared)?.id
    }

    /// The first incomplete lesson id in catalogue order, or nil
    /// while the catalogue is loading or everything is complete.
    private static func firstIncompleteLessonID(progress: ProgressStore, service: ContentService) -> String? {
        service.allLessons.first { !progress.isLessonComplete($0.id) }?.id
    }

    /// The route for resuming learning: the most recently touched
    /// incomplete lesson, the active path's next lesson, or the
    /// weekly case when neither can be picked.
    private static func resumeRoute(progress: ProgressStore) -> String {
        if let lessonID = mostRecentIncompleteLesson(progress: progress)?.lessonID,
           let url = PaymentForgeDeepLink.lessonURL(lessonID: lessonID) {
            return url.absoluteString
        }
        if let lessonID = activePathFirstIncompleteLessonID(progress: progress),
           let url = PaymentForgeDeepLink.lessonURL(lessonID: lessonID) {
            return url.absoluteString
        }
        return PaymentForgeDeepLink.weeklyCaseURL().absoluteString
    }

    /// The route for the first incomplete lesson, for offer
    /// fallbacks. Nil while the catalogue is loading or when
    /// everything is complete.
    private static func fallbackLessonRoute() -> String? {
        let progress = ProgressStore.shared
        guard let lessonID = firstIncompleteLessonID(progress: progress, service: ContentService.shared),
              let url = PaymentForgeDeepLink.lessonURL(lessonID: lessonID) else {
            return nil
        }
        return url.absoluteString
    }

    /// The first lesson of each chapter: the free sample lessons.
    /// Offer routes skip these, so the tap lands on a locked
    /// lesson whose lock screen is the purchase path.
    private static func sampleLessonIDs(service: ContentService) -> Set<String> {
        Set(PFChapterHelper.chapterNumbers(in: service).compactMap {
            PFChapterHelper.lessons(forChapter: $0, in: service).first?.id
        })
    }

    /// A locked, non-sample lesson link: the first lesson in
    /// catalogue order, optionally restricted to the given chapter
    /// ids, whose chapter StoreManager reports locked. Tapping it
    /// opens the lesson's locked state, which carries the existing
    /// purchase path. Nil when no such lesson exists in the loaded
    /// catalogue, for example while it is still loading.
    private static func lockedLessonRoute(storeManager: StoreManager, onlyChapterIDs: [String]? = nil) -> String? {
        let service = ContentService.shared
        let wanted = onlyChapterIDs.map(Set.init)
        let samples = sampleLessonIDs(service: service)
        for lesson in service.allLessons {
            guard let chapterNumber = lesson.chapterNumber else { continue }
            let chapterID = "ch\(chapterNumber)"
            if let wanted, !wanted.contains(chapterID) { continue }
            guard !samples.contains(lesson.id),
                  !storeManager.isChapterUnlocked(chapterID) else { continue }
            if let url = PaymentForgeDeepLink.lessonURL(lessonID: lesson.id) {
                return url.absoluteString
            }
        }
        return nil
    }

    // MARK: - Scheduling primitives

    /// The next daytime slot at the given hour: today when that
    /// time is still at least the minimum lead time away,
    /// otherwise tomorrow. The hour must be within 09:00 to
    /// 20:00; every caller passes a daytime hour.
    private static func nextDaytimeSlot(hour: Int, minute: Int, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let earliest = now.addingTimeInterval(minimumLeadTime)
        if let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now),
           today > earliest {
            return today
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)
            ?? now.addingTimeInterval(24 * 3600)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: tomorrow)
            ?? earliest.addingTimeInterval(3600)
    }

    /// Replace any pending request with this identifier with one
    /// request firing once at fireDate. Content carries only the
    /// title, the body, the default sound and the route in
    /// userInfo. No badge, no category, no attachments.
    private static func schedule(
        identifier: String,
        body: String,
        route: String,
        fireDate: Date,
        center: UNUserNotificationCenter
    ) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let content = UNMutableNotificationContent()
        content.title = "Payments Training Hub"
        content.body = body
        content.sound = .default
        content.userInfo = ["route": route]
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }
}
