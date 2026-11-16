// Phase3ExceptionLabTests.swift
// TrainingHub iOS - Phase 3 tests: the payment exception
// investigation lab (ExceptionCases.swift, ExceptionLabStore.swift).
// Covers catalogue structure, the pure scoring rules, level order,
// and account-namespaced score storage. Model and store logic only;
// no view tests.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the implementation files before writing.
//
// The store base key below mirrors the private key constant in
// ExceptionLabStore and must be kept in step with that file.

import XCTest
@testable import TrainingHub

@MainActor
final class Phase3ExceptionLabTests: XCTestCase {

    private let namespaceA = "test-exception-lab-a"
    private let namespaceB = "test-exception-lab-b"
    private let resultsBaseKey = "pf.exceptionLabResults.v1"

    override func setUp() {
        super.setUp()
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        UserDefaults.standard.removeObject(forKey: resultsBaseKey)
        AccountScopedStorage.removeAllKeys(in: namespaceA)
        AccountScopedStorage.removeAllKeys(in: namespaceB)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: resultsBaseKey)
        AccountScopedStorage.removeAllKeys(in: namespaceA)
        AccountScopedStorage.removeAllKeys(in: namespaceB)
        AccountScopedStorage.setCurrentNamespace(nil)
        super.tearDown()
    }

    // MARK: - Fixtures

    /// A small synthetic case with known arithmetic: 2 steps, 2
    /// genuine evidence items and 1 red herring item. Maximum is
    /// 2 x 20 + 10 + 2 x 4 = 58.
    private func syntheticCase() -> ExceptionCase {
        ExceptionCase(
            id: "test-synthetic",
            incidentType: "Test incident",
            title: "Test case",
            level: .foundation,
            narrative: "A test narrative.",
            evidence: [
                ExceptionEvidence(id: "ev-1", title: "Genuine one", detail: "A clue.", revealedAfterStep: 0, isRedHerring: false, redHerringNote: nil),
                ExceptionEvidence(id: "ev-2", title: "Genuine two", detail: "Another clue.", revealedAfterStep: 1, isRedHerring: false, redHerringNote: nil),
                ExceptionEvidence(id: "ev-3", title: "Distraction", detail: "A distraction.", revealedAfterStep: 0, isRedHerring: true, redHerringNote: "It leads away from the cause.")
            ],
            steps: [
                InvestigationStep(
                    id: "step-1",
                    prompt: "What do you do first?",
                    options: [
                        InvestigationOption(text: "Best action", isRedHerring: false, feedback: "Correct."),
                        InvestigationOption(text: "Wrong action", isRedHerring: false, feedback: "Not yet."),
                        InvestigationOption(text: "Distracting action", isRedHerring: true, feedback: "A distraction.")
                    ],
                    bestOptionIndex: 0,
                    whyCorrect: "It follows the evidence.",
                    wrongTurnCost: "Time is lost.",
                    evidenceNote: nil
                ),
                InvestigationStep(
                    id: "step-2",
                    prompt: "What do you do next?",
                    options: [
                        InvestigationOption(text: "Wrong action", isRedHerring: false, feedback: "Not yet."),
                        InvestigationOption(text: "Best action", isRedHerring: false, feedback: "Correct."),
                        InvestigationOption(text: "Another wrong action", isRedHerring: false, feedback: "Not yet.")
                    ],
                    bestOptionIndex: 1,
                    whyCorrect: "It closes the case.",
                    wrongTurnCost: "The case stays open.",
                    evidenceNote: "The resolution is revealed."
                )
            ],
            resolution: "The case is resolved.",
            messages: ["pacs.002"],
            systems: ["Payment hub"],
            sourceSituationID: nil,
            sourceSituationTitle: nil,
            sourceTakeaway: nil
        )
    }

    private func breakdown(total: Int, maximum: Int) -> ExceptionLabScoreBreakdown {
        ExceptionLabScoreBreakdown(
            bestFirstPoints: total,
            recoveredPoints: 0,
            wrongTurnDeductions: 0,
            redHerringDeductions: 0,
            efficiencyBonus: 0,
            thoroughnessPoints: 0,
            total: total,
            maximum: maximum,
            stepsSolvedBestFirst: 0,
            stepsSolvedAfterWrongTurn: 0,
            totalWrongPicks: 0,
            totalRedHerringPicks: 0,
            evidenceOpenedCount: 0,
            evidenceTotalCount: 0
        )
    }

    // MARK: - Catalogue structure

    func testCatalogueHasTwelveCasesWithUniqueIDs() {
        XCTAssertEqual(ExceptionCaseCatalogue.allCases.count, 12)
        let ids = ExceptionCaseCatalogue.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ExceptionCaseCatalogue.checkCatalogue().isEmpty, "Catalogue check found issues: \(ExceptionCaseCatalogue.checkCatalogue())")
    }

    func testEveryStepHasThreePlusOptionsWithExactlyOneBestIndexInRange() {
        // The model encodes "exactly one best option" as a single
        // bestOptionIndex per step; there is no per-option best
        // flag, so the check is that the one index exists and is
        // in range for every step.
        for exceptionCase in ExceptionCaseCatalogue.allCases {
            XCTAssertFalse(exceptionCase.steps.isEmpty, "\(exceptionCase.id) has no steps.")
            for step in exceptionCase.steps {
                XCTAssertGreaterThanOrEqual(step.options.count, 3, "\(step.id) has fewer than 3 options.")
                XCTAssertGreaterThanOrEqual(step.bestOptionIndex, 0, "\(step.id) best index is negative.")
                XCTAssertLessThan(step.bestOptionIndex, step.options.count, "\(step.id) best index is out of range.")
                XCTAssertFalse(step.prompt.isEmpty)
                XCTAssertFalse(step.whyCorrect.isEmpty)
                XCTAssertFalse(step.wrongTurnCost.isEmpty)
                for option in step.options {
                    XCTAssertFalse(option.text.isEmpty, "\(step.id) has an empty option.")
                    XCTAssertFalse(option.feedback.isEmpty, "\(step.id) has an option with no feedback.")
                }
            }
        }
    }

    func testStepAndOptionShapeFollowsLevel() {
        // Header comment: foundation 3 steps of 3 options, core 3
        // steps of 4 options, advanced 4 steps of 4 options.
        for exceptionCase in ExceptionCaseCatalogue.allCases {
            switch exceptionCase.level {
            case .foundation:
                XCTAssertEqual(exceptionCase.steps.count, 3, "\(exceptionCase.id) is foundation and must have 3 steps.")
                for step in exceptionCase.steps {
                    XCTAssertEqual(step.options.count, 3, "\(step.id) is foundation and must have 3 options.")
                }
            case .core:
                XCTAssertEqual(exceptionCase.steps.count, 3, "\(exceptionCase.id) is core and must have 3 steps.")
                for step in exceptionCase.steps {
                    XCTAssertEqual(step.options.count, 4, "\(step.id) is core and must have 4 options.")
                }
            case .advanced:
                XCTAssertEqual(exceptionCase.steps.count, 4, "\(exceptionCase.id) is advanced and must have 4 steps.")
                for step in exceptionCase.steps {
                    XCTAssertEqual(step.options.count, 4, "\(step.id) is advanced and must have 4 options.")
                }
            }
        }
    }

    func testEvidenceIDsUniqueRevealInRangeAndRedHerringsExplained() {
        for exceptionCase in ExceptionCaseCatalogue.allCases {
            XCTAssertFalse(exceptionCase.evidence.isEmpty, "\(exceptionCase.id) has no evidence.")
            let ids = exceptionCase.evidence.map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "\(exceptionCase.id) has duplicate evidence ids.")
            for item in exceptionCase.evidence {
                XCTAssertFalse(item.title.isEmpty)
                XCTAssertFalse(item.detail.isEmpty)
                XCTAssertGreaterThanOrEqual(item.revealedAfterStep, 0)
                XCTAssertLessThanOrEqual(item.revealedAfterStep, exceptionCase.steps.count)
                if item.isRedHerring {
                    XCTAssertNotNil(item.redHerringNote, "\(item.id) is a red herring with no explanation note.")
                    XCTAssertFalse(item.redHerringNote?.isEmpty ?? true)
                }
            }
        }
    }

    func testCaseLevelsNeverStepBackInCatalogueOrder() {
        func order(of level: SituationLevel) -> Int {
            switch level {
            case .foundation: return 0
            case .core: return 1
            case .advanced: return 2
            }
        }
        let levels = ExceptionCaseCatalogue.allCases.map(\.level)
        XCTAssertEqual(
            levels,
            [.foundation, .foundation, .foundation, .foundation, .foundation,
             .core, .core, .core, .core, .core,
             .advanced, .advanced]
        )
        var previous = -1
        for level in levels {
            XCTAssertGreaterThanOrEqual(order(of: level), previous, "Catalogue levels step back.")
            previous = order(of: level)
        }
    }

    func testEveryCatalogueCaseIsGroundedAndCarriesItsSourceFields() {
        for exceptionCase in ExceptionCaseCatalogue.allCases {
            XCTAssertFalse(exceptionCase.isPracticeExercise, "\(exceptionCase.id) is unexpectedly a practice exercise.")
            XCTAssertNotNil(exceptionCase.sourceSituationID)
            XCTAssertNotNil(exceptionCase.sourceSituationTitle)
            XCTAssertNotNil(exceptionCase.sourceTakeaway)
            XCTAssertFalse(exceptionCase.incidentType.isEmpty)
            XCTAssertFalse(exceptionCase.title.isEmpty)
            XCTAssertFalse(exceptionCase.narrative.isEmpty)
            XCTAssertFalse(exceptionCase.resolution.isEmpty)
        }
    }

    func testGenuineEvidenceCountExcludesRedHerrings() {
        let synthetic = syntheticCase()
        XCTAssertEqual(synthetic.genuineEvidenceCount, 2)
        XCTAssertEqual(synthetic.evidence.count, 3)
        for exceptionCase in ExceptionCaseCatalogue.allCases {
            XCTAssertEqual(
                exceptionCase.genuineEvidenceCount,
                exceptionCase.evidence.filter { !$0.isRedHerring }.count
            )
        }
    }

    // MARK: - Scoring constants and maximum

    func testScoringConstantsMatchTheDocumentedNumbers() {
        XCTAssertEqual(ExceptionLabScoring.bestFirstPointsPerStep, 20)
        XCTAssertEqual(ExceptionLabScoring.recoveredPointsPerStep, 8)
        XCTAssertEqual(ExceptionLabScoring.wrongPickDeduction, 5)
        XCTAssertEqual(ExceptionLabScoring.redHerringPickDeduction, 10)
        XCTAssertEqual(ExceptionLabScoring.efficiencyBonusNoWrongTurn, 10)
        XCTAssertEqual(ExceptionLabScoring.efficiencyBonusOneWrongTurn, 5)
        XCTAssertEqual(ExceptionLabScoring.thoroughnessPointsPerEvidence, 4)
    }

    func testMaximumIsBestFirstPlusEfficiencyPlusThoroughness() {
        let synthetic = syntheticCase()
        XCTAssertEqual(ExceptionLabScoring.maximum(for: synthetic), 58)
        for exceptionCase in ExceptionCaseCatalogue.allCases {
            XCTAssertEqual(
                ExceptionLabScoring.maximum(for: exceptionCase),
                exceptionCase.steps.count * 20 + 10 + exceptionCase.genuineEvidenceCount * 4
            )
        }
    }

    func testSolvedBestFirstRequiresSolvedWithNoWrongPicks() {
        XCTAssertTrue(ExceptionStepResult(stepID: "s", wrongPicks: 0, redHerringPicks: 0, solved: true).solvedBestFirst)
        XCTAssertFalse(ExceptionStepResult(stepID: "s", wrongPicks: 1, redHerringPicks: 0, solved: true).solvedBestFirst)
        XCTAssertFalse(ExceptionStepResult(stepID: "s", wrongPicks: 0, redHerringPicks: 0, solved: false).solvedBestFirst)
    }

    // MARK: - Scoring breakdowns

    func testPerfectRunScoresTheMaximum() {
        let exceptionCase = syntheticCase()
        let results = [
            ExceptionStepResult(stepID: "step-1", wrongPicks: 0, redHerringPicks: 0, solved: true),
            ExceptionStepResult(stepID: "step-2", wrongPicks: 0, redHerringPicks: 0, solved: true)
        ]
        let score = ExceptionLabScoring.breakdown(for: exceptionCase, stepResults: results, evidenceOpenedIDs: ["ev-1", "ev-2"])
        XCTAssertEqual(score.bestFirstPoints, 40)
        XCTAssertEqual(score.recoveredPoints, 0)
        XCTAssertEqual(score.wrongTurnDeductions, 0)
        XCTAssertEqual(score.redHerringDeductions, 0)
        XCTAssertEqual(score.efficiencyBonus, 10)
        XCTAssertEqual(score.thoroughnessPoints, 8)
        XCTAssertEqual(score.total, 58)
        XCTAssertEqual(score.maximum, 58)
        XCTAssertEqual(score.stepsSolvedBestFirst, 2)
        XCTAssertEqual(score.stepsSolvedAfterWrongTurn, 0)
        XCTAssertEqual(score.evidenceOpenedCount, 2)
        XCTAssertEqual(score.evidenceTotalCount, 2)
    }

    func testRecoveredStepScoresRecoveredPointsWithOneWrongTurnBonus() {
        let exceptionCase = syntheticCase()
        let results = [
            ExceptionStepResult(stepID: "step-1", wrongPicks: 1, redHerringPicks: 0, solved: true),
            ExceptionStepResult(stepID: "step-2", wrongPicks: 0, redHerringPicks: 0, solved: true)
        ]
        let score = ExceptionLabScoring.breakdown(for: exceptionCase, stepResults: results, evidenceOpenedIDs: ["ev-1"])
        XCTAssertEqual(score.bestFirstPoints, 20)
        XCTAssertEqual(score.recoveredPoints, 8)
        XCTAssertEqual(score.wrongTurnDeductions, 5)
        XCTAssertEqual(score.efficiencyBonus, 5)
        XCTAssertEqual(score.thoroughnessPoints, 4)
        XCTAssertEqual(score.total, 20 + 8 + 5 + 4 - 5)
        XCTAssertEqual(score.totalWrongPicks, 1)
        XCTAssertEqual(score.stepsSolvedAfterWrongTurn, 1)
    }

    func testTwoOrMoreWrongTurnsEarnNoEfficiencyBonus() {
        let exceptionCase = syntheticCase()
        let results = [
            ExceptionStepResult(stepID: "step-1", wrongPicks: 2, redHerringPicks: 0, solved: true),
            ExceptionStepResult(stepID: "step-2", wrongPicks: 0, redHerringPicks: 0, solved: true)
        ]
        let score = ExceptionLabScoring.breakdown(for: exceptionCase, stepResults: results, evidenceOpenedIDs: [])
        XCTAssertEqual(score.efficiencyBonus, 0)
        XCTAssertEqual(score.wrongTurnDeductions, 10)
        XCTAssertEqual(score.total, 20 + 8 - 10)
    }

    func testRedHerringPickCostsExtraOnTopOfTheWrongTurn() {
        let exceptionCase = syntheticCase()
        let results = [
            ExceptionStepResult(stepID: "step-1", wrongPicks: 1, redHerringPicks: 1, solved: true),
            ExceptionStepResult(stepID: "step-2", wrongPicks: 0, redHerringPicks: 0, solved: true)
        ]
        let score = ExceptionLabScoring.breakdown(for: exceptionCase, stepResults: results, evidenceOpenedIDs: [])
        XCTAssertEqual(score.wrongTurnDeductions, 5)
        XCTAssertEqual(score.redHerringDeductions, 10)
        XCTAssertEqual(score.totalRedHerringPicks, 1)
        XCTAssertEqual(score.total, 20 + 8 + 5 - 5 - 10)
    }

    func testOpeningARedHerringItemEarnsNothingAndCostsNothing() {
        let exceptionCase = syntheticCase()
        let results = [
            ExceptionStepResult(stepID: "step-1", wrongPicks: 0, redHerringPicks: 0, solved: true),
            ExceptionStepResult(stepID: "step-2", wrongPicks: 0, redHerringPicks: 0, solved: true)
        ]
        let score = ExceptionLabScoring.breakdown(for: exceptionCase, stepResults: results, evidenceOpenedIDs: ["ev-3"])
        XCTAssertEqual(score.thoroughnessPoints, 0)
        XCTAssertEqual(score.evidenceOpenedCount, 0)
        XCTAssertEqual(score.total, 50)
    }

    func testUnsolvedStepEarnsNoStepPoints() {
        let exceptionCase = syntheticCase()
        let results = [
            ExceptionStepResult(stepID: "step-1", wrongPicks: 0, redHerringPicks: 0, solved: true),
            ExceptionStepResult(stepID: "step-2", wrongPicks: 3, redHerringPicks: 0, solved: false)
        ]
        let score = ExceptionLabScoring.breakdown(for: exceptionCase, stepResults: results, evidenceOpenedIDs: [])
        XCTAssertEqual(score.bestFirstPoints, 20)
        XCTAssertEqual(score.recoveredPoints, 0)
        XCTAssertEqual(score.wrongTurnDeductions, 15)
        XCTAssertEqual(score.efficiencyBonus, 0)
        XCTAssertEqual(score.total, 5)
    }

    func testTotalFloorsAtZero() {
        let exceptionCase = syntheticCase()
        let results = [
            ExceptionStepResult(stepID: "step-1", wrongPicks: 5, redHerringPicks: 2, solved: true),
            ExceptionStepResult(stepID: "step-2", wrongPicks: 5, redHerringPicks: 0, solved: false)
        ]
        let score = ExceptionLabScoring.breakdown(for: exceptionCase, stepResults: results, evidenceOpenedIDs: [])
        XCTAssertEqual(score.total, 0)
        XCTAssertGreaterThan(score.wrongTurnDeductions + score.redHerringDeductions, score.recoveredPoints)
    }

    // MARK: - Store namespacing

    func testStoreKeysAreAccountNamespaced() {
        let store = ExceptionLabStore()
        store.recordCompletion(caseID: "lab-abh-01", breakdown: breakdown(total: 40, maximum: 58))
        XCTAssertEqual(store.completedCount, 1)
        XCTAssertNotNil(
            UserDefaults.standard.data(forKey: AccountScopedStorage.key(resultsBaseKey, namespace: namespaceA)),
            "The result must be stored under the current account namespace."
        )
        XCTAssertNil(
            UserDefaults.standard.object(forKey: resultsBaseKey),
            "The result must never be stored under the bare, unnamespaced key."
        )
        XCTAssertNil(
            UserDefaults.standard.object(forKey: AccountScopedStorage.key(resultsBaseKey, namespace: namespaceB)),
            "The result must not leak into another namespace."
        )
    }

    func testStoreDoesNotLeakAcrossNamespaces() {
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let firstStore = ExceptionLabStore()
        firstStore.recordCompletion(caseID: "lab-abh-01", breakdown: breakdown(total: 40, maximum: 58))
        XCTAssertTrue(firstStore.isCompleted("lab-abh-01"))

        AccountScopedStorage.setCurrentNamespace(namespaceB)
        let secondStore = ExceptionLabStore()
        XCTAssertEqual(secondStore.completedCount, 0, "The second namespace must not see the first namespace's results.")
        XCTAssertFalse(secondStore.isCompleted("lab-abh-01"))

        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let firstStoreAgain = ExceptionLabStore()
        XCTAssertEqual(firstStoreAgain.completedCount, 1, "Returning to the first namespace restores its results.")
    }

    func testReloadForCurrentAccountClearsInMemoryState() {
        AccountScopedStorage.setCurrentNamespace(namespaceA)
        let store = ExceptionLabStore()
        store.recordCompletion(caseID: "lab-abh-01", breakdown: breakdown(total: 40, maximum: 58))
        XCTAssertEqual(store.completedCount, 1)

        AccountScopedStorage.setCurrentNamespace(namespaceB)
        store.reloadForCurrentAccount()
        XCTAssertEqual(store.completedCount, 0, "Reloading for a new namespace must clear the previous account's results from memory.")

        AccountScopedStorage.setCurrentNamespace(namespaceA)
        store.reloadForCurrentAccount()
        XCTAssertEqual(store.completedCount, 1)
        XCTAssertEqual(store.result(for: "lab-abh-01")?.bestTotal, 40)
    }

    func testBestTotalIsKeptAndCompletionsCounted() {
        let store = ExceptionLabStore()
        store.recordCompletion(caseID: "lab-abh-01", breakdown: breakdown(total: 40, maximum: 58))
        store.recordCompletion(caseID: "lab-abh-01", breakdown: breakdown(total: 25, maximum: 58))
        let result = store.result(for: "lab-abh-01")
        XCTAssertEqual(result?.bestTotal, 40, "A lower retry must never lower the best total.")
        XCTAssertEqual(result?.completions, 2)
        XCTAssertEqual(store.completedCaseIDs, ["lab-abh-01"])
        store.recordCompletion(caseID: "lab-abh-01", breakdown: breakdown(total: 50, maximum: 58))
        XCTAssertEqual(store.result(for: "lab-abh-01")?.bestTotal, 50)
        XCTAssertEqual(store.result(for: "lab-abh-01")?.completions, 3)
    }
}
