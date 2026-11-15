// ExceptionCases.swift
// Payments Training Hub iOS - Payment Exception Investigation Lab cases.
//
// Each case is an investigation exercise built from one real Payment
// Situation: the narrative and evidence paraphrase that situation's
// explain text, and the resolution paraphrases its BA Takeaway. The
// situation's own takeaway is carried verbatim as sourceTakeaway and
// is shown only inside an unlocked case, the same way Practice Mode
// shows a takeaway after the learner decides. No scheme-specific
// mandatory rule is invented here: every rule a case teaches comes
// from its source situation, and incident mechanics stay general and
// educational. A case with no sourceSituationID is a purely authored
// teaching exercise, labelled "Practice exercise" in the UI, and must
// never carry a source takeaway.
//
// Cases are ordered by SituationLevel, foundation first, then core,
// then advanced, so investigations get progressively harder.
// Foundation cases have 3 steps with 3 options each; core cases have
// 3 steps with 4 options; advanced cases have 4 steps with 4 options.
//
// Gating (settled, follows the existing Investigation Lab entitlement only):
// a case grounded in a non-free situation requires
// StoreManager.isInvestigationLabUnlocked; a case grounded in a free-sample
// situation (ContentService.freeSampleIDs) is open to all; a purely
// authored practice exercise is open to all. This file defines the
// rule through requiresSituationsUnlock; it changes no gating code.
// No em dashes in any user-facing text.

import Foundation

// MARK: - Evidence

/// One piece of evidence in a case. Evidence is revealed as the
/// learner investigates: an item becomes visible once
/// revealedAfterStep steps have been solved (0 means visible from
/// the start). A red herring item looks relevant but leads away from
/// the true cause; its note explains why, and the note is shown only
/// in the completed-case summary, never during play.
struct ExceptionEvidence: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let revealedAfterStep: Int
    let isRedHerring: Bool
    let redHerringNote: String?
}

// MARK: - Investigation options and steps

/// One possible next action in an investigation step. Exactly one
/// option per step is the best next step (see
/// InvestigationStep.bestOptionIndex). A red herring option follows
/// a distraction in the evidence instead of the investigation; picking
/// it costs more than an ordinary wrong turn. Every option carries
/// its own feedback, shown after the learner picks it.
struct InvestigationOption: Hashable {
    let text: String
    let isRedHerring: Bool
    let feedback: String
}

/// One investigation step: the learner selects the next action from
/// the options. whyCorrect explains why the best option is correct;
/// wrongTurnCost explains what an incorrect investigation at this
/// point would cause. evidenceNote, when present, names what the
/// correct action reveals, and is shown with the feedback for the
/// best option.
struct InvestigationStep: Identifiable, Hashable {
    let id: String
    let prompt: String
    let options: [InvestigationOption]
    let bestOptionIndex: Int
    let whyCorrect: String
    let wrongTurnCost: String
    let evidenceNote: String?
}

// MARK: - Exception case

/// One investigation case in the lab.
struct ExceptionCase: Identifiable, Hashable {
    let id: String
    /// The incident type, one of the lab's incident types, for
    /// example "Missing confirmation" or "Duplicate transaction".
    let incidentType: String
    /// The case title. For a grounded case this is the source
    /// situation's title, verbatim.
    let title: String
    let level: SituationLevel
    /// The incident narrative, paraphrased from the source
    /// situation's explain text.
    let narrative: String
    let evidence: [ExceptionEvidence]
    let steps: [InvestigationStep]
    /// The final resolution, paraphrased from the source
    /// situation's BA Takeaway section.
    let resolution: String
    /// Payment messages named in the source situation. Empty when
    /// the source situation names no message; the UI says so
    /// honestly instead of inventing one.
    let messages: [String]
    /// System components involved in the incident, in general
    /// terms taken from the source situation.
    let systems: [String]
    /// The source situation id, or nil for a purely authored
    /// practice exercise.
    let sourceSituationID: String?
    /// The source situation title, or nil for a practice exercise.
    let sourceSituationTitle: String?
    /// The source situation's takeaway, verbatim, or nil for a
    /// practice exercise. Shown only inside an unlocked case.
    let sourceTakeaway: String?

    /// True when this case is a purely authored teaching exercise
    /// with no source situation. Such cases are open to all and
    /// labelled "Practice exercise" in the UI.
    var isPracticeExercise: Bool { sourceSituationID == nil }

    /// True when this case is grounded in one of the free-sample
    /// situations. The free-sample list is ContentService's single
    /// source of truth; it is never copied here.
    var isGroundedInFreeSample: Bool {
        guard let sourceSituationID else { return false }
        return ContentService.freeSampleIDs.contains(sourceSituationID)
    }

    /// True when opening this case requires the situations
    /// entitlement. Grounded non-free cases require it; free-sample
    /// and practice-exercise cases do not.
    var requiresSituationsUnlock: Bool {
        sourceSituationID != nil && !isGroundedInFreeSample
    }

    /// Evidence items that are genuine clues, used for the
    /// thoroughness part of the score. Opening a red herring item
    /// is investigation, not an error, so it earns no points and
    /// costs none; acting on a red herring option is what costs.
    var genuineEvidenceCount: Int {
        evidence.filter { !$0.isRedHerring }.count
    }
}

// MARK: - Scoring

/// How one step was solved, recorded by the play view as the learner
/// investigates. A step is solved only when the best option is
/// picked; wrong picks before that are recorded as wrong turns.
struct ExceptionStepResult: Hashable {
    let stepID: String
    let wrongPicks: Int
    let redHerringPicks: Int
    let solved: Bool

    /// True when the step was solved on the first pick, with no
    /// wrong turn before it.
    var solvedBestFirst: Bool { solved && wrongPicks == 0 }
}

/// The score breakdown for one completed case. Scores measure
/// investigation quality, not just a right or wrong answer: points
/// for best-first actions, deductions for wrong turns and red
/// herrings, plus efficiency and thoroughness. Deduction fields hold
/// positive magnitudes; the UI shows them with a minus sign. The
/// total is never below zero.
struct ExceptionLabScoreBreakdown: Codable, Hashable {
    let bestFirstPoints: Int
    let recoveredPoints: Int
    let wrongTurnDeductions: Int
    let redHerringDeductions: Int
    let efficiencyBonus: Int
    let thoroughnessPoints: Int
    let total: Int
    let maximum: Int
    let stepsSolvedBestFirst: Int
    let stepsSolvedAfterWrongTurn: Int
    let totalWrongPicks: Int
    let totalRedHerringPicks: Int
    let evidenceOpenedCount: Int
    let evidenceTotalCount: Int
}

/// Pure scoring rules for the lab. The UI copy in
/// ExceptionInvestigationLabView states these same numbers from
/// these same constants, so the two can never drift apart.
enum ExceptionLabScoring {
    /// Points for solving a step on the first pick.
    static let bestFirstPointsPerStep = 20
    /// Points for solving a step after at least one wrong turn.
    static let recoveredPointsPerStep = 8
    /// Deduction for each wrong turn (a pick that is not the best
    /// next step).
    static let wrongPickDeduction = 5
    /// Extra deduction for each red herring pick, on top of the
    /// wrong-turn deduction: chasing a distraction costs more.
    static let redHerringPickDeduction = 10
    /// Efficiency bonus for completing a case with no wrong turn.
    static let efficiencyBonusNoWrongTurn = 10
    /// Efficiency bonus for completing a case with exactly one
    /// wrong turn.
    static let efficiencyBonusOneWrongTurn = 5
    /// Points for opening each genuine piece of evidence.
    static let thoroughnessPointsPerEvidence = 4

    /// The highest score a case can earn: every step solved
    /// best-first, the full efficiency bonus, and every genuine
    /// piece of evidence opened.
    static func maximum(for exceptionCase: ExceptionCase) -> Int {
        exceptionCase.steps.count * bestFirstPointsPerStep
            + efficiencyBonusNoWrongTurn
            + exceptionCase.genuineEvidenceCount * thoroughnessPointsPerEvidence
    }

    /// The score breakdown for a completed case. stepResults must
    /// hold one result per step, in step order; evidenceOpenedIDs
    /// holds the ids of the evidence items the learner opened.
    static func breakdown(
        for exceptionCase: ExceptionCase,
        stepResults: [ExceptionStepResult],
        evidenceOpenedIDs: Set<String>
    ) -> ExceptionLabScoreBreakdown {
        let bestFirst = stepResults.filter { $0.solvedBestFirst }.count
        let recovered = stepResults.filter { $0.solved && !$0.solvedBestFirst }.count
        let wrongPicks = stepResults.reduce(0) { $0 + $1.wrongPicks }
        let redHerringPicks = stepResults.reduce(0) { $0 + $1.redHerringPicks }
        let openedGenuine = exceptionCase.evidence.filter {
            !$0.isRedHerring && evidenceOpenedIDs.contains($0.id)
        }.count
        let efficiency: Int
        if wrongPicks == 0 {
            efficiency = efficiencyBonusNoWrongTurn
        } else if wrongPicks == 1 {
            efficiency = efficiencyBonusOneWrongTurn
        } else {
            efficiency = 0
        }
        let bestFirstPoints = bestFirst * bestFirstPointsPerStep
        let recoveredPoints = recovered * recoveredPointsPerStep
        let wrongTurnDeductions = wrongPicks * wrongPickDeduction
        let redHerringDeductions = redHerringPicks * redHerringPickDeduction
        let thoroughnessPoints = openedGenuine * thoroughnessPointsPerEvidence
        let total = max(
            0,
            bestFirstPoints + recoveredPoints + efficiency + thoroughnessPoints
                - wrongTurnDeductions - redHerringDeductions
        )
        return ExceptionLabScoreBreakdown(
            bestFirstPoints: bestFirstPoints,
            recoveredPoints: recoveredPoints,
            wrongTurnDeductions: wrongTurnDeductions,
            redHerringDeductions: redHerringDeductions,
            efficiencyBonus: efficiency,
            thoroughnessPoints: thoroughnessPoints,
            total: total,
            maximum: maximum(for: exceptionCase),
            stepsSolvedBestFirst: bestFirst,
            stepsSolvedAfterWrongTurn: recovered,
            totalWrongPicks: wrongPicks,
            totalRedHerringPicks: redHerringPicks,
            evidenceOpenedCount: openedGenuine,
            evidenceTotalCount: exceptionCase.genuineEvidenceCount
        )
    }
}

// MARK: - Catalogue

/// All investigation cases, in play order: foundation first, then
/// core, then advanced. Every case in this catalogue is grounded in
/// a real situation; there are no purely authored practice exercises
/// in this version, because a matching situation exists for every
/// incident type the lab covers.
enum ExceptionCaseCatalogue {
    static let allCases: [ExceptionCase] = [
        missingConfirmationCase,
        invalidBeneficiaryCase,
        returnReceivedCase,
        validationRejectionCase,
        duplicateTransactionCase,
        sanctionsHoldCase,
        chargeHandlingCase,
        insufficientFundsCase,
        settlementDelayCase,
        reconciliationBreakCase,
        clearingRejectionCase,
        downstreamTimeoutCase,
    ]

    /// Structural checks over the catalogue: steps carry at least
    /// 3 options with exactly one best option in range, evidence
    /// ids are unique and reveal in range, levels never step back,
    /// and no authored case carries a source takeaway. Returns the
    /// problems found, empty when the catalogue is sound. Pure
    /// logic with no UI, so it can be covered by unit tests.
    static func checkCatalogue() -> [String] {
        var issues: [String] = []
        var previousOrder = -1
        for exceptionCase in allCases {
            let order: Int
            switch exceptionCase.level {
            case .foundation: order = 0
            case .core: order = 1
            case .advanced: order = 2
            }
            if order < previousOrder {
                issues.append("\(exceptionCase.id): level steps back from the previous case.")
            }
            previousOrder = order
            if exceptionCase.steps.isEmpty {
                issues.append("\(exceptionCase.id): no investigation steps.")
            }
            for step in exceptionCase.steps {
                if step.options.count < 3 {
                    issues.append("\(step.id): fewer than 3 options.")
                }
                if step.bestOptionIndex < 0 || step.bestOptionIndex >= step.options.count {
                    issues.append("\(step.id): best option index out of range.")
                }
            }
            let evidenceIDs = exceptionCase.evidence.map { $0.id }
            if Set(evidenceIDs).count != evidenceIDs.count {
                issues.append("\(exceptionCase.id): duplicate evidence ids.")
            }
            for item in exceptionCase.evidence {
                if item.revealedAfterStep < 0 || item.revealedAfterStep > exceptionCase.steps.count {
                    issues.append("\(item.id): reveal step out of range.")
                }
                if item.isRedHerring && (item.redHerringNote ?? "").isEmpty {
                    issues.append("\(item.id): red herring with no explanation note.")
                }
            }
            if exceptionCase.isPracticeExercise && exceptionCase.sourceTakeaway != nil {
                issues.append("\(exceptionCase.id): practice exercise carries a source takeaway.")
            }
            if exceptionCase.sourceSituationID == nil && exceptionCase.sourceSituationTitle != nil {
                issues.append("\(exceptionCase.id): practice exercise carries a source title.")
            }
        }
        return issues
    }
}

// MARK: - Foundation cases

extension ExceptionCaseCatalogue {

    /// Missing confirmation, grounded in ABH-01 (free sample).
    static let missingConfirmationCase = ExceptionCase(
        id: "lab-abh-01",
        incidentType: "Missing confirmation",
        title: "EUR 50,000 sent, and nobody could say where it was",
        level: .foundation,
        narrative: "A corporate customer sent EUR 50,000 to a supplier. The money left the account. Three days later, nobody could say where it was, because the screen showed the payment as sent once the instruction went out and the team stopped looking.",
        evidence: [
            ExceptionEvidence(
                id: "abh-01-e1",
                title: "Customer instruction",
                detail: "A pain.001 instruction was raised by the customer for EUR 50,000 to the supplier.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "abh-01-e2",
                title: "Screen status",
                detail: "The payment screen shows Sent. It was set to show Sent once pacs.008 went out, and the team stopped looking after that.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "abh-01-e3",
                title: "Status report never checked",
                detail: "No pacs.002 status report was ever checked for this payment.",
                revealedAfterStep: 1,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "abh-01-e4",
                title: "No investigation, no return",
                detail: "No pacs.028 status request was sent, and no pacs.004 return arrived.",
                revealedAfterStep: 2,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "abh-01-e5",
                title: "Supplier asks for a resend",
                detail: "The supplier says they have not been paid and asks the customer to send the money again.",
                revealedAfterStep: 0,
                isRedHerring: true,
                redHerringNote: "The supplier cannot see inside the chain. A resend before the status is known risks paying twice."
            ),
        ],
        steps: [
            InvestigationStep(
                id: "abh-01-s1",
                prompt: "The customer asks where the EUR 50,000 is. The screen says Sent. What is the best first step?",
                options: [
                    InvestigationOption(
                        text: "Check the pacs.002 status report for this payment.",
                        isRedHerring: false,
                        feedback: "Right instinct. The status report is where the current state lives."
                    ),
                    InvestigationOption(
                        text: "Tell the customer the payment is complete because the screen says Sent.",
                        isRedHerring: false,
                        feedback: "Sent on this screen only means the instruction went out. It does not prove the payment arrived."
                    ),
                    InvestigationOption(
                        text: "Ask the customer to send the payment again.",
                        isRedHerring: true,
                        feedback: "Resending before the status is known risks paying the supplier twice."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "pacs.008 proves only that the instruction was sent. The status lives in pacs.002, so checking it first replaces a guess with evidence.",
                wrongTurnCost: "Calling the payment complete, or resending it, can leave the customer paying twice while the first payment is still moving.",
                evidenceNote: "The pacs.002 check reveals whether any status was ever recorded for this payment."
            ),
            InvestigationStep(
                id: "abh-01-s2",
                prompt: "No pacs.002 status was ever checked for this payment, and no final status is on file. What next?",
                options: [
                    InvestigationOption(
                        text: "Send a pacs.028 status request to ask what happened to the payment.",
                        isRedHerring: false,
                        feedback: "A status request opens a real investigation instead of waiting on a screen that already stopped looking."
                    ),
                    InvestigationOption(
                        text: "Wait and check the same screen again tomorrow.",
                        isRedHerring: false,
                        feedback: "The screen only repeats what it showed before. Waiting adds no new evidence."
                    ),
                    InvestigationOption(
                        text: "Raise a return for a payment that may not have arrived.",
                        isRedHerring: false,
                        feedback: "A return answers a different question. It cannot be raised until the payment state is known."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "When the status report holds nothing, pacs.028 asks the chain what happened, and pacs.029 carries the answer.",
                wrongTurnCost: "Waiting, or raising a return on an unknown state, leaves the customer without an answer and can start the wrong process.",
                evidenceNote: "The investigation confirms no pacs.028 was ever sent and no pacs.004 return arrived."
            ),
            InvestigationStep(
                id: "abh-01-s3",
                prompt: "The investigation shows the payment is still in the chain and no return has arrived. What do you tell the customer?",
                options: [
                    InvestigationOption(
                        text: "The instruction was sent, the status is being traced, and no return has arrived, so do not resend yet.",
                        isRedHerring: false,
                        feedback: "An honest status with a clear next step. The customer knows what is proved and what is still being traced."
                    ),
                    InvestigationOption(
                        text: "The payment has failed.",
                        isRedHerring: false,
                        feedback: "Nothing proves failure. A payment still in the chain is not a failed payment."
                    ),
                    InvestigationOption(
                        text: "The money is with the supplier.",
                        isRedHerring: false,
                        feedback: "No evidence proves the supplier was credited. Saying so would mislead the customer."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "Each message answers a different question, so the update reports exactly what each one proves and nothing more.",
                wrongTurnCost: "Calling the payment failed, or claiming it arrived, sends the customer down the wrong path and can trigger a duplicate payment.",
                evidenceNote: nil
            ),
        ],
        resolution: "Keep each pacs message separate. pacs.008 answers whether the instruction was sent, pacs.002 answers what the status is now, pacs.028 and pacs.029 answer what is being investigated, and pacs.004 answers whether the money came back. A payment is complete only when the evidence proves it reached its destination, not when a screen says Sent.",
        messages: ["pain.001", "pacs.008", "pacs.002", "pacs.028", "pacs.029", "pacs.004"],
        systems: ["Customer payment screen", "Payment hub", "Status reporting"],
        sourceSituationID: "ABH-01",
        sourceSituationTitle: "EUR 50,000 sent, and nobody could say where it was",
        sourceTakeaway: "A message sent is not a payment completed."
    )

    /// Invalid beneficiary information, grounded in JEB-C01 (free sample).
    static let invalidBeneficiaryCase = ExceptionCase(
        id: "lab-jeb-c01",
        incidentType: "Invalid beneficiary information",
        title: "VoP said No Match, GBP 12,000 went anyway",
        level: .foundation,
        narrative: "A payer sent GBP 12,000 to a supplier. Verification of Payee returned No Match. The payer carried on past the warning, and the money went to the wrong account.",
        evidence: [
            ExceptionEvidence(
                id: "jeb-c01-e1",
                title: "VoP result",
                detail: "Verification of Payee returned No Match for the payee name and account details entered.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "jeb-c01-e2",
                title: "Payer continued",
                detail: "The payer reviewed the warning and continued anyway. The payment reached the wrong payee.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "jeb-c01-e3",
                title: "What No Match means",
                detail: "A No Match says only that the name does not match the name the payee bank holds. It does not say whether the cause is fraud, a typing error, a trading name, or a joint account held under a different name.",
                revealedAfterStep: 1,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "jeb-c01-e4",
                title: "Invoice name looks similar",
                detail: "The name on the invoice looks almost the same as the name entered. A similar name is not proof that the account is the right one.",
                revealedAfterStep: 0,
                isRedHerring: true,
                redHerringNote: "Similarity is not a match. Only the payee bank record, or confirmation from the supplier through a known channel, settles the name."
            ),
            ExceptionEvidence(
                id: "jeb-c01-e5",
                title: "No record of the decision",
                detail: "Nothing records that the payer understood the risk before continuing.",
                revealedAfterStep: 2,
                isRedHerring: false,
                redHerringNote: nil
            ),
        ],
        steps: [
            InvestigationStep(
                id: "jeb-c01-s1",
                prompt: "Verification of Payee returns No Match before the payment is sent. What is the best first step?",
                options: [
                    InvestigationOption(
                        text: "Stop and check the payee name and account details against a trusted source before sending.",
                        isRedHerring: false,
                        feedback: "The warning exists to pause the payment. Checking the details first costs minutes and can save the full amount."
                    ),
                    InvestigationOption(
                        text: "Send the payment anyway. The warning is probably a typing error.",
                        isRedHerring: true,
                        feedback: "Probably is not evidence. In this case the payment reached the wrong account."
                    ),
                    InvestigationOption(
                        text: "Block the supplier as a fraud risk.",
                        isRedHerring: false,
                        feedback: "No Match does not prove fraud. Blocking a genuine supplier creates a second problem."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "A No Match is a warning, not a verdict. It calls for a check of the details, not for sending anyway and not for assuming fraud.",
                wrongTurnCost: "Sending anyway can put the money in the wrong account. Treating the warning as proof of fraud can cut off a genuine supplier.",
                evidenceNote: "Checking the details reveals what a No Match actually proves, and what it does not."
            ),
            InvestigationStep(
                id: "jeb-c01-s2",
                prompt: "The details still do not match after checking. What next?",
                options: [
                    InvestigationOption(
                        text: "Contact the supplier through a known channel to confirm the correct name and account details.",
                        isRedHerring: false,
                        feedback: "Confirmation through a known channel settles the details from the source that owns them."
                    ),
                    InvestigationOption(
                        text: "Guess the corrected spelling and send the payment.",
                        isRedHerring: false,
                        feedback: "A guessed correction is another unverified detail. It can send the money to a third account."
                    ),
                    InvestigationOption(
                        text: "Send a small test payment to see where it lands.",
                        isRedHerring: false,
                        feedback: "A test payment still moves real money to an unverified account, and it proves nothing about the full payment."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "Only the supplier, reached through a channel already trusted, can confirm which name and account are correct.",
                wrongTurnCost: "Guessing, or testing with real money, moves funds on unverified details and can add a second wrong payment to the first.",
                evidenceNote: "The check confirms no record exists of the payer understanding the risk."
            ),
            InvestigationStep(
                id: "jeb-c01-s3",
                prompt: "The payer still wants to continue after the warning and the checks. What must happen before the payment goes?",
                options: [
                    InvestigationOption(
                        text: "Record that the payer saw the warning, understood the risk, and chose to continue.",
                        isRedHerring: false,
                        feedback: "The record proves the payer decided with the risk explained, instead of the warning being quietly passed."
                    ),
                    InvestigationOption(
                        text: "Remove the warning so the payer is not slowed down.",
                        isRedHerring: false,
                        feedback: "Removing the warning removes the only protection the payer had."
                    ),
                    InvestigationOption(
                        text: "Send the payment and record nothing.",
                        isRedHerring: false,
                        feedback: "With no record, nobody can later prove the payer understood the risk."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "A name check, a payer decision, and a payment outcome are three different things. Each needs its own record.",
                wrongTurnCost: "Sending without a record leaves the bank unable to prove the payer chose to continue with the risk explained.",
                evidenceNote: nil
            ),
        ],
        resolution: "Keep the VoP result, the payer decision to correct or continue, and the confirmed destination separate. Give a clear warning, a correction path, and a record of the payer choosing to continue. The question to answer is what evidence proves the payer understood the risk before continuing.",
        messages: [],
        systems: ["Verification of Payee check", "Payer payment screen", "Payee bank account records"],
        sourceSituationID: "JEB-C01",
        sourceSituationTitle: "VoP said No Match, GBP 12,000 went anyway",
        sourceTakeaway: "No Match is a warning, not a verdict."
    )

    /// Return received, grounded in ABH-03 (free sample).
    static let returnReceivedCase = ExceptionCase(
        id: "lab-abh-03",
        incidentType: "Return received",
        title: "EUR 20,000 SEPA payment came back, the team treated it as a reject",
        level: .foundation,
        narrative: "A SEPA payment of EUR 20,000 failed. The team raised it as a reject and asked the customer to resend it. The customer had already been debited, and the money came back twice.",
        evidence: [
            ExceptionEvidence(
                id: "abh-03-e1",
                title: "Instruction and payment",
                detail: "A pain.001 instruction was raised and a pacs.008 was sent for EUR 20,000.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "abh-03-e2",
                title: "Payment settled",
                detail: "The payment settled before the problem was raised.",
                revealedAfterStep: 1,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "abh-03-e3",
                title: "Return arrived",
                detail: "A pacs.004 return arrived after settlement.",
                revealedAfterStep: 1,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "abh-03-e4",
                title: "Team label: reject",
                detail: "The team raised the case as a reject and asked the customer to resend. The label came from treating every failed SEPA payment the same way.",
                revealedAfterStep: 0,
                isRedHerring: true,
                redHerringNote: "Failed is not a stage. Reject and return are decided by timing, not by the label the team picks first."
            ),
            ExceptionEvidence(
                id: "abh-03-e5",
                title: "Funds position",
                detail: "The customer had already been debited when the team asked for a resend.",
                revealedAfterStep: 2,
                isRedHerring: false,
                redHerringNote: nil
            ),
        ],
        steps: [
            InvestigationStep(
                id: "abh-03-s1",
                prompt: "A SEPA payment of EUR 20,000 is reported as failed. What is the best first step?",
                options: [
                    InvestigationOption(
                        text: "Check whether the payment settled before deciding how to handle it.",
                        isRedHerring: false,
                        feedback: "Timing is the whole distinction. Settlement state decides the path."
                    ),
                    InvestigationOption(
                        text: "Raise it as a reject and ask the customer to resend.",
                        isRedHerring: true,
                        feedback: "A reject path assumes the money never moved. Here it had already moved."
                    ),
                    InvestigationOption(
                        text: "Tell the customer the money is lost.",
                        isRedHerring: false,
                        feedback: "Nothing proves a loss. The funds position has not even been checked."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "A reject happens before settlement and is reported with pacs.002. A return happens after settlement and uses pacs.004. The stage decides the path.",
                wrongTurnCost: "Following the reject path for a settled payment, and asking for a resend without checking, credits the customer twice.",
                evidenceNote: "Checking the stage reveals that the payment settled and a pacs.004 return arrived."
            ),
            InvestigationStep(
                id: "abh-03-s2",
                prompt: "The payment settled, and a pacs.004 return arrived. What next?",
                options: [
                    InvestigationOption(
                        text: "Follow the return path and confirm the funds position before any resend.",
                        isRedHerring: false,
                        feedback: "The return means the money moved and came back. The funds position must be confirmed first."
                    ),
                    InvestigationOption(
                        text: "Resend the payment at once so the supplier is not kept waiting.",
                        isRedHerring: false,
                        feedback: "Resending before the funds position is confirmed is how the customer ends up credited twice."
                    ),
                    InvestigationOption(
                        text: "Raise a reject with pacs.002.",
                        isRedHerring: false,
                        feedback: "pacs.002 reports a reject before settlement. This payment already settled, so the reject report does not fit."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "After settlement, the return path is the only path that matches what actually happened to the money.",
                wrongTurnCost: "Resending, or raising a reject for a settled payment, misstates the payment state and risks a double credit.",
                evidenceNote: nil
            ),
            InvestigationStep(
                id: "abh-03-s3",
                prompt: "The customer asks whether it is safe to send the payment again. What do you confirm first?",
                options: [
                    InvestigationOption(
                        text: "That the returned funds are credited back, and only then send once.",
                        isRedHerring: false,
                        feedback: "One confirmed credit back, then one resend. That order keeps the customer whole exactly once."
                    ),
                    InvestigationOption(
                        text: "That the supplier is still waiting.",
                        isRedHerring: false,
                        feedback: "The supplier waiting does not prove the funds position. It answers urgency, not safety."
                    ),
                    InvestigationOption(
                        text: "That the first payment shows as failed on screen.",
                        isRedHerring: false,
                        feedback: "Failed on screen does not say whether the funds moved. The funds position is the evidence that matters."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "The real question is what evidence proves whether the funds moved, before anyone is told to resend.",
                wrongTurnCost: "A resend approved on a screen label instead of the funds position can credit the customer twice.",
                evidenceNote: nil
            ),
        ],
        resolution: "Before and after settlement are different worlds. Reject before settlement with pacs.002, return after settlement with pacs.004, and confirm the funds position before any resend. The stage decides the path.",
        messages: ["pain.001", "pacs.008", "pacs.002", "pacs.004"],
        systems: ["Payment hub", "Settlement records", "Customer account"],
        sourceSituationID: "ABH-03",
        sourceSituationTitle: "EUR 20,000 SEPA payment came back, the team treated it as a reject",
        sourceTakeaway: "The stage decides the path."
    )

    /// Payment rejected by validation, grounded in PAI-C091.
    static let validationRejectionCase = ExceptionCase(
        id: "lab-pai-c091",
        incidentType: "Payment rejected by validation",
        title: "EUR 30,000 payment rejected because the name had one wrong character",
        level: .foundation,
        narrative: "A EUR 30,000 payment names a beneficiary with characters from their own script. The SWIFT network rejects the message outright. The payment never leaves the sending bank, and the beneficiary waits while the name is rewritten.",
        evidence: [
            ExceptionEvidence(
                id: "pai-c091-e1",
                title: "Message raised",
                detail: "An MT103 was raised with the beneficiary name written in local script.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "pai-c091-e2",
                title: "Network rejection",
                detail: "The SWIFT network rejected the message: the characters are outside the allowed set.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "pai-c091-e3",
                title: "Payment never left",
                detail: "The payment never left the sending bank.",
                revealedAfterStep: 1,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "pai-c091-e4",
                title: "Name spelled correctly",
                detail: "The name is spelled correctly in the customer's own script. Correct spelling in the wrong script still fails validation.",
                revealedAfterStep: 0,
                isRedHerring: true,
                redHerringNote: "The check is about the character set, not about spelling. A correctly spelled name in an unsupported script cannot be accepted."
            ),
            ExceptionEvidence(
                id: "pai-c091-e5",
                title: "Validation gap",
                detail: "No check ran on the name and address against the allowed character set before the message was sent.",
                revealedAfterStep: 2,
                isRedHerring: false,
                redHerringNote: nil
            ),
        ],
        steps: [
            InvestigationStep(
                id: "pai-c091-s1",
                prompt: "The MT103 is rejected outright. What is the best first step?",
                options: [
                    InvestigationOption(
                        text: "Read the rejection reason and find which characters fall outside the allowed set.",
                        isRedHerring: false,
                        feedback: "The rejection names the problem. Reading it first points the fix at the characters, not at the payment."
                    ),
                    InvestigationOption(
                        text: "Resend the same message and hope it passes.",
                        isRedHerring: false,
                        feedback: "The same characters will be rejected the same way. Resending changes nothing."
                    ),
                    InvestigationOption(
                        text: "Ask the beneficiary bank to accept the message as it stands.",
                        isRedHerring: false,
                        feedback: "The message never left the sending bank. The beneficiary bank cannot accept what it never received."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "SWIFT MT messages use a restricted character set, and characters outside it cannot be used in a message at all. The fix starts with knowing which characters those are.",
                wrongTurnCost: "Resending unchanged, or chasing the beneficiary bank, wastes the wait while the real fault sits in the characters.",
                evidenceNote: "The rejection confirms the payment never left the sending bank."
            ),
            InvestigationStep(
                id: "pai-c091-s2",
                prompt: "The name uses characters outside the allowed set. What next?",
                options: [
                    InvestigationOption(
                        text: "Rewrite the name using only characters the SWIFT set allows, and confirm the rewritten name with the customer.",
                        isRedHerring: false,
                        feedback: "The rewritten name must stay recognisable to the customer, so confirmation matters as much as the rewrite."
                    ),
                    InvestigationOption(
                        text: "Drop the characters that fail and send the shortened name.",
                        isRedHerring: false,
                        feedback: "Dropping characters without confirmation can change the name into a different name."
                    ),
                    InvestigationOption(
                        text: "Change the beneficiary to a different person with an allowed name.",
                        isRedHerring: false,
                        feedback: "Changing the beneficiary changes who gets paid. That is a different payment, not a fix."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "Names and addresses must be written with the characters the SWIFT set allows, or the message will not be accepted, and the customer must agree the rewritten form.",
                wrongTurnCost: "Shortening or swapping the name without confirmation risks paying the wrong person or failing validation again.",
                evidenceNote: nil
            ),
            InvestigationStep(
                id: "pai-c091-s3",
                prompt: "The payment is fixed and sent. What stops the next payment failing the same way?",
                options: [
                    InvestigationOption(
                        text: "Validate every name and address against the SWIFT character set before the message is sent.",
                        isRedHerring: false,
                        feedback: "Validation before sending catches the fault while it is still cheap to fix."
                    ),
                    InvestigationOption(
                        text: "Warn customers to avoid their own script.",
                        isRedHerring: false,
                        feedback: "A warning with no check still lets the next unsupported name through."
                    ),
                    InvestigationOption(
                        text: "Check the character set only after a rejection arrives.",
                        isRedHerring: false,
                        feedback: "Checking after rejection means the beneficiary waits every time, exactly as in this case."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "Keep the name as the customer writes it, the name as the SWIFT set allows it, validation before sending, and rejection handling before the beneficiary waits, as separate controls.",
                wrongTurnCost: "Without validation before sending, every new payment with unsupported characters fails the same way and the beneficiary waits again.",
                evidenceNote: nil
            ),
        ],
        resolution: "Validate every name and address against the SWIFT character set before the message is sent. Keep the customer-written name, the SWIFT-allowed name, the validation, and the rejection handling separate, so a single character never holds up a payment unnoticed.",
        messages: ["MT103", "MT101"],
        systems: ["Message validation", "SWIFT network", "Customer instruction capture"],
        sourceSituationID: "PAI-C091",
        sourceSituationTitle: "EUR 30,000 payment rejected because the name had one wrong character",
        sourceTakeaway: "Names and addresses must be written with the characters the SWIFT set allows, or the message will not be accepted."
    )
}

// MARK: - Foundation and core cases (continued)

extension ExceptionCaseCatalogue {

    /// Duplicate transaction, grounded in PAI-C010.
    static let duplicateTransactionCase = ExceptionCase(
        id: "lab-pai-c010",
        incidentType: "Duplicate transaction",
        title: "EUR 12,000 paid twice from one pacs.008 file",
        level: .foundation,
        narrative: "A bulk pacs.008 file pays a supplier EUR 12,000. The same supplier is paid EUR 12,000 again the next day. The file contained the same transaction twice, and no duplicate check ran before processing.",
        evidence: [
            ExceptionEvidence(
                id: "pai-c010-e1",
                title: "File carried the instruction twice",
                detail: "A pain.001 carried one instruction more than once, and the pacs.008 file was built with the same payment inside it twice.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "pai-c010-e2",
                title: "No duplicate check",
                detail: "No duplicate check ran before processing.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "pai-c010-e3",
                title: "Both payments settled",
                detail: "Both payments settled, and the supplier was paid double.",
                revealedAfterStep: 1,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "pai-c010-e4",
                title: "File came from the customer",
                detail: "The file was trusted because the customer sent it. Origin is not a check.",
                revealedAfterStep: 0,
                isRedHerring: true,
                redHerringNote: "A file received is not a file checked. Trust in the sender cannot replace a check on the contents."
            ),
            ExceptionEvidence(
                id: "pai-c010-e5",
                title: "Unique identification",
                detail: "Every payment inside a pacs.008 file carries its own unique identification, and that identifier is the control that catches a repeated transaction.",
                revealedAfterStep: 2,
                isRedHerring: false,
                redHerringNote: nil
            ),
        ],
        steps: [
            InvestigationStep(
                id: "pai-c010-s1",
                prompt: "A bulk file arrives for processing. What is the best first step?",
                options: [
                    InvestigationOption(
                        text: "Run the duplicate check on the unique identification of every payment in the file before processing any of them.",
                        isRedHerring: false,
                        feedback: "The check is cheap before processing and expensive after settlement. Running it first is the whole discipline."
                    ),
                    InvestigationOption(
                        text: "Process the file at once. The customer sent it, so it must be clean.",
                        isRedHerring: true,
                        feedback: "The file in this case came from the customer and still contained the same transaction twice."
                    ),
                    InvestigationOption(
                        text: "Process the file and check for duplicates at the end of the day.",
                        isRedHerring: false,
                        feedback: "An end of day check finds the duplicate after both payments have settled."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "Duplicate detection is a pre-processing discipline, not a post-payment investigation. The unique identification on each payment is the control that catches a repeat before it is processed.",
                wrongTurnCost: "Processing first and checking later pays the supplier twice, turning a file check into a recovery case.",
                evidenceNote: "The check reveals the file holds the same payment twice."
            ),
            InvestigationStep(
                id: "pai-c010-s2",
                prompt: "Both payments have already settled and the supplier was paid double. What next?",
                options: [
                    InvestigationOption(
                        text: "Stop further payments from the file, confirm both credits, then start recovery for the duplicate.",
                        isRedHerring: false,
                        feedback: "Stopping the file first prevents a third payment. Confirming both credits proves which payment is the duplicate."
                    ),
                    InvestigationOption(
                        text: "Ask the supplier to send the money back without checking the credits.",
                        isRedHerring: false,
                        feedback: "Recovery without confirmed credits can chase the wrong amount or the wrong payment."
                    ),
                    InvestigationOption(
                        text: "Leave the duplicate and adjust it in the next file.",
                        isRedHerring: false,
                        feedback: "Netting a duplicate into a later file hides the error and leaves the books wrong in between."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "Recovery starts from confirmed facts: both credits proved, the duplicate identified, then the money pursued through the proper route.",
                wrongTurnCost: "Chasing recovery without proof, or hiding the duplicate in a later file, leaves the loss unproved and the books misstated.",
                evidenceNote: nil
            ),
            InvestigationStep(
                id: "pai-c010-s3",
                prompt: "The duplicate is recovered. What stops the next file paying twice?",
                options: [
                    InvestigationOption(
                        text: "Require evidence that the duplicate check ran on every payment before settlement, for every bulk file.",
                        isRedHerring: false,
                        feedback: "Evidence the check ran is what turns a good intention into a control that holds."
                    ),
                    InvestigationOption(
                        text: "Ask customers to check their files more carefully.",
                        isRedHerring: false,
                        feedback: "Asking senders to be careful is not a control. The check must run on receipt, whoever sent the file."
                    ),
                    InvestigationOption(
                        text: "Check only files above a value threshold.",
                        isRedHerring: false,
                        feedback: "A duplicate below any threshold still pays twice. The check must cover every payment in the file."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "Keep the unique identification, the duplicate check before processing, the release for settlement, and the recovery route as separate controls.",
                wrongTurnCost: "Without a required check on every file, the next repeated instruction pays twice the same way.",
                evidenceNote: nil
            ),
        ],
        resolution: "Run the duplicate check on unique identification before any payment in the file is processed. Duplicate detection is a pre-processing discipline, not a post-payment investigation.",
        messages: ["pain.001", "pacs.008"],
        systems: ["File intake", "Duplicate detection", "Payment processing"],
        sourceSituationID: "PAI-C010",
        sourceSituationTitle: "EUR 12,000 paid twice from one pacs.008 file",
        sourceTakeaway: "Duplicate detection is therefore a pre-processing discipline, not a post-payment investigation."
    )

    /// Sanctions screening hold, grounded in SCN-24.
    static let sanctionsHoldCase = ExceptionCase(
        id: "lab-scn-24",
        incidentType: "Sanctions screening hold",
        title: "A USD 500,000 payment matched the sanctions list. The funds froze, and the trail mattered.",
        level: .core,
        narrative: "A USD 500,000 payment matches a name on the sanctions list. The payment is held at once and no funds move. The analyst wonders whether to release it quietly and move on.",
        evidence: [
            ExceptionEvidence(
                id: "scn-24-e1",
                title: "List match",
                detail: "A USD 500,000 payment was screened and a name matched the sanctions list.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "scn-24-e2",
                title: "Payment held, funds still",
                detail: "The payment is held immediately and no funds move while the review is open.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "scn-24-e3",
                title: "Quiet release considered",
                detail: "The analyst considers releasing the payment without a trail.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "scn-24-e4",
                title: "Customer is known",
                detail: "The customer has paid before and is known to the bank. History does not clear a list match.",
                revealedAfterStep: 1,
                isRedHerring: true,
                redHerringNote: "A list match is decided by verification of the match itself, not by how well the customer is known."
            ),
            ExceptionEvidence(
                id: "scn-24-e5",
                title: "Trail requirement",
                detail: "Every step must be documented, because the decision trail is what regulators will ask for.",
                revealedAfterStep: 2,
                isRedHerring: false,
                redHerringNote: nil
            ),
        ],
        steps: [
            InvestigationStep(
                id: "scn-24-s1",
                prompt: "A payment matches a name on the sanctions list. What is the best first step?",
                options: [
                    InvestigationOption(
                        text: "Hold the payment at once and keep the funds still while the review is open.",
                        isRedHerring: false,
                        feedback: "A list match stops the payment. Holding first protects the funds while the facts are checked."
                    ),
                    InvestigationOption(
                        text: "Release the payment quietly. The customer is known.",
                        isRedHerring: true,
                        feedback: "Releasing on familiarity, with no trail, is the decision this case warns against."
                    ),
                    InvestigationOption(
                        text: "Reject the payment outright without verifying the match.",
                        isRedHerring: false,
                        feedback: "Rejection without verification decides the case before the facts are known."
                    ),
                    InvestigationOption(
                        text: "Ask the customer to resend under a slightly different name.",
                        isRedHerring: false,
                        feedback: "Resending under a different name hides the match instead of resolving it."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "A sanctions list match stops the payment at once. It is held immediately and no funds move while the review is open.",
                wrongTurnCost: "Releasing quietly, rejecting unverified, or hiding the match all destroy the trail and can move funds that should never have moved.",
                evidenceNote: "Holding the payment opens a review case with the match evidence attached."
            ),
            InvestigationStep(
                id: "scn-24-s2",
                prompt: "The payment is held. What next?",
                options: [
                    InvestigationOption(
                        text: "Wait for the match to clear itself.",
                        isRedHerring: false,
                        feedback: "A match does not clear itself. Waiting leaves the payment held with no progress and no record."
                    ),
                    InvestigationOption(
                        text: "Escalate to the compliance officer with the match evidence attached.",
                        isRedHerring: false,
                        feedback: "Escalation with evidence puts the decision with the officer who owns it, with the facts in hand."
                    ),
                    InvestigationOption(
                        text: "Ask the customer whether they are the listed person.",
                        isRedHerring: false,
                        feedback: "The customer cannot verify their own list match. Verification belongs to the compliance review."
                    ),
                    InvestigationOption(
                        text: "Delete the screening alert to keep the queue clean.",
                        isRedHerring: false,
                        feedback: "Deleting the alert destroys the evidence the decision trail needs."
                    ),
                ],
                bestOptionIndex: 1,
                whyCorrect: "The analyst escalates to the compliance officer with the match evidence attached, so the decision is made on the evidence, not on a queue being tidy.",
                wrongTurnCost: "Waiting, asking the customer to clear themselves, or deleting the alert leaves the match unverified and the trail broken.",
                evidenceNote: nil
            ),
            InvestigationStep(
                id: "scn-24-s3",
                prompt: "The compliance review is under way. How is the case closed?",
                options: [
                    InvestigationOption(
                        text: "Release the payment and file no record.",
                        isRedHerring: false,
                        feedback: "A release with no record cannot be defended later. The trail is the proof."
                    ),
                    InvestigationOption(
                        text: "Block the payment without recording why.",
                        isRedHerring: false,
                        feedback: "A block with no recorded reason cannot be explained to the customer or to a regulator."
                    ),
                    InvestigationOption(
                        text: "Verify whether it is a true match, release if false or block if true, and document every step.",
                        isRedHerring: false,
                        feedback: "True-match verification decides the path, and the documented trail proves the decision."
                    ),
                    InvestigationOption(
                        text: "Keep the payment held forever so no decision is needed.",
                        isRedHerring: false,
                        feedback: "Holding forever is not a decision. It leaves the customer and the funds in limbo with no outcome."
                    ),
                ],
                bestOptionIndex: 2,
                whyCorrect: "True-match verification decides the path: release if false, block if true. Where the activity meets the threshold a Suspicious Activity Report is filed, and every step is documented.",
                wrongTurnCost: "Closing the case without verification or documentation leaves the decision unprovable when regulators ask for the trail.",
                evidenceNote: nil
            ),
        ],
        resolution: "Hold on a match, escalate with the evidence, verify the true match, and document every step. A list match stops the payment. The trail proves the decision.",
        messages: [],
        systems: ["Sanctions screening engine", "Case management", "Compliance review"],
        sourceSituationID: "SCN-24",
        sourceSituationTitle: "A USD 500,000 payment matched the sanctions list. The funds froze, and the trail mattered.",
        sourceTakeaway: "A list match stops the payment. The trail proves the decision."
    )

    /// Incorrect charge handling, grounded in PAI-C024.
    static let chargeHandlingCase = ExceptionCase(
        id: "lab-pai-c024",
        incidentType: "Incorrect charge handling",
        title: "USD 100,000 sent, USD 99,850 received, and no one could explain the gap",
        level: .core,
        narrative: "A customer sent USD 100,000 by serial payment. The beneficiary was credited USD 99,850. USD 150 had vanished, and no one at the bank could explain where it went.",
        evidence: [
            ExceptionEvidence(
                id: "pai-c024-e1",
                title: "Amount sent",
                detail: "The ordering customer sent USD 100,000.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "pai-c024-e2",
                title: "First deduction",
                detail: "The first intermediary deducted its charge as the payment passed through.",
                revealedAfterStep: 1,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "pai-c024-e3",
                title: "Second deduction",
                detail: "The second intermediary deducted its charge as the payment passed through.",
                revealedAfterStep: 1,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "pai-c024-e4",
                title: "Final credit",
                detail: "The beneficiary was credited USD 99,850.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "pai-c024-e5",
                title: "Beneficiary bank took it all",
                detail: "The team assumes the beneficiary bank took the whole USD 150. The gap is the sum of the deductions in the chain, not one bank taking it all.",
                revealedAfterStep: 0,
                isRedHerring: true,
                redHerringNote: "Blaming one bank stops the trace at the first step. Each deduction in the chain must be accounted for."
            ),
        ],
        steps: [
            InvestigationStep(
                id: "pai-c024-s1",
                prompt: "The beneficiary received USD 99,850 from USD 100,000 sent. What is the best first step?",
                options: [
                    InvestigationOption(
                        text: "Tell the customer the beneficiary bank took USD 150.",
                        isRedHerring: true,
                        feedback: "That blames one bank for a gap made across the chain, and it cannot be proved."
                    ),
                    InvestigationOption(
                        text: "Trace each deduction in the chain and match it to the charge each intermediary applied.",
                        isRedHerring: false,
                        feedback: "The chain holds the answer. Each intermediary deduction must be traced and matched to its charge."
                    ),
                    InvestigationOption(
                        text: "Tell the customer the amount is correct and close the case.",
                        isRedHerring: false,
                        feedback: "Correct needs proof. Closing without a trace leaves the gap unexplained."
                    ),
                    InvestigationOption(
                        text: "Refund USD 150 from the bank's own funds.",
                        isRedHerring: false,
                        feedback: "A refund before the trace pays for charges that may have been agreed and expected."
                    ),
                ],
                bestOptionIndex: 1,
                whyCorrect: "In a serial payment, every intermediary deducts its own charge on the way, and every deduction lands on the beneficiary. The gap can only be explained by tracing each one.",
                wrongTurnCost: "Blaming one bank, closing the case, or refunding blind all leave the real deductions unproved and the customer without a true explanation.",
                evidenceNote: "The trace reveals a deduction at each intermediary step."
            ),
            InvestigationStep(
                id: "pai-c024-s2",
                prompt: "Each intermediary deduction is traced. What next?",
                options: [
                    InvestigationOption(
                        text: "Reconcile the actual credit against every charge taken, then explain the gap to the customer.",
                        isRedHerring: false,
                        feedback: "Reconciliation proves the arithmetic before the customer is given an explanation."
                    ),
                    InvestigationOption(
                        text: "Explain the gap from memory of the usual charges.",
                        isRedHerring: false,
                        feedback: "Usual charges are not this payment's charges. The explanation must come from the reconciled trace."
                    ),
                    InvestigationOption(
                        text: "Ask the beneficiary to accept the short credit.",
                        isRedHerring: false,
                        feedback: "Acceptance without an explanation asks the beneficiary to trust a gap nobody has proved."
                    ),
                    InvestigationOption(
                        text: "Raise a return for USD 150.",
                        isRedHerring: false,
                        feedback: "A return is for money that came back, not for charges deducted in the chain."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "The actual credit must be reconciled against every charge taken, so the explanation to the customer is proved, not guessed.",
                wrongTurnCost: "Explaining from memory, or asking for acceptance without proof, leaves the customer with an answer that cannot be checked.",
                evidenceNote: nil
            ),
            InvestigationStep(
                id: "pai-c024-s3",
                prompt: "The gap is explained. What stops the next customer being surprised the same way?",
                options: [
                    InvestigationOption(
                        text: "Send the next payment by a different route without telling the customer.",
                        isRedHerring: false,
                        feedback: "Changing the route silently changes the charges without the customer agreeing to them."
                    ),
                    InvestigationOption(
                        text: "Stop using serial payments entirely.",
                        isRedHerring: false,
                        feedback: "The route is not the fault. The fault is that the expected credit was never shown."
                    ),
                    InvestigationOption(
                        text: "Show the customer the expected credit before sending, accounting for every deduction in the chain.",
                        isRedHerring: false,
                        feedback: "An expected credit shown before sending turns a surprise into an agreed outcome."
                    ),
                    InvestigationOption(
                        text: "Quote only the first intermediary charge.",
                        isRedHerring: false,
                        feedback: "Quoting only the first charge repeats the original error and hides the rest of the chain."
                    ),
                ],
                bestOptionIndex: 2,
                whyCorrect: "Price a serial payment by accounting for every deduction in the chain, not just the first one, and show the customer the expected credit before sending.",
                wrongTurnCost: "Quoting part of the chain, or changing the route silently, keeps the surprise in place for the next payment.",
                evidenceNote: nil
            ),
        ],
        resolution: "Price a serial payment by accounting for every deduction in the chain, not just the first one. Show the customer the expected credit before sending, and reconcile the actual credit against every charge taken.",
        messages: [],
        systems: ["Correspondent chain records", "Charge schedules", "Customer account"],
        sourceSituationID: "PAI-C024",
        sourceSituationTitle: "USD 100,000 sent, USD 99,850 received, and no one could explain the gap",
        sourceTakeaway: "In a serial payment, every deduction in the chain lands on the beneficiary."
    )
}

// MARK: - Core cases (continued)

extension ExceptionCaseCatalogue {

    /// Insufficient funds, grounded in JEB-F07.
    static let insufficientFundsCase = ExceptionCase(
        id: "lab-jeb-f07",
        incidentType: "Insufficient funds",
        title: "A EUR 900 direct debit failed for insufficient funds. The scheduler retried it in the wrong order.",
        level: .core,
        narrative: "A EUR 900 direct debit fails because the account cannot fund it. The scheduler retries in first-in-first-out order and fails again. The salary credit lands two days later, and the D+5 window is almost gone.",
        evidence: [
            ExceptionEvidence(
                id: "jeb-f07-e1",
                title: "Debit failed",
                detail: "A EUR 900 direct debit failed for insufficient funds.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "jeb-f07-e2",
                title: "FIFO retries",
                detail: "The scheduler retried in first-in-first-out order and failed again.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "jeb-f07-e3",
                title: "Salary lands later",
                detail: "The salary credit lands two days later. Salary accounts hold a balance on the dates salary credits land.",
                revealedAfterStep: 1,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "jeb-f07-e4",
                title: "Window nearly closed",
                detail: "The D+5 window of inter-PSP business days is almost gone.",
                revealedAfterStep: 1,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "jeb-f07-e5",
                title: "Scheduler ran on time",
                detail: "The scheduler ran exactly on time. Running on time is not the same as collecting at a time the balance can fund.",
                revealedAfterStep: 0,
                isRedHerring: true,
                redHerringNote: "The scheduler working proves the queue ran. It says nothing about whether the balance could fund the debit."
            ),
        ],
        steps: [
            InvestigationStep(
                id: "jeb-f07-s1",
                prompt: "A direct debit fails for insufficient funds. What is the best first step?",
                options: [
                    InvestigationOption(
                        text: "Retry at once in first-in-first-out order.",
                        isRedHerring: false,
                        feedback: "An immediate retry on queue order fails the same way, because the balance has not changed."
                    ),
                    InvestigationOption(
                        text: "Check the account balance pattern, including when salary credits land, before scheduling the next retry.",
                        isRedHerring: false,
                        feedback: "Retry logic is seasonal. Knowing when the balance can fund the debit sets the retry time."
                    ),
                    InvestigationOption(
                        text: "Mark the debit as failed and close the case.",
                        isRedHerring: false,
                        feedback: "Closing the case wastes the D+5 window while the debit could still be collected."
                    ),
                    InvestigationOption(
                        text: "Charge the customer a penalty for the failed debit.",
                        isRedHerring: true,
                        feedback: "D+5 is a window, not a penalty. A penalty answers nothing about when the debit can be collected."
                    ),
                ],
                bestOptionIndex: 1,
                whyCorrect: "When a direct debit fails for insufficient funds, retries are confined to the D+5 window, and retry timing must follow the balance, not the queue.",
                wrongTurnCost: "Retrying on queue order keeps failing while the window closes, and the collectable debit is lost.",
                evidenceNote: "The balance pattern shows the salary credit landing two days later."
            ),
            InvestigationStep(
                id: "jeb-f07-s2",
                prompt: "The salary credit lands two days later, inside the window. What next?",
                options: [
                    InvestigationOption(
                        text: "Check the balance daily inside the D+5 window and collect when the account can fund the debit.",
                        isRedHerring: false,
                        feedback: "A daily balance check collects at the first moment the account can fund the debit."
                    ),
                    InvestigationOption(
                        text: "Wait until the last day of the window.",
                        isRedHerring: false,
                        feedback: "Waiting until the last day risks missing the balance and leaves no room if the collection fails."
                    ),
                    InvestigationOption(
                        text: "Retry every hour until it succeeds.",
                        isRedHerring: false,
                        feedback: "Hourly retries hammer the account without new information. The balance check is what decides the time."
                    ),
                    InvestigationOption(
                        text: "Ask the customer to pay by a different method and abandon the debit.",
                        isRedHerring: false,
                        feedback: "Abandoning the debit wastes a window that still holds a collectable balance."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "D+5 is a window, not a penalty. Collect when the balance can fund it, checked daily, rather than assuming the scheduler order is the answer.",
                wrongTurnCost: "Waiting until the last day, or retrying blind, can miss the balance and lose the collection inside the window.",
                evidenceNote: nil
            ),
            InvestigationStep(
                id: "jeb-f07-s3",
                prompt: "The debit is collected. What stops the next retry failing the same way?",
                options: [
                    InvestigationOption(
                        text: "Keep the first-in-first-out scheduler unchanged.",
                        isRedHerring: false,
                        feedback: "The unchanged scheduler will retry the next failed debit in queue order and fail the same way."
                    ),
                    InvestigationOption(
                        text: "Set the retry to follow the daily balance check, and agree who owns a retry failure.",
                        isRedHerring: false,
                        feedback: "Balance-led retries fix the timing, and agreed ownership fixes who acts when a retry still fails."
                    ),
                    InvestigationOption(
                        text: "Blame the developer for the scheduler order.",
                        isRedHerring: false,
                        feedback: "Who owns a retry failure is a stakeholder agreement, not a technical fact to blame on one role."
                    ),
                    InvestigationOption(
                        text: "Remove the retry feature entirely.",
                        isRedHerring: false,
                        feedback: "Removing retries loses every collectable debit that a timed retry would have recovered."
                    ),
                ],
                bestOptionIndex: 1,
                whyCorrect: "Check the balance daily inside the D+5 window, collect when the account can fund the debit, and agree who owns a retry failure.",
                wrongTurnCost: "Leaving the scheduler and the ownership unchanged guarantees the next failed debit is retried the same wrong way.",
                evidenceNote: nil
            ),
        ],
        resolution: "Check the balance daily inside the D+5 window, collect when the account can fund the debit, and agree who owns a retry failure. D+5 is a window, not a penalty.",
        messages: [],
        systems: ["Direct debit scheduler", "Account balance view", "Salary credit records"],
        sourceSituationID: "JEB-F07",
        sourceSituationTitle: "A EUR 900 direct debit failed for insufficient funds. The scheduler retried it in the wrong order.",
        sourceTakeaway: "D+5 is a window, not a penalty. Collect when the balance can fund it."
    )

    /// Settlement delay, grounded in INS-144. The source situation is
    /// a settlement failure on liquidity: the payment cannot settle
    /// because the settlement currency is not held in enough volume.
    static let settlementDelayCase = ExceptionCase(
        id: "lab-ins-144",
        incidentType: "Settlement delay",
        title: "USD 100,000 instant dollars promised, no dollars to settle with on Monday morning",
        level: .core,
        narrative: "A bank promises instant dollar payments. On Monday morning a customer sends USD 100,000. The rate is competitive and the system is ready. There are not enough dollars to settle with.",
        evidence: [
            ExceptionEvidence(
                id: "ins-144-e1",
                title: "Instant promise",
                detail: "The bank offers instant dollar payments at a good rate.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "ins-144-e2",
                title: "Payment sent",
                detail: "A customer sends USD 100,000 on Monday morning.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "ins-144-e3",
                title: "Currency short",
                detail: "The settlement currency is not held in enough volume to settle the payment.",
                revealedAfterStep: 1,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "ins-144-e4",
                title: "Fails on liquidity",
                detail: "The payment fails, not on price, on liquidity.",
                revealedAfterStep: 1,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "ins-144-e5",
                title: "Rate is competitive",
                detail: "The exchange rate is competitive. A good rate is not the same as having the settlement currency available when it is needed.",
                revealedAfterStep: 0,
                isRedHerring: true,
                redHerringNote: "Rate is not liquidity. The rate answers price. Only the nostro balance answers whether the payment can settle."
            ),
        ],
        steps: [
            InvestigationStep(
                id: "ins-144-s1",
                prompt: "An instant dollar payment cannot settle on Monday morning. What is the best first step?",
                options: [
                    InvestigationOption(
                        text: "Improve the exchange rate to attract more dollars.",
                        isRedHerring: false,
                        feedback: "The rate is already competitive. Price is not the constraint."
                    ),
                    InvestigationOption(
                        text: "Check the nostro balance in the settlement currency before promising the customer a time.",
                        isRedHerring: false,
                        feedback: "The nostro balance is the evidence that decides whether the payment can settle."
                    ),
                    InvestigationOption(
                        text: "Restart the payment engine.",
                        isRedHerring: true,
                        feedback: "The system is ready. Restarting it cannot create dollars that are not held."
                    ),
                    InvestigationOption(
                        text: "Tell the customer the payment settled.",
                        isRedHerring: false,
                        feedback: "The payment did not settle. Saying so misleads the customer about money that has not moved."
                    ),
                ],
                bestOptionIndex: 1,
                whyCorrect: "A bank can offer instant dollar payments and still fail on some mornings because it does not hold enough dollars to settle. The constraint is liquidity, not conversion.",
                wrongTurnCost: "Chasing price or the system leaves the real shortfall untouched, and the next morning fails the same way.",
                evidenceNote: "The balance check confirms the settlement currency is not held in enough volume."
            ),
            InvestigationStep(
                id: "ins-144-s2",
                prompt: "The nostro is short of dollars for the morning peak. What next?",
                options: [
                    InvestigationOption(
                        text: "Keep promising instant settlement and hope the balance recovers.",
                        isRedHerring: false,
                        feedback: "Promising what the nostro cannot fund repeats the failure for the next customer."
                    ),
                    InvestigationOption(
                        text: "Stop offering dollar payments entirely.",
                        isRedHerring: false,
                        feedback: "The offer is sound when funded. The fix is funding, not withdrawing the service."
                    ),
                    InvestigationOption(
                        text: "Raise the shortfall with treasury so the nostro is funded before the morning peak.",
                        isRedHerring: false,
                        feedback: "Liquidity must be managed by treasury, not just by the payment engine. Funding before the peak prevents the failure."
                    ),
                    InvestigationOption(
                        text: "Delay the payment silently until dollars arrive.",
                        isRedHerring: false,
                        feedback: "A silent delay leaves the customer believing an instant promise that is not being kept."
                    ),
                ],
                bestOptionIndex: 2,
                whyCorrect: "The constraint must be managed by treasury, funding the nostro before the morning peak, not left to the payment engine alone.",
                wrongTurnCost: "Keeping the promise unfunded, or delaying silently, breaks the instant promise for customers who relied on it.",
                evidenceNote: nil
            ),
            InvestigationStep(
                id: "ins-144-s3",
                prompt: "The nostro is funded. What keeps the promise honest from now on?",
                options: [
                    InvestigationOption(
                        text: "Show the nostro balance beside the instant promise, and pause the promise when liquidity is short.",
                        isRedHerring: false,
                        feedback: "Showing the balance beside the promise makes the offer match the funding, every morning."
                    ),
                    InvestigationOption(
                        text: "Promise instant settlement at all times, whatever the balance.",
                        isRedHerring: false,
                        feedback: "An unconditional promise will fail again on the next short morning."
                    ),
                    InvestigationOption(
                        text: "Hide the promise from customers on Mondays.",
                        isRedHerring: false,
                        feedback: "Hiding the promise on one weekday does not manage liquidity on any other day."
                    ),
                    InvestigationOption(
                        text: "Quote a better rate on short mornings.",
                        isRedHerring: false,
                        feedback: "A better rate on a short morning attracts more payments the nostro cannot settle."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "Never promise instant settlement the nostro cannot fund. The instant promise holds only where liquidity is proved.",
                wrongTurnCost: "An unconditional promise, or a better rate on a short morning, invites payments that cannot settle.",
                evidenceNote: nil
            ),
        ],
        resolution: "Manage settlement liquidity with treasury, and never promise instant settlement the nostro cannot fund. Show the nostro balance beside the instant promise, and pause the promise when liquidity is short.",
        messages: [],
        systems: ["Payment engine", "Treasury liquidity view", "Nostro account"],
        sourceSituationID: "INS-144",
        sourceSituationTitle: "USD 100,000 instant dollars promised, no dollars to settle with on Monday morning",
        sourceTakeaway: "The constraint is liquidity, not conversion, and it must be managed by treasury, not just by the payment engine."
    )

    /// Reconciliation break, grounded in SCN-21 (free sample).
    static let reconciliationBreakCase = ExceptionCase(
        id: "lab-scn-21",
        incidentType: "Reconciliation break",
        title: "Small breaks, ignored for months, added up to a USD 2 million surprise before the audit.",
        level: .core,
        narrative: "Small uncleared items pile up for months, each one looking harmless. Volumes rise, and a USD 2 million discrepancy appears just before an audit. The team had optimised the manual workaround, never the process that created the breaks.",
        evidence: [
            ExceptionEvidence(
                id: "scn-21-e1",
                title: "Breaks accumulate",
                detail: "Small breaks accumulate for months, each one looking harmless.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "scn-21-e2",
                title: "Value dates differ",
                detail: "Two systems derive the transaction value date with different logic.",
                revealedAfterStep: 1,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "scn-21-e3",
                title: "Discrepancy before audit",
                detail: "A USD 2 million discrepancy is found just before the audit, as volumes rise.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "scn-21-e4",
                title: "Workaround optimised",
                detail: "The manual workaround was optimised. The root cause was untouched.",
                revealedAfterStep: 1,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "scn-21-e5",
                title: "Each break is small",
                detail: "Each break on its own looks too small to act on. Small breaks accumulate into the discrepancy that surprises the audit.",
                revealedAfterStep: 0,
                isRedHerring: true,
                redHerringNote: "Small is not harmless when the cause keeps creating breaks. The pattern across breaks is the signal, not the size of one."
            ),
        ],
        steps: [
            InvestigationStep(
                id: "scn-21-s1",
                prompt: "Small reconciliation breaks keep appearing. What is the best first step?",
                options: [
                    InvestigationOption(
                        text: "Clear each break by hand as it appears.",
                        isRedHerring: false,
                        feedback: "Hand clearing keeps the queue tidy and the cause untouched. The breaks keep coming."
                    ),
                    InvestigationOption(
                        text: "Age the breaks and look for the pattern across them instead of clearing them one by one.",
                        isRedHerring: false,
                        feedback: "Aging and pattern finding turns a queue of small items into one diagnosable cause."
                    ),
                    InvestigationOption(
                        text: "Ignore the breaks until the audit.",
                        isRedHerring: true,
                        feedback: "Ignoring small breaks is how a USD 2 million discrepancy appears just before the audit."
                    ),
                    InvestigationOption(
                        text: "Write off the oldest breaks.",
                        isRedHerring: false,
                        feedback: "Writing off breaks hides the discrepancy instead of explaining it."
                    ),
                ],
                bestOptionIndex: 1,
                whyCorrect: "Small uncleared items accumulated for months, looking harmless, until rising volumes exposed the discrepancy. The pattern is the evidence that matters.",
                wrongTurnCost: "Clearing by hand, ignoring, or writing off breaks leaves the creating process running, so the discrepancy grows until the audit finds it.",
                evidenceNote: "The pattern points at the value date logic differing between two systems."
            ),
            InvestigationStep(
                id: "scn-21-s2",
                prompt: "The pattern points at two systems deriving value dates differently. What next?",
                options: [
                    InvestigationOption(
                        text: "Compare how each system derives the value date and align the logic that creates the breaks.",
                        isRedHerring: false,
                        feedback: "Aligning the logic removes the cause, so new breaks stop appearing."
                    ),
                    InvestigationOption(
                        text: "Build a faster manual workaround.",
                        isRedHerring: false,
                        feedback: "A faster workaround optimises the wrong thing. The process that creates the break stays broken."
                    ),
                    InvestigationOption(
                        text: "Change one system without checking the other.",
                        isRedHerring: false,
                        feedback: "Changing one side blind can move the mismatch instead of removing it."
                    ),
                    InvestigationOption(
                        text: "Ask the audit team to accept the breaks.",
                        isRedHerring: false,
                        feedback: "The audit team cannot accept a discrepancy the process keeps creating."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "Fix the process that creates the break, not the workaround. Aligning the value date logic is the fix.",
                wrongTurnCost: "A faster workaround, or a one-sided change, keeps creating breaks while looking like progress.",
                evidenceNote: nil
            ),
            InvestigationStep(
                id: "scn-21-s3",
                prompt: "The value date logic is aligned. What stops the next accumulation?",
                options: [
                    InvestigationOption(
                        text: "Go back to month-end reconciliation.",
                        isRedHerring: false,
                        feedback: "Month-end reconciliation finds the next accumulation months late, as before."
                    ),
                    InvestigationOption(
                        text: "Check breaks only before audits.",
                        isRedHerring: false,
                        feedback: "Audit-time checks repeat the surprise this case started with."
                    ),
                    InvestigationOption(
                        text: "Run reconciliation as an early warning, with alerts on break aging.",
                        isRedHerring: false,
                        feedback: "Early warning with aging alerts surfaces the next pattern while it is still small and fixable."
                    ),
                    InvestigationOption(
                        text: "Stop reconciling small items.",
                        isRedHerring: false,
                        feedback: "Stopping small-item reconciliation removes the only view of the pattern forming."
                    ),
                ],
                bestOptionIndex: 2,
                whyCorrect: "Run reconciliation as an early warning, not as a month-end chore, with break aging watched and alerts raised early.",
                wrongTurnCost: "Returning to month-end or audit-time checks lets the next pattern accumulate unseen until it surprises the audit again.",
                evidenceNote: nil
            ),
        ],
        resolution: "Align the logic that creates breaks, and run reconciliation as an early warning, not as a month-end chore. Fix the process that creates the break, not the workaround.",
        messages: [],
        systems: ["Reconciliation engine", "General ledger", "Source systems"],
        sourceSituationID: "SCN-21",
        sourceSituationTitle: "Small breaks, ignored for months, added up to a USD 2 million surprise before the audit.",
        sourceTakeaway: "Fix the process that creates the break, not the workaround."
    )
}

// MARK: - Advanced cases

extension ExceptionCaseCatalogue {

    /// Clearing rejection, grounded in INS-141.
    static let clearingRejectionCase = ExceptionCase(
        id: "lab-ins-141",
        incidentType: "Clearing rejection",
        title: "Two instant payment systems connected by API, and a EUR 10,000 payment still failed at clearing",
        level: .advanced,
        narrative: "Two banks connected their instant payment systems through an API. The connection test passed: a message went out and a response came back. Then a EUR 10,000 payment was accepted by the channel and rejected by clearing, because the scheme rules do not match.",
        evidence: [
            ExceptionEvidence(
                id: "ins-141-e1",
                title: "API connected",
                detail: "Two banks connected their instant payment systems through an API.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "ins-141-e2",
                title: "Connection test passed",
                detail: "A message was sent and a response received, and the connection was declared working.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "ins-141-e3",
                title: "Channel accepted, clearing rejected",
                detail: "A EUR 10,000 payment was accepted by the channel and rejected by clearing. The scheme rules do not match.",
                revealedAfterStep: 1,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "ins-141-e4",
                title: "Both banks blame the connection",
                detail: "The customer waits while both banks point at the connection that works.",
                revealedAfterStep: 2,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "ins-141-e5",
                title: "API test passed",
                detail: "The API test passed, so the integration was declared done. Connectivity proves a message can travel. It does not prove a payment will clear.",
                revealedAfterStep: 0,
                isRedHerring: true,
                redHerringNote: "Connectivity is the easiest part of the integration. The test that matters is a payment clearing end to end."
            ),
            ExceptionEvidence(
                id: "ins-141-e6",
                title: "Alignment gaps",
                detail: "Message formats, scheme rules, clearing, settlement, compliance and operations must also align. None of those was tested by the connection test.",
                revealedAfterStep: 3,
                isRedHerring: false,
                redHerringNote: nil
            ),
        ],
        steps: [
            InvestigationStep(
                id: "ins-141-s1",
                prompt: "A payment is accepted by the channel and rejected by clearing. What is the best first step?",
                options: [
                    InvestigationOption(
                        text: "Retest the API connection.",
                        isRedHerring: true,
                        feedback: "The connection already works. Retesting it answers a question nobody is asking."
                    ),
                    InvestigationOption(
                        text: "Read the clearing rejection and find which scheme rule the payment breaks.",
                        isRedHerring: false,
                        feedback: "The rejection names the rule. Reading it first points the fix at the mismatch."
                    ),
                    InvestigationOption(
                        text: "Ask the customer to send the payment again.",
                        isRedHerring: false,
                        feedback: "Resending the same payment breaks the same rule the same way."
                    ),
                    InvestigationOption(
                        text: "Blame the other bank for the rejection.",
                        isRedHerring: false,
                        feedback: "Blame without the rejection detail leaves both banks pointing at a connection that works."
                    ),
                ],
                bestOptionIndex: 1,
                whyCorrect: "Clearing rejects on scheme rules, not on connectivity. The rejection detail is the first evidence that matters.",
                wrongTurnCost: "Retesting the connection, resending, or blaming the other bank leaves the rule mismatch in place and the customer waiting.",
                evidenceNote: "The rejection confirms the scheme rules do not match."
            ),
            InvestigationStep(
                id: "ins-141-s2",
                prompt: "The scheme rules do not match. What next?",
                options: [
                    InvestigationOption(
                        text: "Compare message formats and scheme rules on both sides, side by side.",
                        isRedHerring: false,
                        feedback: "A side by side comparison finds every mismatch, not just the one this payment hit."
                    ),
                    InvestigationOption(
                        text: "Change the formats on one side without telling the other bank.",
                        isRedHerring: false,
                        feedback: "A one-sided change can break the other side and creates a mismatch nobody owns."
                    ),
                    InvestigationOption(
                        text: "Bypass clearing for this payment.",
                        isRedHerring: false,
                        feedback: "Bypassing clearing sends a payment past the control that exists to stop it."
                    ),
                    InvestigationOption(
                        text: "Wait for the scheme to change its rules.",
                        isRedHerring: false,
                        feedback: "The scheme rules are the fixed point. The integration must align to them, not wait for them to move."
                    ),
                ],
                bestOptionIndex: 0,
                whyCorrect: "The systems must align on message formats and scheme rules, not just on the API that carries the messages.",
                wrongTurnCost: "One-sided changes or bypasses hide the mismatch and risk payments that clear on one side and fail on the other.",
                evidenceNote: nil
            ),
            InvestigationStep(
                id: "ins-141-s3",
                prompt: "Formats and rules are compared. How do you prove the integration works?",
                options: [
                    InvestigationOption(
                        text: "Run the API connection test again.",
                        isRedHerring: false,
                        feedback: "The connection test passed before the failure. Passing it again proves nothing new."
                    ),
                    InvestigationOption(
                        text: "Send one test message and check the response.",
                        isRedHerring: false,
                        feedback: "A message and a response prove connectivity. They do not prove a payment clears."
                    ),
                    InvestigationOption(
                        text: "Run a payment end to end: it clears, settles, and reconciles under the scheme rules of both sides.",
                        isRedHerring: false,
                        feedback: "An end to end payment under both sides rules is the only test that proves the integration."
                    ),
                    InvestigationOption(
                        text: "Ask both banks to confirm the connection is working.",
                        isRedHerring: false,
                        feedback: "Two confirmations of a working connection still leave clearing, settlement, and reconciliation untested."
                    ),
                ],
                bestOptionIndex: 2,
                whyCorrect: "An integration is done when a payment clears, settles, and reconciles under the scheme rules of both sides.",
                wrongTurnCost: "Declaring the work done on a connection test repeats the original error and leaves the next payment to fail at clearing.",
                evidenceNote: "The end to end test confirms the payment path, and leaves compliance and operations alignment still to prove."
            ),
            InvestigationStep(
                id: "ins-141-s4",
                prompt: "The end to end payment clears, settles, and reconciles. What remains before the integration is declared done?",
                options: [
                    InvestigationOption(
                        text: "Nothing. The payment worked.",
                        isRedHerring: false,
                        feedback: "The payment worked, but compliance and operations alignment is still unproved."
                    ),
                    InvestigationOption(
                        text: "Align compliance and operations as well, then declare the integration done.",
                        isRedHerring: false,
                        feedback: "Compliance and operations alignment completes the integration. Connectivity alone was never the full job."
                    ),
                    InvestigationOption(
                        text: "Declare it done and fix compliance later.",
                        isRedHerring: false,
                        feedback: "Declaring done with compliance unaligned leaves the live service carrying a known gap."
                    ),
                    InvestigationOption(
                        text: "Run the same payment again to be sure.",
                        isRedHerring: false,
                        feedback: "Repeating a passed test adds no evidence about the parts still unaligned."
                    ),
                ],
                bestOptionIndex: 1,
                whyCorrect: "The systems must also align on compliance and operations. An integration is done only when all of those hold together.",
                wrongTurnCost: "Declaring the integration done early leaves compliance and operations gaps for live payments to find.",
                evidenceNote: nil
            ),
        ],
        resolution: "An integration is not done when the API responds. It is done when a payment clears, settles, and reconciles under the scheme rules of both sides, with compliance and operations aligned. Connected is not interoperable.",
        messages: [],
        systems: ["API connection", "Clearing system", "Settlement and reconciliation", "Compliance and operations"],
        sourceSituationID: "INS-141",
        sourceSituationTitle: "Two instant payment systems connected by API, and a EUR 10,000 payment still failed at clearing",
        sourceTakeaway: "Connected is not interoperable."
    )

    /// Timeout from a downstream service, grounded in SCN-34.
    static let downstreamTimeoutCase = ExceptionCase(
        id: "lab-scn-34",
        incidentType: "Timeout from a downstream service",
        title: "Processed, timed out, then paid twice",
        level: .advanced,
        narrative: "A core banking API processes a EUR 35,000 transaction, then times out before responding. The caller, believing it failed, re-submits a completed transaction, and the customer is debited twice.",
        evidence: [
            ExceptionEvidence(
                id: "scn-34-e1",
                title: "Transaction processed",
                detail: "A core banking API processes a EUR 35,000 transaction.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "scn-34-e2",
                title: "Timeout before response",
                detail: "The API times out before responding.",
                revealedAfterStep: 0,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "scn-34-e3",
                title: "Blind retry",
                detail: "The caller re-submits the completed transaction, believing it failed.",
                revealedAfterStep: 1,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "scn-34-e4",
                title: "Double debit",
                detail: "The customer is debited twice.",
                revealedAfterStep: 1,
                isRedHerring: false,
                redHerringNote: nil
            ),
            ExceptionEvidence(
                id: "scn-34-e5",
                title: "No response means failure",
                detail: "No response arrived, so the team assumes the transaction failed. A timeout hides the true state. It does not prove failure.",
                revealedAfterStep: 0,
                isRedHerring: true,
                redHerringNote: "A timeout means the answer did not arrive. It says nothing about whether the transaction completed."
            ),
            ExceptionEvidence(
                id: "scn-34-e6",
                title: "Missing controls",
                detail: "The missing controls were idempotency keys, a smart timeout strategy, and a reconciliation layer.",
                revealedAfterStep: 3,
                isRedHerring: false,
                redHerringNote: nil
            ),
        ],
        steps: [
            InvestigationStep(
                id: "scn-34-s1",
                prompt: "A mutating call times out with no response. What is the best first step?",
                options: [
                    InvestigationOption(
                        text: "Resubmit the transaction at once.",
                        isRedHerring: true,
                        feedback: "Resubmitting blind is how the customer was debited twice in this case."
                    ),
                    InvestigationOption(
                        text: "Query the true state of the transaction before doing anything else.",
                        isRedHerring: false,
                        feedback: "Querying first replaces the assumption with evidence about what actually happened to the money."
                    ),
                    InvestigationOption(
                        text: "Tell the customer the transaction failed.",
                        isRedHerring: false,
                        feedback: "Failure is unproved. The transaction may already have completed."
                    ),
                    InvestigationOption(
                        text: "Restart the caller service.",
                        isRedHerring: false,
                        feedback: "Restarting the caller answers nothing about the transaction state, and can lose the record of the first call."
                    ),
                ],
                bestOptionIndex: 1,
                whyCorrect: "On any timeout, ask what actually happened to the money. The true state must be queried first, never assumed.",
                wrongTurnCost: "Resubmitting, or telling the customer it failed, acts on an assumption and can double the transaction.",
                evidenceNote: "Querying the state reveals the original transaction already completed."
            ),
            InvestigationStep(
                id: "scn-34-s2",
                prompt: "The query shows the original transaction completed before the timeout. What next?",
                options: [
                    InvestigationOption(
                        text: "Resubmit anyway to be safe.",
                        isRedHerring: false,
                        feedback: "Resubmitting a completed transaction creates the second debit this case warns against."
                    ),
                    InvestigationOption(
                        text: "Delete the record of the first call.",
                        isRedHerring: false,
                        feedback: "Deleting the record destroys the proof that the transaction completed."
                    ),
                    InvestigationOption(
                        text: "Use the completed transaction as the outcome, and do not resubmit.",
                        isRedHerring: false,
                        feedback: "The completed transaction is the outcome. No second call is needed."
                    ),
                    InvestigationOption(
                        text: "Ask the customer to confirm whether they were debited.",
                        isRedHerring: false,
                        feedback: "The customer cannot prove the transaction state. The system record already does."
                    ),
                ],
                bestOptionIndex: 2,
                whyCorrect: "A pending-state transaction model checks state before acting, so a completed transaction is never submitted twice.",
                wrongTurnCost: "Resubmitting a completed transaction, or deleting its record, turns one good transaction into a double debit with no proof.",
                evidenceNote: nil
            ),
            InvestigationStep(
                id: "scn-34-s3",
                prompt: "The double debit is fixed for this customer. What stops the next timeout paying twice?",
                options: [
                    InvestigationOption(
                        text: "Shorten the timeout so failures arrive faster.",
                        isRedHerring: false,
                        feedback: "A shorter timeout creates more timeouts. It does not make retries safe."
                    ),
                    InvestigationOption(
                        text: "Put idempotency keys on every mutating call, so a retry cannot create a second transaction.",
                        isRedHerring: false,
                        feedback: "An idempotency key makes the retry safe: the same key cannot create a second transaction."
                    ),
                    InvestigationOption(
                        text: "Ban all retries.",
                        isRedHerring: false,
                        feedback: "Banning retries leaves genuine failures unrecovered. Safe retries are the answer, not no retries."
                    ),
                    InvestigationOption(
                        text: "Log the timeout and move on.",
                        isRedHerring: false,
                        feedback: "Logging records the failure. It does not prevent the next one."
                    ),
                ],
                bestOptionIndex: 1,
                whyCorrect: "Idempotency keys on every mutating call, a pending-state model, and a query-first rule together make a timeout safe.",
                wrongTurnCost: "Without idempotency keys, the next timeout retry can pay twice the same way.",
                evidenceNote: "The missing controls are now named: idempotency keys, a smart timeout strategy, and a reconciliation layer."
            ),
            InvestigationStep(
                id: "scn-34-s4",
                prompt: "Idempotency keys are in place. What completes the fix?",
                options: [
                    InvestigationOption(
                        text: "Nothing further is needed.",
                        isRedHerring: false,
                        feedback: "Keys alone do not catch every failure mode. The reconciliation layer is still missing."
                    ),
                    InvestigationOption(
                        text: "Remove the pending-state model to simplify the code.",
                        isRedHerring: false,
                        feedback: "Removing the pending-state model removes the state check that stops a blind resubmission."
                    ),
                    InvestigationOption(
                        text: "Keep the blind retry for small amounts.",
                        isRedHerring: false,
                        feedback: "A blind retry is unsafe at any amount. The rule must hold for every timeout."
                    ),
                    InvestigationOption(
                        text: "Add a reconciliation layer, and make query-first on any timeout a standing rule.",
                        isRedHerring: false,
                        feedback: "The reconciliation layer catches what slips through, and the standing rule keeps every future timeout safe."
                    ),
                ],
                bestOptionIndex: 3,
                whyCorrect: "The fix is idempotency keys on every mutating call, a pending-state transaction model that checks state before acting, and a standing rule that on any timeout the true state is queried first.",
                wrongTurnCost: "Leaving the fix half done keeps a path open for the next timeout to pay twice.",
                evidenceNote: nil
            ),
        ],
        resolution: "Put idempotency keys on every mutating call, keep a pending-state model that checks state before acting, and make it a standing rule: on any timeout, query the true state first, never blindly re-submit. The fix is completed by a reconciliation layer that catches what slips through.",
        messages: [],
        systems: ["Core banking API", "Caller service", "Pending-state transaction store", "Reconciliation layer"],
        sourceSituationID: "SCN-34",
        sourceSituationTitle: "Processed, timed out, then paid twice",
        sourceTakeaway: "The fix is idempotency keys on every mutating call, a pending-state transaction model that checks state before acting, and a standing rule that on any timeout the true state is queried first."
    )
}
