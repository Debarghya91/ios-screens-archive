// CommunityChallengeTests.swift
// PaymentForge iOS - Phase 4 tests: the weekly community challenge
// (CommunityChallenge.swift). Covers deterministic weekly selection
// from the existing lab catalogue, week boundaries, share text, the
// account-namespaced attempt store, and the honest empty
// leaderboard. Model and store logic only; no view tests.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the implementation files before writing.
//
// The store base key below mirrors the private key constant in
// CommunityChallengeStore and must be kept in step with that file,
// the same mirroring pattern Phase3ExceptionLabTests uses.

import XCTest
@testable import PaymentForge

@MainActor
final class CommunityChallengeTests: XCTestCase {

    private let namespaceA = "test-community-challenge-a"
    private let namespaceB = "test-community-challenge-b"
    private let attemptsBaseKey = "pf.communityChallengeAttempts.v1"

    override func setUp() {
        super.setUp()
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        UserDefaults.standard.removeObject(forKey: attemptsBaseKey)
        AccountScopedStorage.removeAllKeys(in: namespaceA)
        AccountScopedStorage.removeAllKeys(in: namespaceB)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: attemptsBaseKey)
        AccountScopedStorage.removeAllKeys(in: namespaceA)
        AccountScopedStorage.removeAllKeys(in: namespaceB)
        AccountScopedStorage.setCurrentNamespace(nil)
        super.tearDown()
    }

    // MARK: - Fixtures

    /// Noon UTC on a calendar date, so the ISO week is the same
    /// whatever the test host's time zone.
    private func utcDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
            ?? Date(timeIntervalSince1970: 0)
    }

    /// A perfect breakdown for the first catalogue case: every step
    /// solved best-first, no wrong turns, every genuine evidence
    /// item opened. Total equals the maximum.
    private func perfectBreakdown() -> ExceptionLabScoreBreakdown {
        let exceptionCase = ExceptionCaseCatalogue.allCases[0]
        let results = exceptionCase.steps.map {
            ExceptionStepResult(stepID: $0.id, wrongPicks: 0, redHerringPicks: 0, solved: true)
        }
        let genuineIDs = Set(exceptionCase.evidence.filter { !$0.isRedHerring }.map { $0.id })
        return ExceptionLabScoring.breakdown(
            for: exceptionCase,
            stepResults: results,
            evidenceOpenedIDs: genuineIDs
        )
    }

    /// A poor breakdown for the first catalogue case: every step
    /// solved after two wrong turns, no evidence opened. Total is
    /// below the maximum and never below zero.
    private func poorBreakdown() -> ExceptionLabScoreBreakdown {
        let exceptionCase = ExceptionCaseCatalogue.allCases[0]
        let results = exceptionCase.steps.map {
            ExceptionStepResult(stepID: $0.id, wrongPicks: 2, redHerringPicks: 0, solved: true)
        }
        return ExceptionLabScoring.breakdown(
            for: exceptionCase,
            stepResults: results,
            evidenceOpenedIDs: []
        )
    }

    // MARK: - Week keys and boundaries

    func testWeekKeyForKnownDate() {
        // 12 Nov 2026 is a Thursday in ISO week 46 of 2026.
        XCTAssertEqual(CommunityChallenge.weekKey(for: utcDate(year: 2026, month: 11, day: 12)), "2026-W46")
    }

    func testWeekKeyZeroPadsSingleDigitWeeks() {
        // 1 Jan 2026 is in ISO week 1 of 2026.
        XCTAssertEqual(CommunityChallenge.weekKey(for: utcDate(year: 2026, month: 1, day: 1)), "2026-W01")
    }

    func testEveryDayOfOneWeekSharesKeyAndCase() {
        let days = (9...15).map { utcDate(year: 2026, month: 11, day: $0) }
        let keys = Set(days.map { CommunityChallenge.weekKey(for: $0) })
        XCTAssertEqual(keys, ["2026-W46"])
        let caseIDs = Set(days.compactMap { CommunityChallenge.caseFor(date: $0)?.id })
        XCTAssertEqual(caseIDs.count, 1)
    }

    func testWeekStartIsMondayAndWeekEndIsSunday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        let date = utcDate(year: 2026, month: 11, day: 12)
        let start = CommunityChallenge.weekStart(for: date)
        let end = CommunityChallenge.weekEnd(for: date)
        XCTAssertNotNil(start)
        XCTAssertNotNil(end)
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: start ?? date), DateComponents(year: 2026, month: 11, day: 9))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: end ?? date), DateComponents(year: 2026, month: 11, day: 15))
        XCTAssertEqual(calendar.component(.weekday, from: start ?? date), 2)
        XCTAssertEqual(calendar.component(.weekday, from: end ?? date), 1)
    }

    func testWeekOrdinalIncrementsByOneEachWeek() {
        let monday = utcDate(year: 2026, month: 11, day: 9)
        let nextMonday = utcDate(year: 2026, month: 11, day: 16)
        XCTAssertEqual(
            CommunityChallenge.weekOrdinal(for: nextMonday),
            CommunityChallenge.weekOrdinal(for: monday) + 1
        )
    }

    func testWeekKeyFormat() {
        let key = CommunityChallenge.weekKey(for: utcDate(year: 2026, month: 11, day: 12))
        let parts = key.split(separator: "-")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].count, 4)
        XCTAssertTrue(parts[1].hasPrefix("W"))
        let week = Int(parts[1].dropFirst()) ?? 0
        XCTAssertTrue((1...53).contains(week))
    }

    // MARK: - Case selection

    func testKnownWeekSelectsFirstCatalogueCase() {
        // Ordinal 2026 x 53 + 46 = 107424, divisible by the 12-case
        // catalogue, so week 2026-W46 selects allCases[0].
        let selected = CommunityChallenge.caseFor(date: utcDate(year: 2026, month: 11, day: 12))
        XCTAssertEqual(selected?.id, ExceptionCaseCatalogue.allCases[0].id)
        XCTAssertEqual(selected?.id, "lab-abh-01")
    }

    func testTwelveConsecutiveWeeksVisitEveryCaseExactlyOnce() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        let firstMonday = utcDate(year: 2026, month: 11, day: 9)
        var seen: [String] = []
        for offset in 0..<12 {
            let monday = calendar.date(byAdding: .day, value: offset * 7, to: firstMonday) ?? firstMonday
            if let selected = CommunityChallenge.caseFor(date: monday) {
                seen.append(selected.id)
            }
        }
        XCTAssertEqual(seen.count, 12)
        XCTAssertEqual(Set(seen), Set(ExceptionCaseCatalogue.allCases.map { $0.id }))
    }

    func testSelectionNeverInventsACase() {
        let catalogueIDs = Set(ExceptionCaseCatalogue.allCases.map { $0.id })
        for ordinal in 0..<60 {
            let selected = CommunityChallenge.caseForWeek(ordinal: ordinal)
            XCTAssertNotNil(selected)
            XCTAssertTrue(catalogueIDs.contains(selected?.id ?? ""))
        }
    }

    func testExceptionCaseLookupByID() {
        XCTAssertEqual(CommunityChallenge.exceptionCase(forID: "lab-abh-01")?.title, ExceptionCaseCatalogue.allCases[0].title)
        XCTAssertNil(CommunityChallenge.exceptionCase(forID: "no-such-case"))
    }

    func testFourCasesAreGroundedInFreeSamples() {
        // ABH-01, JEB-C01, ABH-03 and SCN-21 are the free-sample
        // situations with lab cases; those four weeks are open to
        // all, and the other eight follow the lab gate.
        let open = ExceptionCaseCatalogue.allCases.filter { !$0.requiresSituationsUnlock }
        XCTAssertEqual(open.count, 4)
        XCTAssertEqual(
            Set(open.compactMap { $0.sourceSituationID }),
            ["ABH-01", "JEB-C01", "ABH-03", "SCN-21"]
        )
    }

    // MARK: - Share text

    func testShareTextNamesWeekTitleAndScoreOnly() {
        let text = CommunityChallenge.shareText(
            weekKey: "2026-W46",
            caseTitle: "Test case title",
            total: 42,
            maximum: 58
        )
        XCTAssertTrue(text.contains("2026-W46"))
        XCTAssertTrue(text.contains("Test case title"))
        XCTAssertTrue(text.contains("42 out of 58"))
        XCTAssertFalse(text.contains("@"))
        // No em dash (U+2014): asserted via scalar so the test file
        // itself never contains the character.
        XCTAssertFalse(text.unicodeScalars.contains("\u{2014}"))
    }

    // MARK: - Scoring fixtures

    func testPerfectPlayReachesMaximum() {
        let breakdown = perfectBreakdown()
        XCTAssertEqual(breakdown.total, breakdown.maximum)
        XCTAssertGreaterThan(breakdown.maximum, 0)
    }

    func testPoorPlayScoresBelowMaximumAndNeverBelowZero() {
        let breakdown = poorBreakdown()
        XCTAssertLessThan(breakdown.total, breakdown.maximum)
        XCTAssertGreaterThanOrEqual(breakdown.total, 0)
    }

    // MARK: - Store

    func testRecordCompletionKeepsBestAndCountsCompletions() {
        let store = CommunityChallengeStore()
        let perfect = perfectBreakdown()
        let poor = poorBreakdown()
        store.recordCompletion(weekKey: "2026-W46", caseID: "lab-abh-01", breakdown: poor)
        store.recordCompletion(weekKey: "2026-W46", caseID: "lab-abh-01", breakdown: perfect)
        store.recordCompletion(weekKey: "2026-W46", caseID: "lab-abh-01", breakdown: poor)
        let attempt = store.attempt(forWeekKey: "2026-W46")
        XCTAssertNotNil(attempt)
        XCTAssertEqual(attempt?.bestTotal, perfect.total)
        XCTAssertEqual(attempt?.completions, 3)
        XCTAssertEqual(attempt?.lastBreakdown.total, poor.total)
        XCTAssertEqual(attempt?.id, "2026-W46")
        XCTAssertTrue(store.isCompleted(weekKey: "2026-W46"))
        XCTAssertFalse(store.isCompleted(weekKey: "2026-W47"))
    }

    func testPersonalBestPicksHighestTotal() {
        let store = CommunityChallengeStore()
        store.recordCompletion(weekKey: "2026-W46", caseID: "lab-abh-01", breakdown: poorBreakdown())
        store.recordCompletion(weekKey: "2026-W47", caseID: "lab-jeb-c01", breakdown: perfectBreakdown())
        XCTAssertEqual(store.personalBest?.weekKey, "2026-W47")
        XCTAssertEqual(store.completedWeekKeys, ["2026-W46", "2026-W47"])
    }

    func testPersonalBestIsNilBeforeAnyCompletion() {
        let store = CommunityChallengeStore()
        XCTAssertNil(store.personalBest)
        XCTAssertTrue(store.attempts.isEmpty)
    }

    func testLeaderboardHasNoCommunityData() {
        let store = CommunityChallengeStore()
        store.recordCompletion(weekKey: "2026-W46", caseID: "lab-abh-01", breakdown: perfectBreakdown())
        let board = store.leaderboard(forWeekKey: "2026-W46")
        XCTAssertEqual(board.weekKey, "2026-W46")
        XCTAssertTrue(board.communityEntries.isEmpty)
        XCTAssertFalse(board.hasCommunityData)
        XCTAssertEqual(board.personalBest?.weekKey, "2026-W46")
    }

    func testAttemptsAreNamespacedPerAccount() {
        let storeA = CommunityChallengeStore()
        storeA.recordCompletion(weekKey: "2026-W46", caseID: "lab-abh-01", breakdown: perfectBreakdown())
        XCTAssertEqual(storeA.attempts.count, 1)

        AccountScopedStorage.setCurrentNamespace(namespaceB)
        let storeB = CommunityChallengeStore()
        XCTAssertTrue(storeB.attempts.isEmpty)

        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let storeAAgain = CommunityChallengeStore()
        XCTAssertEqual(storeAAgain.attempts.count, 1)
    }

    func testReloadForCurrentAccountSwitchesNamespaces() {
        let store = CommunityChallengeStore()
        store.recordCompletion(weekKey: "2026-W46", caseID: "lab-abh-01", breakdown: perfectBreakdown())
        XCTAssertEqual(store.attempts.count, 1)

        AccountScopedStorage.setCurrentNamespace(namespaceB)
        store.reloadForCurrentAccount()
        XCTAssertTrue(store.attempts.isEmpty)

        AccountScopedStorage.setCurrentNamespace(namespaceA)
        store.reloadForCurrentAccount()
        XCTAssertEqual(store.attempts.count, 1)
    }
}
