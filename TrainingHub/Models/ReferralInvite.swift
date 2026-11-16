// ReferralInvite.swift
// Payments Training Hub iOS - Referral invitations, deep links and the weekly
// free case selector.
//
// Local only. Nothing in this file talks to a server, stores a
// referral on a backend, or tracks who opened a link. The decided
// referral and promo rules live in ReferralRules (ReferralStore)
// and are website-validated; no invite text here promises a
// reward, bonus, discount or credit. An invite is plain text plus
// a link to the free experience: the website, or the app deep link
// for a device that already has the app.
//
// Deep links. The app already registers the custom scheme
// com.paymentstraininghub.app in Info.plist (CFBundleURLTypes) for
// Supabase Auth callbacks, so no new scheme and no plist change
// is needed: the host distinguishes an auth callback from a
// deep link. TrainingHubApp checks for a deep link BEFORE it
// forwards a URL to AuthService, because handleAuthCallback
// treats every URL on this scheme as an auth callback and would
// otherwise show a spurious sign-in error for a lesson link.
// Supported formats:
//   com.paymentstraininghub.app://lesson?id=ch1s1
//   com.paymentstraininghub.app://lesson/ch1s1
//   com.paymentstraininghub.app://weekly-case
// A lesson link opens LessonView for that lesson. LessonView
// applies its existing gate, so a link to a lesson that is not
// the first lesson of its chapter shows the locked state, never
// free content: deep links never bypass gating. The builders
// below only generate lesson links for verified free sample
// lessons (the first lesson of a chapter, D77). A weekly-case
// link opens this week's free case; it takes no situation id,
// so a link can never be edited to open an arbitrary situation
// free. HTTPS lesson URLs are NOT handled: the app has no
// associated-domains setup, so a website link opens in the
// browser, never in the app.
// No em dashes in any user-facing text.

import Foundation
import Combine

// MARK: - Deep links

/// A deep link into the free experience: one lesson, or this
/// week's free payment case. Parsed from the app's custom scheme
/// only. Auth callbacks (host "auth-callback") and every other
/// host return nil, so the auth flow is untouched.
enum TrainingHubDeepLink: Hashable, Equatable {
    /// Open one lesson by catalogue id, for example "ch1s1".
    /// Routing applies the existing LessonView gate; only free
    /// sample lessons open with full content.
    case lesson(lessonID: String)
    /// Open this week's free payment case.
    case weeklyFreeCase

    /// The app's custom URL scheme, shared with Supabase Auth
    /// callbacks. The host is what tells the two apart.
    static var scheme: String { SupabaseConfig.authRedirectScheme }

    init?(url: URL) {
        guard url.scheme == Self.scheme,
              let host = url.host?.lowercased() else { return nil }
        switch host {
        case "lesson":
            guard let lessonID = Self.lessonID(from: url), !lessonID.isEmpty else { return nil }
            self = .lesson(lessonID: lessonID)
        case "weekly-case":
            self = .weeklyFreeCase
        default:
            // Includes "auth-callback" and every unknown host:
            // not a deep link, so the caller routes it elsewhere.
            return nil
        }
    }

    /// The lesson id from a lesson link: the ?id= query item first,
    /// then the first path component. The id must be one path-safe
    /// token (letters, digits, hyphen, underscore), which covers
    /// catalogue ids such as "ch1s1" and supplemental ids such as
    /// "ch1s901-supp", and rejects anything with a slash or a
    /// space. Whether the id names a real lesson is checked by
    /// the router against the loaded catalogue, not here.
    private static func lessonID(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let queryID = components?.queryItems?.first(where: { $0.name == "id" })?.value,
           isValidLessonID(queryID) {
            return queryID
        }
        let pathID = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard isValidLessonID(pathID) else { return nil }
        return pathID
    }

    private static func isValidLessonID(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// The URL for this deep link, in the documented format.
    var url: URL {
        switch self {
        case .lesson(let lessonID):
            var components = URLComponents()
            components.scheme = Self.scheme
            components.host = "lesson"
            components.queryItems = [URLQueryItem(name: "id", value: lessonID)]
            return components.url!
        case .weeklyFreeCase:
            var components = URLComponents()
            components.scheme = Self.scheme
            components.host = "weekly-case"
            return components.url!
        }
    }

    /// A lesson link for any lesson id. Callers that mean to share
    /// a free lesson must use sampleLessonURL instead, which
    /// refuses non-sample lessons.
    static func lessonURL(lessonID: String) -> URL? {
        guard isValidLessonID(lessonID) else { return nil }
        return TrainingHubDeepLink.lesson(lessonID: lessonID).url
    }

    /// A lesson link only when the entry is the first lesson of
    /// its chapter, the free sample lesson (D77). Nil for every
    /// other lesson and while the catalogue is still loading, so
    /// a shared link can never promise free access to a gated
    /// lesson. Gating itself is unchanged: LessonView still
    /// applies its own gate to whatever link arrives.
    static func sampleLessonURL(for entry: SearchEntry, in service: ContentService) -> URL? {
        guard PFChapterHelper.isSampleLesson(entry, in: service) else { return nil }
        return lessonURL(lessonID: entry.id)
    }

    /// The weekly-case link. It carries no situation id on purpose:
    /// the case is chosen deterministically for the current week,
    /// so the link always opens this week's free case and nothing
    /// else.
    static func weeklyCaseURL() -> URL {
        TrainingHubDeepLink.weeklyFreeCase.url
    }
}

/// Holds a deep link until MainTabView can route it. The link
/// arrives in TrainingHubApp.onOpenURL, which lives above the
/// tab view, so the router is the handoff: the app owns one
/// instance, MainTabView reads it, resolves the link against the
/// loaded catalogue, and clears it once routed.
@MainActor
final class TrainingHubDeepLinkRouter: ObservableObject {
    /// The link waiting to be routed, nil when none is pending.
    @Published private(set) var pendingLink: TrainingHubDeepLink? = nil

    /// Record an incoming link, replacing any link still waiting.
    /// The newest tap wins: a stale link must never open after a
    /// newer one.
    func receive(_ link: TrainingHubDeepLink) {
        pendingLink = link
    }

    /// Clear the pending link after routing, or after deciding it
    /// cannot be routed.
    func clear() {
        pendingLink = nil
    }
}

// MARK: - Referral invitations

/// One referral invitation: honest text plus links to the free
/// experience. No reward is offered, no invite code is generated,
/// and nothing is recorded anywhere: the text names only what is
/// actually free (the first lesson of each chapter, and one
/// payment case every week), and the links carry no tracking
/// parameters.
struct ReferralInvite: Hashable {
    /// What the invite points at.
    enum Kind: Hashable {
        /// This week's free payment case.
        case weeklyFreeCase
        /// One free sample lesson, by title.
        case sampleLesson(title: String)
    }

    let kind: Kind
    /// The website link, for recipients without the app. For a
    /// sample lesson this is the lesson page when the catalogue
    /// knows its path, otherwise the site home page.
    let webLink: URL
    /// The app deep link, for recipients who already have the app.
    let appLink: URL

    /// An invite to this week's free payment case.
    static func weeklyFreeCase() -> ReferralInvite {
        ReferralInvite(
            kind: .weeklyFreeCase,
            webLink: SupabaseConfig.siteBaseURL,
            appLink: TrainingHubDeepLink.weeklyCaseURL()
        )
    }

    /// An invite to one free sample lesson. The caller must have
    /// verified the lesson is the first lesson of its chapter
    /// (see TrainingHubDeepLink.sampleLessonURL): this factory
    /// trusts the caller and never checks the catalogue itself.
    /// `websitePath` is the catalogue entry's url path, when the
    /// catalogue knows one; empty or nil falls back to the site
    /// home page.
    static func sampleLesson(lessonID: String, title: String, websitePath: String?) -> ReferralInvite? {
        guard let appLink = TrainingHubDeepLink.lessonURL(lessonID: lessonID) else { return nil }
        let trimmedPath = (websitePath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let webLink: URL
        if trimmedPath.isEmpty {
            webLink = SupabaseConfig.siteBaseURL
        } else {
            webLink = SupabaseConfig.siteBaseURL.appendingPathComponent(trimmedPath)
        }
        return ReferralInvite(kind: .sampleLesson(title: title), webLink: webLink, appLink: appLink)
    }

    /// An invite to one free sample lesson, from its catalogue
    /// entry. Same caller-verifies rule as the id-based factory.
    static func sampleLesson(entry: SearchEntry) -> ReferralInvite? {
        sampleLesson(lessonID: entry.id, title: entry.title, websitePath: entry.url)
    }

    /// The subject line for a mailed invite.
    var subject: String {
        switch kind {
        case .weeklyFreeCase:
            return "This week's free payment case"
        case .sampleLesson:
            return "A free payments lesson worth a look"
        }
    }

    /// The invite text, as shared. It names only the free
    /// experience, promises no reward, and links to the website
    /// so it works for anyone, with or without the app.
    var inviteText: String {
        switch kind {
        case .weeklyFreeCase:
            return [
                "Payments Training Hub shares one real payment case free every week.",
                "This week's case is free to open, no purchase needed.",
                "Have a look: \(webLink.absoluteString)"
            ].joined(separator: "\n")
        case .sampleLesson(let title):
            return [
                "I am learning payments with Payments Training Hub.",
                "The first lesson of each chapter is free to open, with the full content. This one is \"\(title)\".",
                "Have a look: \(webLink.absoluteString)"
            ].joined(separator: "\n")
        }
    }

    /// The text handed to the share sheet: the invite text, which
    /// already carries the website link.
    var shareText: String { inviteText }

    /// Post text for sharing the invite on LinkedIn. The learner
    /// pastes this into their own post: LinkedIn does not accept
    /// post text through a share link, so nothing here claims the
    /// text is posted automatically. No statistics, no
    /// testimonials, no participation numbers.
    var linkedInText: String {
        switch kind {
        case .weeklyFreeCase:
            return [
                "Payments Training Hub shares one real payment case free every week.",
                "This week's case is free to open, no purchase needed.",
                webLink.absoluteString
            ].joined(separator: "\n\n")
        case .sampleLesson(let title):
            return [
                "Learning payments with Payments Training Hub. The first lesson of each chapter is free to open, with the full content.",
                "Starting with: \(title)",
                webLink.absoluteString
            ].joined(separator: "\n\n")
        }
    }
}

// MARK: - LinkedIn share links

/// LinkedIn share-offsite links. The link opens LinkedIn's share
/// composer with the given URL attached; LinkedIn ignores any
/// text parameter, so the learner pastes the post text
/// themselves. This helper builds the link only: it never posts,
/// never opens the LinkedIn app on its own, and never claims a
/// post was made.
enum LinkedInShare {
    /// The LinkedIn share-offsite URL for one link, for example a
    /// certificate verification URL or the site home page.
    static func shareOffsiteURL(for url: URL) -> URL? {
        var components = URLComponents(string: "https://www.linkedin.com/sharing/share-offsite/")
        components?.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        return components?.url
    }
}

// MARK: - Weekly free case selection

/// Picks this week's free payment case, deterministically: the
/// same week and the same list always pick the same case, on
/// every device, with no server and no stored rotation.
///
/// The primary list is the dedicated 52-case weekly list, in
/// week order. The pick is the week ordinal (ISO year times 53
/// plus ISO week) modulo 52, so the cases come one after the
/// other, one per week, changing on Monday, and the cycle runs
/// continuously across year boundaries: it does not reset on
/// 1 January, and a 53-week ISO year simply advances the ordinal
/// by one more week, so the next case in the sequence follows.
/// After 52 weeks the cycle wraps to the first case again. The
/// same function also serves the catalogue fallback, with the
/// same ordinal modulo the catalogue length, for the weeks when
/// the weekly list has not loaded. Two honest limits: the pick
/// depends on the order of the ids passed in, so callers must
/// always pass a stable order (weekly list in week order, or
/// catalogue order: full data first, search index fallback, the
/// same order SituationsView shows); and when the fallback
/// catalogue grows, later weeks may pick different cases than
/// they would have before, because the list length changed.
/// Neither limit invents a case: the pick is always one real id
/// from the list passed in, or nil when the list is empty.
enum WeeklyFreeCaseSelector {
    /// The week key for a date, for example "2026-W46": the ISO
    /// year for the week plus the ISO week number. Used as the
    /// storage key for the opened marker, so one marker per week.
    static func weekKey(for date: Date, calendar: Calendar = Calendar(identifier: .iso8601)) -> String {
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return String(format: "%d-W%02d", year, week)
    }

    /// The index picked for a week, or nil when the list is empty.
    /// The week ordinal (ISO year times 53 plus ISO week) modulo
    /// the list length. Over the 52-case weekly list this is
    /// (ISO year times 53 plus ISO week) mod 52: one case per
    /// week in continuous sequence across year boundaries,
    /// wrapping after 52 weeks. Stable for a fixed list, and it
    /// advances by one each week until it wraps.
    static func index(for date: Date, count: Int, calendar: Calendar = Calendar(identifier: .iso8601)) -> Int? {
        guard count > 0 else { return nil }
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        let ordinal = year * 53 + week
        return ordinal % count
    }

    /// The situation id picked for a week, from ids in catalogue
    /// order. Nil when the list is empty.
    static func situationID(from ids: [String], on date: Date, calendar: Calendar = Calendar(identifier: .iso8601)) -> String? {
        guard let picked = index(for: date, count: ids.count, calendar: calendar) else { return nil }
        return ids[picked]
    }

    /// The Monday to Sunday range of the week containing a date,
    /// for the "this week" label. Nil only when the calendar
    /// cannot form a week interval.
    static func weekRange(for date: Date, calendar: Calendar = Calendar(identifier: .iso8601)) -> (start: Date, end: Date)? {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return nil }
        let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return (start: interval.start, end: end)
    }

    /// The label for the week containing a date, for example
    /// "Week of 9 Nov 2026". Built from the week start only, so it
    /// never depends on the device time zone shifting the end date.
    static func weekLabel(for date: Date, calendar: Calendar = Calendar(identifier: .iso8601)) -> String {
        guard let range = weekRange(for: date, calendar: calendar) else {
            return "This week"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Week of \(formatter.string(from: range.start))"
    }
}
