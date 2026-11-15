// DailyChallengeGateTests.swift
// PaymentForge iOS - v70 tests: the Daily Challenge entitlement
// gate. Non-entitled learners see only the 6 free samples plus
// this week's free case; entitled learners see the full list
// unchanged. No locked explain or takeaway text may surface
// through the gated pool.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the final app source before writing.
//
// No network and no store: the tests exercise only the pure static
// gate, DailyChallengeView.eligiblePool, over fixtures built in
// this file. The free sample ids come from ContentService, the
// same source the situation mapping functions use to set
// isFreeSample, so the fixtures stay in step with the app.

import XCTest
@testable import PaymentForge

final class DailyChallengeGateTests: XCTestCase {

    private let weeklyCaseID = "INS-050"

    private func makeSituation(id: String, isFreeSample: Bool, explain: String, takeaway: String) -> Situation {
        Situation(
            id: id,
            title: "Case \(id)",
            stage: 1,
            stageName: "Payment mechanics",
            level: .core,
            explain: explain,
            takeaway: takeaway,
            isFreeSample: isFreeSample,
            visual: nil
        )
    }

    /// Six free samples (the real ids, in ContentService order),
    /// one locked weekly case, and three locked cases, interleaved
    /// so order preservation is visible.
    private var fixtures: [Situation] {
        let freeIDs = ContentService.freeSampleIDs
        var list: [Situation] = []
        list.append(makeSituation(id: freeIDs[0], isFreeSample: true, explain: "FREE-EXPLAIN-\(freeIDs[0])", takeaway: "FREE-TAKEAWAY-\(freeIDs[0])"))
        list.append(makeSituation(id: "ABH-02", isFreeSample: false, explain: "LOCKED-EXPLAIN-ABH-02", takeaway: "LOCKED-TAKEAWAY-ABH-02"))
        list.append(makeSituation(id: freeIDs[1], isFreeSample: true, explain: "FREE-EXPLAIN-\(freeIDs[1])", takeaway: "FREE-TAKEAWAY-\(freeIDs[1])"))
        list.append(makeSituation(id: freeIDs[2], isFreeSample: true, explain: "FREE-EXPLAIN-\(freeIDs[2])", takeaway: "FREE-TAKEAWAY-\(freeIDs[2])"))
        list.append(makeSituation(id: weeklyCaseID, isFreeSample: false, explain: "WEEKLY-EXPLAIN", takeaway: "WEEKLY-TAKEAWAY"))
        list.append(makeSituation(id: "INS-001", isFreeSample: false, explain: "LOCKED-EXPLAIN-INS-001", takeaway: "LOCKED-TAKEAWAY-INS-001"))
        list.append(makeSituation(id: freeIDs[3], isFreeSample: true, explain: "FREE-EXPLAIN-\(freeIDs[3])", takeaway: "FREE-TAKEAWAY-\(freeIDs[3])"))
        list.append(makeSituation(id: freeIDs[4], isFreeSample: true, explain: "FREE-EXPLAIN-\(freeIDs[4])", takeaway: "FREE-TAKEAWAY-\(freeIDs[4])"))
        list.append(makeSituation(id: "JEB-A01", isFreeSample: false, explain: "LOCKED-EXPLAIN-JEB-A01", takeaway: "LOCKED-TAKEAWAY-JEB-A01"))
        list.append(makeSituation(id: freeIDs[5], isFreeSample: true, explain: "FREE-EXPLAIN-\(freeIDs[5])", takeaway: "FREE-TAKEAWAY-\(freeIDs[5])"))
        return list
    }

    // MARK: - The gate

    func testFreeSampleCountIsSix() {
        XCTAssertEqual(ContentService.freeSampleIDs.count, 6, "The policy names 6 free samples; the gate input must stay 6.")
    }

    func testNonEntitledPoolContainsOnlyFreeSamplesAndWeeklyCase() {
        let pool = DailyChallengeView.eligiblePool(
            from: fixtures, isSituationsUnlocked: false, weeklyCaseID: weeklyCaseID)
        XCTAssertEqual(pool.count, 7, "6 free samples plus the weekly case.")
        XCTAssertEqual(Set(pool.map(\.id)), Set(ContentService.freeSampleIDs + [weeklyCaseID]))
        XCTAssertTrue(pool.allSatisfy { $0.isFreeSample || $0.id == weeklyCaseID },
                      "Every pooled situation must be a free sample or the weekly case.")
    }

    func testNonEntitledPoolPreservesCatalogueOrder() {
        let pool = DailyChallengeView.eligiblePool(
            from: fixtures, isSituationsUnlocked: false, weeklyCaseID: weeklyCaseID)
        let freeIDs = ContentService.freeSampleIDs
        XCTAssertEqual(
            pool.map(\.id),
            [freeIDs[0], freeIDs[1], freeIDs[2], weeklyCaseID, freeIDs[3], freeIDs[4], freeIDs[5]],
            "The gate filters in place; it must not reorder the survivors.")
    }

    func testEntitledPoolIsUnfiltered() {
        let input = fixtures
        let pool = DailyChallengeView.eligiblePool(
            from: input, isSituationsUnlocked: true, weeklyCaseID: weeklyCaseID)
        XCTAssertEqual(pool, input, "Entitled learners get the full list unchanged: same items, same order.")
    }

    func testEntitledPoolIsUnfilteredEvenWithoutAWeeklyCase() {
        let input = fixtures
        let pool = DailyChallengeView.eligiblePool(
            from: input, isSituationsUnlocked: true, weeklyCaseID: nil)
        XCTAssertEqual(pool, input)
    }

    func testNoLockedExplainOrTakeawayTextSurfacesForNonEntitled() {
        let pool = DailyChallengeView.eligiblePool(
            from: fixtures, isSituationsUnlocked: false, weeklyCaseID: weeklyCaseID)
        let surfaced = pool.map { $0.explain + " " + $0.takeaway }.joined(separator: " ")
        XCTAssertFalse(surfaced.contains("LOCKED-"), "No locked explain or takeaway text may reach a non-entitled learner.")
        XCTAssertTrue(surfaced.contains("WEEKLY-EXPLAIN"), "The weekly case content is free and must surface.")
        XCTAssertTrue(surfaced.contains("WEEKLY-TAKEAWAY"))
        XCTAssertTrue(surfaced.contains("FREE-EXPLAIN"), "The free sample content must surface.")
        XCTAssertTrue(surfaced.contains("FREE-TAKEAWAY"))
    }

    func testWeeklyCaseThatIsAlsoFreeSampleAppearsOnce() {
        let weeklyAsSample = ContentService.freeSampleIDs[0]
        let pool = DailyChallengeView.eligiblePool(
            from: fixtures, isSituationsUnlocked: false, weeklyCaseID: weeklyAsSample)
        XCTAssertEqual(pool.count, 6, "A weekly case that is already a free sample must not duplicate.")
        XCTAssertEqual(Set(pool.map(\.id)), Set(ContentService.freeSampleIDs))
    }

    func testNilWeeklyCaseIDLeavesOnlyFreeSamples() {
        let pool = DailyChallengeView.eligiblePool(
            from: fixtures, isSituationsUnlocked: false, weeklyCaseID: nil)
        XCTAssertEqual(pool.count, 6)
        XCTAssertEqual(Set(pool.map(\.id)), Set(ContentService.freeSampleIDs))
        XCTAssertFalse(pool.contains { $0.id == weeklyCaseID },
                       "With no weekly case identified, the locked weekly case must not surface.")
    }

    func testUnknownWeeklyCaseIDLeavesOnlyFreeSamples() {
        let pool = DailyChallengeView.eligiblePool(
            from: fixtures, isSituationsUnlocked: false, weeklyCaseID: "NO-SUCH-CASE")
        XCTAssertEqual(pool.count, 6)
        XCTAssertEqual(Set(pool.map(\.id)), Set(ContentService.freeSampleIDs))
    }

    func testWeeklyCaseSurfacesEvenWhenItIsTheOnlyEligibleItem() {
        let onlyWeekly = [
            makeSituation(id: weeklyCaseID, isFreeSample: false, explain: "WEEKLY-EXPLAIN", takeaway: "WEEKLY-TAKEAWAY"),
            makeSituation(id: "ABH-02", isFreeSample: false, explain: "LOCKED-EXPLAIN", takeaway: "LOCKED-TAKEAWAY")
        ]
        let pool = DailyChallengeView.eligiblePool(
            from: onlyWeekly, isSituationsUnlocked: false, weeklyCaseID: weeklyCaseID)
        XCTAssertEqual(pool.map(\.id), [weeklyCaseID])
    }

    func testEmptyInputStaysEmpty() {
        XCTAssertTrue(DailyChallengeView.eligiblePool(
            from: [], isSituationsUnlocked: false, weeklyCaseID: weeklyCaseID).isEmpty)
        XCTAssertTrue(DailyChallengeView.eligiblePool(
            from: [], isSituationsUnlocked: true, weeklyCaseID: weeklyCaseID).isEmpty)
    }
}
