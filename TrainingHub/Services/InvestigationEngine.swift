// InvestigationEngine.swift
// Builds InvestigationCase values for the Payments Mystery
// Investigation Experience: the derived tier from a Situation plus
// its full data-file item, and the authored tier from an
// ExceptionCase. Implements the derivation rules in
// INVESTIGATION-PLAN.md section 7 (rules 1 to 18) and the template
// tables verbatim. Every list has a template fallback, so the engine
// never returns a case with an empty briefing, empty evidence, empty
// hypotheses, or empty decisions.
//
// Parsing: the existing parseSituationExplain in SituationsView.swift
// is a private function and cannot be reused, so this file implements
// its own paragraph parsing following the plan rules exactly. The
// existing parser is untouched. The deterministic shuffle reuses
// PracticeModeBuilder (stableSeed plus deterministicShuffle), which
// are internal and accessible at module level. Message purposes reuse
// ISO20022Catalogue where the catalogue covers the code.
// Synthetic values are labeled SAMPLE, parties are
// generic, absent fields are stated once in plain words, and no
// real bank names, customer names, accounts,
// references, or dates are invented. No em dashes in any
// user-facing text.

import Foundation

// MARK: - Parsed explain (engine-local)

/// The explain text split into its parts, following plan rule 1
/// (blank-line paragraphs only; never split on single newlines).
/// Any part may be empty; the builders below apply the fallback
/// chains from the plan rules.
private struct InvestigationParsedExplain {
    var opening: [String] = []
    var flowSteps: [String] = []
    var flawedRequirement: [String] = []
    var rootCause: [String] = []
    var insight: String? = nil
    var baBody: [String] = []
    var controls: [String] = []
    var realRequirement: [String] = []
    var closingQuestion: String? = nil

    /// True when the explain carries the structured format at all
    /// (an opening plus a BA Takeaway body or controls list).
    var isParsed: Bool { !opening.isEmpty && (!baBody.isEmpty || !controls.isEmpty) }
}

/// One flow step from the preferred source (visual flow steps when
/// present, parsed arrow lines otherwise).
private struct InvestigationFlowStepSource {
    let title: String
    let note: String?
    let isDecision: Bool
}

/// The failure-category key used by the template tables. Derived
/// from the failure_category field (derived tier) or the incident
/// type (authored tier) by keyword matching.
private enum InvestigationCategoryKey {
    case rejectedOrReturned
    case duplicate
    case sanctions
    case reconciliation
    case other
}

// MARK: - Engine

enum InvestigationEngine {

    // MARK: - Public API

    /// Builds the derived tier case for one situation. `fullItem`
    /// carries the stage-map fields (messages, failure_category,
    /// resolution, domain) when the data file supplied them; when
    /// it is nil, every field falls back to the regex and template
    /// rules. The case is built per difficulty because Expert
    /// changes evidence completeness.
    static func caseFor(
        situation: Situation,
        fullItem: FullSituationItem?,
        difficulty: InvestigationDifficulty
    ) -> InvestigationCase {
        let parsed = parseExplain(situation.explain)
        let header = paymentHeader(title: situation.title, explain: situation.explain)
        let failureCategory = nonEmpty(fullItem?.failureCategory)
        let resolution = nonEmpty(fullItem?.resolution)
        let category = categoryKey(for: failureCategory)
        let messages = resolveMessages(fullItem: fullItem, title: situation.title, explain: situation.explain)

        let incidentReport = incidentReportText(parsed: parsed, situation: situation)
        let businessContext = businessContextText(parsed: parsed, situation: situation, fullItem: fullItem)
        let incidentType = incidentTypeText(failureCategory: failureCategory, level: situation.level)
        let customerImpact = incidentReport + "\n\n" + impactSentence(for: category)

        let realRequirementText = realRequirementText(parsed: parsed, takeaway: situation.takeaway)
        let rootCauseText = rootCauseText(parsed: parsed, takeaway: situation.takeaway, realRequirementText: realRequirementText)
        let flawedCore = flawedRequirementCore(parsed: parsed, rootCauseText: rootCauseText, category: category)
        let rootCauseFirst = PracticeModeBuilder.firstSentence(of: rootCauseText)

        let flowSteps = flowStepSources(situation: situation, parsed: parsed)
        let timelineSourceField = (situation.visual?.flow?.steps.isEmpty == false) ? "visual" : "explain"
        let evidence = buildDerivedEvidence(
            caseID: situation.id,
            flowSteps: flowSteps,
            timelineSourceField: timelineSourceField,
            messages: messages,
            header: header,
            explain: situation.explain,
            domain: fullItem?.domain,
            failureCategory: failureCategory,
            incidentReport: incidentReport,
            parsed: parsed,
            resolution: resolution,
            difficulty: difficulty
        )
        let timeline = evidence.filter { $0.kind == .timeline }
        let supportingEvidenceIDs = evidence
            .filter { $0.kind == .timeline || $0.kind == .message || $0.kind == .log }
            .map { $0.id }

        let diagnosis = diagnosisText(rootCauseText: rootCauseText, takeaway: situation.takeaway, insight: parsed.insight)
        let hypotheses = buildHypotheses(
            caseID: situation.id,
            assumptionCore: flawedCore,
            rootCauseFirstSentence: rootCauseFirst,
            category: category,
            diagnosisText: diagnosis
        )

        let decisionSteps = Array(flowSteps.filter { $0.isDecision }.prefix(4))
        let evidenceKinds = orderedKinds(of: evidence)
        let closingEvidenceNote = resolution.map { "The stated resolution path for this case is: \($0)." }
            ?? "The real requirement section of the case states the fix."
        let actionText = correctiveActionText(realRequirementText: realRequirementText, takeaway: situation.takeaway)
        let decisions = buildDerivedDecisions(
            caseID: situation.id,
            decisionSteps: decisionSteps,
            hasMessages: !messages.isEmpty,
            evidenceKinds: evidenceKinds,
            correctiveOptionText: actionText,
            closingWhyCorrect: nonEmpty(situation.takeaway) ?? "The real requirement in the case text states the fix.",
            closingEvidenceNote: closingEvidenceNote
        )

        return InvestigationCase(
            id: situation.id,
            situationID: situation.id,
            title: situation.title,
            severity: severityLabel(level: situation.level, failureCategory: failureCategory),
            incidentType: incidentType,
            businessContext: businessContext,
            customerImpact: customerImpact,
            incidentReport: incidentReport,
            objectives: objectives,
            paymentHeader: header,
            timeline: timeline,
            evidence: evidence,
            hypotheses: hypotheses,
            decisions: decisions,
            correctDiagnosis: diagnosis,
            supportingEvidenceIDs: supportingEvidenceIDs,
            correctiveAction: actionText,
            preventiveControls: preventiveControls(parsed: parsed),
            lessons: lessons(takeaway: situation.takeaway, insight: parsed.insight),
            source: .derived,
            difficulty: difficulty,
            reflectionPrompt: parsed.closingQuestion
        )
    }

    /// Adapts an authored lab case to the experience. The narrative
    /// becomes the incident report, evidence maps 1:1 (kind note,
    /// except message-named items map to kind message), steps map to
    /// decision points, resolution maps to corrective action plus
    /// diagnosis, and the source takeaway maps to lessons. Authored
    /// red herrings are preserved.
    static func caseForLabCase(
        _ labCase: ExceptionCase,
        difficulty: InvestigationDifficulty
    ) -> InvestigationCase {
        let category = categoryKey(for: labCase.incidentType)
        let header = paymentHeader(title: labCase.title, explain: labCase.narrative)
        let resolutionText = nonEmpty(labCase.resolution)
            ?? nonEmpty(labCase.sourceTakeaway)
            ?? "The case does not state a resolution."
        let customerImpact = labCase.narrative + "\n\n" + impactSentence(for: category)

        var evidence = labCase.evidence.map { authoredEvidence(from: $0) }
        if evidence.isEmpty {
            evidence.append(InvestigationEvidence(
                id: "\(labCase.id)-note-1",
                kind: .note,
                title: "Case narrative",
                body: labCase.narrative,
                structuredLines: [],
                sourceField: "authored",
                revealedAfterStep: 0,
                completeness: .complete,
                isRedHerring: false
            ))
        }
        evidence = applyingExpertCompleteness(to: evidence, difficulty: difficulty)
        let timeline = evidence.filter { $0.kind == .timeline }
        let genuineIDs = evidence.filter { !$0.isRedHerring }.map { $0.id }
        let supportingEvidenceIDs = genuineIDs.isEmpty ? evidence.map { $0.id } : genuineIDs

        let assumptionCore = authoredAssumptionCore(labCase: labCase, category: category)
        let rootCauseFirst = PracticeModeBuilder.firstSentence(of: resolutionText)
        let diagnosis = authoredDiagnosisText(resolutionText: resolutionText)
        let hypotheses = buildHypotheses(
            caseID: labCase.id,
            assumptionCore: assumptionCore,
            rootCauseFirstSentence: rootCauseFirst.isEmpty ? "the evidence does not state a root cause." : rootCauseFirst,
            category: category,
            diagnosisText: diagnosis
        )

        var decisions = labCase.steps.enumerated().map { offset, step in
            authoredDecision(step: step, isLast: offset == labCase.steps.count - 1)
        }
        if decisions.count < 2 {
            decisions.append(closingDecision(
                caseID: labCase.id,
                index: decisions.count + 1,
                correctOptionText: rootCauseFirst.isEmpty ? resolutionText : rootCauseFirst,
                whyCorrect: nonEmpty(labCase.sourceTakeaway) ?? "The resolution states the fix.",
                evidenceNote: "The resolution for this case states the fix."
            ))
        }

        let takeaway = nonEmpty(labCase.sourceTakeaway)
        var lessonsList: [String] = []
        if let takeaway { lessonsList.append(takeaway) }
        if !rootCauseFirst.isEmpty, rootCauseFirst != takeaway { lessonsList.append(rootCauseFirst) }
        if lessonsList.isEmpty { lessonsList.append("Check the evidence before confirming the payment outcome.") }

        return InvestigationCase(
            id: labCase.id,
            situationID: labCase.sourceSituationID ?? labCase.id,
            title: labCase.title,
            severity: severityLabel(level: labCase.level, failureCategory: labCase.incidentType),
            incidentType: labCase.incidentType,
            businessContext: authoredBusinessContext(labCase: labCase),
            customerImpact: customerImpact,
            incidentReport: labCase.narrative,
            objectives: objectives,
            paymentHeader: header,
            timeline: timeline,
            evidence: evidence,
            hypotheses: hypotheses,
            decisions: decisions,
            correctDiagnosis: diagnosis,
            supportingEvidenceIDs: supportingEvidenceIDs,
            correctiveAction: authoredCorrectiveActionText(resolutionText: resolutionText),
            preventiveControls: takeaway.map { [$0] } ?? ["Check the status evidence before confirming the payment outcome."],
            lessons: lessonsList,
            source: .authored,
            difficulty: difficulty,
            reflectionPrompt: nil
        )
    }

    /// The derived severity label. Advanced plus a failure category
    /// present is High; core plus a failure category present is
    /// Medium; otherwise Moderate. The briefing states that severity
    /// is derived from the case level and failure category.
    static func severityLabel(level: SituationLevel, failureCategory: String?) -> String {
        let hasCategory = nonEmpty(failureCategory) != nil
        switch (level, hasCategory) {
        case (.advanced, true): return "High"
        case (.core, true): return "Medium"
        default: return "Moderate"
        }
    }

    /// The derived payment header. The regex looks for a currency
    /// code plus a number, and for Rs or the rupee sign plus a
    /// number, in the title first and then the explain. No match
    /// means the amount is not stated in the case. Parties are
    /// always generic. The reference is not stated unless the
    /// explain names one with a label. A scale word after the
    /// number (million, billion, thousand, crore, lakh) is kept.
    static func paymentHeader(title: String, explain: String) -> InvestigationPaymentHeader {
        let match = amountMatch(in: title) ?? amountMatch(in: explain)
        return InvestigationPaymentHeader(
            amountText: match?.amountText ?? notStatedAmountText,
            currencyText: match?.currencyText ?? "Not stated in the case",
            partiesText: "The customer sends the payment to the beneficiary through the sending bank and the beneficiary bank.",
            referenceText: referenceText(in: explain)
        )
    }

    /// The Rookie and Professional hint for one decision point.
    /// Every hint guides METHOD only: it names no answer, no
    /// evidence item, and no section of the case text. The learner
    /// must still decide what to inspect and what it proves.
    static func hintText(for decision: InvestigationDecisionPoint) -> String {
        if decision.isResolution {
            return "Work backwards from the outcome. Ask what would have to be true for the payment to complete, then pick the action that makes it true."
        }
        if decision.prompt.lowercased().contains("check first") {
            return "Establish the order of events before interpreting any single record."
        }
        if decision.isTechnical {
            return "Compare what was sent with what was expected, and treat a missing record as a finding to explain, not a gap to skip."
        }
        return "Ask what the next step would prove, and pick the action that settles the most open questions."
    }

    // MARK: - Parsing (engine-local, plan rules 1 to 9)

    /// Splits the explain into paragraphs on blank lines only and
    /// assigns each paragraph to a section by its markers. Mirrors
    /// the marker semantics of the existing parser without editing
    /// or calling it: flow headers start with "Here" and end with a
    /// colon and contain "happen"; flawed headers are the
    /// requirement and assumption variants; "Why?", "BA Takeaway",
    /// and "The real requirement" head their sections; the closing
    /// question is the last paragraph when it addresses the reader.
    private static func parseExplain(_ explain: String) -> InvestigationParsedExplain {
        let paragraphs = explain
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var parsed = InvestigationParsedExplain()
        guard !paragraphs.isEmpty else { return parsed }

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

        // Opening: paragraphs before the first "Here is" marker; when
        // there is no flow header, up to the flawed requirement when
        // one exists, otherwise the first 2 paragraphs (rule 2).
        let openingEnd: Int
        if let flowIndex {
            openingEnd = flowIndex
        } else if let flawedIndex {
            openingEnd = flawedIndex
        } else {
            openingEnd = min(2, bodyEnd)
        }
        parsed.opening = slice(paragraphs, from: 0, to: min(openingEnd, bodyEnd))

        // Flow steps: the arrow list right after the flow header.
        if let flowIndex, flowIndex + 1 < paragraphs.count {
            parsed.flowSteps = arrowLines(paragraphs[flowIndex + 1])
        }

        // Flawed requirement: the flawed paragraph plus what followed
        // from it, up to "Why?" (or the single flawed paragraph when
        // there is no "Why?" and a BA section follows).
        if let flawedIndex {
            if let whyIndex, flawedIndex < whyIndex {
                parsed.flawedRequirement = slice(paragraphs, from: flawedIndex, to: whyIndex)
            } else if let baIndex, baIndex > flawedIndex + 1 {
                parsed.flawedRequirement = [paragraphs[flawedIndex]]
            } else {
                parsed.flawedRequirement = slice(paragraphs, from: flawedIndex, to: bodyEnd)
            }
        }

        // Root cause and insight: the paragraphs after "Why?" (or
        // after the flawed requirement when there is no "Why?"), up
        // to the insight sentence just before "BA Takeaway".
        if let baIndex, baIndex > 0 {
            let candidate = paragraphs[baIndex - 1]
            if !candidate.contains("→") && !isFlowHeader(candidate) {
                parsed.insight = candidate
            }
            let causeStart: Int?
            if let whyIndex {
                causeStart = whyIndex + 1
            } else if let flawedIndex {
                causeStart = flawedIndex + 1
            } else {
                causeStart = nil
            }
            if let causeStart, causeStart < baIndex {
                let causeEnd = parsed.insight == nil ? baIndex : baIndex - 1
                if causeStart < causeEnd {
                    parsed.rootCause = slice(paragraphs, from: causeStart, to: causeEnd)
                }
            }
        }

        // Solution: everything after "BA Takeaway" up to the real
        // requirement. Arrow lists are the controls; a paragraph
        // ending in "separate:" is their heading; the rest is body.
        if let baIndex {
            let solutionEnd = realIndex ?? bodyEnd
            if baIndex + 1 < solutionEnd {
                for para in paragraphs[(baIndex + 1)..<min(solutionEnd, paragraphs.count)] {
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

        // The real requirement: from its marker to the end of the body.
        if let realIndex, realIndex < bodyEnd {
            parsed.realRequirement = slice(paragraphs, from: realIndex, to: bodyEnd)
        }

        return parsed
    }

    private static func isFlowHeader(_ para: String) -> Bool {
        para.hasPrefix("Here") && para.hasSuffix(":") && para.contains("happen")
    }

    private static func isFlawedHeader(_ para: String) -> Bool {
        para.hasPrefix("The requirement said:")
            || para.hasPrefix("The assumption was:")
            || para.hasPrefix("The assumption said:")
            || para.hasPrefix("The requirement says")
            || para.hasPrefix("The requirement is written")
            || para.hasPrefix("The instruction was:")
    }

    private static func arrowLines(_ para: String) -> [String] {
        para.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("→") }
            .map { String($0.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
    }

    /// A bounds-safe paragraph slice, empty when the range is invalid.
    private static func slice(_ paragraphs: [String], from start: Int, to end: Int) -> [String] {
        guard start >= 0, end > start, start < paragraphs.count else { return [] }
        return Array(paragraphs[start..<min(end, paragraphs.count)])
    }

    // MARK: - Briefing derivation (rules 2, 4 to 9, 12 to 14)

    private static func incidentReportText(parsed: InvestigationParsedExplain, situation: Situation) -> String {
        let opening = parsed.opening.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !opening.isEmpty { return opening }
        let explain = situation.explain.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explain.isEmpty { return explain }
        return situation.title
    }

    private static func businessContextText(
        parsed: InvestigationParsedExplain,
        situation: Situation,
        fullItem: FullSituationItem?
    ) -> String {
        let hook = parsed.opening.first ?? ""
        let domain = nonEmpty(fullItem?.domain) ?? ""
        if !domain.isEmpty, !hook.isEmpty { return "\(domain). \(hook)" }
        if !hook.isEmpty { return hook }
        if !domain.isEmpty { return domain }
        return situation.title.isEmpty ? "Payment investigation." : situation.title
    }

    private static func incidentTypeText(failureCategory: String?, level: SituationLevel) -> String {
        if let failureCategory, !failureCategory.isEmpty {
            return failureCategory.prefix(1).uppercased() + failureCategory.dropFirst()
        }
        return "\(level.displayName) payment incident"
    }

    private static func realRequirementText(parsed: InvestigationParsedExplain, takeaway: String) -> String {
        let joined = parsed.realRequirement.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !joined.isEmpty { return joined }
        return takeaway.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rootCauseText(
        parsed: InvestigationParsedExplain,
        takeaway: String,
        realRequirementText: String
    ) -> String {
        let joined = parsed.rootCause.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !joined.isEmpty { return joined }
        let combined = [takeaway, realRequirementText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        if !combined.isEmpty { return combined }
        return "The case does not state a root cause in the text provided."
    }

    /// The flawed requirement core: the quoted text after the
    /// requirement or assumption marker, else the first sentence of
    /// the flawed section, else the first sentence of the Why?
    /// section, else the category template assumption (rule 4).
    private static func flawedRequirementCore(
        parsed: InvestigationParsedExplain,
        rootCauseText: String,
        category: InvestigationCategoryKey
    ) -> String {
        let substance = parsed.flawedRequirement.filter { !isHeaderOnlyFlawedParagraph($0) }
        var joined = substance.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        joined = strippingFlawedHeaderPrefix(joined)
        if let groups = firstMatchGroups(pattern: "\"([^\"]+)\"", in: joined),
           let quoted = groups.first {
            let trimmed = quoted.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        let cleaned = strippingQuotes(joined)
        if !cleaned.isEmpty {
            let first = PracticeModeBuilder.firstSentence(of: cleaned)
            if !first.isEmpty { return first }
        }
        let causeFirst = PracticeModeBuilder.firstSentence(of: rootCauseText)
        if !causeFirst.isEmpty { return causeFirst }
        return templateAssumption(for: category)
    }

    private static func isHeaderOnlyFlawedParagraph(_ para: String) -> Bool {
        let exactHeaders = [
            "The requirement said:",
            "The assumption was:",
            "The assumption said:",
            "The instruction was:",
        ]
        if exactHeaders.contains(para) { return true }
        if para.hasPrefix("The requirement says") || para.hasPrefix("The requirement is written") {
            return para.count < 60
        }
        return false
    }

    private static func strippingFlawedHeaderPrefix(_ text: String) -> String {
        let prefixes = [
            "The requirement said:",
            "The assumption was:",
            "The assumption said:",
            "The requirement says",
            "The requirement is written",
            "The instruction was:",
        ]
        for prefix in prefixes where text.hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private static func strippingQuotes(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count >= 2 {
            result = String(result.dropFirst().dropLast())
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The diagnosis as it reads in the report: a cause plus its
    /// mechanism, never a bare fact. The first sentence of the root
    /// cause text becomes the cause ("The root cause is that ..."),
    /// and the remaining sentences carry the mechanism. When the
    /// root cause is a single sentence, the takeaway or the insight
    /// sentence supplies the mechanism, because both are case text.
    /// The honest-absence fallback is returned unchanged.
    private static func diagnosisText(
        rootCauseText: String,
        takeaway: String,
        insight: String?
    ) -> String {
        let trimmed = rootCauseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "The case does not state a root cause in the text provided."
        }
        if trimmed == "The case does not state a root cause in the text provided." {
            return trimmed
        }
        let sentences = splitSentences(trimmed)
        guard let first = sentences.first else { return trimmed }
        let cause = lowercasedFirst(first)
        var mechanism = Array(sentences.dropFirst())
        if mechanism.isEmpty {
            let extra = nonEmpty(insight) ?? nonEmpty(takeaway)
            if let extra {
                let extraFirst = splitSentences(extra).first ?? extra
                if extraFirst.lowercased() != first.lowercased() {
                    mechanism.append(extraFirst)
                }
            }
        }
        let framed = "The root cause is that \(cause)"
        if mechanism.isEmpty { return framed }
        return ([framed] + mechanism).joined(separator: " ")
    }

    /// The authored-tier diagnosis: the resolution framed as the
    /// investigation conclusion, so it reads as a finding rather
    /// than a bare statement. The resolution text itself is
    /// authored and is never rewritten.
    private static func authoredDiagnosisText(resolutionText: String) -> String {
        let trimmed = resolutionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "The case does not state a root cause in the text provided."
        }
        if trimmed.hasPrefix("The investigation concludes:") { return trimmed }
        return "The investigation concludes: \(trimmed)"
    }

    /// The corrective action as it reads in the report and in the
    /// closing decision: a verb-led ACTION, never a quoted
    /// question. Candidates in order: the "It is" sentence of the
    /// real requirement (the "is not" sentence states what the
    /// requirement is not, so it must never be the action), the
    /// first non-negation sentence of the real requirement, the
    /// takeaway, then the template fix. A quoted question is
    /// converted to a "Confirm ..." action; quotes are stripped.
    private static func correctiveActionText(realRequirementText: String, takeaway: String) -> String {
        if let sentence = itIsSentence(in: realRequirementText) {
            let action = actionSentence(from: sentence)
            if !action.isEmpty { return action }
        }
        for sentence in splitSentences(realRequirementText) {
            let lower = sentence.lowercased()
            if lower.contains("is not") || lower.contains("isn't") { continue }
            let action = actionSentence(from: sentence)
            if !action.isEmpty { return action }
        }
        let takeawayFirst = PracticeModeBuilder.firstSentence(of: takeaway)
        if !takeawayFirst.isEmpty {
            let action = actionSentence(from: takeawayFirst)
            if !action.isEmpty { return action }
        }
        return "Confirm the payment state from evidence before telling the customer it is complete."
    }

    /// The authored-tier corrective action: the authored resolution
    /// unchanged, except that a resolution phrased as a question is
    /// converted to a verb-led action, so no corrective action ever
    /// reads as a quoted question.
    private static func authoredCorrectiveActionText(resolutionText: String) -> String {
        let trimmed = resolutionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Confirm the payment state from evidence before telling the customer it is complete."
        }
        if trimmed.hasSuffix("?") {
            return actionSentence(from: trimmed)
        }
        return trimmed
    }

    /// Converts one requirement sentence into a verb-led action
    /// sentence. Questions become "Confirm ..." actions, "to ..."
    /// infinitives become imperatives, and sentences that already
    /// start with an action verb are kept. Quotes are stripped and
    /// the result never ends with a question mark.
    private static func actionSentence(from sentence: String) -> String {
        var text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "\"", with: "")
        if let range = text.range(of: "It is ", options: [.caseInsensitive]), range.lowerBound == text.startIndex {
            text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty else { return "" }
        if text.hasSuffix("?") {
            let question = String(text.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            let words = question.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let firstWord = words.first else { return "" }
            let lowerFirst = firstWord.lowercased()
            let questionWords: Set<String> = ["what", "when", "how", "which", "why", "who", "where"]
            let auxiliaryWords: Set<String> = ["is", "are", "was", "were", "did", "does", "do", "can", "could", "should", "has", "have"]
            if questionWords.contains(String(lowerFirst)) {
                return "Confirm \(lowercasedFirst(question))."
            }
            if auxiliaryWords.contains(String(lowerFirst)) {
                let rest = words.count > 1 ? String(words[1]) : ""
                if rest.isEmpty { return "" }
                return "Confirm whether \(lowercasedFirst(rest))."
            }
            return "Confirm \(lowercasedFirst(question))."
        }
        if text.hasPrefix("to ") || text.hasPrefix("To ") {
            text = String(text.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            return capitalizedFirst(ensuringPeriod(text))
        }
        let firstWord = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        if actionVerbs.contains(firstWord.lowercased()) {
            return capitalizedFirst(ensuringPeriod(text))
        }
        return "Follow the stated requirement: \(ensuringPeriod(text))"
    }

    /// Splits text into sentences on ". ", "? " and "! " boundaries
    /// and on newlines, keeping each terminator. Fragments with no
    /// terminator keep their text; the caller adds one when needed.
    private static func splitSentences(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\n", with: " ")
        var sentences: [String] = []
        var current = ""
        let chars = Array(normalized)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            current.append(char)
            if char == "." || char == "?" || char == "!" {
                let nextIsBoundary = index + 1 >= chars.count || chars[index + 1] == " "
                if nextIsBoundary {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { sentences.append(trimmed) }
                    current = ""
                }
            }
            index += 1
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }

    private static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    private static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private static func ensuringPeriod(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") { return trimmed }
        if trimmed.hasSuffix("?") { return String(trimmed.dropLast()) + "." }
        return trimmed + "."
    }

    /// Verbs that already make a sentence a verb-led action.
    private static let actionVerbs: Set<String> = [
        "confirm", "check", "keep", "use", "send", "record", "validate",
        "request", "establish", "follow", "apply", "review", "compare",
        "trace", "investigate", "ensure", "require", "update", "fix",
        "raise", "ask", "wait", "treat", "show", "tell", "give", "hold",
        "stop", "start", "build", "add", "remove", "separate", "match",
        "reconcile", "monitor", "escalate", "notify", "document",
    ]

    /// Controls: arrow lines in the BA Takeaway section, else the
    /// full BA Takeaway section as one control, else one template
    /// control (rule 7).
    private static func preventiveControls(parsed: InvestigationParsedExplain) -> [String] {
        if !parsed.controls.isEmpty { return parsed.controls }
        let body = parsed.baBody.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { return [body] }
        return ["Check the status evidence before confirming the payment outcome."]
    }

    private static func lessons(takeaway: String, insight: String?) -> [String] {
        var result: [String] = []
        let trimmedTakeaway = takeaway.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTakeaway.isEmpty { result.append(trimmedTakeaway) }
        if let insight {
            let trimmed = insight.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !result.contains(trimmed) { result.append(trimmed) }
        }
        if result.isEmpty {
            result.append("Check the evidence before confirming the payment outcome.")
        }
        return result
    }

    /// The "It is" sentence of the real requirement, when one
    /// exists. The "is not" sentence states what the requirement is
    /// not, so callers must use this sentence, never the first
    /// sentence of the requirement, as the fix.
    private static func itIsSentence(in text: String) -> String? {
        guard let range = text.range(of: "It is ") else { return nil }
        let rest = String(text[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let dotRange = rest.range(of: ". ") {
            let sentence = String(rest[..<dotRange.lowerBound]) + "."
            return sentence.count >= 10 ? sentence : nil
        }
        if let questionRange = rest.range(of: "? ") {
            let sentence = String(rest[..<questionRange.lowerBound]) + "?"
            return sentence.count >= 10 ? sentence : nil
        }
        return rest.count >= 10 ? rest : nil
    }

    // MARK: - Messages, header extraction, categories (rules 10, 11)

    /// Messages: stage-map messages when present, else message codes
    /// found by regex in the title and explain, deduplicated, in
    /// order of first mention, capped at 6 (rule 10).
    private static func resolveMessages(
        fullItem: FullSituationItem?,
        title: String,
        explain: String
    ) -> [String] {
        if let listed = fullItem?.messages?
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty }),
           !listed.isEmpty {
            var seen: [String] = []
            for code in listed {
                let normalized = normalizedMessageCode(code)
                if !seen.contains(normalized) { seen.append(normalized) }
            }
            return Array(seen.prefix(6))
        }
        return Array(messageCodes(in: title + "\n" + explain).prefix(6))
    }

    private static func messageCodes(in text: String) -> [String] {
        var seen: [String] = []
        for raw in allMatches(
            pattern: "\\b(pacs\\.\\d{3}|pain\\.\\d{3}|camt\\.\\d{3}|MT\\d{3})\\b",
            in: text,
            options: [.caseInsensitive]
        ) {
            let normalized = normalizedMessageCode(raw)
            if !seen.contains(normalized) { seen.append(normalized) }
        }
        return seen
    }

    private static func normalizedMessageCode(_ code: String) -> String {
        let lower = code.lowercased()
        if lower.hasPrefix("mt") { return "MT" + lower.dropFirst(2) }
        return lower
    }

    private static func categoryKey(for text: String?) -> InvestigationCategoryKey {
        guard let text else { return .other }
        let lower = text.lowercased()
        if lower.contains("duplicat") { return .duplicate }
        if lower.contains("sanction") { return .sanctions }
        if lower.contains("reconcil") { return .reconciliation }
        if lower.contains("reject") || lower.contains("return") { return .rejectedOrReturned }
        return .other
    }

    private static func amountMatch(in text: String) -> (amountText: String, currencyText: String)? {
        let codePattern = currencyCodes.joined(separator: "|")
        if let groups = firstMatchGroups(
            pattern: "\\b(\(codePattern))\\s*(\\d[\\d,]*(?:\\.\\d+)?)(?:\\s+([Mm]illions?|[Bb]illions?|[Tt]housands?|[Cc]rore|[Ll]akh))?",
            in: text,
            options: [.caseInsensitive]
        ), groups.count == 3 {
            let number = cleanAmountNumber(groups[1])
            if !number.isEmpty {
                let scale = groups[2].isEmpty ? "" : " \(groups[2])"
                return ("\(groups[0].uppercased()) \(number)\(scale)", groups[0].uppercased())
            }
        }
        if let groups = firstMatchGroups(
            pattern: "(Rs\\.?|₹)\\s*(\\d[\\d,]*(?:\\.\\d+)?)(?:\\s+([Mm]illions?|[Bb]illions?|[Tt]housands?|[Cc]rore|[Ll]akh))?",
            in: text,
            options: [.caseInsensitive]
        ), groups.count == 3 {
            let number = cleanAmountNumber(groups[1])
            if !number.isEmpty {
                let symbol = groups[0].contains("₹") ? "₹" : "Rs"
                let scale = groups[2].isEmpty ? "" : " \(groups[2])"
                return ("\(symbol) \(number)\(scale)", "INR")
            }
        }
        if let groups = firstMatchGroups(
            pattern: "\\b(\\d[\\d,]*(?:\\.\\d+)?)\\s*(\(codePattern))\\b",
            in: text,
            options: [.caseInsensitive]
        ), groups.count == 2 {
            let number = cleanAmountNumber(groups[0])
            if !number.isEmpty {
                return ("\(groups[1].uppercased()) \(number)", groups[1].uppercased())
            }
        }
        return nil
    }

    private static func cleanAmountNumber(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: ","))
        guard trimmed.contains(where: { $0.isNumber }) else { return "" }
        return trimmed
    }

    private static func referenceText(in explain: String) -> String {
        if let groups = firstMatchGroups(
            pattern: "(?i)reference\\s*:\\s*[\"']?([A-Za-z0-9][A-Za-z0-9\\-]{3,})",
            in: explain
        ), let value = groups.first, !value.isEmpty {
            let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'.,;"))
            if !cleaned.isEmpty { return cleaned }
        }
        return "Reference not stated in the case"
    }

    // MARK: - Evidence (rules 3, 17, 18)

    private static func flowStepSources(
        situation: Situation,
        parsed: InvestigationParsedExplain
    ) -> [InvestigationFlowStepSource] {
        if let steps = situation.visual?.flow?.steps, !steps.isEmpty {
            return steps.map {
                InvestigationFlowStepSource(
                    title: $0.title,
                    note: $0.note,
                    isDecision: $0.kind?.lowercased() == "decision"
                )
            }
        }
        return parsed.flowSteps.map {
            InvestigationFlowStepSource(title: $0, note: nil, isDecision: isDecisionLine($0))
        }
    }

    private static func isDecisionLine(_ line: String) -> Bool {
        line.contains("?") || line.lowercased().contains("decided")
    }

    private static func buildDerivedEvidence(
        caseID: String,
        flowSteps: [InvestigationFlowStepSource],
        timelineSourceField: String,
        messages: [String],
        header: InvestigationPaymentHeader,
        explain: String,
        domain: String?,
        failureCategory: String?,
        incidentReport: String,
        parsed: InvestigationParsedExplain,
        resolution: String?,
        difficulty: InvestigationDifficulty
    ) -> [InvestigationEvidence] {
        var evidence: [InvestigationEvidence] = []
        evidence.append(contentsOf: timelineEvidence(
            caseID: caseID,
            flowSteps: flowSteps,
            sourceField: timelineSourceField,
            incidentReport: incidentReport,
            header: header,
            parsed: parsed,
            resolution: resolution
        ))
        for (index, code) in messages.enumerated() {
            evidence.append(messageEvidence(code: code, index: index, caseID: caseID, header: header))
        }
        evidence.append(logEvidence(
            caseID: caseID,
            flowSteps: flowSteps,
            timelineSourceField: timelineSourceField,
            messages: messages,
            header: header
        ))
        if triggersLedger(explain: explain, domain: domain) {
            evidence.append(ledgerEvidence(caseID: caseID, header: header))
        }
        if triggersRecon(explain: explain, failureCategory: failureCategory) {
            evidence.append(reconEvidence(caseID: caseID, header: header))
        }
        if triggersAPI(explain: explain) {
            evidence.append(apiEvidence(caseID: caseID, header: header))
        }
        if let clearing = clearingEvidence(caseID: caseID, explain: explain, header: header) {
            evidence.append(clearing)
        }
        return applyingExpertCompleteness(to: evidence, difficulty: difficulty)
    }

    /// Timeline evidence: one item per flow step, in order. Each
    /// item carries a relative sequence marker (T+0, T+1, ...) from
    /// its step order, the amount and parties from the payment
    /// header, and ONE narrative sentence derived from the case
    /// text: the visual step note when present, else the case
    /// sentence that best matches the step. The body never repeats
    /// the step title. Where the case gives no further detail about
    /// a step, the item says so once, in plain words. Nothing is
    /// fabricated: no clock times, no invented amounts or parties.
    private static func timelineEvidence(
        caseID: String,
        flowSteps: [InvestigationFlowStepSource],
        sourceField: String,
        incidentReport: String,
        header: InvestigationPaymentHeader,
        parsed: InvestigationParsedExplain,
        resolution: String?
    ) -> [InvestigationEvidence] {
        guard !flowSteps.isEmpty else {
            let firstParagraph = incidentReport
                .components(separatedBy: "\n\n").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return [InvestigationEvidence(
                id: "\(caseID)-timeline-1",
                kind: .timeline,
                title: "What happened",
                body: firstParagraph.isEmpty ? "The case states what happened in its opening text." : firstParagraph,
                structuredLines: timelineFieldLines(sequence: 0, isDecision: false, header: header),
                sourceField: "explain",
                revealedAfterStep: 0,
                completeness: .complete,
                isRedHerring: false
            )]
        }
        let pool = timelineNarrativePool(parsed: parsed, resolution: resolution)
        var usedSentences: Set<String> = []
        var items: [InvestigationEvidence] = []
        for (offset, step) in flowSteps.enumerated() {
            let body = timelineNarrativeSentence(for: step, pool: pool, used: &usedSentences)
            items.append(InvestigationEvidence(
                id: "\(caseID)-timeline-\(offset + 1)",
                kind: .timeline,
                title: step.title,
                body: body,
                structuredLines: timelineFieldLines(sequence: offset, isDecision: step.isDecision, header: header),
                sourceField: sourceField,
                revealedAfterStep: 0,
                completeness: .complete,
                isRedHerring: false
            ))
        }
        return items
    }

    /// The one sequence label for a step offset, shared by the
    /// timeline field lines and the processing log, so the same
    /// event always carries the same label in both. The first
    /// step or event is always T+0. Both renderers must use this
    /// helper and the same flow-step order; neither may invent
    /// its own labels, or the two sequences drift apart again.
    private static func sequenceLabel(for offset: Int) -> String {
        "T+\(offset)"
    }

    /// The field lines for one timeline item: the relative sequence
    /// marker, the amount (or one plain absence statement), and the
    /// generic parties. A decision step is marked as one.
    private static func timelineFieldLines(
        sequence: Int,
        isDecision: Bool,
        header: InvestigationPaymentHeader
    ) -> [String] {
        var lines = ["Sequence: \(sequenceLabel(for: sequence))"]
        if hasStatedAmount(header: header) {
            lines.append("Amount: \(header.amountText)")
        } else {
            lines.append("Amount: not stated in the case")
        }
        lines.append("Parties: the customer and the beneficiary, through the sending bank and the beneficiary bank")
        if isDecision { lines.append("Decision step") }
        return lines
    }

    /// The sentence pool for timeline narratives, in order of
    /// investigable value: the root cause section, the insight
    /// sentence, the flawed requirement, the opening, the BA
    /// Takeaway body and controls, the real requirement, and the
    /// stage-map resolution. Every sentence comes from the case.
    private static func timelineNarrativePool(
        parsed: InvestigationParsedExplain,
        resolution: String?
    ) -> [String] {
        var pool: [String] = []
        for paragraph in parsed.rootCause { pool.append(contentsOf: splitSentences(paragraph)) }
        if let insight = parsed.insight { pool.append(contentsOf: splitSentences(insight)) }
        for paragraph in parsed.flawedRequirement { pool.append(contentsOf: splitSentences(paragraph)) }
        for paragraph in parsed.opening { pool.append(contentsOf: splitSentences(paragraph)) }
        for paragraph in parsed.baBody { pool.append(contentsOf: splitSentences(paragraph)) }
        for control in parsed.controls { pool.append(ensuringPeriod(control)) }
        for paragraph in parsed.realRequirement { pool.append(contentsOf: splitSentences(paragraph)) }
        if let resolution { pool.append(contentsOf: splitSentences(resolution)) }
        return pool
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 20 }
    }

    /// One narrative sentence for one step. The visual step note
    /// wins when present; otherwise the best-scoring unused pool
    /// sentence wins (message codes score double, distinctive words
    /// score single). A sentence already used for an earlier step
    /// is never reused, and the body never equals the step title.
    /// When nothing in the case describes the step further, the
    /// honest-absence sentence is used, once per item.
    private static func timelineNarrativeSentence(
        for step: InvestigationFlowStepSource,
        pool: [String],
        used: inout Set<String>
    ) -> String {
        if let note = nonEmpty(step.note) {
            let first = splitSentences(note).first ?? note
            if first.lowercased() != step.title.lowercased() {
                used.insert(first.lowercased())
                return ensuringPeriod(first)
            }
        }
        let codes = messageCodes(in: step.title)
        let keywords = distinctiveWords(in: step.title)
        var best: (sentence: String, score: Int)? = nil
        for sentence in pool {
            let key = sentence.lowercased()
            guard !used.contains(key), key != step.title.lowercased() else { continue }
            var score = 0
            let lower = sentence.lowercased()
            for code in codes where lower.contains(code.lowercased()) { score += 2 }
            for word in keywords where lower.contains(word) { score += 1 }
            if score > 0, best == nil || score > best!.score {
                best = (sentence, score)
            }
        }
        if let best {
            used.insert(best.sentence.lowercased())
            return ensuringPeriod(best.sentence)
        }
        return "The case records this step in the flow but gives no further detail about it."
    }

    /// Distinctive words from a step title: words of four or more
    /// letters, lowercased, without the generic words that appear
    /// in almost every step and would match the wrong sentences.
    private static func distinctiveWords(in title: String) -> [String] {
        let stopwords: Set<String> = [
            "that", "this", "with", "from", "were", "been", "have",
            "would", "could", "should", "after", "before", "through",
            "sent", "never", "status", "report", "request", "return",
            "arrived", "checked", "raised", "payment", "under",
        ]
        return title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !stopwords.contains($0) }
    }

    private static func hasStatedAmount(header: InvestigationPaymentHeader) -> Bool {
        header.amountText != notStatedAmountText
    }

    private static func messageEvidence(
        code: String,
        index: Int,
        caseID: String,
        header: InvestigationPaymentHeader
    ) -> InvestigationEvidence {
        let purpose = ISO20022Catalogue.messages.first { $0.id.lowercased() == code.lowercased() }?.purpose
            ?? "The case names this message. Check the case text for what it proves in this investigation."
        var lines = ["Message: \(code)"]
        if hasStatedAmount(header: header) {
            lines.append("Amount: \(header.amountText)")
        }
        lines.append("From: the sending bank")
        lines.append("To: the beneficiary bank")
        if header.referenceText != "Reference not stated in the case" {
            lines.append("Reference: \(header.referenceText)")
        }
        return InvestigationEvidence(
            id: "\(caseID)-message-\(index + 1)",
            kind: .message,
            title: code,
            body: purpose,
            structuredLines: lines,
            sourceField: "messages",
            revealedAfterStep: 0,
            completeness: .complete,
            isRedHerring: false
        )
    }

    /// One log item per case. When the case has flow steps, the
    /// log carries exactly one line per flow step, in the same
    /// order and with the same sequence labels as the timeline
    /// (see sequenceLabel): the first step is T+0 in both, and
    /// the same event carries the same label in both. The lines
    /// are the step titles from the case text, so the log can
    /// never drift from the timeline. When the case has no flow
    /// steps, template lines use the message codes and the
    /// derived amount with the same shared labels (T+0 and so
    /// on, never clock times).
    private static func logEvidence(
        caseID: String,
        flowSteps: [InvestigationFlowStepSource],
        timelineSourceField: String,
        messages: [String],
        header: InvestigationPaymentHeader
    ) -> InvestigationEvidence {
        if !flowSteps.isEmpty {
            let lines = flowSteps.enumerated().map { offset, step in
                "\(sequenceLabel(for: offset)) \(ensuringPeriod(step.title))"
            }
            return InvestigationEvidence(
                id: "\(caseID)-log-1",
                kind: .log,
                title: "Processing log",
                body: "Log lines drawn from the case flow steps. Sequence markers are illustrative only; no clock times are stated.",
                structuredLines: lines,
                sourceField: timelineSourceField,
                revealedAfterStep: 0,
                completeness: .complete,
                isRedHerring: false
            )
        }
        let firstCode = messages.first
        let secondCode = messages.count > 1 ? messages[1] : nil
        let lines = [
            "\(sequenceLabel(for: 0)) Instruction received from the customer. Amount: \(amountShortText(header: header)). SAMPLE.",
            "\(sequenceLabel(for: 1)) Sent: \(firstCode ?? "no message code is named in the case").",
            "\(sequenceLabel(for: 2)) Checked: \(secondCode ?? "no further message code is named in the case").",
            "\(sequenceLabel(for: 3)) Outcome: not stated in the case.",
        ]
        return InvestigationEvidence(
            id: "\(caseID)-log-1",
            kind: .log,
            title: "Processing log (SAMPLE)",
            body: "SAMPLE processing log. Sequence markers are illustrative only; no clock times are stated in the case.",
            structuredLines: lines,
            sourceField: "messages",
            revealedAfterStep: 0,
            completeness: .complete,
            isRedHerring: false
        )
    }

    private static func triggersLedger(explain: String, domain: String?) -> Bool {
        let lowerDomain = domain?.lowercased() ?? ""
        let domainTrigger = ["clearing", "settlement", "reconciliation", "ledger", "accounting"]
            .contains(where: { lowerDomain.contains($0) })
        let lowerExplain = explain.lowercased()
        return domainTrigger || lowerExplain.contains("ledger") || lowerExplain.contains("settlement")
    }

    private static func ledgerEvidence(caseID: String, header: InvestigationPaymentHeader) -> InvestigationEvidence {
        let stated = hasStatedAmount(header: header)
        let body = stated
            ? "SAMPLE ledger entries built only from the case amount. No account numbers are stated in the case."
            : "SAMPLE ledger entries. The case states no amount and no account numbers."
        let lines = stated
            ? [
                "Debit: the customer account, \(header.amountText)",
                "Credit: the settlement account, \(header.amountText)",
                "Values: SAMPLE",
            ]
            : [
                "Debit: the customer account",
                "Credit: the settlement account",
                "Values: SAMPLE",
            ]
        return InvestigationEvidence(
            id: "\(caseID)-ledger-1",
            kind: .ledger,
            title: "Ledger entries (SAMPLE)",
            body: body,
            structuredLines: lines,
            sourceField: "domain",
            revealedAfterStep: 0,
            completeness: .complete,
            isRedHerring: false
        )
    }

    private static func triggersRecon(explain: String, failureCategory: String?) -> Bool {
        let categoryTrigger = failureCategory?.lowercased().contains("reconcil") ?? false
        return categoryTrigger || explain.lowercased().contains("reconciliation")
    }

    private static func reconEvidence(caseID: String, header: InvestigationPaymentHeader) -> InvestigationEvidence {
        let amountLine = hasStatedAmount(header: header)
            ? "Bank record amount: \(header.amountText)"
            : "Bank record amount: not stated in the case"
        return InvestigationEvidence(
            id: "\(caseID)-recon-1",
            kind: .recon,
            title: "Reconciliation break (SAMPLE)",
            body: "SAMPLE reconciliation break. The case does not state the matching records.",
            structuredLines: [
                amountLine,
                "Values: SAMPLE",
            ],
            sourceField: "failure_category",
            revealedAfterStep: 0,
            completeness: .complete,
            isRedHerring: false
        )
    }

    private static func triggersAPI(explain: String) -> Bool {
        containsMatch(pattern: "\\bapi\\b", in: explain, options: [.caseInsensitive])
    }

    private static func apiEvidence(caseID: String, header: InvestigationPaymentHeader) -> InvestigationEvidence {
        var lines = ["Request: status check for the payment (SAMPLE)"]
        if hasStatedAmount(header: header) {
            lines.append("Amount: \(header.amountText)")
        }
        lines.append("Response: not stated in the case")
        return InvestigationEvidence(
            id: "\(caseID)-api-1",
            kind: .api,
            title: "API request and response (SAMPLE)",
            body: "SAMPLE request and response for the API named in the case.",
            structuredLines: lines,
            sourceField: "explain",
            revealedAfterStep: 0,
            completeness: .complete,
            isRedHerring: false
        )
    }

    private static func clearingEvidence(
        caseID: String,
        explain: String,
        header: InvestigationPaymentHeader
    ) -> InvestigationEvidence? {
        let matchedSystem = clearingSystems.first { containsWholeWord($0, in: explain) }
        guard explain.lowercased().contains("clearing") || matchedSystem != nil else { return nil }
        var lines: [String] = []
        if let matchedSystem {
            lines.append("Clearing system: \(matchedSystem)")
        }
        lines.append("Status: not stated in the case")
        if hasStatedAmount(header: header) {
            lines.append("Amount: \(header.amountText)")
        }
        lines.append("Values: SAMPLE")
        return InvestigationEvidence(
            id: "\(caseID)-clearing-1",
            kind: .clearing,
            title: "Clearing status (SAMPLE)",
            body: "SAMPLE clearing status record.",
            structuredLines: lines,
            sourceField: "explain",
            revealedAfterStep: 0,
            completeness: .complete,
            isRedHerring: false
        )
    }

    /// Expert difficulty: the last message evidence item, or the last
    /// evidence item when no message evidence exists, starts partial
    /// with the systemic reason. All other difficulties keep every
    /// item complete.
    private static func applyingExpertCompleteness(
        to evidence: [InvestigationEvidence],
        difficulty: InvestigationDifficulty
    ) -> [InvestigationEvidence] {
        guard difficulty == .expert, !evidence.isEmpty else { return evidence }
        let targetIndex = evidence.lastIndex(where: { $0.kind == .message }) ?? (evidence.count - 1)
        var updated = evidence
        updated[targetIndex] = updated[targetIndex].withCompleteness(
            .partial(reason: "available only after a targeted status request")
        )
        return updated
    }

    private static func amountShortText(header: InvestigationPaymentHeader) -> String {
        header.amountText == notStatedAmountText ? "not stated in the case" : header.amountText
    }

    private static func orderedKinds(of evidence: [InvestigationEvidence]) -> [InvestigationEvidenceKind] {
        var kinds: [InvestigationEvidenceKind] = []
        for item in evidence where !kinds.contains(item.kind) {
            kinds.append(item.kind)
        }
        return kinds
    }

    // MARK: - Hypotheses (rule 15)

    /// Exactly three hypotheses, all competing candidate
    /// explanations at the same level of specificity, in plain
    /// mechanism language: the flawed requirement phrased as the
    /// assumption the team acted on, the root cause phrased as a
    /// mechanism claim, and the category alternative. No option
    /// may contain an ISO or SWIFT message code, quote the
    /// report root-cause sentence, or share any run of 8 or more
    /// words with it; a candidate that breaks any of these rules
    /// falls back to its category template, so the answer can
    /// never leak through the options. The order is shuffled
    /// deterministically by case id.
    private static func buildHypotheses(
        caseID: String,
        assumptionCore: String,
        rootCauseFirstSentence: String,
        category: InvestigationCategoryKey,
        diagnosisText: String
    ) -> [InvestigationHypothesis] {
        var used: [String] = []

        let assumptionText = firstSafeCandidate(
            [
                "The team assumed: \(hypothesisSafeSentence(assumptionCore))",
                "The team assumed: \(templateAssumption(for: category))",
            ],
            diagnosisText: diagnosisText,
            used: used
        )
        used.append(assumptionText.lowercased())
        let first = InvestigationHypothesis(
            id: "\(caseID)-hyp-1",
            text: ensuringPeriod(assumptionText),
            isCorrect: false,
            source: .flawedRequirement
        )

        let causeText = firstSafeCandidate(
            [
                hypothesisSafeSentence(rootCauseFirstSentence),
                correctHypothesisTemplate(for: category),
            ],
            diagnosisText: diagnosisText,
            used: used
        )
        used.append(causeText.lowercased())
        let second = InvestigationHypothesis(
            id: "\(caseID)-hyp-2",
            text: ensuringPeriod(causeText),
            isCorrect: true,
            source: .rootCause
        )

        let alternativeText = firstSafeCandidate(
            alternativeCandidates(for: category),
            diagnosisText: diagnosisText,
            used: used
        )
        let third = InvestigationHypothesis(
            id: "\(caseID)-hyp-3",
            text: ensuringPeriod(alternativeText),
            isCorrect: false,
            source: .categoryAlternative
        )
        return PracticeModeBuilder.deterministicShuffle(
            [first, second, third],
            seed: PracticeModeBuilder.stableSeed(for: caseID)
        )
    }

    /// One case sentence made safe for use as a hypothesis
    /// option: quotes stripped, every message code replaced with
    /// a generic phrase, capitalised, with a final full stop.
    /// Safety against the diagnosis (no codes left, no long
    /// shared run) is checked by the caller.
    private static func hypothesisSafeSentence(_ sentence: String) -> String {
        let stripped = strippingMessageCodes(sentence.replacingOccurrences(of: "\"", with: ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return "" }
        return ensuringPeriod(capitalizedFirst(stripped))
    }

    /// Replaces every ISO 20022 and MT message code in the text
    /// with a generic phrase, keeping any article that already
    /// precedes the code ("a pacs.008" becomes "a payment
    /// message"; a bare code becomes "the payment message"), so
    /// hypothesis options never name a message code.
    private static func strippingMessageCodes(_ text: String) -> String {
        let codePattern = "pacs\\.\\d{3}|pain\\.\\d{3}|camt\\.\\d{3}|MT\\d{3}"
        var result = text
        if let withArticle = try? NSRegularExpression(
            pattern: "\\b(a|an|the)\\s+(\(codePattern))\\b",
            options: [.caseInsensitive]
        ) {
            let range = NSRange(result.startIndex..., in: result)
            result = withArticle.stringByReplacingMatches(
                in: result, options: [], range: range, withTemplate: "$1 payment message"
            )
        }
        if let bare = try? NSRegularExpression(
            pattern: "\\b(\(codePattern))\\b",
            options: [.caseInsensitive]
        ) {
            let range = NSRange(result.startIndex..., in: result)
            result = bare.stringByReplacingMatches(
                in: result, options: [], range: range, withTemplate: "the payment message"
            )
        }
        return result
    }

    /// The words of a text: lowercase alphanumeric tokens, so
    /// punctuation and capitalisation never hide a shared run.
    private static func words(of text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// The longest run of words the two texts share verbatim, in
    /// order. A hypothesis option must stay below 8 against the
    /// report root-cause sentence.
    private static func longestSharedWordRun(_ first: String, _ second: String) -> Int {
        let firstWords = words(of: first)
        let secondWords = words(of: second)
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

    /// True when a hypothesis candidate is safe to show: it says
    /// something (at least four words), names no message code,
    /// and shares no run of 8 or more words with the report
    /// root-cause sentence.
    private static func hypothesisCandidateIsSafe(_ candidate: String, diagnosisText: String) -> Bool {
        guard words(of: candidate).count >= 4 else { return false }
        guard messageCodes(in: candidate).isEmpty else { return false }
        return longestSharedWordRun(candidate, diagnosisText) < 8
    }

    /// The first candidate that is safe against the diagnosis
    /// and not already used by another option, or the generic
    /// fallback when every candidate fails. The fallback is
    /// plain mechanism language with no case wording, so it
    /// cannot quote the root cause.
    private static func firstSafeCandidate(
        _ candidates: [String],
        diagnosisText: String,
        used: [String]
    ) -> String {
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !used.contains(trimmed.lowercased()) else { continue }
            if hypothesisCandidateIsSafe(trimmed, diagnosisText: diagnosisText) {
                return trimmed
            }
        }
        return "The payment did not complete as expected, and the cause was never confirmed from the evidence."
    }

    /// The correct-candidate mechanism templates, used when the
    /// case root-cause sentence cannot be phrased as a safe
    /// option. Plain mechanism language, no message codes, one
    /// per failure category.
    private static func correctHypothesisTemplate(for category: InvestigationCategoryKey) -> String {
        switch category {
        case .rejectedOrReturned:
            return "The payment failed at a later stage in the chain, and the failure was never traced back to its cause."
        case .duplicate:
            return "The same payment was processed more than once because the first attempt was never confirmed."
        case .sanctions:
            return "The payment was held by a screening check, and no one followed up on the hold."
        case .reconciliation:
            return "The records in two systems disagreed, and the break was never investigated."
        case .other:
            return "The payment was treated as complete once it was sent, and its outcome was never confirmed from the records."
        }
    }

    /// The category alternative plus its fallback pool, in
    /// preference order. The caller picks the first safe,
    /// unused entry.
    private static func alternativeCandidates(for category: InvestigationCategoryKey) -> [String] {
        [
            categoryAlternative(for: category),
            categoryAlternative(for: .other),
            "A manual step in the process was missed.",
            "The payment was held for a check that was never completed.",
            "A timing difference between systems created a false break.",
        ]
    }

    // MARK: - Decisions (rule 16)

    /// One decision per decision step found (at most four), plus
    /// exactly one closing decision. When no decision step exists,
    /// the first decision is the first-check decision. Minimum two
    /// decisions, maximum five. Extra decision steps beyond four
    /// stay in the timeline as events, not decisions.
    private static func buildDerivedDecisions(
        caseID: String,
        decisionSteps: [InvestigationFlowStepSource],
        hasMessages: Bool,
        evidenceKinds: [InvestigationEvidenceKind],
        correctiveOptionText: String,
        closingWhyCorrect: String,
        closingEvidenceNote: String
    ) -> [InvestigationDecisionPoint] {
        var decisions: [InvestigationDecisionPoint] = []
        if decisionSteps.isEmpty {
            decisions.append(firstCheckDecision(
                caseID: caseID,
                index: 1,
                hasMessages: hasMessages,
                evidenceKinds: evidenceKinds
            ))
        } else {
            for (offset, step) in decisionSteps.enumerated() {
                decisions.append(stepDecision(caseID: caseID, index: offset + 1, step: step))
            }
        }
        decisions.append(closingDecision(
            caseID: caseID,
            index: decisions.count + 1,
            correctOptionText: correctiveOptionText,
            whyCorrect: closingWhyCorrect,
            evidenceNote: closingEvidenceNote
        ))
        return decisions
    }

    private static func stepDecision(
        caseID: String,
        index: Int,
        step: InvestigationFlowStepSource
    ) -> InvestigationDecisionPoint {
        let best = InvestigationDecisionOption(
            text: "Inspect the evidence for this step and confirm what it proves before moving on.",
            isBest: true,
            feedback: "Confirming each step from evidence is what separates an investigation from a guess."
        )
        let wrongs = [
            InvestigationDecisionOption(
                text: "Assume this step completed because the earlier steps did.",
                isBest: false,
                feedback: "An earlier step completing proves nothing about this step.",
                consequence: "The investigation moves on without evidence for this step, and the fault stays hidden."
            ),
            InvestigationDecisionOption(
                text: "Skip this step and look only at the final outcome.",
                isBest: false,
                feedback: "The final outcome alone cannot show where the flow went wrong.",
                consequence: "Skipping the step leaves a gap the report cannot explain."
            ),
            InvestigationDecisionOption(
                text: "Ask the customer to explain what happened at this step.",
                isBest: false,
                feedback: "The customer cannot see inside the payment chain; the evidence must answer this.",
                consequence: "The customer is asked to answer a question only the evidence can settle."
            ),
        ]
        let (options, bestIndex) = shuffledOptions([best] + wrongs, seedText: "\(caseID)-dec-\(index)")
        let whyCorrect: String
        if let note = nonEmpty(step.note) {
            whyCorrect = "The case evidence for this step says: \(note)"
        } else {
            whyCorrect = "Each step in the flow must be confirmed from evidence before the investigation moves on."
        }
        return InvestigationDecisionPoint(
            id: "\(caseID)-dec-\(index)",
            prompt: "The flow reaches a decision point: \(step.title). What should the investigator do next?",
            options: options,
            bestOptionIndex: bestIndex,
            whyCorrect: whyCorrect,
            evidenceNote: "The timeline shows this step as: \(step.title).",
            hypothesisPrompt: "Does this step change your leading hypothesis?",
            isTechnical: mentionsMessageOrSystem(step.title + " " + (step.note ?? ""))
        )
    }

    private static func firstCheckDecision(
        caseID: String,
        index: Int,
        hasMessages: Bool,
        evidenceKinds: [InvestigationEvidenceKind]
    ) -> InvestigationDecisionPoint {
        let bestText = hasMessages
            ? "Start with the timeline, then check the message evidence."
            : "Start with the timeline and confirm each step from the evidence."
        let best = InvestigationDecisionOption(
            text: bestText,
            isBest: true,
            feedback: "The timeline shows what happened in order, and the evidence for each step replaces guesses with facts."
        )
        let wrongs = [
            InvestigationDecisionOption(
                text: "Ask the customer to send the payment again.",
                isBest: false,
                feedback: "Resending before the cause is known risks paying twice.",
                consequence: "The customer may pay twice for the same payment."
            ),
            InvestigationDecisionOption(
                text: "Wait for the next processing window and check again.",
                isBest: false,
                feedback: "Waiting adds no new evidence.",
                consequence: "The customer waits without an answer, and the cause stays unknown."
            ),
            InvestigationDecisionOption(
                text: "Start with the final outcome and skip the timeline.",
                isBest: false,
                feedback: "The final outcome alone cannot show where the flow went wrong.",
                consequence: "The investigation starts without the order of events it needs."
            ),
        ]
        let (options, bestIndex) = shuffledOptions([best] + wrongs, seedText: "\(caseID)-dec-\(index)")
        let kindsList = evidenceKinds.map { $0.displayName }.joined(separator: ", ")
        return InvestigationDecisionPoint(
            id: "\(caseID)-dec-\(index)",
            prompt: "What should the investigator check first?",
            options: options,
            bestOptionIndex: bestIndex,
            whyCorrect: "The timeline shows what happened in order, and the evidence for each step replaces guesses with facts.",
            evidenceNote: "Evidence in this case: \(kindsList).",
            hypothesisPrompt: "Does the timeline change your leading hypothesis?"
        )
    }

    /// The closing decision, built from the real requirement
    /// (correct) plus the three category template distractors.
    private static func closingDecision(
        caseID: String,
        index: Int,
        correctOptionText: String,
        whyCorrect: String,
        evidenceNote: String
    ) -> InvestigationDecisionPoint {
        let best = InvestigationDecisionOption(
            text: correctOptionText,
            isBest: true,
            feedback: "This is the fix the case states."
        )
        let wrongs = correctiveDistractors.map {
            InvestigationDecisionOption(
                text: $0.text,
                isBest: false,
                feedback: $0.feedback,
                consequence: $0.consequence
            )
        }
        let (options, bestIndex) = shuffledOptions([best] + wrongs, seedText: "\(caseID)-dec-\(index)")
        return InvestigationDecisionPoint(
            id: "\(caseID)-dec-\(index)",
            prompt: "What is the right corrective action?",
            options: options,
            bestOptionIndex: bestIndex,
            whyCorrect: whyCorrect,
            evidenceNote: evidenceNote,
            isResolution: true
        )
    }

    private static func shuffledOptions(
        _ options: [InvestigationDecisionOption],
        seedText: String
    ) -> ([InvestigationDecisionOption], Int) {
        let shuffled = PracticeModeBuilder.deterministicShuffle(
            options,
            seed: PracticeModeBuilder.stableSeed(for: seedText)
        )
        let bestIndex = shuffled.firstIndex(where: { $0.isBest }) ?? 0
        return (shuffled, bestIndex)
    }

    /// True when the text names a message code or a system concept:
    /// the message and system decisions counted by the
    /// technicalAccuracy dimension.
    private static func mentionsMessageOrSystem(_ text: String) -> Bool {
        if !messageCodes(in: text).isEmpty { return true }
        let lower = text.lowercased()
        if lower.contains("system") || lower.contains("clearing") || lower.contains("ledger")
            || lower.contains("validation") || lower.contains("character set") {
            return true
        }
        return containsWholeWord("API", in: text)
    }

    // MARK: - Authored tier mapping

    private static func authoredEvidence(from item: ExceptionEvidence) -> InvestigationEvidence {
        let namesMessage = !messageCodes(in: item.title + " " + item.detail).isEmpty
        return InvestigationEvidence(
            id: item.id,
            kind: namesMessage ? .message : .note,
            title: item.title,
            body: item.detail,
            structuredLines: [],
            sourceField: "authored",
            revealedAfterStep: item.revealedAfterStep,
            completeness: .complete,
            isRedHerring: item.isRedHerring
        )
    }

    private static func authoredDecision(
        step: InvestigationStep,
        isLast: Bool
    ) -> InvestigationDecisionPoint {
        let options = step.options.enumerated().map { optionIndex, option in
            InvestigationDecisionOption(
                text: option.text,
                isBest: optionIndex == step.bestOptionIndex,
                feedback: option.feedback,
                consequence: optionIndex == step.bestOptionIndex ? "" : step.wrongTurnCost,
                evidenceNote: nil,
                isRedHerring: option.isRedHerring
            )
        }
        let technicalText = step.prompt + " " + step.options.map { $0.text }.joined(separator: " ")
        return InvestigationDecisionPoint(
            id: step.id,
            prompt: step.prompt,
            options: options,
            bestOptionIndex: step.bestOptionIndex,
            whyCorrect: step.whyCorrect,
            evidenceNote: step.evidenceNote,
            hypothesisPrompt: isLast ? nil : "Does this step change your leading hypothesis?",
            isTechnical: mentionsMessageOrSystem(technicalText),
            isResolution: isLast
        )
    }

    private static func authoredAssumptionCore(
        labCase: ExceptionCase,
        category: InvestigationCategoryKey
    ) -> String {
        if let herring = labCase.evidence.first(where: { $0.isRedHerring }) {
            let first = PracticeModeBuilder.firstSentence(of: herring.detail)
            if !first.isEmpty { return first }
        }
        if let firstStep = labCase.steps.first,
           let wrong = firstStep.options.enumerated().first(where: { $0.offset != firstStep.bestOptionIndex }) {
            let first = PracticeModeBuilder.firstSentence(of: wrong.element.text)
            if !first.isEmpty { return first }
        }
        return templateAssumption(for: category)
    }

    private static func authoredBusinessContext(labCase: ExceptionCase) -> String {
        let first = PracticeModeBuilder.firstSentence(of: labCase.narrative)
        if !first.isEmpty { return "\(labCase.incidentType). \(first)" }
        return labCase.incidentType
    }

    // MARK: - Templates (plan section 7, verbatim unless noted)

    /// The three fixed investigation objectives, shown verbatim for
    /// every case (rule 14).
    private static let objectives: [String] = [
        "Establish what happened to the payment.",
        "Identify the root cause from the evidence.",
        "Recommend the corrective action and the control that prevents recurrence.",
    ]

    private static let currencyCodes: [String] = [
        "EUR", "USD", "GBP", "INR", "JPY", "CHF", "AUD", "CAD", "SGD", "HKD", "AED",
    ]

    private static let clearingSystems: [String] = [
        "TARGET2", "CHAPS", "Fedwire", "SEPA", "RTGS", "NEFT", "IMPS",
        "Faster Payments", "ACH", "BACS", "CHIPS", "FedNow", "UPI",
    ]

    private static let notStatedAmountText = "Amount not stated in the case"

    /// Category alternatives (H3) by failure category, verbatim.
    private static func categoryAlternative(for category: InvestigationCategoryKey) -> String {
        switch category {
        case .rejectedOrReturned:
            return "A downstream system rejected the payment for a reason unrelated to the instruction."
        case .duplicate:
            return "The payment was sent twice because the first attempt timed out."
        case .sanctions:
            return "A sanctions list update held the payment after it was sent."
        case .reconciliation:
            return "A timing difference between systems created a false break."
        case .other:
            return "A fault in a downstream system stopped the payment after it left the sending bank."
        }
    }

    /// Customer impact sentences by failure category, verbatim.
    private static func impactSentence(for category: InvestigationCategoryKey) -> String {
        switch category {
        case .rejectedOrReturned:
            return "The customer expected the payment to arrive and had to chase its status."
        case .duplicate:
            return "The customer was debited more than once for the same payment."
        case .sanctions:
            return "The customer's payment was held without an explanation the customer could act on."
        case .reconciliation:
            return "The customer's balance and the bank's records did not agree."
        case .other:
            return "The customer could not confirm whether the payment had completed."
        }
    }

    /// Corrective-action distractors, verbatim, each with feedback
    /// and a narrative consequence for a wrong pick.
    private static let correctiveDistractors: [(text: String, feedback: String, consequence: String)] = [
        (
            "Ask the customer to send the payment again.",
            "Resending before the cause is known risks paying twice.",
            "The customer may pay twice for the same payment."
        ),
        (
            "Wait for the next processing window and check again.",
            "Waiting adds no new evidence.",
            "The customer waits without an answer, and the cause stays unknown."
        ),
        (
            "Raise a manual adjustment without investigating the cause.",
            "An adjustment without a cause can mask the fault.",
            "The fault stays in place and the next payment can fail the same way."
        ),
    ]

    /// Generic assumption continuations used only when the case text
    /// carries no flawed requirement and no Why? section (rule 4
    /// fallback). These are engine templates, not case facts; the
    /// hypothesis builder prefixes them with "The team assumed:".
    private static func templateAssumption(for category: InvestigationCategoryKey) -> String {
        switch category {
        case .rejectedOrReturned:
            return "a failed payment could be handled the same way at every stage"
        case .duplicate:
            return "a file received from the customer had already been checked"
        case .sanctions:
            return "the payment would pass screening without a hold"
        case .reconciliation:
            return "the records in both systems would agree"
        case .other:
            return "the payment would complete once it was sent"
        }
    }

    // MARK: - Small helpers

    /// The trimmed string, or nil when it is nil or empty.
    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func containsMatch(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func containsWholeWord(_ word: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        return containsMatch(pattern: "\\b\(escaped)\\b", in: text, options: [.caseInsensitive])
    }

    /// The capture groups of the first match, or nil when the
    /// pattern does not match. Groups that did not participate are
    /// empty strings.
    private static func firstMatchGroups(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            let groupRange = match.range(at: index)
            if groupRange.location != NSNotFound, let swiftRange = Range(groupRange, in: text) {
                groups.append(String(text[swiftRange]))
            } else {
                groups.append("")
            }
        }
        return groups
    }

    /// Every full match of the pattern, in order of appearance.
    private static func allMatches(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }
}

// MARK: - Investigation Lab gate

/// The Investigation Lab gate, shared by the Investigation
/// Experience, the Exception Investigation Lab, and the Community
/// Challenge. A case is locked when it is grounded in a non-free
/// situation, is not this week's free case, and the learner has no
/// Investigation Lab entitlement. Cases grounded in a free sample
/// stay open, and the weekly free case stays free. Pure logic,
/// covered by the gate truth-table tests.
enum InvestigationGate {

    /// True when an investigation case must stay locked.
    static func isLocked(
        isFreeSample: Bool,
        isWeeklyFreeCase: Bool,
        isInvestigationLabUnlocked: Bool
    ) -> Bool {
        !isFreeSample && !isWeeklyFreeCase && !isInvestigationLabUnlocked
    }

    /// True when a lab or challenge case may open: it needs no
    /// unlock (grounded in a free sample, or a purely authored
    /// practice exercise), or the Lab entitlement is active.
    static func isOpen(requiresUnlock: Bool, isInvestigationLabUnlocked: Bool) -> Bool {
        !requiresUnlock || isInvestigationLabUnlocked
    }
}
