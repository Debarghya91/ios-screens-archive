// InvestigationGateTests.swift
// v71 unit tests: the situations gate predicate for the
// investigation experience, at the model level. No UI tests are
// attempted: the experience view re-checks the gate on appear with
// a private flag predicate (free sample, weekly free case, or the
// situations unlock), and rendering that gate needs a UI run,
// which is Phase 6 work. What these tests pin is the model-level
// predicate that embodies the same v69 hard-gate rule
// (PracticeModeBuilder.isLocked, weekly case by id), the gate
// inputs each entry route passes (the free-sample set, the
// situation id the engine preserves, and the lab unlock rule),
// and every locked, free, weekly, and unlocked combination.
//
// The view predicate and this predicate differ in one input form
// only: the view takes isFreeSample and isWeeklyFreeCase flags
// from its caller, while the model predicate takes the situation
// and the weekly case id. Both express the same rule: locked
// means not a free sample, not this week's free case, and
// Payment Situations not unlocked. The flag form was verified by
// reading the view source; it cannot be executed without
// rendering the view.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the final app source before writing.

import XCTest
@testable import PaymentForge

final class InvestigationGateTests: XCTestCase {

    private let weeklyCaseID = "INS-001"

    private func situation(id: String, isFreeSample: Bool) -> Situation {
        Situation(
            id: id,
            title: "Case \(id)",
            stage: 1,
            stageName: "Payment mechanics",
            level: .core,
            explain: "Explain text for \(id).",
            takeaway: "Takeaway for \(id).",
            isFreeSample: isFreeSample,
            visual: nil
        )
    }

    private func isLocked(
        _ situation: Situation,
        isSituationsUnlocked: Bool,
        weeklyCaseID: String?
    ) -> Bool {
        PracticeModeBuilder.isLocked(
            situation,
            isSituationsUnlocked: isSituationsUnlocked,
            weeklyCaseID: weeklyCaseID
        )
    }

    // MARK: - The gate truth table

    func testLockedSituationIsLockedForNonEntitledLearner() {
        XCTAssertTrue(isLocked(
            situation(id: "ABH-02", isFreeSample: false),
            isSituationsUnlocked: false,
            weeklyCaseID: weeklyCaseID
        ))
    }

    func testLockedSituationIsLockedWithNoWeeklyCase() {
        XCTAssertTrue(isLocked(
            situation(id: "ABH-02", isFreeSample: false),
            isSituationsUnlocked: false,
            weeklyCaseID: nil
        ))
    }

    func testFreeSampleIsNeverLocked() {
        for id in ContentService.freeSampleIDs {
            XCTAssertFalse(isLocked(
                situation(id: id, isFreeSample: true),
                isSituationsUnlocked: false,
                weeklyCaseID: weeklyCaseID
            ), "\(id) is a free sample and must open for every learner.")
        }
    }

    func testFreeSampleIDOpensEvenWhenItsFlagIsFalse() {
        XCTAssertFalse(isLocked(
            situation(id: "ABH-01", isFreeSample: false),
            isSituationsUnlocked: false,
            weeklyCaseID: weeklyCaseID
        ), "The id set is the backstop when the flag is wrong.")
    }

    func testWeeklyCaseIsNeverLockedOnItsWeek() {
        XCTAssertFalse(isLocked(
            situation(id: weeklyCaseID, isFreeSample: false),
            isSituationsUnlocked: false,
            weeklyCaseID: weeklyCaseID
        ))
    }

    func testWeeklyCaseIsLockedOnAnotherWeek() {
        XCTAssertTrue(isLocked(
            situation(id: weeklyCaseID, isFreeSample: false),
            isSituationsUnlocked: false,
            weeklyCaseID: "INS-002"
        ))
    }

    func testWeeklyCaseIsLockedWhenNoWeeklyCaseIsKnown() {
        XCTAssertTrue(isLocked(
            situation(id: weeklyCaseID, isFreeSample: false),
            isSituationsUnlocked: false,
            weeklyCaseID: nil
        ))
    }

    func testUnlockedLearnerSeesEveryCase() {
        for id in ["ABH-01", "ABH-02", weeklyCaseID, "SCN-99"] {
            XCTAssertFalse(isLocked(
                situation(id: id, isFreeSample: false),
                isSituationsUnlocked: true,
                weeklyCaseID: weeklyCaseID
            ), "An entitled learner is never gated, whatever the case.")
        }
    }

    func testUnlockedLearnerSeesEveryCaseWithNoWeeklyCase() {
        XCTAssertFalse(isLocked(
            situation(id: "ABH-02", isFreeSample: false),
            isSituationsUnlocked: true,
            weeklyCaseID: nil
        ))
    }

    func testFreeSamplePlusWeeklyPlusUnlockedIsNeverLocked() {
        XCTAssertFalse(isLocked(
            situation(id: "ABH-01", isFreeSample: true),
            isSituationsUnlocked: true,
            weeklyCaseID: "ABH-01"
        ))
    }

    // MARK: - The free-sample set the gate reads

    func testFreeSampleSetIsExactlyTheSixKnownIDs() {
        XCTAssertEqual(
            ContentService.freeSampleIDs,
            ["ABH-01", "JEB-C01", "ABH-03", "SCN-21", "RUN4-008", "INS-099"]
        )
    }

    func testEligiblePoolForNonEntitledLearnerIsFreeSamplesPlusWeekly() {
        let catalogue = [
            situation(id: "ABH-01", isFreeSample: true),
            situation(id: "ABH-02", isFreeSample: false),
            situation(id: weeklyCaseID, isFreeSample: false),
            situation(id: "SCN-99", isFreeSample: false)
        ]
        let pool = PracticeModeBuilder.eligiblePool(
            from: catalogue,
            isSituationsUnlocked: false,
            weeklyCaseID: weeklyCaseID
        )
        XCTAssertEqual(pool.map(\.id), ["ABH-01", weeklyCaseID])
    }

    // MARK: - Gate inputs: the engine preserves the situation id

    /// The gate keys on the situation id, so the investigation case
    /// built for a situation must carry that id unchanged, for a
    /// free sample, a locked situation, and the weekly case alike.
    func testEnginePreservesSituationIDForFreeLockedAndWeeklyCases() {
        for id in ["ABH-01", "ABH-02", weeklyCaseID] {
            let investigationCase = InvestigationEngine.caseFor(
                situation: situation(id: id, isFreeSample: id == "ABH-01"),
                fullItem: nil,
                difficulty: .professional
            )
            XCTAssertEqual(investigationCase.id, id)
            XCTAssertEqual(investigationCase.situationID, id)
        }
    }

    /// The lab adapter preserves the source situation id, so a lab
    /// case grounded in a free sample keeps the free-sample gate
    /// input its list row already used.
    func testLabAdapterPreservesSourceSituationID() {
        let labCase = ExceptionCase(
            id: "lab-abh-01",
            incidentType: "Missing confirmation",
            title: "EUR 50,000 sent, and nobody could say where it was",
            level: .foundation,
            narrative: "A payment left the bank and no confirmation came back.",
            evidence: [],
            steps: [],
            resolution: "Request the status report.",
            messages: [],
            systems: [],
            sourceSituationID: "ABH-01",
            sourceSituationTitle: "EUR 50,000 sent, and nobody could say where it was",
            sourceTakeaway: "Confirm arrival from the status report."
        )
        let investigationCase = InvestigationEngine.caseForLabCase(labCase, difficulty: .professional)
        XCTAssertEqual(investigationCase.id, "lab-abh-01")
        XCTAssertEqual(investigationCase.situationID, "ABH-01")
        XCTAssertTrue(ContentService.freeSampleIDs.contains(investigationCase.situationID))
    }

    // MARK: - Gate inputs: the lab unlock rule

    /// The Lab list opens a case when it needs no unlock or the
    /// situations entitlement is active, and the experience entry
    /// passes the same open-to-all value as its free flag. These
    /// tests pin the unlock rule the list and the entry share.
    func testLabCaseGroundedInFreeSampleNeedsNoUnlock() {
        let labCase = ExceptionCase(
            id: "lab-abh-01",
            incidentType: "Missing confirmation",
            title: "A free sample case",
            level: .foundation,
            narrative: "Narrative.",
            evidence: [],
            steps: [],
            resolution: "Resolution.",
            messages: [],
            systems: [],
            sourceSituationID: "ABH-01",
            sourceSituationTitle: "A free sample case",
            sourceTakeaway: "Takeaway."
        )
        XCTAssertFalse(labCase.requiresSituationsUnlock)
        XCTAssertTrue(labCase.isGroundedInFreeSample)
    }

    func testLabCaseGroundedInLockedSituationNeedsUnlock() {
        let labCase = ExceptionCase(
            id: "lab-abh-02",
            incidentType: "Missing confirmation",
            title: "A locked case",
            level: .core,
            narrative: "Narrative.",
            evidence: [],
            steps: [],
            resolution: "Resolution.",
            messages: [],
            systems: [],
            sourceSituationID: "ABH-02",
            sourceSituationTitle: "A locked case",
            sourceTakeaway: "Takeaway."
        )
        XCTAssertTrue(labCase.requiresSituationsUnlock)
        XCTAssertFalse(labCase.isGroundedInFreeSample)
    }

    func testPracticeExerciseNeedsNoUnlock() {
        let labCase = ExceptionCase(
            id: "lab-practice-01",
            incidentType: "Missing confirmation",
            title: "A practice exercise",
            level: .foundation,
            narrative: "Narrative.",
            evidence: [],
            steps: [],
            resolution: "Resolution.",
            messages: [],
            systems: [],
            sourceSituationID: nil,
            sourceSituationTitle: nil,
            sourceTakeaway: nil
        )
        XCTAssertTrue(labCase.isPracticeExercise)
        XCTAssertFalse(labCase.requiresSituationsUnlock)
    }
}
