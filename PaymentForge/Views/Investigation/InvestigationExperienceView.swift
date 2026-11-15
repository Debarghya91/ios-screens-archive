// InvestigationExperienceView.swift
// The investigation experience: one case investigated from briefing
// to report. The journey has six states: briefing, evidence,
// hypotheses, decisions, diagnosis and report. This view owns the
// journey state machine and the run record, and re-checks the
// situations gate on appear. A locked case renders only the locked
// gate, with no case text at all.
//
// This view carries no NavigationStack of its own: the host provides
// the stack, as ExceptionInvestigationLabView does. No new colors,
// fonts, storage keys or network calls. No em dashes in any
// user-facing text.

import SwiftUI

// MARK: - Journey steps

private enum InvestigationJourneyStep: Int, CaseIterable {
    case briefing = 0
    case evidence
    case hypotheses
    case decisions
    case diagnosis
    case report

    var title: String {
        switch self {
        case .briefing:
            return "Briefing"
        case .evidence:
            return "Evidence"
        case .hypotheses:
            return "Hypotheses"
        case .decisions:
            return "Decisions"
        case .diagnosis:
            return "Diagnosis"
        case .report:
            return "Report"
        }
    }
}

// MARK: - Shared helpers

/// An empty run record: nothing opened, no revisions, no picks, no
/// diagnosis and no status request yet.
private func investigationEmptyRun() -> InvestigationRun {
    InvestigationRun(
        openedEvidenceIDs: [],
        hypothesisRevisions: [],
        decisionPicks: [:],
        citedEvidenceIDs: [],
        diagnosisHypothesisID: nil,
        requestedStatusAction: false
    )
}

/// Guidance copy for each difficulty, from the architecture plan.
/// Difficulty changes the suggested order, hints, and completeness;
/// it never locks evidence and never changes the number of decision
/// points or the case content.
private func investigationDifficultyGuidance(for difficulty: InvestigationDifficulty) -> String {
    switch difficulty {
    case .rookie:
        return "Guided. All evidence is available from the start, in a suggested order you can follow or ignore. Hints guide your method before each decision, without naming the answer."
    case .professional:
        return "Independent. All evidence is available from the start, and hints appear only after a wrong pick."
    case .expert:
        return "One evidence item starts incomplete until you request its status. No hints."
    }
}

/// Severity pill colors: High reads as an error, Medium reads as
/// gold, Moderate reads as royal.
private func investigationSeverityColors(for severity: String) -> (background: Color, foreground: Color) {
    switch severity.lowercased() {
    case "high":
        return (Color.pfError.opacity(0.10), .pfError)
    case "medium":
        return (Color.pfGoldSoft, .pfGoldText)
    case "moderate":
        return (Color.pfRoyal.opacity(0.10), .pfRoyal)
    default:
        return (Color.pfRoyal.opacity(0.10), .pfRoyal)
    }
}

/// Labels and icons for the evidence kinds, in workspace order:
/// timeline first, then messages, then the rest.
private enum InvestigationEvidencePresentation {
    static let orderedKinds: [InvestigationEvidenceKind] = [
        .timeline, .message, .log, .ledger, .recon, .api, .clearing, .note,
    ]

    static func label(for kind: InvestigationEvidenceKind) -> String {
        switch kind {
        case .timeline:
            return "Timeline"
        case .message:
            return "Messages"
        case .log:
            return "Logs"
        case .ledger:
            return "Ledger"
        case .recon:
            return "Reconciliation"
        case .api:
            return "API"
        case .clearing:
            return "Clearing"
        case .note:
            return "Notes"
        }
    }

    static func singularLabel(for kind: InvestigationEvidenceKind) -> String {
        switch kind {
        case .timeline:
            return "Timeline"
        case .message:
            return "Message"
        case .log:
            return "Log"
        case .ledger:
            return "Ledger entry"
        case .recon:
            return "Reconciliation record"
        case .api:
            return "API record"
        case .clearing:
            return "Clearing record"
        case .note:
            return "Note"
        }
    }

    static func icon(for kind: InvestigationEvidenceKind) -> String {
        switch kind {
        case .timeline:
            return "clock.fill"
        case .message:
            return "envelope.fill"
        case .log:
            return "doc.text.fill"
        case .ledger:
            return "list.bullet.rectangle"
        case .recon:
            return "arrow.left.arrow.right"
        case .api:
            return "network"
        case .clearing:
            return "checkmark.seal.fill"
        case .note:
            return "note.text"
        }
    }
}

/// The first message code named in a title, if any: an ISO 20022 code
/// (pacs, pain or camt) or an MT code. The message explorer opens the
/// code directly, and shows its list for a code it does not cover.
private func investigationMessageCode(from title: String) -> String? {
    let pattern = #"(?i)\b(pacs|pain|camt)\.[0-9]{3}\b|\bMT[0-9]{3}\b"#
    guard let range = title.range(of: pattern, options: .regularExpression) else { return nil }
    return String(title[range])
}

/// Structured lines split into field pairs on the first colon. A line
/// with no usable colon renders as a plain line, with an empty key.
private func investigationFieldPairs(from lines: [String]) -> [(key: String, value: String)] {
    lines.map { line in
        if let colon = line.firstIndex(of: ":") {
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, !value.isEmpty {
                return (key, value)
            }
        }
        return ("", line)
    }
}

/// API lines split into request and response blocks. Lines before any
/// response marker belong to the request; a line starting with
/// "Response" starts the response block, and a line starting with
/// "Request" starts the request block again.
private func investigationApiSections(from lines: [String]) -> (request: [String], response: [String]) {
    var request: [String] = []
    var response: [String] = []
    var inResponse = false
    for line in lines {
        let lowered = line.lowercased()
        if lowered.hasPrefix("response") {
            inResponse = true
            response.append(line)
        } else if lowered.hasPrefix("request") {
            inResponse = false
            request.append(line)
        } else if inResponse {
            response.append(line)
        } else {
            request.append(line)
        }
    }
    return (request, response)
}

/// The debit or credit side named in a ledger line, if any, so the
/// ledger table can label each posting.
private func investigationLedgerSide(for line: String) -> String? {
    let lowered = line.lowercased()
    if lowered.contains("credit") || lowered.contains(" cr ") || lowered.hasSuffix(" cr") {
        return "Credit"
    }
    if lowered.contains("debit") || lowered.contains(" dr ") || lowered.hasSuffix(" dr") {
        return "Debit"
    }
    return nil
}

// MARK: - Experience view

/// One investigation, from briefing to report. Owns the journey state
/// machine, the run record and the case actually being investigated.
/// The passed case already reflects its difficulty; the briefing step
/// lets the learner pick another difficulty before starting, and the
/// rebuild callback rebuilds the case through the engine. Without a
/// callback the case is returned unchanged, so the briefing keeps
/// showing the difficulty the case was built with.
struct InvestigationExperienceView: View {
    @EnvironmentObject private var storeManager: StoreManager
    @Environment(\.dismiss) private var dismiss

    @State private var currentCase: InvestigationCase
    private let isFreeSample: Bool
    private let isWeeklyFreeCase: Bool
    private let onDifficultyChange: (InvestigationDifficulty) -> InvestigationCase

    @State private var step: InvestigationJourneyStep = .briefing
    @State private var run: InvestigationRun
    @State private var selectedEvidenceID: String?
    @State private var statusRequested = false
    @State private var leadingHypothesisID: String?
    @State private var decisionIndex = 0
    @State private var solvedDecisionIDs: Set<String> = []
    @State private var pickedOption: Int?
    @State private var pickedWasBest = false
    @State private var triedWrong: Set<Int> = []
    @State private var wrongPickSummaries: [String] = []
    @State private var diagnosisHypothesisID: String?
    @State private var citedEvidenceIDs: Set<String> = []
    @State private var report: InvestigationReport?
    @State private var didRecordCompletion = false
    @State private var showCheckout = false

    /// The default entry point. Without a rebuild callback a picked
    /// difficulty returns the passed case unchanged.
    init(investigation: InvestigationCase, isFreeSample: Bool, isWeeklyFreeCase: Bool) {
        self.init(
            investigation: investigation,
            isFreeSample: isFreeSample,
            isWeeklyFreeCase: isWeeklyFreeCase,
            onDifficultyChange: { _ in investigation }
        )
    }

    /// Entry point with a rebuild callback: the caller rebuilds the
    /// case through the engine for the picked difficulty, so Expert
    /// completeness and the hypothesis set match the new difficulty.
    init(
        investigation: InvestigationCase,
        isFreeSample: Bool,
        isWeeklyFreeCase: Bool,
        onDifficultyChange: @escaping (InvestigationDifficulty) -> InvestigationCase
    ) {
        _currentCase = State(initialValue: investigation)
        self.isFreeSample = isFreeSample
        self.isWeeklyFreeCase = isWeeklyFreeCase
        self.onDifficultyChange = onDifficultyChange
        _run = State(initialValue: investigationEmptyRun())
    }

    /// The situations gate, re-checked on every render including
    /// appear, matching SituationDetailView: free sample, weekly free
    /// case, or the situations unlock. Nothing else decides it.
    private var isLocked: Bool {
        !isFreeSample && !isWeeklyFreeCase && !storeManager.isSituationsUnlocked
    }

    private var difficulty: InvestigationDifficulty { currentCase.difficulty }

    /// Difficulty may change only before the investigation starts:
    /// once any evidence is opened, any hypothesis revised, any
    /// decision picked or a diagnosis chosen, the difficulty is fixed.
    private var difficultyChangeAllowed: Bool {
        run.openedEvidenceIDs.isEmpty
            && run.hypothesisRevisions.isEmpty
            && run.decisionPicks.isEmpty
            && run.diagnosisHypothesisID == nil
    }

    /// Timeline items first, then the remaining evidence, in case
    /// order. The workspace groups this list by kind.
    private var allEvidence: [InvestigationEvidence] {
        currentCase.timeline + currentCase.evidence
    }

    /// Evidence the learner may see now. All evidence is available
    /// from the start at every difficulty: the learner decides
    /// which evidence to inspect, in any order. Rookie offers a
    /// suggested order in the workspace header; it is a suggestion,
    /// never a lock. Only Expert completeness can withhold an item
    /// body, and only until the status request is made.
    private var visibleEvidence: [InvestigationEvidence] {
        allEvidence
    }

    private var currentDecision: InvestigationDecisionPoint? {
        guard decisionIndex >= 0, decisionIndex < currentCase.decisions.count else { return nil }
        return currentCase.decisions[decisionIndex]
    }

    private var openedEvidence: [InvestigationEvidence] {
        allEvidence.filter { run.openedEvidenceIDs.contains($0.id) }
    }

    private var citedEvidence: [InvestigationEvidence] {
        allEvidence.filter { citedEvidenceIDs.contains($0.id) }
    }

    /// Incorrect assumptions for the report: earlier leading
    /// hypotheses that were wrong, wrong decision picks, and anything
    /// the scoring pass recorded, deduplicated in that order.
    private var incorrectAssumptions: [String] {
        var items: [String] = []
        for revision in run.hypothesisRevisions {
            if let prior = currentCase.hypotheses.first(where: { $0.id == revision.from }),
               !prior.isCorrect,
               !items.contains(prior.text) {
                items.append(prior.text)
            }
        }
        for summary in wrongPickSummaries where !items.contains(summary) {
            items.append(summary)
        }
        if let scored = report {
            for assumption in scored.incorrectAssumptions where !items.contains(assumption) {
                items.append(assumption)
            }
        }
        return items
    }

    /// The scroll anchor at the top of the journey. Every step
    /// transition and every decision change scrolls back to it, so
    /// the learner always lands on the new content without having
    /// to scroll manually.
    private let journeyTopID = "investigationJourneyTop"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.lg) {
                    if isLocked {
                        lockedGateView
                    } else {
                        progressHeader
                        stepContent
                    }
                }
                .padding(PFSpacing.lg)
                .id(journeyTopID)
            }
            .onChange(of: step.rawValue) { _, _ in
                withAnimation {
                    proxy.scrollTo(journeyTopID, anchor: .top)
                }
            }
            .onChange(of: decisionIndex) { _, _ in
                withAnimation {
                    proxy.scrollTo(journeyTopID, anchor: .top)
                }
            }
            .pfProtectedContent()
            .background(Color.pfBackground)
            .pfTabBarClearance()
            .navigationTitle("Investigation")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCheckout) {
                CheckoutView()
            }
        }
    }

    // MARK: - Progress and gate

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Step \(step.rawValue + 1) of 6")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfNavy)
                Spacer()
                Text(step.title)
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
            }
            PFProgressBar(progress: Double(step.rawValue + 1) / 6.0)
        }
    }

    /// The locked gate: generic copy plus the checkout entry, reusing
    /// the SituationDetailView pattern. No case text of any kind
    /// renders here: no title, no id, no briefing and no evidence.
    private var lockedGateView: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.sm) {
                    PFIconTile(systemImage: "lock.fill", size: 44)
                    Text("Unlock this case")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                }
                Text("This investigation case is part of the full Payment Situations set. Unlock all \(ContentManifest.situationCount)\(storeManager.isPriceAvailable(for: ProductCatalogue.situationsProductID) ? " for \(storeManager.priceText)" : ""). The free samples stay free. The Integrated Course includes all situations too.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                PFPrimaryButton(title: "Go to checkout") {
                    showCheckout = true
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("investigationLockedGate")
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .briefing:
            InvestigationBriefingView(
                investigation: currentCase,
                difficultyChangeAllowed: difficultyChangeAllowed,
                onDifficultySelected: changeDifficulty,
                onStart: beginInvestigation
            )
        case .evidence:
            InvestigationEvidenceWorkspaceView(
                investigation: currentCase,
                visibleEvidence: visibleEvidence,
                totalEvidenceCount: allEvidence.count,
                selectedEvidenceID: $selectedEvidenceID,
                openedEvidenceIDs: run.openedEvidenceIDs,
                statusRequested: statusRequested,
                onSelect: selectEvidence,
                onRequestStatus: requestStatus,
                onContinue: { step = .hypotheses },
                onBack: { step = .briefing }
            )
        case .hypotheses:
            InvestigationHypothesisView(
                investigation: currentCase,
                leadingHypothesisID: $leadingHypothesisID,
                onSelect: selectLeadingHypothesis,
                onContinue: goToDecisions,
                onBack: { step = .evidence }
            )
        case .decisions:
            if let decision = currentDecision {
                InvestigationDecisionView(
                    decision: decision,
                    decisionIndex: decisionIndex,
                    decisionCount: currentCase.decisions.count,
                    solvedCount: solvedDecisionIDs.count,
                    difficulty: difficulty,
                    hypotheses: currentCase.hypotheses,
                    leadingHypothesisID: leadingHypothesisID,
                    isSolved: solvedDecisionIDs.contains(decision.id),
                    pickedOption: $pickedOption,
                    pickedWasBest: pickedWasBest,
                    triedWrong: triedWrong,
                    onPick: { pickDecisionOption(decision, index: $0) },
                    onRetry: { pickedOption = nil },
                    onContinue: { continueDecision(decision) },
                    onReviseHypothesis: selectLeadingHypothesis,
                    onBack: { step = .hypotheses },
                    onReviewEvidence: { step = .evidence }
                )
            } else {
                // No decision to show: the case has no decisions, or
                // every decision is solved. Move on to the diagnosis.
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("There are no more decisions in this case.")
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                        PFPrimaryButton(title: "Continue to the diagnosis") {
                            step = .diagnosis
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .diagnosis:
            InvestigationDiagnosisView(
                investigation: currentCase,
                openedEvidence: openedEvidence,
                diagnosisHypothesisID: $diagnosisHypothesisID,
                citedEvidenceIDs: $citedEvidenceIDs,
                onConfirm: confirmDiagnosis,
                onBack: goToDecisions,
                onGoToEvidence: { step = .evidence }
            )
        case .report:
            if let report {
                InvestigationReportView(
                    investigation: currentCase,
                    report: report,
                    incorrectAssumptions: incorrectAssumptions,
                    citedEvidence: citedEvidence,
                    onDone: { dismiss() }
                )
            } else {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("The report is not available yet. Complete the diagnosis to see it.")
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                        PFPrimaryButton(title: "Done") { dismiss() }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Journey actions

    private func changeDifficulty(to difficulty: InvestigationDifficulty) {
        guard difficultyChangeAllowed, difficulty != currentCase.difficulty else { return }
        currentCase = onDifficultyChange(difficulty)
        resetJourneyState()
    }

    private func resetJourneyState() {
        run = investigationEmptyRun()
        selectedEvidenceID = nil
        statusRequested = false
        leadingHypothesisID = nil
        decisionIndex = 0
        solvedDecisionIDs = []
        pickedOption = nil
        pickedWasBest = false
        triedWrong = []
        wrongPickSummaries = []
        diagnosisHypothesisID = nil
        citedEvidenceIDs = []
        report = nil
        didRecordCompletion = false
    }

    /// Starts the investigation: the workspace auto-displays the
    /// first evidence item before any tap, so that item counts as
    /// opened from the start. The opened set is initialised with
    /// it here, so "Evidence opened" is 1 when it is displayed
    /// and the evidence-interpretation score counts it, exactly
    /// as if the learner had tapped it.
    private func beginInvestigation() {
        if let first = visibleEvidence.first {
            run.openedEvidenceIDs.insert(first.id)
        }
        step = .evidence
    }

    private func selectEvidence(_ item: InvestigationEvidence) {
        selectedEvidenceID = item.id
        run.openedEvidenceIDs.insert(item.id)
    }

    private func requestStatus() {
        statusRequested = true
        run.requestedStatusAction = true
    }

    private func selectLeadingHypothesis(_ hypothesis: InvestigationHypothesis) {
        if let current = leadingHypothesisID, current != hypothesis.id {
            run.hypothesisRevisions.append((from: current, to: hypothesis.id))
        }
        leadingHypothesisID = hypothesis.id
    }

    /// Enter the decisions step at the first unsolved decision, or
    /// the last decision when all are solved. Moving to another
    /// decision clears any feedback showing for the previous one.
    private func goToDecisions() {
        let target = currentCase.decisions.firstIndex { !solvedDecisionIDs.contains($0.id) }
            ?? max(0, currentCase.decisions.count - 1)
        if target != decisionIndex {
            decisionIndex = target
            pickedOption = nil
            pickedWasBest = false
            triedWrong = []
        }
        step = .decisions
    }

    /// Pick an option for a decision, following the Lab pattern: a
    /// wrong pick can be retried, and the decision is solved only on
    /// the best pick. The run keeps the first pick per decision, so
    /// scoring can tell a best-first decision from a recovered one.
    private func pickDecisionOption(_ decision: InvestigationDecisionPoint, index: Int) {
        guard pickedOption == nil, !triedWrong.contains(index) else { return }
        guard index >= 0, index < decision.options.count else { return }
        if run.decisionPicks[decision.id] == nil {
            run.decisionPicks[decision.id] = index
        }
        if index == decision.bestOptionIndex {
            pickedWasBest = true
        } else {
            pickedWasBest = false
            triedWrong.insert(index)
            wrongPickSummaries.append("Action considered: \(decision.options[index].text)")
        }
        pickedOption = index
    }

    private func continueDecision(_ decision: InvestigationDecisionPoint) {
        solvedDecisionIDs.insert(decision.id)
        pickedOption = nil
        pickedWasBest = false
        triedWrong = []
        if decisionIndex + 1 < currentCase.decisions.count {
            decisionIndex += 1
        } else {
            step = .diagnosis
        }
    }

    private func confirmDiagnosis() {
        guard let diagnosisID = diagnosisHypothesisID, !citedEvidenceIDs.isEmpty else { return }
        run.diagnosisHypothesisID = diagnosisID
        run.citedEvidenceIDs = allEvidence.filter { citedEvidenceIDs.contains($0.id) }.map(\.id)
        let scored = InvestigationScoring.score(case: currentCase, run: run)
        report = scored
        recordCompletion(report: scored)
        step = .report
    }

    /// Record the completion once. The store owns the merge: the
    /// best overall score is kept and the completion count grows
    /// by one.
    private func recordCompletion(report: InvestigationReport) {
        guard !didRecordCompletion else { return }
        didRecordCompletion = true
        InvestigationStore.shared.recordCompletion(result: report)
    }
}

// MARK: - Briefing

struct InvestigationBriefingView: View {
    let investigation: InvestigationCase
    let difficultyChangeAllowed: Bool
    let onDifficultySelected: (InvestigationDifficulty) -> Void
    let onStart: () -> Void

    private let difficulties: [InvestigationDifficulty] = [.rookie, .professional, .expert]

    private var previousResult: InvestigationResult? {
        InvestigationStore.shared.result(for: investigation.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            headerSection
            contextSection
            paymentHeaderCard
            objectivesSection
            difficultySection
            if let previous = previousResult {
                Text("Best score so far: \(previous.bestOverall) out of 100. Completed \(previous.completions) \(previous.completions == 1 ? "time" : "times").")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfRoyal)
            }
            PFGoldButton(title: "Start the investigation", action: onStart)
            Text("Your investigation results stay on this device.")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text(investigation.incidentType)
                .font(.pfCaptionBold)
                .foregroundColor(.pfRoyal)
            Text(investigation.title)
                .font(.pfScreenTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: PFSpacing.sm) {
                PFPill(
                    text: "Case \(investigation.situationID)",
                    background: Color.pfNavy.opacity(0.08),
                    foreground: .pfNavy
                )
                severityPill
                PFPill(
                    text: investigation.difficulty.displayName,
                    background: Color.pfGoldSoft,
                    foreground: Color.pfGoldText
                )
            }
            Text("Severity is derived from the case level and failure category.")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var severityPill: some View {
        let colors = investigationSeverityColors(for: investigation.severity)
        return PFPill(
            text: "Severity: \(investigation.severity)",
            background: colors.background,
            foreground: colors.foreground
        )
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            briefingTextSection(title: "Business context", text: investigation.businessContext)
            briefingTextSection(title: "Customer impact", text: investigation.customerImpact)
            briefingTextSection(title: "Incident report", text: investigation.incidentReport)
        }
    }

    private func briefingTextSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text(title)
                .font(.pfCaptionBold)
                .foregroundColor(.pfNavy)
            PFBodyText(text: text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The payment details card. The amount row always renders,
    /// and carries the single not-stated statement when the case
    /// names no amount. Currency and reference rows are omitted
    /// when the case does not state them, so an absent field is
    /// never repeated across the panel.
    private var paymentHeaderCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("Payment details")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                paymentRow(label: "Amount", value: investigation.paymentHeader.amountText)
                if investigation.paymentHeader.currencyText != "Not stated in the case" {
                    paymentRow(label: "Currency", value: investigation.paymentHeader.currencyText)
                }
                paymentRow(label: "Parties", value: investigation.paymentHeader.partiesText)
                if investigation.paymentHeader.referenceText != "Reference not stated in the case" {
                    paymentRow(label: "Reference", value: investigation.paymentHeader.referenceText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func paymentRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PFSpacing.md) {
            Text(label)
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.pfBody)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private var objectivesSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Investigation objectives")
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                ForEach(Array(investigation.objectives.enumerated()), id: \.offset) { index, objective in
                    HStack(alignment: .top, spacing: PFSpacing.sm) {
                        ZStack {
                            Circle()
                                .stroke(Color.pfRoyal, lineWidth: 2)
                                .frame(width: 24, height: 24)
                            Text("\(index + 1)")
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfRoyal)
                        }
                        .padding(.top, 2)
                        Text(objective)
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Choose your difficulty")
            Text("Difficulty can be changed here, before the investigation starts.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(difficulties, id: \.self) { difficulty in
                difficultyRow(difficulty)
            }
            if !difficultyChangeAllowed {
                Text("Difficulty is fixed once the investigation has started.")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfSecondaryText)
            }
        }
    }

    private func difficultyRow(_ difficulty: InvestigationDifficulty) -> some View {
        let isSelected = investigation.difficulty == difficulty
        return Button {
            onDifficultySelected(difficulty)
        } label: {
            HStack(alignment: .top, spacing: PFSpacing.sm) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.pfRoyal : Color.pfBorder, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Circle()
                            .fill(Color.pfRoyal)
                            .frame(width: 12, height: 12)
                    }
                }
                .padding(.top, 2)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(difficulty.displayName)
                        .font(.pfBody)
                        .fontWeight(.semibold)
                        .foregroundColor(.pfNavy)
                    Text(investigationDifficultyGuidance(for: difficulty))
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(PFSpacing.md)
            .background(isSelected ? Color.pfRoyal.opacity(0.06) : Color.pfCard)
            .cornerRadius(PFSpacing.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                    .stroke(isSelected ? Color.pfRoyal : Color.pfBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!difficultyChangeAllowed)
        .opacity(difficultyChangeAllowed ? 1.0 : 0.7)
        .accessibilityLabel("Difficulty: \(difficulty.displayName)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

// MARK: - Evidence workspace

struct InvestigationEvidenceWorkspaceView: View {
    let investigation: InvestigationCase
    let visibleEvidence: [InvestigationEvidence]
    let totalEvidenceCount: Int
    @Binding var selectedEvidenceID: String?
    let openedEvidenceIDs: Set<String>
    let statusRequested: Bool
    let onSelect: (InvestigationEvidence) -> Void
    let onRequestStatus: () -> Void
    let onContinue: () -> Void
    let onBack: () -> Void

    /// The scroll anchor at the top of the evidence detail. Every
    /// selection scrolls to it, following the journey top-anchor
    /// pattern, so the detail heading is fully visible.
    private let evidenceDetailTopID = "investigationEvidenceDetailTop"

    private var groupedEvidence: [(kind: InvestigationEvidenceKind, items: [InvestigationEvidence])] {
        InvestigationEvidencePresentation.orderedKinds.compactMap { kind in
            let items = visibleEvidence.filter { $0.kind == kind }
            return items.isEmpty ? nil : (kind: kind, items: items)
        }
    }

    private var selectedEvidence: InvestigationEvidence? {
        if let selectedEvidenceID,
           let found = visibleEvidence.first(where: { $0.id == selectedEvidenceID }) {
            return found
        }
        return visibleEvidence.first
    }

    /// Every item is available from the start at every difficulty.
    /// Rookie adds a suggested order; it is a suggestion, never a
    /// lock, and Continue is always available.
    private var headerSubtitle: String {
        switch investigation.difficulty {
        case .rookie:
            return "\(visibleEvidence.count) of \(totalEvidenceCount) items available. Suggested order: timeline first, then messages, then the rest. Open them in any order you choose."
        case .professional:
            return "\(visibleEvidence.count) of \(totalEvidenceCount) items available. All evidence is available from the start."
        case .expert:
            return "\(visibleEvidence.count) of \(totalEvidenceCount) items available. One item may be incomplete until you request its status."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            workspaceHeader
            if visibleEvidence.isEmpty {
                Text("No evidence is available for this case yet.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
            } else {
                evidenceList
                evidenceDetail
            }
            HStack(spacing: PFSpacing.md) {
                PFSecondaryButton(title: "Back", action: onBack)
                PFPrimaryButton(title: "Continue to hypotheses", action: onContinue)
            }
        }
    }

    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text("Evidence workspace")
                .font(.pfSectionTitle)
                .foregroundColor(.white)
            Text(headerSubtitle)
                .font(.pfBody)
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PFSpacing.lg)
        .background(Color.pfHeroGradient)
        .cornerRadius(PFSpacing.cardRadius)
    }

    private var evidenceList: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            ForEach(groupedEvidence, id: \.kind) { group in
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(InvestigationEvidencePresentation.label(for: group.kind))
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfNavy)
                        Spacer()
                        Text("\(group.items.count) items")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                    }
                    ForEach(group.items, id: \.id) { item in
                        evidenceRow(item)
                    }
                }
            }
        }
    }

    private func evidenceRow(_ item: InvestigationEvidence) -> some View {
        let isSelected = selectedEvidence?.id == item.id
        let isOpened = openedEvidenceIDs.contains(item.id)
        return Button {
            onSelect(item)
        } label: {
            HStack(spacing: PFSpacing.sm) {
                PFIconTile(systemImage: InvestigationEvidencePresentation.icon(for: item.kind), size: 36)
                Text(item.title)
                    .font(.pfBody)
                    .fontWeight(.semibold)
                    .foregroundColor(.pfNavy)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if isOpened {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.pfBody.weight(.semibold))
                        .foregroundColor(.pfSuccess)
                        .accessibilityLabel("Opened")
                }
                Image(systemName: "chevron.right")
                    .font(.pfCaption.weight(.semibold))
                    .foregroundColor(.pfSecondaryText)
                    .accessibilityHidden(true)
            }
            .padding(PFSpacing.md)
            .background(isSelected ? Color.pfRoyal.opacity(0.08) : Color.pfCard)
            .cornerRadius(PFSpacing.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                    .stroke(isSelected ? Color.pfRoyal : Color.pfBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Evidence: \(item.title)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    @ViewBuilder
    private var evidenceDetail: some View {
        if let selected = selectedEvidence {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    // Top anchor above the detail heading: scrolling
                    // to it lands the heading below the top edge with
                    // clearance, so opening an item never leaves its
                    // heading clipped at the top of the viewport.
                    Color.clear
                        .frame(height: PFSpacing.xl)
                        .id(evidenceDetailTopID)
                    HStack(spacing: PFSpacing.sm) {
                        PFPill(text: InvestigationEvidencePresentation.singularLabel(for: selected.kind))
                        if openedEvidenceIDs.contains(selected.id) {
                            PFPill(
                                text: "Opened",
                                background: Color.pfSuccess.opacity(0.12),
                                foreground: .pfSuccess
                            )
                        }
                    }
                    Text(selected.title)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    detailContent(for: selected)
                }
                .onChange(of: selectedEvidenceID) { _, _ in
                    withAnimation {
                        proxy.scrollTo(evidenceDetailTopID, anchor: .top)
                    }
                }
            }
        }
    }

    /// Completeness decides what renders. Partial and unavailable
    /// items show their reason and never show withheld body text. In
    /// Expert, the partial item offers a status request, and the full
    /// record appears only after the request is made.
    @ViewBuilder
    private func detailContent(for item: InvestigationEvidence) -> some View {
        switch item.completeness {
        case .complete:
            renderer(for: item)
        case .partial(let reason):
            if statusRequested && investigation.difficulty == .expert {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    Text("Status received. The full record is now shown.")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSuccess)
                    renderer(for: item)
                }
            } else {
                incompleteCard(
                    title: "This evidence is incomplete.",
                    reason: reason,
                    showRequestAction: investigation.difficulty == .expert
                )
            }
        case .unavailable(let reason):
            incompleteCard(
                title: "This evidence is not available.",
                reason: reason,
                showRequestAction: false
            )
        }
    }

    private func incompleteCard(title: String, reason: String, showRequestAction: Bool) -> some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Text(title)
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                Text(reason)
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if showRequestAction {
                    PFPrimaryButton(title: "Request status", action: onRequestStatus)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func renderer(for item: InvestigationEvidence) -> some View {
        switch item.kind {
        case .timeline:
            InvestigationTimelineView(
                evidence: item,
                positionText: timelinePositionText(for: item)
            )
        case .message:
            InvestigationMessageEvidenceView(evidence: item)
        case .log:
            InvestigationLogEvidenceView(evidence: item)
        case .ledger:
            InvestigationLedgerEvidenceView(evidence: item)
        case .recon:
            InvestigationReconEvidenceView(evidence: item)
        case .api:
            InvestigationApiEvidenceView(evidence: item)
        case .clearing:
            InvestigationClearingEvidenceView(evidence: item)
        case .note:
            InvestigationNoteEvidenceView(evidence: item)
        }
    }

    private func timelinePositionText(for item: InvestigationEvidence) -> String? {
        guard item.kind == .timeline else { return nil }
        guard let index = investigation.timeline.firstIndex(where: { $0.id == item.id }) else { return nil }
        return "Step \(index + 1) of \(investigation.timeline.count)"
    }
}

// MARK: - Hypotheses

struct InvestigationHypothesisView: View {
    let investigation: InvestigationCase
    @Binding var leadingHypothesisID: String?
    let onSelect: (InvestigationHypothesis) -> Void
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("What do you believe happened?")
                    .font(.pfSectionTitle)
                    .foregroundColor(.pfNavy)
                Text("Pick a leading hypothesis. You can revise it at any time before the diagnosis. Each revision is recorded for the final report.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Test each hypothesis against the evidence you opened. The strongest hypothesis is the one the records support, not the one that sounds most familiar.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if investigation.hypotheses.isEmpty {
                Text("No hypotheses were provided for this case.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
            } else {
                ForEach(investigation.hypotheses, id: \.id) { hypothesis in
                    hypothesisCard(hypothesis)
                }
            }
            if leadingHypothesisID == nil && !investigation.hypotheses.isEmpty {
                Text("Pick a leading hypothesis to continue.")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfSecondaryText)
            }
            HStack(spacing: PFSpacing.md) {
                PFSecondaryButton(title: "Back", action: onBack)
                PFPrimaryButton(
                    title: "Continue to decisions",
                    action: onContinue,
                    isEnabled: leadingHypothesisID != nil || investigation.hypotheses.isEmpty
                )
            }
        }
    }

    private func hypothesisCard(_ hypothesis: InvestigationHypothesis) -> some View {
        let isLeading = leadingHypothesisID == hypothesis.id
        return Button {
            onSelect(hypothesis)
        } label: {
            HStack(alignment: .top, spacing: PFSpacing.sm) {
                ZStack {
                    Circle()
                        .stroke(isLeading ? Color.pfRoyal : Color.pfBorder, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if isLeading {
                        Circle()
                            .fill(Color.pfRoyal)
                            .frame(width: 12, height: 12)
                    }
                }
                .padding(.top, 2)
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text(hypothesis.text)
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    if isLeading {
                        PFPill(
                            text: "Leading hypothesis",
                            background: Color.pfRoyal.opacity(0.10),
                            foreground: .pfRoyal
                        )
                    }
                }
                Spacer()
            }
            .padding(PFSpacing.md)
            .background(isLeading ? Color.pfRoyal.opacity(0.06) : Color.pfCard)
            .cornerRadius(PFSpacing.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                    .stroke(isLeading ? Color.pfRoyal : Color.pfBorder, lineWidth: isLeading ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hypothesis: \(hypothesis.text)")
        .accessibilityAddTraits(isLeading ? [.isButton, .isSelected] : [.isButton])
    }
}

// MARK: - Decisions

struct InvestigationDecisionView: View {
    let decision: InvestigationDecisionPoint
    let decisionIndex: Int
    let decisionCount: Int
    let solvedCount: Int
    let difficulty: InvestigationDifficulty
    let hypotheses: [InvestigationHypothesis]
    let leadingHypothesisID: String?
    let isSolved: Bool
    @Binding var pickedOption: Int?
    let pickedWasBest: Bool
    let triedWrong: Set<Int>
    let onPick: (Int) -> Void
    let onRetry: () -> Void
    let onContinue: () -> Void
    let onReviseHypothesis: (InvestigationHypothesis) -> Void
    let onBack: () -> Void
    let onReviewEvidence: () -> Void

    private var optionLetters: [String] { ["A", "B", "C", "D", "E", "F"] }

    private var isLastDecision: Bool {
        decisionIndex >= decisionCount - 1
    }

    private var continueTitle: String {
        isLastDecision ? "Continue to the diagnosis" : "Continue to the next decision"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Decision \(decisionIndex + 1) of \(decisionCount)")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfNavy)
                    Spacer()
                    Text("\(solvedCount) solved")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                }
                PFProgressBar(progress: decisionCount > 0 ? Double(solvedCount) / Double(decisionCount) : 0)
            }
            Text(decision.prompt)
                .font(.pfCardTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            if isSolved {
                solvedCard
            } else {
                if difficulty == .rookie && pickedOption == nil {
                    hintCard
                }
                if decision.options.isEmpty {
                    Text("No options were provided for this decision.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                } else {
                    ForEach(Array(decision.options.enumerated()), id: \.offset) { index, option in
                        optionButton(option: option, index: index)
                    }
                }
                if let picked = pickedOption, picked >= 0, picked < decision.options.count {
                    feedbackCard(pickedIndex: picked)
                }
            }
            HStack(spacing: PFSpacing.md) {
                PFSecondaryButton(title: "Back", action: onBack)
                PFSecondaryButton(title: "Review evidence", action: onReviewEvidence)
            }
        }
    }

    /// The Rookie hint, shown before the pick. It guides method
    /// only: it names no answer and no evidence item.
    private var hintCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                Text("Hint")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfNavy)
                PFBodyText(text: InvestigationEngine.hintText(for: decision), textColor: .pfSecondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var solvedCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Label("You solved this decision.", systemImage: "checkmark.circle.fill")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                PFBodyText(text: decision.whyCorrect, textColor: .pfSecondaryText)
                PFPrimaryButton(title: continueTitle, action: onContinue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func optionButton(option: InvestigationDecisionOption, index: Int) -> some View {
        let isPicked = pickedOption == index
        let isBest = index == decision.bestOptionIndex
        let wasTried = triedWrong.contains(index)
        let feedbackShown = pickedOption != nil
        let border: Color = {
            if feedbackShown && isBest { return .pfSuccess }
            if feedbackShown && isPicked { return .pfError }
            if isPicked { return .pfRoyal }
            return .pfBorder
        }()
        let letter = index < optionLetters.count ? optionLetters[index] : "\(index + 1)"
        var stateText = ""
        if feedbackShown && isBest { stateText = ", best next step" }
        else if feedbackShown && isPicked { stateText = ", not the best next step" }
        else if wasTried { stateText = ", already tried" }
        return Button {
            onPick(index)
        } label: {
            HStack(alignment: .top, spacing: PFSpacing.sm) {
                ZStack {
                    Circle()
                        .stroke(border, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if isPicked {
                        Circle()
                            .fill(border)
                            .frame(width: 12, height: 12)
                    }
                }
                .padding(.top, 2)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text("\(letter). \(option.text)")
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    if feedbackShown && isBest {
                        Label("Best next step", systemImage: "checkmark.circle.fill")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSuccess)
                    } else if feedbackShown && isPicked {
                        Label("Not the best next step", systemImage: "xmark.circle.fill")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfError)
                    } else if wasTried {
                        Text("Already tried")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                    }
                }
                Spacer()
            }
            .padding(PFSpacing.md)
            .background(isPicked ? Color.pfRoyal.opacity(0.06) : Color.pfCard)
            .cornerRadius(PFSpacing.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                    .stroke(border, lineWidth: (feedbackShown && (isBest || isPicked)) ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(feedbackShown || wasTried)
        .opacity(wasTried && !isPicked ? 0.6 : 1.0)
        .accessibilityLabel("Option \(letter): \(option.text)\(stateText)")
    }

    private func feedbackCard(pickedIndex: Int) -> some View {
        let option = decision.options[pickedIndex]
        return PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                HStack(spacing: PFSpacing.sm) {
                    Image(systemName: pickedWasBest ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.pfCardTitle.weight(.semibold))
                        .foregroundColor(pickedWasBest ? .pfSuccess : .pfError)
                        .accessibilityHidden(true)
                    Text(pickedWasBest ? "Best next step." : "Not the best next step.")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PFBodyText(text: option.feedback)
                if pickedWasBest {
                    PFBodyText(text: decision.whyCorrect, textColor: .pfSecondaryText)
                    if let evidenceNote = decision.evidenceNote {
                        PFBodyText(text: evidenceNote, textColor: .pfSecondaryText)
                    }
                    if let hypothesisPrompt = decision.hypothesisPrompt {
                        hypothesisRevisionSection(prompt: hypothesisPrompt)
                    }
                    PFPrimaryButton(title: continueTitle, action: onContinue)
                } else {
                    PFBodyText(text: "Consequence: \(option.consequence)", textColor: .pfSecondaryText)
                    Text("This wrong turn costs \(decision.wrongTurnCost) points.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if difficulty == .professional {
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text("Hint")
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfNavy)
                            PFBodyText(text: InvestigationEngine.hintText(for: decision), textColor: .pfSecondaryText)
                        }
                    }
                    PFPrimaryButton(title: "Try again", action: onRetry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func hypothesisRevisionSection(prompt: String) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text(prompt)
                .font(.pfBody)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(hypotheses, id: \.id) { hypothesis in
                hypothesisChip(hypothesis)
            }
            Text("You can keep your current leading hypothesis and continue. Any change is recorded for the final report.")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func hypothesisChip(_ hypothesis: InvestigationHypothesis) -> some View {
        let isLeading = leadingHypothesisID == hypothesis.id
        return Button {
            onReviseHypothesis(hypothesis)
        } label: {
            HStack(spacing: PFSpacing.sm) {
                Text(hypothesis.text)
                    .font(.pfBody)
                    .foregroundColor(.pfNavy)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if isLeading {
                    PFPill(
                        text: "Leading",
                        background: Color.pfRoyal.opacity(0.10),
                        foreground: .pfRoyal
                    )
                }
            }
            .padding(PFSpacing.md)
            .background(isLeading ? Color.pfRoyal.opacity(0.06) : Color.pfCard)
            .cornerRadius(PFSpacing.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                    .stroke(isLeading ? Color.pfRoyal : Color.pfBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set leading hypothesis: \(hypothesis.text)")
    }
}

// MARK: - Diagnosis

struct InvestigationDiagnosisView: View {
    let investigation: InvestigationCase
    let openedEvidence: [InvestigationEvidence]
    @Binding var diagnosisHypothesisID: String?
    @Binding var citedEvidenceIDs: Set<String>
    let onConfirm: () -> Void
    let onBack: () -> Void
    let onGoToEvidence: () -> Void

    /// True after a blocked submit with no citation chosen. The
    /// citation gate error stays visible until the learner cites
    /// an evidence item.
    @State private var showCitationGateError = false

    private var guidanceText: String? {
        if diagnosisHypothesisID == nil && citedEvidenceIDs.isEmpty {
            return "Pick a root cause and cite at least one evidence item you opened."
        } else if diagnosisHypothesisID == nil {
            return "Pick a root cause from the list."
        } else if citedEvidenceIDs.isEmpty {
            return "Cite at least one evidence item you opened to support the diagnosis."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("Confirm the diagnosis")
                    .font(.pfSectionTitle)
                    .foregroundColor(.pfNavy)
                Text("Pick the root cause and cite the evidence that supports it. A diagnosis without cited evidence is not accepted.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if investigation.difficulty == .rookie {
                    Text("Cite the items you opened whose content matches the cause you picked. A strong citation is one that proves the cause, not one that only mentions it.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                PFSectionHeader(title: "Root cause")
                if investigation.hypotheses.isEmpty {
                    Text("No hypotheses were provided for this case.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                } else {
                    ForEach(investigation.hypotheses, id: \.id) { hypothesis in
                        diagnosisRow(hypothesis)
                    }
                }
            }
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                PFSectionHeader(title: "Supporting evidence")
                if openedEvidence.isEmpty {
                    Text("You have not opened any evidence yet. Open evidence first, then return here to cite it.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    PFSecondaryButton(title: "Go to the evidence workspace", action: onGoToEvidence)
                } else {
                    ForEach(openedEvidence, id: \.id) { item in
                        citationRow(item)
                    }
                }
            }
            if let guidanceText {
                Text(guidanceText)
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showCitationGateError && citedEvidenceIDs.isEmpty {
                Text("Choose one piece of evidence you opened to support this diagnosis, then submit again.")
                    .font(.pfBody)
                    .fontWeight(.semibold)
                    .foregroundColor(.pfError)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("investigationCitationGate")
            }
            HStack(spacing: PFSpacing.md) {
                PFSecondaryButton(title: "Back", action: onBack)
                PFGoldButton(title: "Confirm diagnosis", action: confirmTapped)
            }
        }
        .onChange(of: citedEvidenceIDs) { _, cited in
            if !cited.isEmpty {
                showCitationGateError = false
            }
        }
    }

    /// A blocked submit is never silent: with no citation chosen,
    /// the citation gate error shows and stays visible until a
    /// citation is chosen. With a citation, the confirm action
    /// runs and the parent still requires a root-cause pick.
    private func confirmTapped() {
        if citedEvidenceIDs.isEmpty {
            showCitationGateError = true
        } else {
            onConfirm()
        }
    }

    private func diagnosisRow(_ hypothesis: InvestigationHypothesis) -> some View {
        let isPicked = diagnosisHypothesisID == hypothesis.id
        return Button {
            diagnosisHypothesisID = hypothesis.id
        } label: {
            HStack(alignment: .top, spacing: PFSpacing.sm) {
                ZStack {
                    Circle()
                        .stroke(isPicked ? Color.pfRoyal : Color.pfBorder, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if isPicked {
                        Circle()
                            .fill(Color.pfRoyal)
                            .frame(width: 12, height: 12)
                    }
                }
                .padding(.top, 2)
                Text(hypothesis.text)
                    .font(.pfBody)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(PFSpacing.md)
            .background(isPicked ? Color.pfRoyal.opacity(0.06) : Color.pfCard)
            .cornerRadius(PFSpacing.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                    .stroke(isPicked ? Color.pfRoyal : Color.pfBorder, lineWidth: isPicked ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Diagnosis: \(hypothesis.text)")
        .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : [.isButton])
    }

    private func citationRow(_ item: InvestigationEvidence) -> some View {
        let isCited = citedEvidenceIDs.contains(item.id)
        return Button {
            if isCited {
                citedEvidenceIDs.remove(item.id)
            } else {
                citedEvidenceIDs.insert(item.id)
            }
        } label: {
            HStack(spacing: PFSpacing.sm) {
                Image(systemName: isCited ? "checkmark.square.fill" : "square")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(isCited ? .pfRoyal : .pfSecondaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(item.title)
                        .font(.pfBody)
                        .fontWeight(.semibold)
                        .foregroundColor(.pfNavy)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(InvestigationEvidencePresentation.singularLabel(for: item.kind))
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                }
                Spacer()
            }
            .padding(PFSpacing.md)
            .background(isCited ? Color.pfRoyal.opacity(0.06) : Color.pfCard)
            .cornerRadius(PFSpacing.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                    .stroke(isCited ? Color.pfRoyal : Color.pfBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cite evidence: \(item.title)")
        .accessibilityAddTraits(isCited ? [.isButton, .isSelected] : [.isButton])
    }
}

// MARK: - Report

struct InvestigationReportView: View {
    let investigation: InvestigationCase
    let report: InvestigationReport
    let incorrectAssumptions: [String]
    let citedEvidence: [InvestigationEvidence]
    let onDone: () -> Void

    private var completedLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: report.completedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("Investigation report")
                    .font(.pfSectionTitle)
                    .foregroundColor(.pfNavy)
                Text("Difficulty: \(investigation.difficulty.displayName). Completed \(completedLabel).")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfSecondaryText)
            }
            summarySection
            rootCauseSection
            supportingEvidenceSection
            incorrectAssumptionsSection
            correctiveActionSection
            impactSection
            preventiveControlsSection
            lessonsSection
            reflectionSection
            scoreSection
            PFPrimaryButton(title: "Done", action: onDone)
            Text("Your investigation results stay on this device.")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
        }
    }

    /// The closing question from the case, rendered as a reflection
    /// prompt. Shown only when the case carries one.
    private var reflectionSection: some View {
        Group {
            if let reflectionPrompt = investigation.reflectionPrompt, !reflectionPrompt.isEmpty {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("Reflection")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text(reflectionPrompt)
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Incident summary")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    HStack(spacing: PFSpacing.sm) {
                        PFPill(
                            text: "Case \(investigation.situationID)",
                            background: Color.pfNavy.opacity(0.08),
                            foreground: .pfNavy
                        )
                        PFPill(text: investigation.incidentType)
                        severityPill
                    }
                    Text(investigation.title)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    PFBodyText(text: investigation.incidentReport)
                    Text("Business context")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfNavy)
                    PFBodyText(text: investigation.businessContext, textColor: .pfSecondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var severityPill: some View {
        let colors = investigationSeverityColors(for: investigation.severity)
        return PFPill(
            text: "Severity: \(investigation.severity)",
            background: colors.background,
            foreground: colors.foreground
        )
    }

    private var rootCauseSection: some View {
        reportTextSection(title: "Correct root cause", text: investigation.correctDiagnosis)
    }

    private var correctiveActionSection: some View {
        reportTextSection(title: "Corrective action", text: investigation.correctiveAction)
    }

    private var impactSection: some View {
        reportTextSection(title: "Customer and operational impact", text: investigation.customerImpact)
    }

    private var incorrectAssumptionsSection: some View {
        reportListSection(
            title: "Incorrect assumptions made",
            items: incorrectAssumptions,
            emptyText: "No incorrect assumptions were recorded."
        )
    }

    private var preventiveControlsSection: some View {
        reportListSection(
            title: "Preventive controls",
            items: investigation.preventiveControls,
            emptyText: "No preventive controls were recorded for this case."
        )
    }

    private var lessonsSection: some View {
        reportListSection(
            title: "Technical and architectural lessons",
            items: investigation.lessons,
            emptyText: "No lessons were recorded for this case."
        )
    }

    private func reportTextSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: title)
            PFCard {
                PFBodyText(text: text)
            }
        }
    }

    private func reportListSection(title: String, items: [String], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: title)
            PFCard {
                if items.isEmpty {
                    Text(emptyText)
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: PFSpacing.sm) {
                                Text("•")
                                    .font(.pfBody)
                                    .foregroundColor(.pfRoyal)
                                Text(item)
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var supportingEvidenceSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Evidence supporting the diagnosis")
            PFCard {
                if citedEvidence.isEmpty {
                    Text("No evidence was cited.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        ForEach(citedEvidence, id: \.id) { item in
                            citedEvidenceRow(item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func citedEvidenceRow(_ item: InvestigationEvidence) -> some View {
        let supports = investigation.supportingEvidenceIDs.contains(item.id)
        return VStack(alignment: .leading, spacing: PFSpacing.xs) {
            Text(item.title)
                .font(.pfBody)
                .fontWeight(.semibold)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: PFSpacing.sm) {
                PFPill(text: InvestigationEvidencePresentation.singularLabel(for: item.kind))
                if supports {
                    PFPill(
                        text: "Supports the diagnosis",
                        background: Color.pfSuccess.opacity(0.12),
                        foreground: .pfSuccess
                    )
                } else {
                    PFPill(
                        text: "Does not support the diagnosis",
                        background: Color.pfNavy.opacity(0.08),
                        foreground: .pfNavy
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Overall investigation score")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Overall")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Spacer()
                        Text("\(report.dimensionScores.overall) out of 100")
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                    }
                    PFProgressBar(progress: Double(report.dimensionScores.overall) / 100.0)
                    Divider()
                    dimensionRow(label: "Evidence interpretation", value: report.dimensionScores.evidenceInterpretation)
                    dimensionRow(label: "Efficiency", value: report.dimensionScores.efficiency)
                    dimensionRow(label: "Technical accuracy", value: report.dimensionScores.technicalAccuracy)
                    dimensionRow(label: "Root cause identification", value: report.dimensionScores.rootCauseIdentification)
                    dimensionRow(label: "Resolution quality", value: report.dimensionScores.resolutionQuality)
                    Divider()
                    Text("Decisions correct: \(report.decisionsCorrect) of \(report.decisionsTotal). Evidence opened: \(report.evidenceOpenedCount). Wrong picks: \(report.wrongPicks).")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func dimensionRow(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.pfBody)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text("\(value)")
                    .font(.pfBody)
                    .fontWeight(.semibold)
                    .foregroundColor(.pfNavy)
            }
            PFProgressBar(progress: Double(value) / 100.0)
        }
    }
}

// MARK: - Evidence renderers

/// Timeline evidence: the step position, one narrative sentence
/// derived from the case text, and the step fields (sequence,
/// amount, parties) as a field table. The narrative sentence never
/// repeats the step title, and the fields never render as numbered
/// step bullets.
struct InvestigationTimelineView: View {
    let evidence: InvestigationEvidence
    let positionText: String?

    /// The body renders only when it adds to the title. The engine
    /// guarantees this; the guard keeps a title repeat out even if
    /// an authored item ever carries one.
    private var showsBody: Bool {
        !evidence.body.isEmpty && evidence.body != evidence.title
    }

    var body: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                if let positionText {
                    Text(positionText)
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                }
                if showsBody {
                    PFBodyText(text: evidence.body)
                }
                if !evidence.structuredLines.isEmpty {
                    InvestigationKeyValueTable(lines: evidence.structuredLines)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Message evidence: the message text, a field table from the
/// structured lines, and a link into the message explorer when the
/// title names a message code.
struct InvestigationMessageEvidenceView: View {
    let evidence: InvestigationEvidence

    var body: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                if !evidence.body.isEmpty {
                    PFBodyText(text: evidence.body)
                }
                if !evidence.structuredLines.isEmpty {
                    InvestigationKeyValueTable(lines: evidence.structuredLines)
                }
                if let code = investigationMessageCode(from: evidence.title) {
                    NavigationLink(destination: ISO20022ExplorerView(initialMessageID: code)) {
                        HStack {
                            Text("Open \(code) in the message explorer")
                                .font(.pfBody.weight(.semibold))
                                .foregroundColor(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.pfBody.weight(.semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, PFSpacing.lg)
                        .background(Color.pfRoyal)
                        .cornerRadius(PFSpacing.cornerRadius)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(code) in the message explorer")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Log evidence: monospace lines on a soft navy block.
struct InvestigationLogEvidenceView: View {
    let evidence: InvestigationEvidence

    private var logLines: [String] {
        if !evidence.structuredLines.isEmpty { return evidence.structuredLines }
        return evidence.body.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    private var showsBodySeparately: Bool {
        !evidence.structuredLines.isEmpty
            && !evidence.body.isEmpty
            && evidence.body != evidence.structuredLines.joined(separator: "\n")
    }

    var body: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                if showsBodySeparately {
                    PFBodyText(text: evidence.body)
                }
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PFSpacing.md)
                .background(Color.pfNavySoft)
                .cornerRadius(PFSpacing.cornerRadius)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Ledger evidence: the ledger text plus debit and credit postings
/// from the structured lines, each labelled with its side.
struct InvestigationLedgerEvidenceView: View {
    let evidence: InvestigationEvidence

    var body: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                if !evidence.body.isEmpty {
                    PFBodyText(text: evidence.body)
                }
                if !evidence.structuredLines.isEmpty {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        ForEach(Array(evidence.structuredLines.enumerated()), id: \.offset) { _, line in
                            ledgerRow(line)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func ledgerRow(_ line: String) -> some View {
        HStack(alignment: .top, spacing: PFSpacing.sm) {
            Text(line)
                .font(.pfBody)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let side = investigationLedgerSide(for: line) {
                PFPill(
                    text: side,
                    background: Color.pfRoyal.opacity(0.10),
                    foreground: .pfRoyal
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Reconciliation evidence: the break text plus a break table from
/// the structured lines.
struct InvestigationReconEvidenceView: View {
    let evidence: InvestigationEvidence

    var body: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                if !evidence.body.isEmpty {
                    PFBodyText(text: evidence.body)
                }
                if !evidence.structuredLines.isEmpty {
                    InvestigationKeyValueTable(lines: evidence.structuredLines)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// API evidence: request and response blocks on soft navy.
struct InvestigationApiEvidenceView: View {
    let evidence: InvestigationEvidence

    private var sections: (request: [String], response: [String]) {
        investigationApiSections(from: evidence.structuredLines)
    }

    private var showsBodySeparately: Bool {
        !evidence.structuredLines.isEmpty
            && !evidence.body.isEmpty
            && evidence.body != evidence.structuredLines.joined(separator: "\n")
    }

    var body: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                if showsBodySeparately {
                    PFBodyText(text: evidence.body)
                }
                if evidence.structuredLines.isEmpty {
                    apiBlock(
                        title: "Request and response",
                        lines: evidence.body.components(separatedBy: "\n").filter { !$0.isEmpty }
                    )
                } else {
                    if !sections.request.isEmpty {
                        apiBlock(title: "Request", lines: sections.request)
                    }
                    if !sections.response.isEmpty {
                        apiBlock(title: "Response", lines: sections.response)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func apiBlock(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text(title)
                .font(.pfCaptionBold)
                .foregroundColor(.pfNavy)
            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PFSpacing.md)
            .background(Color.pfNavySoft)
            .cornerRadius(PFSpacing.cornerRadius)
        }
    }
}

/// Clearing evidence: the status text plus a status record table
/// from the structured lines.
struct InvestigationClearingEvidenceView: View {
    let evidence: InvestigationEvidence

    var body: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                if !evidence.body.isEmpty {
                    PFBodyText(text: evidence.body)
                }
                if !evidence.structuredLines.isEmpty {
                    InvestigationKeyValueTable(lines: evidence.structuredLines)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Note evidence: a prose card, with any structured lines as bullets.
struct InvestigationNoteEvidenceView: View {
    let evidence: InvestigationEvidence

    var body: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                if !evidence.body.isEmpty {
                    PFBodyText(text: evidence.body)
                }
                if !evidence.structuredLines.isEmpty {
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        ForEach(Array(evidence.structuredLines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: PFSpacing.sm) {
                                Text("•")
                                    .font(.pfBody)
                                    .foregroundColor(.pfRoyal)
                                Text(line)
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Shared evidence table

/// A field table from structured lines: each "Field: value" line
/// renders as a labelled row, and lines without a field name render
/// as plain lines. Shared by the message, reconciliation and
/// clearing renderers.
private struct InvestigationKeyValueTable: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            ForEach(Array(investigationFieldPairs(from: lines).enumerated()), id: \.offset) { _, pair in
                if pair.key.isEmpty {
                    Text(pair.value)
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text(pair.key)
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                        Text(pair.value)
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
