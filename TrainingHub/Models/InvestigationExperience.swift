// InvestigationExperience.swift
// Models for the Payments Mystery Investigation Experience: the
// investigation case, its evidence, hypotheses, decisions, report,
// and the in-memory record of one learner run.
//
// The case model is built by InvestigationEngine from a situation
// (derived tier) or from an authored lab case (authored tier). It
// carries no entitlement, purchase, auth, or progress state; gating
// stays with the existing stores and views. No em dashes in any
// user-facing text.

import Foundation

// MARK: - Evidence

/// The kind of one evidence item, used to group the workspace list
/// and to pick the renderer for the item.
enum InvestigationEvidenceKind: String, Codable, Hashable, CaseIterable {
    case timeline
    case message
    case log
    case ledger
    case recon
    case api
    case clearing
    case note

    /// The group label shown for this kind in the workspace list.
    var displayName: String {
        switch self {
        case .timeline: return "Timeline"
        case .message: return "Messages"
        case .log: return "Logs"
        case .ledger: return "Ledger"
        case .recon: return "Reconciliation"
        case .api: return "API"
        case .clearing: return "Clearing"
        case .note: return "Notes"
        }
    }
}

/// Whether an evidence item is fully available. Partial and
/// unavailable reasons are systemic only (for example "available
/// only after a targeted status request"), never invented facts.
enum InvestigationEvidenceCompleteness: Hashable {
    case complete
    case partial(reason: String)
    case unavailable(reason: String)

    /// True when the item is fully available.
    var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }

    /// The systemic reason, when the item is partial or unavailable.
    var reason: String? {
        switch self {
        case .complete: return nil
        case .partial(let reason): return reason
        case .unavailable(let reason): return reason
        }
    }
}

/// One piece of evidence in an investigation case. `structuredLines`
/// carries field tables and log lines; `sourceField` names the
/// structured field the item derived from (for example "explain",
/// "messages", "visual", "domain", or "authored"), for auditability.
/// `revealedAfterStep` is kept from the authored Lab data for
/// auditability only: it never gates visibility, because the
/// learner decides which evidence to inspect, in any order, at
/// every difficulty. `isRedHerring` is authored tier only and is
/// always false in the derived tier.
struct InvestigationEvidence: Identifiable, Hashable {
    let id: String
    let kind: InvestigationEvidenceKind
    let title: String
    let body: String
    let structuredLines: [String]
    let sourceField: String
    let revealedAfterStep: Int
    let completeness: InvestigationEvidenceCompleteness
    let isRedHerring: Bool

    /// A copy of this item with a different completeness, used when
    /// the Expert difficulty marks one item partial.
    func withCompleteness(_ completeness: InvestigationEvidenceCompleteness) -> InvestigationEvidence {
        InvestigationEvidence(
            id: id,
            kind: kind,
            title: title,
            body: body,
            structuredLines: structuredLines,
            sourceField: sourceField,
            revealedAfterStep: revealedAfterStep,
            completeness: completeness,
            isRedHerring: isRedHerring
        )
    }
}

// MARK: - Hypotheses

/// Where one hypothesis came from: the flawed requirement stated in
/// the case, the root cause, or the category alternative template.
enum InvestigationHypothesisSource: String, Codable, Hashable {
    case flawedRequirement
    case rootCause
    case categoryAlternative
}

/// One hypothesis the learner can hold and revise. Exactly one
/// hypothesis per case is correct.
struct InvestigationHypothesis: Identifiable, Hashable {
    let id: String
    let text: String
    let isCorrect: Bool
    let source: InvestigationHypothesisSource
}

// MARK: - Decisions

/// One option in a decision point. `consequence` is the narrative
/// consequence shown on a wrong pick; it is empty for the best
/// option. `isRedHerring` marks an option that follows a distraction
/// in the evidence; it is authored tier only and is always false in
/// the derived tier, mirroring the evidence rule. Scoring charges
/// extra for a red-herring pick.
struct InvestigationDecisionOption: Hashable {
    let text: String
    let isBest: Bool
    let feedback: String
    let consequence: String
    let evidenceNote: String?
    let isRedHerring: Bool

    init(
        text: String,
        isBest: Bool,
        feedback: String,
        consequence: String = "",
        evidenceNote: String? = nil,
        isRedHerring: Bool = false
    ) {
        self.text = text
        self.isBest = isBest
        self.feedback = feedback
        self.consequence = consequence
        self.evidenceNote = evidenceNote
        self.isRedHerring = isRedHerring
    }
}

/// One decision point in the journey. `wrongTurnCost` is the score
/// cost of a wrong pick, reusing the Lab constant. `isTechnical`
/// marks a message or system decision (the technicalAccuracy
/// dimension); `isResolution` marks a corrective-action or
/// preventive-control decision (the resolutionQuality dimension).
/// `hypothesisPrompt` is an optional prompt to reconsider the
/// leading hypothesis after this decision.
struct InvestigationDecisionPoint: Identifiable, Hashable {
    let id: String
    let prompt: String
    let options: [InvestigationDecisionOption]
    let bestOptionIndex: Int
    let whyCorrect: String
    let wrongTurnCost: Int
    let evidenceNote: String?
    let hypothesisPrompt: String?
    let isTechnical: Bool
    let isResolution: Bool

    init(
        id: String,
        prompt: String,
        options: [InvestigationDecisionOption],
        bestOptionIndex: Int,
        whyCorrect: String,
        wrongTurnCost: Int = ExceptionLabScoring.wrongPickDeduction,
        evidenceNote: String? = nil,
        hypothesisPrompt: String? = nil,
        isTechnical: Bool = false,
        isResolution: Bool = false
    ) {
        self.id = id
        self.prompt = prompt
        self.options = options
        self.bestOptionIndex = bestOptionIndex
        self.whyCorrect = whyCorrect
        self.wrongTurnCost = wrongTurnCost
        self.evidenceNote = evidenceNote
        self.hypothesisPrompt = hypothesisPrompt
        self.isTechnical = isTechnical
        self.isResolution = isResolution
    }
}

// MARK: - Payment header and difficulty

/// The derived payment header for a case. Amount and currency come
/// from the title regex, or the not-stated wording when the title
/// and explain name none. Parties are always generic; the reference
/// is always not stated unless the explain names one.
struct InvestigationPaymentHeader: Hashable {
    let amountText: String
    let currencyText: String
    let partiesText: String
    let referenceText: String
}

/// The difficulty mode for one run. Difficulty changes the
/// suggested evidence order, hints, and completeness; it never
/// locks evidence and never changes the number of decision points
/// or the case content.
enum InvestigationDifficulty: String, Codable, Hashable, CaseIterable {
    case rookie
    case professional
    case expert

    var displayName: String {
        switch self {
        case .rookie: return "Rookie"
        case .professional: return "Professional"
        case .expert: return "Expert"
        }
    }

    /// The guidance copy shown for this difficulty on the briefing.
    /// Difficulty changes the suggested order, hints, and
    /// completeness; it never locks evidence or changes the number
    /// of decision points or the case content.
    var guidance: String {
        switch self {
        case .rookie:
            return "Guided. All evidence is available from the start, in a suggested order you can follow or ignore, and each decision shows a method hint before you pick."
        case .professional:
            return "Independent. All evidence is available from the start, and hints appear only after a wrong pick."
        case .expert:
            return "Expert. One evidence item starts partial until you request its status, and no hints appear."
        }
    }
}

/// Which tier built the case: derived from a situation by the
/// engine, or adapted from an authored lab case.
enum InvestigationSource: String, Codable, Hashable {
    case derived
    case authored
}

// MARK: - Case

/// One investigation case: the briefing, the evidence workspace
/// contents, the hypothesis set, the decision points, and the
/// report source material. `timeline` holds the journey steps
/// and `evidence` holds every other item: the two lists are
/// disjoint, so timeline plus evidence is the full set with no
/// item twice. `reflectionPrompt` carries the case closing question,
/// which renders as a reflection prompt in the report and is never
/// a question the learner must answer. The case is built per
/// difficulty because Expert changes evidence completeness.
struct InvestigationCase: Identifiable, Hashable {
    let id: String
    let situationID: String
    let title: String
    let severity: String
    let incidentType: String
    let businessContext: String
    let customerImpact: String
    let incidentReport: String
    let objectives: [String]
    let paymentHeader: InvestigationPaymentHeader
    let timeline: [InvestigationEvidence]
    let evidence: [InvestigationEvidence]
    let hypotheses: [InvestigationHypothesis]
    let decisions: [InvestigationDecisionPoint]
    let correctDiagnosis: String
    let supportingEvidenceIDs: [String]
    let correctiveAction: String
    let preventiveControls: [String]
    let lessons: [String]
    let source: InvestigationSource
    let difficulty: InvestigationDifficulty
    let reflectionPrompt: String?
}

// MARK: - Scores, report, stored result

/// The five investigation dimensions, each 0 to 100. `overall` is
/// the mean of the five, rounded to the nearest integer.
struct InvestigationDimensionScores: Codable, Hashable {
    let evidenceInterpretation: Int
    let efficiency: Int
    let technicalAccuracy: Int
    let rootCauseIdentification: Int
    let resolutionQuality: Int

    var overall: Int {
        let sum = evidenceInterpretation + efficiency + technicalAccuracy + rootCauseIdentification + resolutionQuality
        return Int((Double(sum) / 5.0).rounded())
    }
}

/// The investigation report for one completed run.
struct InvestigationReport: Codable, Hashable {
    let caseID: String
    let situationID: String
    let difficulty: InvestigationDifficulty
    let completedAt: Date
    let dimensionScores: InvestigationDimensionScores
    let incorrectAssumptions: [String]
    let citedEvidenceIDs: [String]
    let wrongPicks: Int
    let evidenceOpenedCount: Int
    let decisionsCorrect: Int
    let decisionsTotal: Int
}

/// The stored result for one case: the best overall score earned on
/// it, how many times it has been completed, and the report from the
/// most recent completion. `difficulty` is the difficulty of the run
/// that set the best score.
struct InvestigationResult: Codable, Hashable, Identifiable {
    let caseID: String
    let situationID: String
    let difficulty: InvestigationDifficulty
    let bestOverall: Int
    let completions: Int
    let lastCompletedAt: Date
    let lastReport: InvestigationReport

    var id: String { caseID }
}

// MARK: - Run record

/// The in-memory record of one learner run, owned by the experience
/// view and handed to InvestigationScoring at completion.
/// Hypothesis revision endpoints and the diagnosis pick are
/// hypothesis ids; decision pick keys are decision point ids.
/// `requestedStatusAction` records the Expert-only status request
/// action, which is an investigation action, not a scored decision.
struct InvestigationRun {
    var openedEvidenceIDs: Set<String> = []
    var hypothesisRevisions: [(from: String, to: String)] = []
    var decisionPicks: [String: Int] = [:]
    var citedEvidenceIDs: [String] = []
    var diagnosisHypothesisID: String? = nil
    var requestedStatusAction: Bool = false
}
