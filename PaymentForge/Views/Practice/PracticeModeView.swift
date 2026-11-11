// PracticeModeView.swift
// PaymentForge iOS - Practice Mode for one Payment Situation.
// The learner reads the business problem and the scenario, decides
// what to do next, and ONLY then sees the recommended solution and
// the rest of the case. The solution, the explanation of the
// alternatives, the flow, the happy and negative paths and the
// technical and data considerations are all hidden behind the
// decision: before it, the solution area shows a locked state.
// Nothing is invented. Every option is a real takeaway (the
// situation's own, plus three other real situations'), every section
// is built from the situation's own explain text and visual, and
// anything the case does not state is labelled "Not stated in this
// case" instead of being filled in.
// Design follows the second reference board's Case Resolution screen:
// navy headings, royal blue primary actions, gold accents sparingly,
// white cards, radio-style option rows, expandable sections.
// No em dashes in any user-facing text.

import SwiftUI

// MARK: - Explain parsing (this case only)
//
// The full explain text is paragraphs separated by blank lines. Only
// the structure the text itself carries is used: the opening, the
// "Here is what happened:" arrow list, the flawed requirement, the
// "Why?" root cause, and the "BA Takeaway" resolution. The BA
// Takeaway section is deliberately kept out of the business problem
// and scenario sections, so the solution cannot leak before the
// learner decides.

private struct PracticeExplain {
    var opening: [String] = []
    var flowSteps: [String] = []
    var flawedRequirement: [String] = []
    var rootCause: [String] = []
    var baBody: [String] = []
    var controls: [String] = []
    var realRequirement: [String] = []
    var closingQuestion: String? = nil

    /// Paragraphs before the BA Takeaway heading: the case as the
    /// learner sees it before deciding, with no solution in it.
    var preTakeawayParagraphs: [String] = []
}

private func parsePracticeExplain(_ explain: String) -> PracticeExplain {
    let paragraphs = explain
        .components(separatedBy: "\n\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    var parsed = PracticeExplain()
    guard !paragraphs.isEmpty else { return parsed }

    func isFlowHeader(_ para: String) -> Bool {
        para.hasPrefix("Here") && para.hasSuffix(":") && para.contains("happen")
    }
    func isFlawedHeader(_ para: String) -> Bool {
        para.hasPrefix("The requirement said:")
            || para.hasPrefix("The assumption was:")
            || para.hasPrefix("The assumption said:")
            || para.hasPrefix("The requirement says")
            || para.hasPrefix("The requirement is written")
            || para.hasPrefix("The instruction was:")
    }
    func arrowLines(_ para: String) -> [String] {
        para.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("→") }
            .map { String($0.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
    }

    let flowIndex = paragraphs.firstIndex(where: isFlowHeader)
    let flawedIndex = paragraphs.firstIndex(where: isFlawedHeader)
    let whyIndex = paragraphs.firstIndex { $0 == "Why?" }
    let baIndex = paragraphs.firstIndex { $0 == "BA Takeaway" }
    let realIndex = paragraphs.firstIndex { $0.hasPrefix("The real requirement") }

    var bodyEnd = paragraphs.count
    if let last = paragraphs.last,
       last.hasPrefix("Have you") || last.hasPrefix("Did you know") {
        parsed.closingQuestion = last
        bodyEnd -= 1
    }

    if let baIndex {
        parsed.preTakeawayParagraphs = Array(paragraphs[..<baIndex])
    } else {
        parsed.preTakeawayParagraphs = Array(paragraphs[..<bodyEnd])
    }

    let openingEnd = flowIndex ?? flawedIndex ?? baIndex ?? bodyEnd
    parsed.opening = Array(paragraphs[..<openingEnd])

    if let flowIndex, flowIndex + 1 < paragraphs.count {
        parsed.flowSteps = arrowLines(paragraphs[flowIndex + 1])
    }

    if let flawedIndex {
        let end = whyIndex ?? baIndex ?? bodyEnd
        if flawedIndex < end {
            parsed.flawedRequirement = Array(paragraphs[flawedIndex..<end])
        }
    }

    if let baIndex, baIndex > 0 {
        let causeStart: Int?
        if let whyIndex {
            causeStart = whyIndex + 1
        } else if let flawedIndex {
            causeStart = flawedIndex + 1
        } else {
            causeStart = nil
        }
        if let causeStart {
            // The paragraph just before "BA Takeaway" is the insight
            // sentence when it is a plain sentence; an arrow list or
            // flow header there belongs to the root cause instead.
            let beforeBA = paragraphs[baIndex - 1]
            let hasInsight = !beforeBA.contains("→") && !isFlowHeader(beforeBA)
            let causeEnd = hasInsight ? baIndex - 1 : baIndex
            if causeStart < causeEnd {
                parsed.rootCause = Array(paragraphs[causeStart..<causeEnd])
            }
        }
        let solutionEnd = realIndex ?? bodyEnd
        if baIndex + 1 < solutionEnd {
            for para in paragraphs[(baIndex + 1)..<solutionEnd] {
                let lines = arrowLines(para)
                if !lines.isEmpty {
                    parsed.controls.append(contentsOf: lines)
                } else if para.hasSuffix("separate:") || para.contains("keep them separate:") {
                    continue
                } else {
                    parsed.baBody.append(para)
                }
            }
        }
    }

    if let realIndex, realIndex < bodyEnd {
        parsed.realRequirement = Array(paragraphs[realIndex..<bodyEnd])
    }

    return parsed
}

/// Sentences of a text that mention one of the given keywords
/// (case-insensitive). The sentences are returned verbatim, in the
/// order they appear; nothing is paraphrased or added.
private func sentencesMentioning(_ text: String, keywords: [String]) -> [String] {
    let lowerKeywords = keywords.map { $0.lowercased() }
    var found: [String] = []
    let paragraphs = text
        .components(separatedBy: "\n\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    for paragraph in paragraphs {
        let parts = paragraph.components(separatedBy: ". ")
        for part in parts {
            let sentence = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard sentence.count >= 10 else { continue }
            let lower = sentence.lowercased()
            guard lowerKeywords.contains(where: { lower.contains($0) }) else { continue }
            let display = sentence.hasSuffix(".") ? sentence : sentence + "."
            if !found.contains(display) {
                found.append(display)
            }
        }
    }
    return found
}

// MARK: - Practice Mode screen

struct PracticeModeView: View {
    let situation: Situation
    let allSituations: [Situation]

    @ObservedObject private var practiceStore = PracticeStore.shared

    @State private var selectedOption: Int? = nil
    @State private var decisionMade = false
    @State private var quizSelection: Int? = nil
    @State private var quizAnswered = false
    @State private var assessmentRecorded = false

    /// The decision for this situation, or nil when the situation
    /// has no takeaway and is therefore not eligible.
    private var decision: PracticeDecision? {
        PracticeModeBuilder.decision(for: situation, in: allSituations)
    }

    /// The recall question reuses the same option pool in a
    /// different deterministic order.
    private var recallDecision: PracticeDecision? {
        PracticeModeBuilder.decision(for: situation, in: allSituations, seedSalt: 1000)
    }

    private var parsed: PracticeExplain {
        parsePracticeExplain(situation.explain)
    }

    private var previousAttempts: [PracticeAttempt] {
        practiceStore.attempts(for: situation.id)
    }

    /// Sentences of the explain that name a message, system or code.
    private var technicalSentences: [String] {
        sentencesMentioning(situation.explain, keywords: [
            "pacs.", "pain.", "camt.", "MT103", "MT202", "MT101", "MT900", "MT910",
            "MT940", "MT942", "ISO 20022", "SWIFT", "UETR", "FPS", "SEPA",
            "API", "reason code", "response code", "status code", "return code",
            "timeout", "cut-off", "cutoff", "clearing", "correspondent"
        ])
    }

    /// Sentences of the explain that name a data field or identifier,
    /// excluding sentences already shown under technical.
    private var dataSentences: [String] {
        sentencesMentioning(situation.explain, keywords: [
            "UTR", "RRN", "reference number", "account number", "IBAN",
            "sort code", "value date", "currency", "field "
        ]).filter { !technicalSentences.contains($0) }
    }

    /// The visual flow steps, or the "what happened" steps from the
    /// explain text when there is no visual. Nil when neither exists.
    private var flowSteps: [SituationFlowStep]? {
        if let visual = situation.visual, visual.type == "flow", let flow = visual.flow {
            return flow.steps
        }
        guard !parsed.flowSteps.isEmpty else { return nil }
        return parsed.flowSteps.map { SituationFlowStep(kind: "step", title: $0, note: nil) }
    }

    private var decisionIsCorrect: Bool {
        guard let decision, let selectedOption else { return false }
        return selectedOption == decision.correctOptionIndex
    }

    private var quizIsCorrect: Bool {
        guard let recallDecision, let quizSelection else { return false }
        return quizSelection == recallDecision.correctOptionIndex
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.xl) {
                headerSection

                if let decision {
                    businessProblemSection
                    scenarioSection
                    decisionSection(decision: decision)
                    availableActionsSection(decision: decision)

                    if !decisionMade {
                        lockedSolutionSection
                    } else {
                        solutionSection(decision: decision)
                        alternativesSection(decision: decision)
                        flowSection
                        happyPathSection
                        negativePathsSection
                        technicalSection
                        dataSection
                        knowledgeAssessmentSection
                    }
                } else {
                    notEligibleSection
                }
            }
            .padding(PFSpacing.lg)
        }
        // Copy protection: the case text cannot be selected, a faint
        // identity watermark sits over the content, and recording
        // blurs it out.
        .pfProtectedContent()
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .navigationTitle("Practice Mode")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await practiceStore.syncPendingAttempts()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            HStack(spacing: PFSpacing.sm) {
                PFPill(text: situation.stageName)
                PFPill(
                    text: situation.level.displayName,
                    background: Color.pfGoldSoft,
                    foreground: Color(red: 0.55, green: 0.44, blue: 0.08)
                )
                if let schemeName = scheme(for: situation) {
                    PFPill(text: schemeName)
                }
            }
            .accessibilityElement(children: .combine)
            Text(situation.title)
                .font(.pfScreenTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Text("Read the case, decide what you would do next, then check yourself against the recommended solution.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if !previousAttempts.isEmpty {
                let correct = previousAttempts.filter { $0.isCorrect }.count
                PFPill(
                    text: "Your attempts on this case: \(previousAttempts.count), \(correct) correct",
                    background: Color.pfRoyal.opacity(0.10),
                    foreground: .pfRoyal
                )
            }
        }
    }

    // MARK: - Section helpers

    private func sectionTitle(_ title: String, step: String) -> some View {
        HStack(spacing: PFSpacing.sm) {
            Text(step)
                .font(.pfCaptionBold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.pfRoyal)
                .clipShape(Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.pfSectionTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step). \(title)")
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.pfBody)
            .foregroundColor(.pfNavy)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func notStatedText(_ what: String) -> some View {
        Text("Not stated in this case: \(what).")
            .font(.pfBody)
            .foregroundColor(.pfSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One radio-style option row. The result colouring only appears
    /// after the learner confirms a decision.
    private func optionRow(
        letter: String,
        text: String,
        index: Int,
        isSelected: Bool,
        showResult: Bool,
        isCorrectOption: Bool
    ) -> some View {
        let border: Color = {
            if showResult && isCorrectOption { return .pfSuccess }
            if showResult && isSelected { return .pfError }
            if isSelected { return .pfRoyal }
            return .pfBorder
        }()
        return HStack(alignment: .top, spacing: PFSpacing.sm) {
            ZStack {
                Circle()
                    .stroke(border, lineWidth: 2)
                    .frame(width: 24, height: 24)
                if isSelected {
                    Circle()
                        .fill(border)
                        .frame(width: 12, height: 12)
                }
                if showResult && isCorrectOption {
                    Image(systemName: "checkmark")
                        .font(.pfCaption.weight(.bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.top, 2)
            Text("\(letter). \(text)")
                .font(.pfBody)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(PFSpacing.md)
        .background(isSelected ? Color.pfRoyal.opacity(0.06) : Color.pfCard)
        .cornerRadius(PFSpacing.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                .stroke(border, lineWidth: isSelected || (showResult && isCorrectOption) ? 2 : 1)
        )
        .accessibilityLabel("Option \(letter): \(text)" + (isSelected ? ", selected" : ""))
    }

    private var optionLetters: [String] { ["A", "B", "C", "D"] }

    // MARK: - (1) Business problem

    private var businessProblemSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            sectionTitle("Business problem", step: "1")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    if parsed.opening.isEmpty {
                        bodyText(situation.title)
                    } else {
                        ForEach(Array(parsed.opening.enumerated()), id: \.offset) { _, paragraph in
                            bodyText(paragraph)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - (2) Scenario context

    private var scenarioSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            sectionTitle("Scenario context", step: "2")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    if !parsed.flowSteps.isEmpty {
                        ForEach(Array(parsed.flowSteps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: PFSpacing.md) {
                                Text("\(index + 1)")
                                    .font(.pfCaptionBold)
                                    .foregroundColor(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Color.pfRoyal)
                                    .clipShape(Circle())
                                bodyText(step)
                            }
                        }
                    } else {
                        ForEach(Array(parsed.preTakeawayParagraphs.enumerated()), id: \.offset) { _, paragraph in
                            bodyText(paragraph)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - (3) Learner decision

    private func decisionSection(decision: PracticeDecision) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            sectionTitle("Your decision", step: "3")
            Text(decision.prompt)
                .font(.pfCardTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(decision.options.enumerated()), id: \.offset) { index, option in
                Button {
                    guard !decisionMade else { return }
                    selectedOption = index
                } label: {
                    optionRow(
                        letter: optionLetters[index],
                        text: option,
                        index: index,
                        isSelected: selectedOption == index,
                        showResult: decisionMade,
                        isCorrectOption: index == decision.correctOptionIndex
                    )
                }
                .buttonStyle(.plain)
                .disabled(decisionMade)
            }
            if !decisionMade {
                PFPrimaryButton(title: "Confirm my decision") {
                    guard let selectedOption else { return }
                    decisionMade = true
                    practiceStore.recordAttempt(
                        situationID: situation.id,
                        chosenOptionIndex: selectedOption,
                        isCorrect: selectedOption == decision.correctOptionIndex
                    )
                }
                .disabled(selectedOption == nil)
                .opacity(selectedOption == nil ? 0.5 : 1)
                .accessibilityLabel("Confirm my decision")
            } else {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        HStack(spacing: PFSpacing.sm) {
                            Image(systemName: decisionIsCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.pfCardTitle.weight(.semibold))
                                .foregroundColor(decisionIsCorrect ? .pfSuccess : .pfError)
                            Text(decisionIsCorrect
                                ? "Correct. That matches the recommended solution for this case."
                                : "Not the recommended solution for this case. See below.")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - (4) Available actions

    private func availableActionsSection(decision: PracticeDecision) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            sectionTitle("Available actions", step: "4")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    ForEach(Array(decision.options.enumerated()), id: \.offset) { index, option in
                        HStack(alignment: .top, spacing: PFSpacing.md) {
                            Text(optionLetters[index])
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfRoyal)
                                .frame(width: 24, height: 24)
                                .background(Color.pfRoyal.opacity(0.10))
                                .clipShape(Circle())
                            bodyText(option)
                        }
                    }
                    Text("These are the four actions to choose from. Pick one above to reveal the solution.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - (5) Recommended solution

    private var lockedSolutionSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            sectionTitle("Recommended solution", step: "5")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    HStack(spacing: PFSpacing.sm) {
                        Image(systemName: "lock.fill")
                            .font(.pfCardTitle.weight(.semibold))
                            .foregroundColor(.pfGold)
                        Text("Make a decision to reveal the solution")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("The recommended solution stays hidden until you decide what you would do next. Choose an option above, then confirm your decision.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func solutionSection(decision: PracticeDecision) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            sectionTitle("Recommended solution", step: "5")
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("One thing to remember")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfNavy)
                Text(decision.explanation)
                    .font(.pfBody)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(PFSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.pfGoldSoft)
            .cornerRadius(PFSpacing.cardRadius)
            if !parsed.baBody.isEmpty || !parsed.controls.isEmpty {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        ForEach(Array(parsed.baBody.enumerated()), id: \.offset) { _, paragraph in
                            bodyText(paragraph)
                        }
                        ForEach(Array(parsed.controls.enumerated()), id: \.offset) { _, control in
                            HStack(alignment: .top, spacing: PFSpacing.md) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.pfCardTitle.weight(.regular))
                                    .foregroundColor(.pfGold)
                                    .padding(.top, 2)
                                bodyText(control)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !parsed.realRequirement.isEmpty {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("The real requirement")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfNavy)
                        ForEach(Array(parsed.realRequirement.enumerated()), id: \.offset) { _, paragraph in
                            bodyText(paragraph)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let closing = parsed.closingQuestion {
                Text(closing)
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - (6) Explanation of alternatives

    private func alternativesSection(decision: PracticeDecision) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            sectionTitle("Explanation of alternatives", step: "6")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    ForEach(Array(decision.options.enumerated()), id: \.offset) { index, option in
                        let isCorrect = index == decision.correctOptionIndex
                        let wasChosen = selectedOption == index
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            HStack(spacing: PFSpacing.sm) {
                                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.pfBody.weight(.semibold))
                                    .foregroundColor(isCorrect ? .pfSuccess : .pfError)
                                Text(optionLetters[index] + (wasChosen ? " (your choice)" : ""))
                                    .font(.pfCaptionBold)
                                    .foregroundColor(.pfNavy)
                            }
                            Text(option)
                                .font(.pfBody)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(isCorrect
                                ? "This is the situation's own takeaway, so it is the recommended solution for this case."
                                : "This is the takeaway of another real situation. It is not the resolution stated for this case.")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if index < decision.options.count - 1 {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - (7) End-to-end process flow

    private var flowSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            sectionTitle("End-to-end process flow", step: "7")
            DisclosureGroup("Show the flow") {
                if let steps = flowSteps {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            let isDecision = (step.kind ?? "").lowercased() == "decision"
                            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                                HStack(alignment: .top, spacing: PFSpacing.md) {
                                    ZStack {
                                        if isDecision {
                                            Rectangle()
                                                .fill(Color.pfGold)
                                                .frame(width: 26, height: 26)
                                                .rotationEffect(.degrees(45))
                                        } else {
                                            Circle()
                                                .fill(Color.pfRoyal)
                                                .frame(width: 28, height: 28)
                                        }
                                        Text("\(index + 1)")
                                            .font(.pfCaptionBold)
                                            .foregroundColor(.white)
                                    }
                                    .frame(width: 28, height: 28)
                                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                        if isDecision {
                                            Text("DECISION")
                                                .font(.pfCaptionBold)
                                                .foregroundColor(Color(red: 0.55, green: 0.44, blue: 0.08))
                                        }
                                        Text(step.title)
                                            .font(.pfCardTitle)
                                            .foregroundColor(.pfNavy)
                                            .fixedSize(horizontal: false, vertical: true)
                                        if let note = step.note, !note.isEmpty {
                                            Text(note)
                                                .font(.pfCallout)
                                                .foregroundColor(.pfSecondaryText)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                if index < steps.count - 1 {
                                    HStack(spacing: PFSpacing.md) {
                                        Image(systemName: "arrow.down")
                                            .font(.pfBody.weight(.semibold))
                                            .foregroundColor(.pfSecondaryText)
                                            .frame(width: 28)
                                        Spacer()
                                    }
                                    .padding(.vertical, PFSpacing.xs)
                                }
                            }
                        }
                    }
                    .padding(.top, PFSpacing.md)
                } else {
                    notStatedText("no flow is given for this case")
                        .padding(.top, PFSpacing.md)
                }
                if let visual = situation.visual, visual.type == "diagram", let diagram = visual.diagram {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text(diagram.centre)
                            .font(.pfCardTitle)
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(PFSpacing.lg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.pfNavy)
                            .cornerRadius(PFSpacing.cardRadius)
                        ForEach(Array(diagram.parts.enumerated()), id: \.offset) { _, part in
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                Text(part.label)
                                    .font(.pfCardTitle)
                                    .foregroundColor(.pfNavy)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let note = part.note, !note.isEmpty {
                                    Text(note)
                                        .font(.pfCallout)
                                        .foregroundColor(.pfSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, PFSpacing.md)
                }
            }
            .font(.pfCardTitle)
            .foregroundColor(.pfNavy)
            .padding(PFSpacing.lg)
            .background(Color.pfCard)
            .cornerRadius(PFSpacing.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                    .stroke(Color.pfBorder, lineWidth: 1)
            )
            .accessibilityLabel("End-to-end process flow, expandable")
        }
    }

    // MARK: - (8) Happy path

    private var happyPathSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            sectionTitle("Happy path", step: "8")
            DisclosureGroup("Show the happy path") {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    if parsed.baBody.isEmpty && parsed.controls.isEmpty {
                        notStatedText("the happy path is not described")
                    } else {
                        Text("The recommended path, as stated in this case:")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(parsed.baBody.enumerated()), id: \.offset) { _, paragraph in
                            bodyText(paragraph)
                        }
                        ForEach(Array(parsed.controls.enumerated()), id: \.offset) { _, control in
                            HStack(alignment: .top, spacing: PFSpacing.md) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.pfCardTitle.weight(.regular))
                                    .foregroundColor(.pfGold)
                                    .padding(.top, 2)
                                bodyText(control)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, PFSpacing.md)
            }
            .font(.pfCardTitle)
            .foregroundColor(.pfNavy)
            .padding(PFSpacing.lg)
            .background(Color.pfCard)
            .cornerRadius(PFSpacing.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                    .stroke(Color.pfBorder, lineWidth: 1)
            )
            .accessibilityLabel("Happy path, expandable")
        }
    }

    // MARK: - (9) Negative paths

    private var negativePathsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            sectionTitle("Negative paths", step: "9")
            DisclosureGroup("Show the negative paths") {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    if parsed.flawedRequirement.isEmpty && parsed.rootCause.isEmpty {
                        notStatedText("the negative paths are not described")
                    } else {
                        if !parsed.flawedRequirement.isEmpty {
                            Text("What went wrong, as stated in this case:")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(Array(parsed.flawedRequirement.enumerated()), id: \.offset) { _, paragraph in
                                bodyText(paragraph)
                            }
                        }
                        if !parsed.rootCause.isEmpty {
                            Text("Root cause, as stated in this case:")
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfNavy)
                            ForEach(Array(parsed.rootCause.enumerated()), id: \.offset) { _, paragraph in
                                bodyText(paragraph)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, PFSpacing.md)
            }
            .font(.pfCardTitle)
            .foregroundColor(.pfNavy)
            .padding(PFSpacing.lg)
            .background(Color.pfCard)
            .cornerRadius(PFSpacing.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                    .stroke(Color.pfBorder, lineWidth: 1)
            )
            .accessibilityLabel("Negative paths, expandable")
        }
    }

    // MARK: - (10) Technical considerations

    private var technicalSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            sectionTitle("Technical considerations", step: "10")
            DisclosureGroup("Show technical considerations") {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    if technicalSentences.isEmpty {
                        notStatedText("no message names, systems or codes are named")
                    } else {
                        ForEach(Array(technicalSentences.prefix(5).enumerated()), id: \.offset) { _, sentence in
                            bodyText(sentence)
                        }
                        if technicalSentences.count > 5 {
                            Text("Showing the first 5 mentions from this case.")
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, PFSpacing.md)
            }
            .font(.pfCardTitle)
            .foregroundColor(.pfNavy)
            .padding(PFSpacing.lg)
            .background(Color.pfCard)
            .cornerRadius(PFSpacing.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                    .stroke(Color.pfBorder, lineWidth: 1)
            )
            .accessibilityLabel("Technical considerations, expandable")
        }
    }

    // MARK: - (11) Data considerations

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            sectionTitle("Data considerations", step: "11")
            DisclosureGroup("Show data considerations") {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    if dataSentences.isEmpty {
                        notStatedText("no reference numbers, identifiers or data fields are named")
                    } else {
                        ForEach(Array(dataSentences.prefix(5).enumerated()), id: \.offset) { _, sentence in
                            bodyText(sentence)
                        }
                        if dataSentences.count > 5 {
                            Text("Showing the first 5 mentions from this case.")
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, PFSpacing.md)
            }
            .font(.pfCardTitle)
            .foregroundColor(.pfNavy)
            .padding(PFSpacing.lg)
            .background(Color.pfCard)
            .cornerRadius(PFSpacing.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                    .stroke(Color.pfBorder, lineWidth: 1)
            )
            .accessibilityLabel("Data considerations, expandable")
        }
    }

    // MARK: - (12) Knowledge assessment

    private var knowledgeAssessmentSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            sectionTitle("Knowledge assessment", step: "12")
            Text("Two questions on this case: your decision above, and one recall check below. Your score is recorded in your competency profile.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let recall = recallDecision {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        Text("Which of these is the one thing to remember from this case?")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(recall.options.enumerated()), id: \.offset) { index, option in
                            Button {
                                guard !quizAnswered else { return }
                                quizSelection = index
                            } label: {
                                optionRow(
                                    letter: optionLetters[index],
                                    text: option,
                                    index: index,
                                    isSelected: quizSelection == index,
                                    showResult: quizAnswered,
                                    isCorrectOption: index == recall.correctOptionIndex
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(quizAnswered)
                        }
                        if !quizAnswered {
                            PFPrimaryButton(title: "Check my answer") {
                                guard quizSelection != nil else { return }
                                quizAnswered = true
                                recordAssessment()
                            }
                            .disabled(quizSelection == nil)
                            .opacity(quizSelection == nil ? 0.5 : 1)
                            .accessibilityLabel("Check my answer")
                        } else {
                            let correctTotal = (decisionIsCorrect ? 1 : 0) + (quizIsCorrect ? 1 : 0)
                            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                                HStack(spacing: PFSpacing.sm) {
                                    Image(systemName: quizIsCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.pfCardTitle.weight(.semibold))
                                        .foregroundColor(quizIsCorrect ? .pfSuccess : .pfError)
                                    Text(quizIsCorrect
                                        ? "Correct. That is the situation's own takeaway."
                                        : "Not this time. The one thing to remember is the takeaway shown in the solution above.")
                                        .font(.pfCardTitle)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Text("Knowledge assessment: \(correctTotal) of 2 correct. Recorded in your competency profile under Exception handling.")
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Record the 2-question check once: the decision plus the
    /// recall question, against the Exception handling dimension.
    private func recordAssessment() {
        guard !assessmentRecorded else { return }
        assessmentRecorded = true
        let correctTotal = (decisionIsCorrect ? 1 : 0) + (quizIsCorrect ? 1 : 0)
        CompetencyStore.shared.recordAssessment(
            dimension: .exceptionHandling,
            correct: correctTotal,
            total: 2
        )
        ProgressStore.shared.recordQuizScore(
            lessonID: "practice-\(situation.id)",
            correct: correctTotal,
            total: 2
        )
    }

    // MARK: - Not eligible

    private var notEligibleSection: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("Practice Mode is not available for this situation")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Text("This situation has no takeaway to practise against, so no decision can be built from it. Read the full situation instead.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
