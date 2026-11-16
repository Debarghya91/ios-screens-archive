// InvestigationGateTests.swift
// v71 unit tests: the Investigation Lab gate predicate for the
// investigation experience, at the model level. No UI tests are
// attempted: rendering the gate needs a UI run, which is Phase 6
// work. What these tests pin is the pure predicate the experience
// view uses (InvestigationGate, flag form), the model-level
// predicate that embodies the same rule in situation-and-weekly-id
// form (PracticeModeBuilder.isLocked, weekly case by id), the gate
// inputs each entry route passes (the free-sample set, the
// situation id the engine preserves, and the lab unlock rule),
// and every locked, free, weekly, and unlocked combination.
//
// The two predicates differ in input form only: InvestigationGate
// takes isFreeSample and isWeeklyFreeCase flags from its caller
// plus the Investigation Lab unlock, while the model predicate
// takes the situation and the weekly case id plus the Practice
// unlock. Both express the same rule: locked means not a free
// sample, not this week's free case, and the Lab entitlement not
// active. The flag form is the one the experience view calls; the
// model form is the one Practice Mode and the Daily Challenge
// call, and it is kept here as the cross-check that the two forms
// agree on every combination.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the final app source before writing.

import XCTest
@testable import TrainingHub

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
        isPracticeUnlocked: Bool,
        weeklyCaseID: String?
    ) -> Bool {
        PracticeModeBuilder.isLocked(
            situation,
            isPracticeUnlocked: isPracticeUnlocked,
            weeklyCaseID: weeklyCaseID
        )
    }

    // MARK: - InvestigationGate truth table (flag form)

    func testInvestigationGateTruthTable() {
        // Locked only when all three escape routes are closed.
        XCTAssertTrue(InvestigationGate.isLocked(isFreeSample: false, isWeeklyFreeCase: false, isInvestigationLabUnlocked: false))
        XCTAssertFalse(InvestigationGate.isLocked(isFreeSample: true, isWeeklyFreeCase: false, isInvestigationLabUnlocked: false), "A free sample is never locked.")
        XCTAssertFalse(InvestigationGate.isLocked(isFreeSample: false, isWeeklyFreeCase: true, isInvestigationLabUnlocked: false), "This week's free case is never locked.")
        XCTAssertFalse(InvestigationGate.isLocked(isFreeSample: false, isWeeklyFreeCase: false, isInvestigationLabUnlocked: true), "The Investigation Lab unlock opens every case.")
        XCTAssertFalse(InvestigationGate.isLocked(isFreeSample: true, isWeeklyFreeCase: true, isInvestigationLabUnlocked: true))
        XCTAssertFalse(InvestigationGate.isLocked(isFreeSample: true, isWeeklyFreeCase: false, isInvestigationLabUnlocked: true))
        XCTAssertFalse(InvestigationGate.isLocked(isFreeSample: false, isWeeklyFreeCase: true, isInvestigationLabUnlocked: true))
        XCTAssertFalse(InvestigationGate.isLocked(isFreeSample: true, isWeeklyFreeCase: true, isInvestigationLabUnlocked: false))
    }

    func testInvestigationGateIsOpenTruthTable() {
        XCTAssertTrue(InvestigationGate.isOpen(requiresUnlock: false, isInvestigationLabUnlocked: false), "A case needing no unlock opens for everyone.")
        XCTAssertTrue(InvestigationGate.isOpen(requiresUnlock: false, isInvestigationLabUnlocked: true))
        XCTAssertFalse(InvestigationGate.isOpen(requiresUnlock: true, isInvestigationLabUnlocked: false), "A case needing an unlock stays shut without the Lab entitlement.")
        XCTAssertTrue(InvestigationGate.isOpen(requiresUnlock: true, isInvestigationLabUnlocked: true))
    }

    // MARK: - The gate truth table

    func testLockedSituationIsLockedForNonEntitledLearner() {
        XCTAssertTrue(isLocked(
            situation(id: "ABH-02", isFreeSample: false),
            isPracticeUnlocked: false,
            weeklyCaseID: weeklyCaseID
        ))
    }

    func testLockedSituationIsLockedWithNoWeeklyCase() {
        XCTAssertTrue(isLocked(
            situation(id: "ABH-02", isFreeSample: false),
            isPracticeUnlocked: false,
            weeklyCaseID: nil
        ))
    }

    func testFreeSampleIsNeverLocked() {
        for id in ContentService.freeSampleIDs {
            XCTAssertFalse(isLocked(
                situation(id: id, isFreeSample: true),
                isPracticeUnlocked: false,
                weeklyCaseID: weeklyCaseID
            ), "\(id) is a free sample and must open for every learner.")
        }
    }

    func testFreeSampleIDOpensEvenWhenItsFlagIsFalse() {
        XCTAssertFalse(isLocked(
            situation(id: "ABH-01", isFreeSample: false),
            isPracticeUnlocked: false,
            weeklyCaseID: weeklyCaseID
        ), "The id set is the backstop when the flag is wrong.")
    }

    func testWeeklyCaseIsNeverLockedOnItsWeek() {
        XCTAssertFalse(isLocked(
            situation(id: weeklyCaseID, isFreeSample: false),
            isPracticeUnlocked: false,
            weeklyCaseID: weeklyCaseID
        ))
    }

    func testWeeklyCaseIsLockedOnAnotherWeek() {
        XCTAssertTrue(isLocked(
            situation(id: weeklyCaseID, isFreeSample: false),
            isPracticeUnlocked: false,
            weeklyCaseID: "INS-002"
        ))
    }

    func testWeeklyCaseIsLockedWhenNoWeeklyCaseIsKnown() {
        XCTAssertTrue(isLocked(
            situation(id: weeklyCaseID, isFreeSample: false),
            isPracticeUnlocked: false,
            weeklyCaseID: nil
        ))
    }

    func testUnlockedLearnerSeesEveryCase() {
        for id in ["ABH-01", "ABH-02", weeklyCaseID, "SCN-99"] {
            XCTAssertFalse(isLocked(
                situation(id: id, isFreeSample: false),
                isPracticeUnlocked: true,
                weeklyCaseID: weeklyCaseID
            ), "An entitled learner is never gated, whatever the case.")
        }
    }

    func testUnlockedLearnerSeesEveryCaseWithNoWeeklyCase() {
        XCTAssertFalse(isLocked(
            situation(id: "ABH-02", isFreeSample: false),
            isPracticeUnlocked: true,
            weeklyCaseID: nil
        ))
    }

    func testFreeSamplePlusWeeklyPlusUnlockedIsNeverLocked() {
        XCTAssertFalse(isLocked(
            situation(id: "ABH-01", isFreeSample: true),
            isPracticeUnlocked: true,
            weeklyCaseID: "ABH-01"
        ))
    }

    // MARK: - The free-sample set the gate reads

    func testFreeSampleSetIsExactlyTheTwoKnownIDs() {
        XCTAssertEqual(
            ContentService.freeSampleIDs,
            ["ABH-01", "JEB-C01"]
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
            isPracticeUnlocked: false,
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
    /// Investigation Lab entitlement is active, and the experience
    /// entry passes the same open-to-all value as its free flag.
    /// These tests pin the grounding rule the list and the entry
    /// share. The requiresSituationsUnlock property name is
    /// retained: it describes what the case is grounded in, not
    /// which product unlocks it.
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
