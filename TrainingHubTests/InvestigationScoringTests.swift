// InvestigationScoringTests.swift
// v71 unit tests: the five-dimension scoring rules in
// InvestigationScoring. Dimension boundaries: a perfect run scores
// 100 on every dimension, wrong picks subtract from efficiency,
// diagnosis scores 100 or 0, and the overall score is the
// rounded mean of the five dimensions. No network, no file reads:
// the case fixture is built inline in this file.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the final app source before writing.

import XCTest
@testable import TrainingHub

final class InvestigationScoringTests: XCTestCase {

    // MARK: - Fixtures

    private func evidence(id: String) -> InvestigationEvidence {
        InvestigationEvidence(
            id: id,
            kind: .note,
            title: "Evidence \(id)",
            body: "Body for \(id).",
            structuredLines: [],
            sourceField: "explain",
            revealedAfterStep: 0,
            completeness: .complete,
            isRedHerring: false
        )
    }

    private func option(text: String, isBest: Bool, isRedHerring: Bool = false) -> InvestigationDecisionOption {
        InvestigationDecisionOption(
            text: text,
            isBest: isBest,
            feedback: "Feedback for \(text).",
            consequence: isBest ? "" : "A wrong turn.",
            isRedHerring: isRedHerring
        )
    }

    private func decision(
        id: String,
        bestOptionIndex: Int,
        isTechnical: Bool = false,
        isResolution: Bool = false,
        redHerringOptionIndex: Int? = nil
    ) -> InvestigationDecisionPoint {
        InvestigationDecisionPoint(
            id: id,
            prompt: "Prompt for \(id).",
            options: [
                option(text: "First option", isBest: bestOptionIndex == 0, isRedHerring: redHerringOptionIndex == 0),
                option(text: "Second option", isBest: bestOptionIndex == 1, isRedHerring: redHerringOptionIndex == 1)
            ],
            bestOptionIndex: bestOptionIndex,
            whyCorrect: "Why \(id) is correct.",
            isTechnical: isTechnical,
            isResolution: isResolution
        )
    }

    /// Four evidence items, two of them supporting; three
    /// hypotheses with one correct; two technical decisions, one
    /// resolution decision, and one plain decision.
    private func makeCase(
        supportingEvidenceIDs: [String] = ["ev-1", "ev-2"],
        decisions: [InvestigationDecisionPoint]? = nil
    ) -> InvestigationCase {
        InvestigationCase(
            id: "TEST-01",
            situationID: "TEST-01",
            title: "A test case",
            severity: "Moderate",
            incidentType: "Missing confirmation",
            businessContext: "Business context.",
            customerImpact: "Customer impact.",
            incidentReport: "Incident report.",
            objectives: ["Establish what happened to the payment."],
            paymentHeader: InvestigationPaymentHeader(
                amountText: "Amount not stated in the case",
                currencyText: "Not stated in the case",
                partiesText: "The customer sends the payment to the beneficiary.",
                referenceText: "Reference not stated in the case"
            ),
            timeline: [evidence(id: "ev-1")],
            evidence: ["ev-1", "ev-2", "ev-3", "ev-4"].map(evidence(id:)),
            hypotheses: [
                InvestigationHypothesis(id: "h-wrong-1", text: "The team assumed the payment had arrived.", isCorrect: false, source: .flawedRequirement),
                InvestigationHypothesis(id: "h-correct", text: "The root cause is: no status report was requested.", isCorrect: true, source: .rootCause),
                InvestigationHypothesis(id: "h-wrong-2", text: "A fault in a downstream system stopped the payment.", isCorrect: false, source: .categoryAlternative)
            ],
            decisions: decisions ?? [
                decision(id: "d-tech-1", bestOptionIndex: 0, isTechnical: true),
                decision(id: "d-tech-2", bestOptionIndex: 1, isTechnical: true),
                decision(id: "d-res-1", bestOptionIndex: 0, isResolution: true),
                decision(id: "d-plain-1", bestOptionIndex: 0)
            ],
            correctDiagnosis: "No status report was requested.",
            supportingEvidenceIDs: supportingEvidenceIDs,
            correctiveAction: "Request the status report.",
            preventiveControls: ["Check the status report before confirming completion."],
            lessons: ["Confirm arrival from the status report."],
            source: .derived,
            difficulty: .professional,
            reflectionPrompt: nil
        )
    }

    /// A run that opens every evidence item, picks every best
    /// option, cites a supporting item, and diagnoses correctly.
    private func perfectRun() -> InvestigationRun {
        var run = InvestigationRun()
        run.openedEvidenceIDs = ["ev-1", "ev-2", "ev-3", "ev-4"]
        run.decisionPicks = [
            "d-tech-1": 0,
            "d-tech-2": 1,
            "d-res-1": 0,
            "d-plain-1": 0
        ]
        run.citedEvidenceIDs = ["ev-1"]
        run.diagnosisHypothesisID = "h-correct"
        return run
    }

    // MARK: - Perfect run and overall mean

    func testPerfectRunScores100OnEveryDimension() {
        let report = InvestigationScoring.score(case: makeCase(), run: perfectRun())
        XCTAssertEqual(report.dimensionScores.evidenceInterpretation, 100)
        XCTAssertEqual(report.dimensionScores.efficiency, 100)
        XCTAssertEqual(report.dimensionScores.technicalAccuracy, 100)
        XCTAssertEqual(report.dimensionScores.rootCauseIdentification, 100)
        XCTAssertEqual(report.dimensionScores.resolutionQuality, 100)
        XCTAssertEqual(report.dimensionScores.overall, 100)
        XCTAssertEqual(report.wrongPicks, 0)
        XCTAssertEqual(report.decisionsCorrect, 4)
        XCTAssertEqual(report.decisionsTotal, 4)
        XCTAssertEqual(report.evidenceOpenedCount, 4)
        XCTAssertTrue(report.incorrectAssumptions.isEmpty)
    }

    func testReportCarriesCaseIdentityAndDifficulty() {
        let report = InvestigationScoring.score(case: makeCase(), run: perfectRun())
        XCTAssertEqual(report.caseID, "TEST-01")
        XCTAssertEqual(report.situationID, "TEST-01")
        XCTAssertEqual(report.difficulty, .professional)
        XCTAssertEqual(report.citedEvidenceIDs, ["ev-1"])
    }

    func testOverallIsRoundedMeanOfDimensions() {
        // Evidence 100, efficiency 90 (one wrong pick), technical
        // 50 (one of two correct), diagnosis 100 (correct pick;
        // the citation does not change this dimension), resolution
        // 100: mean 88 exactly.
        var run = perfectRun()
        run.decisionPicks["d-tech-2"] = 0
        run.citedEvidenceIDs = []
        let report = InvestigationScoring.score(case: makeCase(), run: run)
        XCTAssertEqual(report.dimensionScores.evidenceInterpretation, 100)
        XCTAssertEqual(report.dimensionScores.efficiency, 90)
        XCTAssertEqual(report.dimensionScores.technicalAccuracy, 50)
        XCTAssertEqual(report.dimensionScores.rootCauseIdentification, 100)
        XCTAssertEqual(report.dimensionScores.resolutionQuality, 100)
        XCTAssertEqual(report.dimensionScores.overall, 88)
    }

    func testOverallRoundsToNearestInteger() {
        XCTAssertEqual(
            InvestigationDimensionScores(
                evidenceInterpretation: 100,
                efficiency: 90,
                technicalAccuracy: 67,
                rootCauseIdentification: 50,
                resolutionQuality: 100
            ).overall,
            81,
            "407 / 5 = 81.4, rounded to 81."
        )
        XCTAssertEqual(
            InvestigationDimensionScores(
                evidenceInterpretation: 100,
                efficiency: 100,
                technicalAccuracy: 100,
                rootCauseIdentification: 100,
                resolutionQuality: 99
            ).overall,
            100,
            "499 / 5 = 99.8, rounded to 100."
        )
        XCTAssertEqual(
            InvestigationDimensionScores(
                evidenceInterpretation: 0,
                efficiency: 0,
                technicalAccuracy: 0,
                rootCauseIdentification: 0,
                resolutionQuality: 1
            ).overall,
            0,
            "1 / 5 = 0.2, rounded to 0."
        )
    }

    // MARK: - Efficiency: wrong picks subtract

    func testOneWrongPickMakesEfficiency90() {
        var run = perfectRun()
        run.decisionPicks["d-plain-1"] = 1
        let report = InvestigationScoring.score(case: makeCase(), run: run)
        XCTAssertEqual(report.dimensionScores.efficiency, 90)
        XCTAssertEqual(report.wrongPicks, 1)
        XCTAssertEqual(report.decisionsCorrect, 3)
    }

    func testTwoWrongPicksWithoutRedHerringMakesEfficiency90() {
        var run = perfectRun()
        run.decisionPicks["d-plain-1"] = 1
        run.decisionPicks["d-tech-1"] = 1
        let report = InvestigationScoring.score(case: makeCase(), run: run)
        XCTAssertEqual(report.dimensionScores.efficiency, 90, "100 minus 5 per wrong pick.")
        XCTAssertEqual(report.wrongPicks, 2)
    }

    func testSingleRedHerringPickStillMakesEfficiency90() {
        let redHerringCase = makeCase(decisions: [
            decision(id: "d-tech-1", bestOptionIndex: 0, isTechnical: true),
            decision(id: "d-tech-2", bestOptionIndex: 1, isTechnical: true),
            decision(id: "d-res-1", bestOptionIndex: 0, isResolution: true),
            decision(id: "d-plain-1", bestOptionIndex: 0, redHerringOptionIndex: 1)
        ])
        var run = perfectRun()
        run.decisionPicks["d-plain-1"] = 1
        let report = InvestigationScoring.score(case: redHerringCase, run: run)
        XCTAssertEqual(report.dimensionScores.efficiency, 90, "The one-wrong-pick mapping returns 90; the red herring extra charge applies from two wrong picks.")
    }

    func testRedHerringPickCostsAnExtra10FromTwoWrongPicks() {
        let redHerringCase = makeCase(decisions: [
            decision(id: "d-tech-1", bestOptionIndex: 0, isTechnical: true),
            decision(id: "d-tech-2", bestOptionIndex: 1, isTechnical: true),
            decision(id: "d-res-1", bestOptionIndex: 0, isResolution: true),
            decision(id: "d-plain-1", bestOptionIndex: 0, redHerringOptionIndex: 1)
        ])
        var run = perfectRun()
        run.decisionPicks["d-plain-1"] = 1
        run.decisionPicks["d-tech-1"] = 1
        let report = InvestigationScoring.score(case: redHerringCase, run: run)
        XCTAssertEqual(report.dimensionScores.efficiency, 80, "100 minus 10 for two wrong picks minus 10 for the red herring pick.")
    }

    func testEfficiencyFloorsAtZero() {
        var decisions: [InvestigationDecisionPoint] = []
        var picks: [String: Int] = [:]
        for index in 0..<30 {
            let id = "d-many-\(index)"
            decisions.append(decision(id: id, bestOptionIndex: 0))
            picks[id] = 1
        }
        let manyCase = makeCase(decisions: decisions)
        var run = InvestigationRun()
        run.openedEvidenceIDs = ["ev-1", "ev-2", "ev-3", "ev-4"]
        run.decisionPicks = picks
        run.citedEvidenceIDs = ["ev-1"]
        run.diagnosisHypothesisID = "h-correct"
        let report = InvestigationScoring.score(case: manyCase, run: run)
        XCTAssertEqual(report.dimensionScores.efficiency, 0, "100 minus 150 is floored at 0, never negative.")
        XCTAssertEqual(report.wrongPicks, 30)
    }

    func testOutOfRangePickCountsAsWrongWithoutRedHerringCharge() {
        var run = perfectRun()
        run.decisionPicks["d-plain-1"] = 99
        let report = InvestigationScoring.score(case: makeCase(), run: run)
        XCTAssertEqual(report.wrongPicks, 1)
        XCTAssertEqual(report.dimensionScores.efficiency, 90)
    }

    func testUnansweredDecisionsAreNotWrongPicks() {
        let run = InvestigationRun()
        let report = InvestigationScoring.score(case: makeCase(), run: run)
        XCTAssertEqual(report.wrongPicks, 0)
        XCTAssertEqual(report.dimensionScores.efficiency, 100, "No pick made means no wrong pick.")
        XCTAssertEqual(report.decisionsCorrect, 0)
        XCTAssertEqual(report.dimensionScores.technicalAccuracy, 0, "Unanswered technical decisions count as incorrect.")
        XCTAssertEqual(report.dimensionScores.resolutionQuality, 0, "Unanswered resolution decisions count as incorrect.")
    }

    // MARK: - Evidence interpretation

    func testEvidenceInterpretationIsShareOfRelevantOpened() {
        var run = perfectRun()
        run.openedEvidenceIDs = ["ev-1"]
        let report = InvestigationScoring.score(case: makeCase(), run: run)
        XCTAssertEqual(report.dimensionScores.evidenceInterpretation, 50, "One of two supporting items opened.")
    }

    func testEvidenceInterpretationIsZeroWhenNothingRelevantOpened() {
        var run = perfectRun()
        run.openedEvidenceIDs = ["ev-3", "ev-4"]
        let report = InvestigationScoring.score(case: makeCase(), run: run)
        XCTAssertEqual(report.dimensionScores.evidenceInterpretation, 0)
    }

    func testCitedEvidenceCountsAsRelevant() {
        var run = perfectRun()
        run.openedEvidenceIDs = ["ev-1"]
        run.citedEvidenceIDs = ["ev-4"]
        let report = InvestigationScoring.score(case: makeCase(), run: run)
        XCTAssertEqual(
            report.dimensionScores.evidenceInterpretation,
            33,
            "Relevant is supporting plus cited: one of three opened, 33.33 rounded to 33."
        )
    }

    func testEvidenceInterpretationDefaultsTo100WithNoRelevantEvidence() {
        let noSupportingCase = makeCase(supportingEvidenceIDs: [])
        var run = InvestigationRun()
        run.decisionPicks = [
            "d-tech-1": 0,
            "d-tech-2": 1,
            "d-res-1": 0,
            "d-plain-1": 0
        ]
        run.diagnosisHypothesisID = "h-correct"
        let report = InvestigationScoring.score(case: noSupportingCase, run: run)
        XCTAssertEqual(report.dimensionScores.evidenceInterpretation, 100)
    }

    func testEvidenceOpenedCountIgnoresUnknownIDs() {
        var run = perfectRun()
        run.openedEvidenceIDs = ["ev-1", "not-a-case-item"]
        let report = InvestigationScoring.score(case: makeCase(), run: run)
        XCTAssertEqual(report.evidenceOpenedCount, 1)
    }

    // MARK: - Technical accuracy and resolution quality

    func testTechnicalAccuracyIsShareOfTechnicalDecisionsCorrect() {
        var run = perfectRun()
        run.decisionPicks["d-tech-2"] = 0
        let report = InvestigationScoring.score(case: makeCase(), run: run)
        XCTAssertEqual(report.dimensionScores.technicalAccuracy, 50)
        XCTAssertEqual(report.dimensionScores.resolutionQuality, 100, "A technical miss does not touch resolution quality.")
    }

    func testTechnicalAccuracyDefaultsTo100WithNoTechnicalDecisions() {
        let plainCase = makeCase(decisions: [decision(id: "d-plain-1", bestOptionIndex: 0)])
        var run = InvestigationRun()
        run.openedEvidenceIDs = ["ev-1", "ev-2"]
        run.decisionPicks = ["d-plain-1": 1]
        run.citedEvidenceIDs = ["ev-1"]
        run.diagnosisHypothesisID = "h-correct"
        let report = InvestigationScoring.score(case: plainCase, run: run)
        XCTAssertEqual(report.dimensionScores.technicalAccuracy, 100)
        XCTAssertEqual(report.dimensionScores.resolutionQuality, 100)
    }

    func testResolutionQualityIsShareOfResolutionDecisionsCorrect() {
        let resolutionCase = makeCase(decisions: [
            decision(id: "d-res-1", bestOptionIndex: 0, isResolution: true),
            decision(id: "d-res-2", bestOptionIndex: 1, isResolution: true),
            decision(id: "d-res-3", bestOptionIndex: 0, isResolution: true)
        ])
        var run = InvestigationRun()
        run.openedEvidenceIDs = ["ev-1", "ev-2"]
        run.decisionPicks = ["d-res-1": 0, "d-res-2": 1, "d-res-3": 1]
        run.citedEvidenceIDs = ["ev-1"]
        run.diagnosisHypothesisID = "h-correct"
        let report = InvestigationScoring.score(case: resolutionCase, run: run)
        XCTAssertEqual(report.dimensionScores.resolutionQuality, 67, "Two of three correct, 66.67 rounded to 67.")
    }

    // MARK: - Diagnosis: 100 or 0

    func testDiagnosis100WithCorrectPickAndSupportingCitation() {
        let report = InvestigationScoring.score(case: makeCase(), run: perfectRun())
        XCTAssertEqual(report.dimensionScores.rootCauseIdentification, 100)
    }

    func testDiagnosis100WithCorrectPickButNonSupportingCitation() {
        var run = perfectRun()
        run.citedEvidenceIDs = ["ev-3"]
        let report = InvestigationScoring.score(case: makeCase(), run: run)
        XCTAssertEqual(report.dimensionScores.rootCauseIdentification, 100, "The pick is correct, so the dimension is 100 even though the cited item does not support it.")
    }

    func testDiagnosis100WithCorrectPickAndNoCitation() {
        var run = perfectRun()
        run.citedEvidenceIDs = []
        let report = InvestigationScoring.score(case: makeCase(), run: run)
        XCTAssertEqual(report.dimensionScores.rootCauseIdentification, 100, "The pick is correct, so the dimension is 100; the citation gate still requires a citation to submit.")
    }

    func testDiagnosis0WithWrongPickEvenWhenCitationSupports() {
        var run = perfectRun()
        run.diagnosisHypothesisID = "h-wrong-1"
        let report = InvestigationScoring.score(case: makeCase(), run: run)
        XCTAssertEqual(report.dimensionScores.rootCauseIdentification, 0)
    }

    func testDiagnosis0WithNoPick() {
        var run = perfectRun()
        run.diagnosisHypothesisID = nil
        let report = InvestigationScoring.score(case: makeCase(), run: run)
        XCTAssertEqual(report.dimensionScores.rootCauseIdentification, 0)
    }

    func testDiagnosis0WithUnknownHypothesisID() {
        var run = perfectRun()
        run.diagnosisHypothesisID = "no-such-hypothesis"
        let report = InvestigationScoring.score(case: makeCase(), run: run)
        XCTAssertEqual(report.dimensionScores.rootCauseIdentification, 0)
    }

    // MARK: - Incorrect assumptions

    func testIncorrectAssumptionsRecordRevisedAwayWrongHypotheses() {
        var run = perfectRun()
        run.hypothesisRevisions = [("h-wrong-1", "h-correct")]
        let report = InvestigationScoring.score(case: makeCase(), run: run)
        XCTAssertEqual(report.incorrectAssumptions, ["The team assumed the payment had arrived."])
    }

    func testIncorrectAssumptionsIncludeWrongDiagnosisOnce() {
        var run = perfectRun()
        run.hypothesisRevisions = [("h-wrong-1", "h-wrong-2"), ("h-wrong-1", "h-correct")]
        run.diagnosisHypothesisID = "h-wrong-1"
        let report = InvestigationScoring.score(case: makeCase(), run: run)
        XCTAssertEqual(
            report.incorrectAssumptions,
            ["The team assumed the payment had arrived."],
            "The same wrong hypothesis revised away and diagnosed appears once."
        )
    }

    func testRevisingAwayFromCorrectHypothesisIsNotAnIncorrectAssumption() {
        var run = perfectRun()
        run.hypothesisRevisions = [("h-correct", "h-wrong-1")]
        run.diagnosisHypothesisID = "h-correct"
        let report = InvestigationScoring.score(case: makeCase(), run: run)
        XCTAssertTrue(report.incorrectAssumptions.isEmpty)
    }

    // MARK: - v73 auto-displayed evidence

    /// A run that opened only the auto-displayed first item (the
    /// view initialises the opened set with it when the
    /// investigation starts) counts that item: the opened count
    /// is 1, and the evidence-interpretation score counts the
    /// supporting item it opened.
    func testAutoDisplayedFirstItemCountsAsOpened() {
        var run = InvestigationRun()
        run.openedEvidenceIDs = ["ev-1"]
        let report = InvestigationScoring.score(case: makeCase(), run: run)
        XCTAssertEqual(report.evidenceOpenedCount, 1)
        XCTAssertEqual(
            report.dimensionScores.evidenceInterpretation, 50,
            "One of two supporting items opened scores 50."
        )
    }
}
