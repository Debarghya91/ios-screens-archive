// PracticeModeGateTests.swift
// Payments Training Hub iOS - v70 unit tests: the Practice Mode
// gate in PracticeModeBuilder. Non-entitled learners practise
// only the free samples plus this week's free case, distractors
// never come from locked situations, and entitled learners keep
// the full pool unchanged. No network: all situations are
// fixtures built in this file.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the final app source before writing.

import XCTest
@testable import PaymentForge

final class PracticeModeGateTests: XCTestCase {

    private func situation(id: String, takeaway: String, isFreeSample: Bool) -> Situation {
        Situation(
            id: id,
            title: "Case \(id)",
            stage: 1,
            stageName: "Payment mechanics",
            level: .core,
            explain: "Explain text for \(id).",
            takeaway: takeaway,
            isFreeSample: isFreeSample,
            visual: nil
        )
    }

    /// Ten situations in catalogue order: the 6 real free sample
    /// ids, 3 locked situations, and one locked situation that
    /// acts as this week's free case. Locked takeaways carry a
    /// "Locked case" marker so a leak is visible in any option.
    private var catalogue: [Situation] {
        [
            situation(id: "ABH-01", takeaway: "Always check the UETR before recalling a payment.", isFreeSample: true),
            situation(id: "ABH-02", takeaway: "Locked case takeaway about reversing a duplicate payment.", isFreeSample: false),
            situation(id: "JEB-C01", takeaway: "Confirm the beneficiary account before releasing funds.", isFreeSample: true),
            situation(id: "INS-001", takeaway: "Escalate the stuck payment to the operations lead.", isFreeSample: false),
            situation(id: "ABH-03", takeaway: "Match the value date to the clearing cut-off time.", isFreeSample: true),
            situation(id: "SCN-01", takeaway: "Locked case takeaway about a missing remittance reference.", isFreeSample: false),
            situation(id: "SCN-21", takeaway: "Ask the correspondent bank for the status update.", isFreeSample: true),
            situation(id: "RUN4-008", takeaway: "Keep the return reason code with the original reference.", isFreeSample: true),
            situation(id: "INS-099", takeaway: "Record the investigation steps in the case notes.", isFreeSample: true),
            situation(id: "INS-002", takeaway: "Locked case takeaway about a late settlement report.", isFreeSample: false)
        ]
    }

    private let weeklyCaseID = "INS-001"

    private var freeSampleIDsInOrder: [String] {
        ["ABH-01", "JEB-C01", "ABH-03", "SCN-21", "RUN4-008", "INS-099"]
    }

    /// The takeaway texts a non-entitled decision may use: the
    /// first sentences of the free sample and weekly case
    /// takeaways, computed with the same rule the builder uses.
    private var allowedOptionTexts: Set<String> {
        Set(PracticeModeBuilder.eligiblePool(
            from: catalogue,
            isSituationsUnlocked: false,
            weeklyCaseID: weeklyCaseID
        ).map { PracticeModeBuilder.firstSentence(of: $0.takeaway) })
    }

    // MARK: - Eligible pool

    func testNonEntitledPoolContainsOnlyFreeSamplesAndWeeklyCase() {
        let pool = PracticeModeBuilder.eligiblePool(
            from: catalogue,
            isSituationsUnlocked: false,
            weeklyCaseID: weeklyCaseID
        )
        XCTAssertEqual(pool.map(\.id), ["ABH-01", "JEB-C01", "INS-001", "ABH-03", "SCN-21", "RUN4-008", "INS-099"])
        XCTAssertEqual(pool.count, 7, "Six free samples plus this week's free case.")
    }

    func testNonEntitledPoolPreservesCatalogueOrder() {
        let pool = PracticeModeBuilder.eligiblePool(
            from: catalogue,
            isSituationsUnlocked: false,
            weeklyCaseID: weeklyCaseID
        )
        let catalogueOrder = catalogue.map(\.id)
        let poolPositions = pool.map { catalogueOrder.firstIndex(of: $0.id)! }
        XCTAssertEqual(poolPositions, poolPositions.sorted(), "The pool keeps catalogue order, never a new order.")
    }

    func testNonEntitledPoolHasNoDuplicatesWhenWeeklyCaseIsAFreeSample() {
        let pool = PracticeModeBuilder.eligiblePool(
            from: catalogue,
            isSituationsUnlocked: false,
            weeklyCaseID: "ABH-01"
        )
        XCTAssertEqual(pool.map(\.id), freeSampleIDsInOrder)
        XCTAssertEqual(Set(pool.map(\.id)).count, pool.count, "A weekly case that is already a free sample appears once.")
    }

    func testNonEntitledPoolWithoutWeeklyCaseContainsOnlyFreeSamples() {
        let pool = PracticeModeBuilder.eligiblePool(
            from: catalogue,
            isSituationsUnlocked: false,
            weeklyCaseID: nil
        )
        XCTAssertEqual(pool.map(\.id), freeSampleIDsInOrder)
    }

    func testNonEntitledPoolIgnoresWeeklyCaseIDNotInList() {
        let pool = PracticeModeBuilder.eligiblePool(
            from: catalogue,
            isSituationsUnlocked: false,
            weeklyCaseID: "NOPE-999"
        )
        XCTAssertEqual(pool.map(\.id), freeSampleIDsInOrder, "An unknown weekly id invents no situation.")
    }

    func testEntitledPoolIsUnfiltered() {
        let pool = PracticeModeBuilder.eligiblePool(
            from: catalogue,
            isSituationsUnlocked: true,
            weeklyCaseID: weeklyCaseID
        )
        XCTAssertEqual(pool.map(\.id), catalogue.map(\.id), "Entitled learners keep the full list, in order.")
    }

    func testEmptyListStaysEmpty() {
        XCTAssertTrue(PracticeModeBuilder.eligiblePool(from: [], isSituationsUnlocked: false, weeklyCaseID: weeklyCaseID).isEmpty)
        XCTAssertTrue(PracticeModeBuilder.eligiblePool(from: [], isSituationsUnlocked: true, weeklyCaseID: weeklyCaseID).isEmpty)
    }

    func testFreeSampleFlagAdmitsWithoutIDMatch() {
        let flagged = situation(id: "ZZZ-1", takeaway: "Flagged free case takeaway for practice.", isFreeSample: true)
        let pool = PracticeModeBuilder.eligiblePool(
            from: [flagged],
            isSituationsUnlocked: false,
            weeklyCaseID: nil,
            freeSampleIDs: []
        )
        XCTAssertEqual(pool.map(\.id), ["ZZZ-1"], "The isFreeSample flag alone admits a situation.")
    }

    func testFreeSampleIDAdmitsWithoutFlag() {
        let unflagged = situation(id: "ZZZ-2", takeaway: "Listed free case takeaway for practice.", isFreeSample: false)
        let control = situation(id: "ZZZ-3", takeaway: "Locked case takeaway that must stay out.", isFreeSample: false)
        let pool = PracticeModeBuilder.eligiblePool(
            from: [unflagged, control],
            isSituationsUnlocked: false,
            weeklyCaseID: nil,
            freeSampleIDs: ["ZZZ-2"]
        )
        XCTAssertEqual(pool.map(\.id), ["ZZZ-2"], "A free sample id alone admits a situation, even when the flag is unset.")
    }

    // MARK: - Locked predicate

    func testIsLockedTruthTable() {
        let free = catalogue[0]
        let weekly = catalogue[3]
        let locked = catalogue[1]
        XCTAssertFalse(PracticeModeBuilder.isLocked(free, isSituationsUnlocked: false, weeklyCaseID: weeklyCaseID), "A free sample is never locked.")
        XCTAssertFalse(PracticeModeBuilder.isLocked(weekly, isSituationsUnlocked: false, weeklyCaseID: weeklyCaseID), "This week's free case is never locked.")
        XCTAssertTrue(PracticeModeBuilder.isLocked(locked, isSituationsUnlocked: false, weeklyCaseID: weeklyCaseID), "A locked situation is locked for a non-entitled learner.")
        XCTAssertTrue(PracticeModeBuilder.isLocked(locked, isSituationsUnlocked: false, weeklyCaseID: nil), "No weekly case known means the locked situation stays locked.")
        XCTAssertFalse(PracticeModeBuilder.isLocked(locked, isSituationsUnlocked: true, weeklyCaseID: weeklyCaseID), "Entitlement unlocks every situation.")
        XCTAssertFalse(PracticeModeBuilder.isLocked(free, isSituationsUnlocked: true, weeklyCaseID: weeklyCaseID))
    }

    // MARK: - Gated decisions

    func testGatedDecisionForLockedSituationIsNilWhenNotEntitled() {
        let locked = catalogue[1]
        let decision = PracticeModeBuilder.decision(
            for: locked,
            in: catalogue,
            isSituationsUnlocked: false,
            weeklyCaseID: weeklyCaseID
        )
        XCTAssertNil(decision, "No decision, and therefore no content, is built for a locked situation.")
    }

    func testGatedDecisionDistractorsNeverComeFromLockedSituations() {
        let focal = catalogue[0]
        guard let decision = PracticeModeBuilder.decision(
            for: focal,
            in: catalogue,
            isSituationsUnlocked: false,
            weeklyCaseID: weeklyCaseID
        ) else {
            XCTFail("A decision must be built for a free sample from the free pool.")
            return
        }
        XCTAssertEqual(decision.options.count, 4)
        XCTAssertTrue(decision.options.allSatisfy { allowedOptionTexts.contains($0) }, "Every option must come from a free sample or the weekly case takeaway.")
        XCTAssertFalse(decision.options.contains { $0.contains("Locked case") }, "No option may carry locked takeaway text.")
        XCTAssertEqual(decision.options[decision.correctOptionIndex], PracticeModeBuilder.firstSentence(of: focal.takeaway))
        XCTAssertEqual(decision.explanation, focal.takeaway, "The explanation is the focal situation's own takeaway.")
    }

    func testGatedDecisionForWeeklyCaseUsesFreePoolOnly() {
        let weekly = catalogue[3]
        guard let decision = PracticeModeBuilder.decision(
            for: weekly,
            in: catalogue,
            isSituationsUnlocked: false,
            weeklyCaseID: weeklyCaseID
        ) else {
            XCTFail("A decision must be built for this week's free case.")
            return
        }
        XCTAssertEqual(decision.options.count, 4)
        XCTAssertTrue(decision.options.allSatisfy { allowedOptionTexts.contains($0) })
        XCTAssertFalse(decision.options.contains { $0.contains("Locked case") })
        XCTAssertEqual(decision.options[decision.correctOptionIndex], PracticeModeBuilder.firstSentence(of: weekly.takeaway))
    }

    func testRecallSaltVariantStaysGated() {
        let focal = catalogue[0]
        guard let decision = PracticeModeBuilder.decision(
            for: focal,
            in: catalogue,
            isSituationsUnlocked: false,
            weeklyCaseID: weeklyCaseID
        ), let recall = PracticeModeBuilder.decision(
            for: focal,
            in: catalogue,
            isSituationsUnlocked: false,
            weeklyCaseID: weeklyCaseID,
            seedSalt: 1000
        ) else {
            XCTFail("Both the decision and the recall question must be built for a free sample.")
            return
        }
        XCTAssertEqual(Set(recall.options), Set(decision.options), "The recall question reuses the same gated option pool.")
        XCTAssertTrue(recall.options.allSatisfy { allowedOptionTexts.contains($0) })
        XCTAssertFalse(recall.options.contains { $0.contains("Locked case") })
    }

    func testSixSituationPoolStillBuildsDecision() {
        // Only the 6 free samples, no weekly case. The offset
        // picks alone visit only two distinct neighbours in a
        // pool of six, so without the small-pool fallback this
        // decision would be nil and free practice would be
        // empty whenever the weekly case is itself a sample.
        let samples = catalogue.filter { $0.isFreeSample }
        XCTAssertEqual(samples.count, 6)
        guard let decision = PracticeModeBuilder.decision(
            for: samples[0],
            in: samples,
            isSituationsUnlocked: false,
            weeklyCaseID: nil
        ) else {
            XCTFail("A decision must be built from six free samples alone.")
            return
        }
        XCTAssertEqual(decision.options.count, 4)
        let sampleTexts = Set(samples.map { PracticeModeBuilder.firstSentence(of: $0.takeaway) })
        XCTAssertTrue(decision.options.allSatisfy { sampleTexts.contains($0) })
    }

    func testEntitledDecisionForLockedSituationIsBuilt() {
        let locked = catalogue[1]
        guard let decision = PracticeModeBuilder.decision(
            for: locked,
            in: catalogue,
            isSituationsUnlocked: true,
            weeklyCaseID: weeklyCaseID
        ) else {
            XCTFail("Entitled learners keep decisions for every situation.")
            return
        }
        XCTAssertEqual(decision.options.count, 4)
        XCTAssertEqual(decision.options[decision.correctOptionIndex], PracticeModeBuilder.firstSentence(of: locked.takeaway))
        XCTAssertEqual(decision.explanation, locked.takeaway)
    }

    func testGatedIsEligibleMatchesDecision() {
        let free = catalogue[0]
        let locked = catalogue[1]
        XCTAssertTrue(PracticeModeBuilder.isEligible(free, in: catalogue, isSituationsUnlocked: false, weeklyCaseID: weeklyCaseID))
        XCTAssertFalse(PracticeModeBuilder.isEligible(locked, in: catalogue, isSituationsUnlocked: false, weeklyCaseID: weeklyCaseID))
        XCTAssertTrue(PracticeModeBuilder.isEligible(locked, in: catalogue, isSituationsUnlocked: true, weeklyCaseID: weeklyCaseID))
    }
}
