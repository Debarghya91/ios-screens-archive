// GrowthShareTests.swift
// PaymentForge iOS - Phase 4 unit tests: deep links, referral
// invitations, the weekly free case selector, achievement share
// content, and the weekly opened marker's account namespacing.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only.
//
// No test loads the catalogue, so catalogue-dependent behaviour is
// asserted as invariants that hold for any catalogue state, never
// as specific lesson picks, except the empty-catalogue invariant
// for sample lesson links (no test in this target loads the
// catalogue). setUp and tearDown pin dedicated namespaces and
// clear them, so no test leaks markers into another test.

import XCTest
@testable import PaymentForge

@MainActor
final class GrowthShareTests: XCTestCase {

    private let namespace = "test-growth-share"
    private let otherNamespace = "test-growth-share-other"

    override func setUp() {
        super.setUp()
        AccountScopedStorage.setCurrentNamespace(namespace)
        AccountScopedStorage.removeAllKeys(in: namespace)
        AccountScopedStorage.removeAllKeys(in: otherNamespace)
    }

    override func tearDown() {
        AccountScopedStorage.removeAllKeys(in: namespace)
        AccountScopedStorage.removeAllKeys(in: otherNamespace)
        AccountScopedStorage.setCurrentNamespace(nil)
        super.tearDown()
    }

    // MARK: - Helpers

    private var isoCalendar: Calendar { Calendar(identifier: .iso8601) }

    private func date(year: Int, month: Int, day: Int) -> Date {
        isoCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func samplePathCertificate(score: Double? = 82) -> PFCertificate {
        PFCertificate(
            id: "PF-FUNDAMENTALS-ABC12345",
            pathID: "fundamentals",
            pathTitle: "Payments Fundamentals",
            learnerName: "Test Learner",
            issuedAt: Date(timeIntervalSince1970: 1_793_000_000),
            overallScore: score
        )
    }

    private func sampleCourseCertificate() -> CourseCertificate {
        CourseCertificate(
            id: "PF-FULL-DEF67890",
            courseID: "com.paymentforge.app.full",
            courseName: "Digital Payments and Transaction Banking",
            learnerName: "Test Learner",
            issuedAt: Date(timeIntervalSince1970: 1_793_000_000),
            correctCount: 18,
            totalQuestions: 20
        )
    }

    // MARK: - Deep links

    func testLessonLinkQueryFormParses() {
        let link = PaymentForgeDeepLink(url: URL(string: "com.paymentforge.app://lesson?id=ch1s1")!)
        XCTAssertEqual(link, .lesson(lessonID: "ch1s1"))
    }

    func testLessonLinkPathFormParses() {
        let link = PaymentForgeDeepLink(url: URL(string: "com.paymentforge.app://lesson/ch1s1")!)
        XCTAssertEqual(link, .lesson(lessonID: "ch1s1"))
    }

    func testLessonLinkAcceptsSupplementalIDs() {
        let link = PaymentForgeDeepLink(url: URL(string: "com.paymentforge.app://lesson?id=ch1s901-supp")!)
        XCTAssertEqual(link, .lesson(lessonID: "ch1s901-supp"))
    }

    func testLessonLinkRoundTrips() {
        let link = PaymentForgeDeepLink.lesson(lessonID: "ch27s9")
        XCTAssertEqual(PaymentForgeDeepLink(url: link.url), link)
        XCTAssertEqual(link.url.absoluteString, "com.paymentforge.app://lesson?id=ch27s9")
    }

    func testWeeklyCaseLinkParses() {
        let link = PaymentForgeDeepLink(url: URL(string: "com.paymentforge.app://weekly-case")!)
        XCTAssertEqual(link, .weeklyFreeCase)
    }

    func testWeeklyCaseLinkRoundTrips() {
        let link = PaymentForgeDeepLink.weeklyFreeCase
        XCTAssertEqual(PaymentForgeDeepLink(url: link.url), link)
        XCTAssertEqual(link.url.absoluteString, "com.paymentforge.app://weekly-case")
    }

    func testWeeklyCaseLinkCarriesNoSituationID() {
        let url = PaymentForgeDeepLink.weeklyCaseURL()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.queryItems ?? [], [])
    }

    func testAuthCallbackIsNotADeepLink() {
        XCTAssertNil(PaymentForgeDeepLink(url: URL(string: "com.paymentforge.app://auth-callback?code=abc123")!))
        XCTAssertNil(PaymentForgeDeepLink(url: URL(string: "com.paymentforge.app://auth-callback#access_token=x&refresh_token=y")!))
    }

    func testUnknownHostIsNotADeepLink() {
        XCTAssertNil(PaymentForgeDeepLink(url: URL(string: "com.paymentforge.app://settings")!))
        XCTAssertNil(PaymentForgeDeepLink(url: URL(string: "com.paymentforge.app://certificate?id=PF-1")!))
    }

    func testWrongSchemeIsNotADeepLink() {
        XCTAssertNil(PaymentForgeDeepLink(url: URL(string: "https://www.paymentstraininghub.com/lessons/ch1s1")!))
        XCTAssertNil(PaymentForgeDeepLink(url: URL(string: "otherapp://lesson?id=ch1s1")!))
    }

    func testLessonLinkWithoutIDIsRejected() {
        XCTAssertNil(PaymentForgeDeepLink(url: URL(string: "com.paymentforge.app://lesson")!))
        XCTAssertNil(PaymentForgeDeepLink(url: URL(string: "com.paymentforge.app://lesson/")!))
        XCTAssertNil(PaymentForgeDeepLink(url: URL(string: "com.paymentforge.app://lesson?id=")!))
    }

    func testLessonLinkRejectsUnsafeIDs() {
        XCTAssertNil(PaymentForgeDeepLink(url: URL(string: "com.paymentforge.app://lesson?id=ch1s1%20x")!))
        XCTAssertNil(PaymentForgeDeepLink(url: URL(string: "com.paymentforge.app://lesson?id=ch1s1/x")!))
        XCTAssertNil(PaymentForgeDeepLink.lessonURL(lessonID: "bad id!"))
        XCTAssertNil(PaymentForgeDeepLink.lessonURL(lessonID: ""))
    }

    func testSampleLessonURLIsNilWithoutCatalogue() {
        // No test loads the catalogue, so no entry can be verified
        // as the first lesson of its chapter: the builder refuses.
        let entry = SearchEntry(
            id: "ch1s1",
            title: "What a payment is",
            url: "/lessons/ch1s1",
            type: .lesson,
            text: "What a payment is"
        )
        XCTAssertNil(ContentService.shared.searchIndex)
        XCTAssertNil(PaymentForgeDeepLink.sampleLessonURL(for: entry, in: ContentService.shared))
    }

    // MARK: - Deep-link router

    func testRouterReceiveAndClear() {
        let router = PaymentForgeDeepLinkRouter()
        XCTAssertNil(router.pendingLink)
        router.receive(.weeklyFreeCase)
        XCTAssertEqual(router.pendingLink, .weeklyFreeCase)
        router.receive(.lesson(lessonID: "ch1s1"))
        XCTAssertEqual(router.pendingLink, .lesson(lessonID: "ch1s1"))
        router.clear()
        XCTAssertNil(router.pendingLink)
    }

    // MARK: - Referral invitations

    func testWeeklyInviteTextHasNoRewardLanguage() {
        let invite = ReferralInvite.weeklyFreeCase()
        let lower = invite.inviteText.lowercased()
        for forbidden in ["reward", "bonus", "discount", "earn", "credit", "invite code", "referral code"] {
            XCTAssertFalse(lower.contains(forbidden), "Invite text must not promise: \(forbidden)")
        }
        XCTAssertTrue(invite.inviteText.contains("free to open"))
        XCTAssertTrue(invite.inviteText.contains(SupabaseConfig.siteBaseURL.absoluteString))
    }

    func testSampleLessonInviteNamesLessonAndFreeAccess() {
        let invite = ReferralInvite.sampleLesson(lessonID: "ch1s1", title: "What a payment is", websitePath: "/lessons/ch1s1")
        XCTAssertNotNil(invite)
        XCTAssertTrue(invite!.inviteText.contains("What a payment is"))
        XCTAssertTrue(invite!.inviteText.contains("free to open"))
        XCTAssertEqual(PaymentForgeDeepLink(url: invite!.appLink), .lesson(lessonID: "ch1s1"))
    }

    func testSampleLessonInviteFallsBackToSiteHomeForEmptyPath() {
        let invite = ReferralInvite.sampleLesson(lessonID: "ch1s1", title: "What a payment is", websitePath: "")
        XCTAssertEqual(invite?.webLink, SupabaseConfig.siteBaseURL)
        let nilPath = ReferralInvite.sampleLesson(lessonID: "ch1s1", title: "What a payment is", websitePath: nil)
        XCTAssertEqual(nilPath?.webLink, SupabaseConfig.siteBaseURL)
    }

    func testSampleLessonInviteRejectsInvalidLessonID() {
        XCTAssertNil(ReferralInvite.sampleLesson(lessonID: "bad id!", title: "Title", websitePath: nil))
    }

    func testInviteLinksCarryNoTrackingParameters() {
        let invites = [
            ReferralInvite.weeklyFreeCase(),
            ReferralInvite.sampleLesson(lessonID: "ch1s1", title: "Title", websitePath: "/lessons/ch1s1")!
        ]
        for invite in invites {
            for link in [invite.webLink, invite.appLink] {
                let query = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems ?? []
                for item in query {
                    XCTAssertFalse(item.name.hasPrefix("utm_"), "No tracking parameters: \(item.name)")
                    XCTAssertNotEqual(item.name, "ref")
                }
            }
            XCTAssertFalse(invite.shareText.contains("utm_"))
        }
    }

    func testLinkedInShareOffsiteURLWrapsGivenURL() {
        let target = URL(string: "https://www.paymentstraininghub.com/verify?id=PF-1")!
        let shared = LinkedInShare.shareOffsiteURL(for: target)
        XCTAssertNotNil(shared)
        let query = URLComponents(url: shared!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first(where: { $0.name == "url" })?.value, target.absoluteString)
    }

    func testNoEmDashInInviteOrLinkedInText() {
        let invite = ReferralInvite.weeklyFreeCase()
        for text in [invite.subject, invite.inviteText, invite.shareText, invite.linkedInText] {
            XCTAssertFalse(text.contains("\u{2014}"), "No em dashes: \(text)")
        }
    }

    // MARK: - Weekly free case selector

    func testWeekKeyGroupsMondayToSunday() {
        // 9 Nov 2026 is a Monday, 15 Nov 2026 the following Sunday,
        // 16 Nov 2026 the next Monday.
        let monday = date(year: 2026, month: 11, day: 9)
        let sunday = date(year: 2026, month: 11, day: 15)
        let nextMonday = date(year: 2026, month: 11, day: 16)
        let key = WeeklyFreeCaseSelector.weekKey(for: monday)
        XCTAssertEqual(WeeklyFreeCaseSelector.weekKey(for: sunday), key)
        XCTAssertNotEqual(WeeklyFreeCaseSelector.weekKey(for: nextMonday), key)
        XCTAssertTrue(key.hasPrefix("2026-W"))
        XCTAssertEqual(key.count, "2026-W46".count)
    }

    func testSelectionIsDeterministic() {
        let ids = ["A", "B", "C", "D", "E"]
        let day = date(year: 2026, month: 11, day: 12)
        let first = WeeklyFreeCaseSelector.situationID(from: ids, on: day)
        let second = WeeklyFreeCaseSelector.situationID(from: ids, on: day)
        XCTAssertEqual(first, second)
        XCTAssertNotNil(first)
        XCTAssertTrue(ids.contains(first!))
    }

    func testSelectionStaysInBoundsAcrossAFullYear() {
        for count in [1, 2, 5, 6, 100, 564] {
            let ids = (0..<count).map { "ID-\($0)" }
            var seen: Set<String> = []
            for weekOffset in 0..<52 {
                let day = isoCalendar.date(byAdding: .weekOfYear, value: weekOffset, to: date(year: 2026, month: 1, day: 5))!
                let picked = WeeklyFreeCaseSelector.situationID(from: ids, on: day)
                XCTAssertNotNil(picked)
                XCTAssertTrue(ids.contains(picked!))
                seen.insert(picked!)
            }
            // The pick walks the list: over a year it visits more
            // than one case whenever the list has more than one.
            if count > 1 {
                XCTAssertGreaterThan(seen.count, 1)
            }
        }
    }

    func testSelectionEmptyListIsNil() {
        XCTAssertNil(WeeklyFreeCaseSelector.situationID(from: [], on: Date()))
        XCTAssertNil(WeeklyFreeCaseSelector.index(for: Date(), count: 0))
    }

    func testSelectionSingleItemAlwaysPicksIt() {
        XCTAssertEqual(WeeklyFreeCaseSelector.situationID(from: ["ONLY"], on: Date()), "ONLY")
        XCTAssertEqual(WeeklyFreeCaseSelector.index(for: Date(), count: 1), 0)
    }

    func testWeekRangeStartsMondayEndsSundayAndContainsDate() {
        let day = date(year: 2026, month: 11, day: 12)
        let range = WeeklyFreeCaseSelector.weekRange(for: day)
        XCTAssertNotNil(range)
        XCTAssertEqual(isoCalendar.component(.weekday, from: range!.start), 2, "ISO weeks start on Monday.")
        XCTAssertEqual(isoCalendar.component(.weekday, from: range!.end), 1, "ISO weeks end on Sunday.")
        XCTAssertLessThanOrEqual(range!.start, day)
        XCTAssertGreaterThanOrEqual(isoCalendar.date(byAdding: .day, value: 1, to: range!.end)!, day)
    }

    func testWeekLabelIsStableWithinAWeek() {
        let monday = date(year: 2026, month: 11, day: 9)
        let thursday = date(year: 2026, month: 11, day: 12)
        let label = WeeklyFreeCaseSelector.weekLabel(for: monday)
        XCTAssertEqual(label, WeeklyFreeCaseSelector.weekLabel(for: thursday))
        XCTAssertTrue(label.hasPrefix("Week of "))
    }

    // MARK: - Achievement share content

    func testPathCertificateContentUsesOnlyPassedData() {
        let certificate = samplePathCertificate(score: 82)
        let content = AchievementShareContent.pathCertificate(certificate)
        XCTAssertEqual(content.kind, .certificate)
        XCTAssertEqual(content.title, "Payments Fundamentals")
        XCTAssertEqual(content.learnerName, "Test Learner")
        XCTAssertEqual(content.certificateID, "PF-FUNDAMENTALS-ABC12345")
        XCTAssertEqual(content.scoreLine, "Overall score: 82%")
        XCTAssertEqual(content.verificationURL, certificate.verificationURL)
        XCTAssertTrue(content.shareText.contains("PF-FUNDAMENTALS-ABC12345"))
        XCTAssertTrue(content.shareText.contains("Overall score: 82%"))
        XCTAssertTrue(content.shareText.contains(certificate.verificationURL.absoluteString))
    }

    func testPathCertificateWithoutScoreShowsNoScore() {
        let content = AchievementShareContent.pathCertificate(samplePathCertificate(score: nil))
        XCTAssertNil(content.scoreLine)
        XCTAssertFalse(content.shareText.contains("score"))
        XCTAssertFalse(content.shareText.contains("%"))
    }

    func testCourseCertificateContentUsesOnlyPassedData() {
        let certificate = sampleCourseCertificate()
        let content = AchievementShareContent.courseCertificate(certificate)
        XCTAssertEqual(content.title, "Digital Payments and Transaction Banking")
        XCTAssertEqual(content.scoreLine, "Score: 18/20 (90%)")
        XCTAssertEqual(content.certificateID, "PF-FULL-DEF67890")
        XCTAssertTrue(content.shareText.contains("Score: 18/20 (90%)"))
        XCTAssertTrue(content.linkedInText.contains("Digital Payments and Transaction Banking"))
    }

    func testCertificateContentCarriesDisclaimerAndNoAccreditationClaim() {
        for content in [
            AchievementShareContent.pathCertificate(samplePathCertificate()),
            AchievementShareContent.courseCertificate(sampleCourseCertificate())
        ] {
            for text in [content.shareText, content.linkedInText] {
                XCTAssertTrue(text.contains("not an accredited qualification"))
                XCTAssertFalse(text.lowercased().contains("server-issued"))
                XCTAssertFalse(text.lowercased().contains("regulated qualification"))
                XCTAssertFalse(text.lowercased().contains("bank endorsement"))
                XCTAssertFalse(text.lowercased().contains("endorsed by"))
                let accreditedCount = text.components(separatedBy: "accredited").count - 1
                XCTAssertEqual(accreditedCount, 1, "The only accreditation mention is the disclaimer.")
            }
        }
    }

    func testContentWithoutCertificateShowsNoVerification() {
        let content = AchievementShareContent.pathCompletion(
            pathTitle: "Payments Fundamentals",
            lessonCount: 24,
            earnedOn: Date(timeIntervalSince1970: 1_793_000_000),
            learnerName: "Test Learner"
        )
        XCTAssertEqual(content.kind, .pathCompletion)
        XCTAssertNil(content.certificateID)
        XCTAssertNil(content.verificationURL)
        XCTAssertNil(content.scoreLine)
        XCTAssertFalse(content.shareText.contains("Certificate ID"))
        XCTAssertFalse(content.shareText.contains("Verify at"))
        XCTAssertFalse(content.shareText.contains("http"))
        XCTAssertFalse(content.shareText.contains("%"))
        XCTAssertTrue(content.shareText.contains("24 lessons completed"))
    }

    func testChallengeContentUsesCallerData() {
        let content = AchievementShareContent.challengeCompletion(
            title: "Investigate the stuck pacs.008",
            detail: "Exception Lab case completed",
            completedOn: Date(timeIntervalSince1970: 1_793_000_000),
            learnerName: nil
        )
        XCTAssertEqual(content.kind, .challengeCompletion)
        XCTAssertEqual(content.kind.heading, "Challenge completed")
        XCTAssertTrue(content.shareText.contains("Investigate the stuck pacs.008"))
        XCTAssertTrue(content.shareText.contains("Exception Lab case completed"))
        XCTAssertTrue(content.linkedInText.contains("Investigate the stuck pacs.008"))
        XCTAssertFalse(content.shareText.contains("Earned by"))
    }

    func testAssessmentPassContentPreservesScoreLine() {
        let content = AchievementShareContent.assessmentPass(
            courseName: "Global Payment Rails",
            scoreLine: "Score: 16/20 (80%)",
            passedOn: Date(timeIntervalSince1970: 1_793_000_000),
            learnerName: "Test Learner"
        )
        XCTAssertEqual(content.kind, .assessmentPass)
        XCTAssertEqual(content.scoreLine, "Score: 16/20 (80%)")
        XCTAssertNil(content.certificateID)
        XCTAssertTrue(content.shareText.contains("Final Assessment passed"))
        XCTAssertTrue(content.shareText.contains("Score: 16/20 (80%)"))
    }

    func testKindHeadingsAreDistinct() {
        let headings = [
            AchievementKind.pathCompletion.heading,
            AchievementKind.challengeCompletion.heading,
            AchievementKind.assessmentPass.heading,
            AchievementKind.certificate.heading
        ]
        XCTAssertEqual(Set(headings).count, 4)
        XCTAssertTrue(headings.allSatisfy { !$0.isEmpty })
    }

    func testNoEmDashInShareTexts() {
        let contents = [
            AchievementShareContent.pathCertificate(samplePathCertificate()),
            AchievementShareContent.courseCertificate(sampleCourseCertificate()),
            AchievementShareContent.pathCompletion(pathTitle: "Title", lessonCount: 3, earnedOn: Date(), learnerName: nil),
            AchievementShareContent.challengeCompletion(title: "Title", detail: nil, completedOn: Date(), learnerName: nil),
            AchievementShareContent.assessmentPass(courseName: "Title", scoreLine: "Score: 15/20 (75%)", passedOn: Date(), learnerName: nil)
        ]
        for content in contents {
            XCTAssertFalse(content.shareText.contains("\u{2014}"))
            XCTAssertFalse(content.linkedInText.contains("\u{2014}"))
            XCTAssertFalse(content.accessibilityLabel.contains("\u{2014}"))
        }
    }

    // MARK: - Weekly opened marker namespacing

    func testOpenedMarkerIsNamespacedPerAccount() {
        let store = WeeklyFreeCaseStore()
        store.markOpened(weekKey: "2026-W46", situationID: "ABH-01")
        XCTAssertTrue(store.hasOpened(weekKey: "2026-W46"))
        XCTAssertEqual(store.openedSituationID(forWeekKey: "2026-W46"), "ABH-01")

        AccountScopedStorage.setCurrentNamespace(otherNamespace)
        let otherStore = WeeklyFreeCaseStore()
        XCTAssertFalse(otherStore.hasOpened(weekKey: "2026-W46"))
        XCTAssertNil(otherStore.openedSituationID(forWeekKey: "2026-W46"))

        AccountScopedStorage.setCurrentNamespace(namespace)
        let backStore = WeeklyFreeCaseStore()
        XCTAssertTrue(backStore.hasOpened(weekKey: "2026-W46"))
        XCTAssertEqual(backStore.openedSituationID(forWeekKey: "2026-W46"), "ABH-01")
    }

    func testMarkOpenedIgnoresEmptyKeys() {
        let store = WeeklyFreeCaseStore()
        store.markOpened(weekKey: "", situationID: "ABH-01")
        store.markOpened(weekKey: "2026-W46", situationID: "")
        XCTAssertTrue(store.openedByWeek.isEmpty)
    }

    func testReloadClearsPreviousAccountMarkers() {
        let store = WeeklyFreeCaseStore()
        store.markOpened(weekKey: "2026-W46", situationID: "ABH-01")
        XCTAssertFalse(store.openedByWeek.isEmpty)
        AccountScopedStorage.setCurrentNamespace(otherNamespace)
        store.reloadForCurrentAccount()
        XCTAssertTrue(store.openedByWeek.isEmpty)
    }
}
