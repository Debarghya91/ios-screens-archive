// InvestigationEngineTests.swift
// v71 unit tests: the investigation derivation rules in
// InvestigationEngine. An ABH-01 shaped fixture with the full
// marker structure, one unparsed-shape fixture, the NOT STATED
// fallbacks, the severity mapping, the payment-header regex, the
// decision min/max counts, and the 3-hypothesis rule. No network,
// no file reads: all fixtures are built inline in this file.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the implementation plan and checked
// against the final app source before writing.

import XCTest
@testable import TrainingHub

final class InvestigationEngineTests: XCTestCase {

    // MARK: - Fixtures

    /// The full marker structure: opening, flow header plus arrow
    /// list, flawed requirement, Why?, insight sentence, BA
    /// Takeaway with controls, real requirement, closing question.
    /// Arrow lines use the same arrow character the explain parser
    /// recognises. The flow list names pacs.008, pacs.009 and
    /// pacs.002, and one step is a decision step ("decided").
    private var abh01Explain: String {
        [
            "A customer sent EUR 50,000 to a beneficiary overseas. The money left the account, but nobody could say where it was.",
            "Here is what happened:",
            [
                "→ The sending bank sent a pacs.008 payment instruction.",
                "→ The payment moved through a correspondent bank using pacs.009.",
                "→ No pacs.002 status report came back.",
                "→ The operations team decided to wait for the next status update."
            ].joined(separator: "\n"),
            "The requirement said: \"Treat a payment as sent once the instruction leaves the bank.\"",
            "Why?",
            "The status report was never requested, so the bank had no confirmation that the payment reached the beneficiary bank.",
            "The missing status check was the gap.",
            "BA Takeaway",
            "Request a status report for every cross-border payment and check it before telling the customer the payment is complete.",
            [
                "Keep these controls separate:",
                "→ Check the status report before confirming completion.",
                "→ Record the UETR with the case notes."
            ].joined(separator: "\n"),
            "The real requirement is not to assume the payment arrived. It is to confirm arrival from the status report.",
            "Have you ever chased a payment with no status report?"
        ].joined(separator: "\n\n")
    }

    private var abh01Situation: Situation {
        Situation(
            id: "ABH-01",
            title: "EUR 50,000 sent, and nobody could say where it was",
            stage: 1,
            stageName: "Payment mechanics",
            level: .foundation,
            explain: abh01Explain,
            takeaway: "Confirm arrival from the status report before telling the customer the payment is complete.",
            isFreeSample: true,
            visual: nil
        )
    }

    /// No markers at all: one plain paragraph, no flow header, no
    /// Why?, no BA Takeaway, no message codes, no amount.
    private var unparsedSituation: Situation {
        Situation(
            id: "UNP-01",
            title: "A payment went missing",
            stage: 3,
            stageName: "Clearing and settlement",
            level: .core,
            explain: "A payment was sent in the morning and the beneficiary had not received it by the evening. The operations team could not explain the delay.",
            takeaway: "Check each stage of the payment journey before giving the customer an answer.",
            isFreeSample: false,
            visual: nil
        )
    }

    // MARK: - ABH-01 shaped fixture

    func testABH01CaseKeepsIdentityAndTitle() {
        let investigationCase = InvestigationEngine.caseFor(
            situation: abh01Situation,
            fullItem: nil,
            difficulty: .professional
        )
        XCTAssertEqual(investigationCase.id, "ABH-01")
        XCTAssertEqual(investigationCase.situationID, "ABH-01")
        XCTAssertEqual(investigationCase.title, abh01Situation.title)
        XCTAssertEqual(investigationCase.source, .derived)
        XCTAssertEqual(investigationCase.difficulty, .professional)
    }

    func testABH01BriefingIsNeverEmpty() {
        let investigationCase = InvestigationEngine.caseFor(
            situation: abh01Situation,
            fullItem: nil,
            difficulty: .professional
        )
        XCTAssertFalse(investigationCase.incidentReport.isEmpty)
        XCTAssertFalse(investigationCase.businessContext.isEmpty)
        XCTAssertFalse(investigationCase.customerImpact.isEmpty)
        XCTAssertFalse(investigationCase.incidentType.isEmpty)
        XCTAssertFalse(investigationCase.severity.isEmpty)
        XCTAssertEqual(investigationCase.objectives.count, 3)
        XCTAssertFalse(investigationCase.correctDiagnosis.isEmpty)
        XCTAssertFalse(investigationCase.correctiveAction.isEmpty)
        XCTAssertFalse(investigationCase.lessons.isEmpty)
        XCTAssertFalse(investigationCase.preventiveControls.isEmpty)
    }

    func testABH01EvidenceCoversTimelineMessagesAndLog() {
        let investigationCase = InvestigationEngine.caseFor(
            situation: abh01Situation,
            fullItem: nil,
            difficulty: .professional
        )
        XCTAssertFalse(investigationCase.timeline.isEmpty)
        XCTAssertTrue(investigationCase.timeline.allSatisfy { $0.kind == .timeline })
        XCTAssertFalse(investigationCase.evidence.isEmpty)
        let kinds = Set(investigationCase.evidence.map(\.kind))
        XCTAssertTrue(kinds.contains(.message), "Message codes in the explain must produce message evidence.")
        XCTAssertTrue(kinds.contains(.log), "Every case gets one log evidence item.")
        let messageTitles = investigationCase.evidence
            .filter { $0.kind == .message }
            .map { $0.title + " " + $0.body }
            .joined(separator: " ")
        XCTAssertTrue(messageTitles.contains("pacs.008"))
        XCTAssertTrue(messageTitles.contains("pacs.009"))
        XCTAssertTrue(messageTitles.contains("pacs.002"))
        XCTAssertTrue(investigationCase.evidence.allSatisfy { !$0.title.isEmpty && !$0.body.isEmpty })
        XCTAssertTrue(investigationCase.evidence.allSatisfy { !$0.isRedHerring }, "The derived tier never invents red herrings.")
    }

    func testABH01HypothesesAreExactlyThreeWithOneCorrect() {
        let investigationCase = InvestigationEngine.caseFor(
            situation: abh01Situation,
            fullItem: nil,
            difficulty: .professional
        )
        XCTAssertEqual(investigationCase.hypotheses.count, 3)
        XCTAssertEqual(investigationCase.hypotheses.filter(\.isCorrect).count, 1)
        XCTAssertTrue(investigationCase.hypotheses.allSatisfy { !$0.text.isEmpty })
    }

    func testABH01DecisionsWithinMinMaxAndHaveBestOption() {
        let investigationCase = InvestigationEngine.caseFor(
            situation: abh01Situation,
            fullItem: nil,
            difficulty: .professional
        )
        XCTAssertGreaterThanOrEqual(investigationCase.decisions.count, 2)
        XCTAssertLessThanOrEqual(investigationCase.decisions.count, 5)
        for decision in investigationCase.decisions {
            XCTAssertFalse(decision.prompt.isEmpty)
            XCTAssertGreaterThanOrEqual(decision.options.count, 2)
            XCTAssertTrue(decision.bestOptionIndex >= 0 && decision.bestOptionIndex < decision.options.count)
            XCTAssertTrue(decision.options[decision.bestOptionIndex].isBest)
            XCTAssertEqual(decision.options.filter(\.isBest).count, 1)
        }
        XCTAssertFalse(investigationCase.supportingEvidenceIDs.isEmpty)
    }

    func testABH01PaymentHeaderCarriesDerivedAmount() {
        let investigationCase = InvestigationEngine.caseFor(
            situation: abh01Situation,
            fullItem: nil,
            difficulty: .professional
        )
        XCTAssertTrue(investigationCase.paymentHeader.amountText.contains("50,000"))
        XCTAssertTrue(investigationCase.paymentHeader.currencyText.contains("EUR"))
        XCTAssertEqual(investigationCase.paymentHeader.referenceText, "Reference not stated in the case")
    }

    // MARK: - Unparsed shape and NOT STATED fallbacks

    func testUnparsedShapeStillBuildsACompleteCase() {
        let investigationCase = InvestigationEngine.caseFor(
            situation: unparsedSituation,
            fullItem: nil,
            difficulty: .professional
        )
        XCTAssertFalse(investigationCase.incidentReport.isEmpty)
        XCTAssertFalse(investigationCase.evidence.isEmpty)
        XCTAssertEqual(investigationCase.hypotheses.count, 3)
        XCTAssertEqual(investigationCase.hypotheses.filter(\.isCorrect).count, 1)
        XCTAssertGreaterThanOrEqual(investigationCase.decisions.count, 2)
        XCTAssertLessThanOrEqual(investigationCase.decisions.count, 5)
        XCTAssertFalse(investigationCase.correctDiagnosis.isEmpty)
        XCTAssertFalse(investigationCase.correctiveAction.isEmpty)
    }

    func testUnparsedShapeHasNoMessageEvidenceAndNotStatedHeader() {
        let investigationCase = InvestigationEngine.caseFor(
            situation: unparsedSituation,
            fullItem: nil,
            difficulty: .professional
        )
        XCTAssertFalse(
            investigationCase.evidence.contains { $0.kind == .message },
            "No message code anywhere means no message evidence is generated."
        )
        XCTAssertEqual(investigationCase.paymentHeader.amountText, "Amount not stated in the case")
        XCTAssertEqual(investigationCase.paymentHeader.referenceText, "Reference not stated in the case")
    }

    func testEmptyExplainStillBuildsFallbackCase() {
        let empty = Situation(
            id: "EMPTY-01",
            title: "A case with no text",
            stage: 1,
            stageName: "Payment mechanics",
            level: .foundation,
            explain: "",
            takeaway: "",
            isFreeSample: false,
            visual: nil
        )
        let investigationCase = InvestigationEngine.caseFor(
            situation: empty,
            fullItem: nil,
            difficulty: .professional
        )
        XCTAssertFalse(investigationCase.evidence.isEmpty)
        XCTAssertEqual(investigationCase.hypotheses.count, 3)
        XCTAssertGreaterThanOrEqual(investigationCase.decisions.count, 2)
    }

    // MARK: - Severity mapping

    func testSeverityMappingTable() {
        XCTAssertEqual(InvestigationEngine.severityLabel(level: .advanced, failureCategory: "duplicate"), "High")
        XCTAssertEqual(InvestigationEngine.severityLabel(level: .core, failureCategory: "duplicate"), "Medium")
        XCTAssertEqual(InvestigationEngine.severityLabel(level: .advanced, failureCategory: nil), "Moderate")
        XCTAssertEqual(InvestigationEngine.severityLabel(level: .core, failureCategory: nil), "Moderate")
        XCTAssertEqual(InvestigationEngine.severityLabel(level: .foundation, failureCategory: "duplicate"), "Moderate")
        XCTAssertEqual(InvestigationEngine.severityLabel(level: .foundation, failureCategory: nil), "Moderate")
    }

    func testSeverityOnBuiltCaseFollowsMapping() {
        let advanced = Situation(
            id: "ADV-01",
            title: "A stuck payment",
            stage: 6,
            stageName: "Exceptions",
            level: .advanced,
            explain: unparsedSituation.explain,
            takeaway: unparsedSituation.takeaway,
            isFreeSample: false,
            visual: nil
        )
        let investigationCase = InvestigationEngine.caseFor(
            situation: advanced,
            fullItem: nil,
            difficulty: .professional
        )
        XCTAssertEqual(investigationCase.severity, "Moderate", "No failure category on the item means Moderate even at advanced level.")
    }

    // MARK: - Payment header regex

    func testPaymentHeaderCurrencyCodes() {
        let header = InvestigationEngine.paymentHeader(
            title: "USD 12,500 returned by the beneficiary bank",
            explain: "The payment was returned."
        )
        XCTAssertTrue(header.amountText.contains("12,500"))
        XCTAssertTrue(header.currencyText.contains("USD"))
    }

    func testPaymentHeaderRupeeForms() {
        let rsHeader = InvestigationEngine.paymentHeader(
            title: "Rs 75000 stuck in clearing",
            explain: "The payment did not settle."
        )
        XCTAssertTrue(rsHeader.amountText.contains("75000"))
        let symbolHeader = InvestigationEngine.paymentHeader(
            title: "A payment of \u{20B9}25,000 failed",
            explain: "The payment failed."
        )
        XCTAssertTrue(symbolHeader.amountText.contains("25,000"))
    }

    func testPaymentHeaderKeepsScaleWordAfterCurrencyAmount() {
        let header = InvestigationEngine.paymentHeader(
            title: "EUR 40 million weekly settlement fails",
            explain: "The settlement failed."
        )
        XCTAssertEqual(header.amountText, "EUR 40 million")
        XCTAssertTrue(header.currencyText.contains("EUR"))
        let billionHeader = InvestigationEngine.paymentHeader(
            title: "USD 2.5 billion payment stuck in clearing",
            explain: "The payment is stuck."
        )
        XCTAssertEqual(billionHeader.amountText, "USD 2.5 billion")
        XCTAssertTrue(billionHeader.currencyText.contains("USD"))
    }

    func testPaymentHeaderKeepsScaleWordAfterRupeeAmount() {
        let header = InvestigationEngine.paymentHeader(
            title: "Rs 50 lakh transfer delayed",
            explain: "The transfer is delayed."
        )
        XCTAssertEqual(header.amountText, "Rs 50 lakh")
        XCTAssertTrue(header.currencyText.contains("INR"))
    }

    func testPaymentHeaderWithoutScaleWordIsUnchanged() {
        let header = InvestigationEngine.paymentHeader(
            title: "GBP 12,500 fee dispute",
            explain: "The fee is disputed."
        )
        XCTAssertEqual(header.amountText, "GBP 12,500")
        XCTAssertTrue(header.currencyText.contains("GBP"))
    }

    func testPaymentHeaderFallsBackToExplainWhenTitleHasNoAmount() {
        let header = InvestigationEngine.paymentHeader(
            title: "A payment went missing",
            explain: "The customer sent GBP 9,800 and the beneficiary never received it."
        )
        XCTAssertTrue(header.amountText.contains("9,800"))
        XCTAssertTrue(header.currencyText.contains("GBP"))
    }

    func testPaymentHeaderNoMatchIsNotStated() {
        let header = InvestigationEngine.paymentHeader(
            title: "A payment went missing",
            explain: "No amount is mentioned anywhere in this case."
        )
        XCTAssertEqual(header.amountText, "Amount not stated in the case")
        XCTAssertEqual(header.referenceText, "Reference not stated in the case")
        XCTAssertFalse(header.partiesText.isEmpty)
    }

    func testPaymentHeaderIgnoresBareNumbersWithoutCurrency() {
        let header = InvestigationEngine.paymentHeader(
            title: "5000 payments failed in one batch",
            explain: "The batch held 5000 payments."
        )
        XCTAssertEqual(header.amountText, "Amount not stated in the case")
    }

    // MARK: - Difficulty completeness

    func testProfessionalEvidenceIsAllComplete() {
        let investigationCase = InvestigationEngine.caseFor(
            situation: abh01Situation,
            fullItem: nil,
            difficulty: .professional
        )
        XCTAssertTrue(investigationCase.evidence.allSatisfy { $0.completeness.isComplete })
    }

    func testExpertStartsOneEvidenceItemPartial() {
        let investigationCase = InvestigationEngine.caseFor(
            situation: abh01Situation,
            fullItem: nil,
            difficulty: .expert
        )
        XCTAssertEqual(investigationCase.evidence.filter { !$0.completeness.isComplete }.count, 1)
    }

    func testRookieBuildsSameDecisionCountAsProfessional() {
        let rookie = InvestigationEngine.caseFor(
            situation: abh01Situation,
            fullItem: nil,
            difficulty: .rookie
        )
        let professional = InvestigationEngine.caseFor(
            situation: abh01Situation,
            fullItem: nil,
            difficulty: .professional
        )
        XCTAssertEqual(rookie.decisions.count, professional.decisions.count)
        XCTAssertEqual(rookie.hypotheses.count, professional.hypotheses.count)
        XCTAssertEqual(rookie.evidence.count, professional.evidence.count)
    }

    // MARK: - Lab adapter

    func testLabAdapterMapsAuthoredEvidenceOneToOne() {
        let labCase = ExceptionCase(
            id: "lab-test-01",
            incidentType: "Missing confirmation",
            title: "EUR 50,000 sent, and nobody could say where it was",
            level: .foundation,
            narrative: "A payment left the bank and no confirmation came back.",
            evidence: [
                ExceptionEvidence(id: "ev-1", title: "Status log", detail: "No status report arrived.", revealedAfterStep: 0, isRedHerring: false, redHerringNote: nil),
                ExceptionEvidence(id: "ev-2", title: "A misleading note", detail: "A note that leads away from the cause.", revealedAfterStep: 1, isRedHerring: true, redHerringNote: "This note is a distraction.")
            ],
            steps: [
                InvestigationStep(
                    id: "step-1",
                    prompt: "What should the investigator check first?",
                    options: [
                        InvestigationOption(text: "Check the status log.", isRedHerring: false, feedback: "Correct."),
                        InvestigationOption(text: "Wait for the customer to call.", isRedHerring: false, feedback: "Too slow.")
                    ],
                    bestOptionIndex: 0,
                    whyCorrect: "The log shows whether a status report arrived.",
                    wrongTurnCost: "Waiting loses time.",
                    evidenceNote: nil
                )
            ],
            resolution: "Request the status report and confirm arrival.",
            messages: ["pacs.008"],
            systems: ["Payment hub"],
            sourceSituationID: "ABH-01",
            sourceSituationTitle: "EUR 50,000 sent, and nobody could say where it was",
            sourceTakeaway: "Confirm arrival from the status report."
        )
        let investigationCase = InvestigationEngine.caseForLabCase(labCase, difficulty: .professional)
        XCTAssertEqual(investigationCase.id, "lab-test-01")
        XCTAssertEqual(investigationCase.situationID, "ABH-01")
        XCTAssertEqual(investigationCase.source, .authored)
        XCTAssertEqual(investigationCase.evidence.count, labCase.evidence.count)
        XCTAssertEqual(investigationCase.evidence.filter(\.isRedHerring).count, 1, "Authored red herrings are preserved.")
        XCTAssertGreaterThanOrEqual(investigationCase.decisions.count, labCase.steps.count)
        XCTAssertFalse(investigationCase.correctDiagnosis.isEmpty)
        XCTAssertFalse(investigationCase.correctiveAction.isEmpty)
        XCTAssertFalse(investigationCase.lessons.isEmpty)
    }

    // MARK: - Stage map fields via the full item

    /// FullSituationItem has no memberwise init, so the fixture is
    /// decoded from JSON, the same shape the data file ships. The
    /// messages and failure_category keys are the additive decoder
    /// fields the plan permits; when they are present the engine
    /// uses them for message evidence and severity.
    func testFullItemMessagesProduceMessageEvidence() throws {
        let json = """
        {
            "id": "ABH-01",
            "title": "EUR 50,000 sent, and nobody could say where it was",
            "level": "foundation",
            "explain": "A payment left the bank. The status report never arrived.",
            "takeaway": "Confirm arrival from the status report.",
            "stage": 1,
            "stage_name": "Payment mechanics",
            "domain": "Cross-border payments",
            "messages": ["pacs.008", "pacs.002"],
            "failure_category": "missing confirmation",
            "resolution": "investigate"
        }
        """
        let fullItem = try JSONDecoder().decode(FullSituationItem.self, from: Data(json.utf8))
        let plain = Situation(
            id: "ABH-01",
            title: fullItem.title,
            stage: 1,
            stageName: "Payment mechanics",
            level: .foundation,
            explain: fullItem.explain,
            takeaway: fullItem.takeaway,
            isFreeSample: true,
            visual: nil
        )
        let investigationCase = InvestigationEngine.caseFor(
            situation: plain,
            fullItem: fullItem,
            difficulty: .professional
        )
        let messageEvidence = investigationCase.evidence.filter { $0.kind == .message }
        XCTAssertEqual(messageEvidence.count, 2, "Stage map messages produce one message evidence item each.")
        XCTAssertTrue(messageEvidence.map(\.title).joined(separator: " ").contains("pacs.008"))
        XCTAssertTrue(messageEvidence.map(\.title).joined(separator: " ").contains("pacs.002"))
    }

    // MARK: - v72 defect fixes

    /// Timeline items carry a relative sequence marker, the amount
    /// and parties from the payment header, and a narrative body
    /// that never repeats the step title.
    func testTimelineItemsCarrySequenceAmountPartiesAndNarrative() {
        let investigationCase = InvestigationEngine.caseFor(
            situation: abh01Situation,
            fullItem: nil,
            difficulty: .professional
        )
        XCTAssertEqual(investigationCase.timeline.count, 4)
        for (offset, item) in investigationCase.timeline.enumerated() {
            XCTAssertFalse(item.body.isEmpty)
            XCTAssertNotEqual(item.body, item.title, "A timeline body must never repeat the step title.")
            XCTAssertFalse(item.body.contains("Step \(offset + 1) of"), "Structured step bullets must not appear in the body.")
            XCTAssertTrue(item.structuredLines.contains("Sequence: T+\(offset)"))
            XCTAssertTrue(item.structuredLines.contains("Amount: EUR 50,000"))
            XCTAssertTrue(item.structuredLines.contains("Parties: the customer and the beneficiary, through the sending bank and the beneficiary bank"))
        }
    }

    /// A case with no stated amount says so once per timeline item,
    /// in plain words, and never renders the title as filler.
    func testTimelineWithoutAmountStatesAbsenceOncePerItem() {
        let investigationCase = InvestigationEngine.caseFor(
            situation: unparsedSituation,
            fullItem: nil,
            difficulty: .professional
        )
        XCTAssertEqual(investigationCase.timeline.count, 1)
        let item = investigationCase.timeline[0]
        XCTAssertNotEqual(item.body, item.title)
        XCTAssertEqual(item.structuredLines.filter { $0.contains("not stated in the case") }.count, 1)
        XCTAssertTrue(item.structuredLines.contains("Sequence: T+0"))
    }

    /// Every hint guides method only: no hint names an answer, an
    /// evidence item, or a section of the case text.
    func testHintsNameNoAnswerAndNoEvidenceItem() {
        let options = [
            InvestigationDecisionOption(text: "First option.", isBest: true, feedback: "Good."),
            InvestigationDecisionOption(text: "Second option.", isBest: false, feedback: "Not best."),
        ]
        let decisions = [
            InvestigationDecisionPoint(
                id: "d-resolution", prompt: "What is the right corrective action?",
                options: options, bestOptionIndex: 0, whyCorrect: "Why.",
                isResolution: true
            ),
            InvestigationDecisionPoint(
                id: "d-first", prompt: "What should the investigator check first?",
                options: options, bestOptionIndex: 0, whyCorrect: "Why."
            ),
            InvestigationDecisionPoint(
                id: "d-technical", prompt: "What does the message prove?",
                options: options, bestOptionIndex: 0, whyCorrect: "Why.",
                isTechnical: true
            ),
            InvestigationDecisionPoint(
                id: "d-default", prompt: "What should the investigator do next?",
                options: options, bestOptionIndex: 0, whyCorrect: "Why."
            ),
        ]
        let forbidden = ["timeline", "message evidence", "real requirement", "last message", "message actually said"]
        for decision in decisions {
            let hint = InvestigationEngine.hintText(for: decision)
            XCTAssertFalse(hint.isEmpty)
            for phrase in forbidden {
                XCTAssertFalse(
                    hint.lowercased().contains(phrase),
                    "Hint must not name an answer or an evidence item: \(hint)"
                )
            }
        }
    }

    /// The diagnosis reads as a cause plus its mechanism, and the
    /// corrective action is a verb-led action shared by the report
    /// and the closing decision, never a quoted question.
    func testDiagnosisAndCorrectiveActionReadAsAProfessionalReport() {
        let investigationCase = InvestigationEngine.caseFor(
            situation: abh01Situation,
            fullItem: nil,
            difficulty: .professional
        )
        XCTAssertTrue(investigationCase.correctDiagnosis.hasPrefix("The root cause is that "))
        XCTAssertTrue(investigationCase.correctDiagnosis.contains("status report was never requested"))
        XCTAssertTrue(investigationCase.correctDiagnosis.contains("missing status check"))
        XCTAssertEqual(investigationCase.correctiveAction, "Confirm arrival from the status report.")
        XCTAssertFalse(investigationCase.correctiveAction.hasSuffix("?"))
        XCTAssertFalse(investigationCase.correctiveAction.contains("\""))
        let closing = investigationCase.decisions.last!
        XCTAssertEqual(closing.options[closing.bestOptionIndex].text, investigationCase.correctiveAction)
    }

    /// A real requirement phrased as a quoted question becomes a
    /// "Confirm ..." action, with the "is not" sentence skipped.
    func testQuotedQuestionRequirementBecomesConfirmAction() {
        let explain = [
            "A payment left the bank.",
            "Here is what happened:",
            "→ pacs.008 sent",
            "Why?",
            "pacs.008 is only the instruction.",
            "BA Takeaway",
            "→ Check the status report.",
            "The real requirement is not \"When do we show it as sent?\"",
            "It is \"What evidence proves the payment reached its destination?\"",
        ].joined(separator: "\n\n")
        let situation = Situation(
            id: "ABH-01",
            title: "EUR 50,000 sent, and nobody could say where it was",
            stage: 1,
            stageName: "Payment mechanics",
            level: .foundation,
            explain: explain,
            takeaway: "A message sent is not a payment completed.",
            isFreeSample: true,
            visual: nil
        )
        let investigationCase = InvestigationEngine.caseFor(
            situation: situation,
            fullItem: nil,
            difficulty: .professional
        )
        XCTAssertEqual(
            investigationCase.correctiveAction,
            "Confirm what evidence proves the payment reached its destination."
        )
    }

    /// No evidence panel repeats NOT STATED: absent fields are
    /// omitted from field tables, and each remaining absence is
    /// stated at most once per field per item, in plain words.
    func testNoEvidencePanelRepeatsNotStated() {
        for situation in [abh01Situation, unparsedSituation] {
            let investigationCase = InvestigationEngine.caseFor(
                situation: situation,
                fullItem: nil,
                difficulty: .professional
            )
            for item in investigationCase.evidence {
                let joined = ([item.body] + item.structuredLines).joined(separator: " ")
                XCTAssertFalse(joined.contains("NOT STATED"), "No panel may repeat NOT STATED: \(joined)")
                let absenceCount = joined.components(separatedBy: "not stated in the case").count - 1
                XCTAssertLessThanOrEqual(absenceCount, 2, "Absence must be stated at most once per field per item: \(joined)")
            }
            let messageItems = investigationCase.evidence.filter { $0.kind == .message }
            for item in messageItems {
                XCTAssertFalse(
                    item.structuredLines.contains { $0.hasPrefix("Reference:") },
                    "An unstated reference must be omitted from the message table."
                )
            }
        }
    }

    // MARK: - v73 defect fixes

    /// The processing log and the timeline share one sequence:
    /// one log line per flow step, in the same order, with the
    /// same T-label, starting at T+0, and each log line carries
    /// its timeline step title.
    func testLogLabelsMatchTimelineLabels() {
        let investigationCase = InvestigationEngine.caseFor(
            situation: abh01Situation,
            fullItem: nil,
            difficulty: .professional
        )
        let timeline = investigationCase.timeline
        XCTAssertEqual(timeline.count, 4)
        let logItems = investigationCase.evidence.filter { $0.kind == .log }
        XCTAssertEqual(logItems.count, 1)
        let logLines = logItems[0].structuredLines
        XCTAssertEqual(logLines.count, timeline.count, "The log must carry one line per timeline step.")
        for (offset, item) in timeline.enumerated() {
            let label = "T+\(offset)"
            XCTAssertTrue(
                item.structuredLines.contains("Sequence: \(label)"),
                "Timeline step \(offset) must carry \(label)."
            )
            XCTAssertTrue(
                logLines[offset].hasPrefix("\(label) "),
                "Log line \(offset) must carry the same label as its timeline step: \(logLines[offset])"
            )
            XCTAssertTrue(
                logLines[offset].contains(item.title),
                "Log line \(offset) must describe the same event as its timeline step."
            )
        }
        XCTAssertTrue(logLines[0].hasPrefix("T+0 "))
    }

    /// A case with no flow steps still starts its log at T+0,
    /// matching its single fallback timeline item.
    func testLogStartsAtT0WithoutFlowSteps() {
        let investigationCase = InvestigationEngine.caseFor(
            situation: unparsedSituation,
            fullItem: nil,
            difficulty: .professional
        )
        XCTAssertEqual(investigationCase.timeline.count, 1)
        XCTAssertTrue(investigationCase.timeline[0].structuredLines.contains("Sequence: T+0"))
        let logItems = investigationCase.evidence.filter { $0.kind == .log }
        XCTAssertEqual(logItems.count, 1)
        XCTAssertTrue(logItems[0].structuredLines[0].hasPrefix("T+0 "))
    }

    /// No hypothesis option may name an ISO or SWIFT message
    /// code, on any case shape.
    func testHypothesesContainNoMessageCodes() {
        let codePattern = "\\b(pacs\\.\\d{3}|pain\\.\\d{3}|camt\\.\\d{3}|MT\\d{3})\\b"
        for situation in [abh01Situation, unparsedSituation] {
            let investigationCase = InvestigationEngine.caseFor(
                situation: situation,
                fullItem: nil,
                difficulty: .professional
            )
            for hypothesis in investigationCase.hypotheses {
                XCTAssertNil(
                    hypothesis.text.range(of: codePattern, options: [.regularExpression, .caseInsensitive]),
                    "Hypothesis must not name a message code: \(hypothesis.text)"
                )
            }
        }
    }

    /// No hypothesis option may quote the report root-cause
    /// sentence or share any run of 8 or more words with it,
    /// and the three options must be distinct.
    func testHypothesesShareNoEightWordRunWithDiagnosis() {
        for situation in [abh01Situation, unparsedSituation] {
            let investigationCase = InvestigationEngine.caseFor(
                situation: situation,
                fullItem: nil,
                difficulty: .professional
            )
            XCTAssertEqual(investigationCase.hypotheses.count, 3)
            XCTAssertEqual(
                Set(investigationCase.hypotheses.map { $0.text.lowercased() }).count,
                3,
                "The three hypotheses must be distinct options."
            )
            for hypothesis in investigationCase.hypotheses {
                XCTAssertFalse(
                    investigationCase.correctDiagnosis.contains(hypothesis.text),
                    "Hypothesis must not quote the diagnosis verbatim: \(hypothesis.text)"
                )
                let shared = longestSharedWordRun(hypothesis.text, investigationCase.correctDiagnosis)
                XCTAssertLessThan(
                    shared, 8,
                    "Hypothesis shares a \(shared)-word run with the diagnosis: \(hypothesis.text)"
                )
            }
        }
    }

    /// The longest run of words two texts share verbatim, in
    /// order, comparing lowercase alphanumeric tokens. Mirrors
    /// the engine rule; kept in the test so the test does not
    /// depend on engine internals.
    private func longestSharedWordRun(_ first: String, _ second: String) -> Int {
        func words(_ text: String) -> [String] {
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        }
        let firstWords = words(first)
        let secondWords = words(second)
        guard !firstWords.isEmpty, !secondWords.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: secondWords.count + 1)
        var longest = 0
        for i in 1...firstWords.count {
            var current = [Int](repeating: 0, count: secondWords.count + 1)
            for j in 1...secondWords.count {
                if firstWords[i - 1] == secondWords[j - 1] {
                    current[j] = previous[j - 1] + 1
                    longest = max(longest, current[j])
                }
            }
            previous = current
        }
        return longest
    }
}
