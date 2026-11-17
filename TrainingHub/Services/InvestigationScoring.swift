// InvestigationScoring.swift
// Scores one completed investigation run into the five-dimension
// investigation report, following the dimension rules in
// INVESTIGATION-PLAN.md section 5.1 exactly. Wrong-pick and
// red-herring costs reuse the Lab constants, so the two scores can
// never drift apart. No em dashes in any user-facing text.

import Foundation

enum InvestigationScoring {

    /// Scores one run of one case into its investigation report.
    /// Dimension rules: evidenceInterpretation is the share of
    /// relevant evidence opened, where relevant means in
    /// supportingEvidenceIDs or cited by the learner; efficiency
    /// follows the Lab mapping (0 wrong picks is 100, 1 wrong pick
    /// is 90, otherwise 100 minus 5 per wrong pick and 10 extra per
    /// red-herring pick, floored at 0); technicalAccuracy is the
    /// share of message and system decisions answered correctly,
    /// defaulting to 100 when no such decision exists;
    /// rootCauseIdentification is 100 when the diagnosis pick is
    /// the correct hypothesis and 0 otherwise; the citation is
    /// required to submit a diagnosis but does not change this
    /// dimension;
    /// resolutionQuality is the share of corrective-action and
    /// preventive-control decisions answered correctly, defaulting
    /// to 100 when none exists. Overall is the rounded mean of the
    /// five, computed by InvestigationDimensionScores.
    static func score(case investigationCase: InvestigationCase, run: InvestigationRun) -> InvestigationReport {
        let decisions = investigationCase.decisions
        // Timeline and evidence are disjoint lists since the
        // duplication fix: the scored set is their union, the
        // same ids the old overlapping evidence list carried,
        // so opening a timeline item still counts exactly as
        // it did before.
        let evidenceIDs = Set(
            investigationCase.timeline.map { $0.id }
                + investigationCase.evidence.map { $0.id }
        )
        let openedIDs = run.openedEvidenceIDs.intersection(evidenceIDs)

        var wrongPicks = 0
        var redHerringPicks = 0
        var decisionsCorrect = 0
        for decision in decisions {
            guard let picked = run.decisionPicks[decision.id] else { continue }
            if picked == decision.bestOptionIndex {
                decisionsCorrect += 1
            } else {
                wrongPicks += 1
                if decision.options.indices.contains(picked), decision.options[picked].isRedHerring {
                    redHerringPicks += 1
                }
            }
        }

        let dimensionScores = InvestigationDimensionScores(
            evidenceInterpretation: evidenceInterpretationScore(
                case: investigationCase,
                run: run,
                openedIDs: openedIDs,
                evidenceIDs: evidenceIDs
            ),
            efficiency: efficiencyScore(wrongPicks: wrongPicks, redHerringPicks: redHerringPicks),
            technicalAccuracy: pickAccuracy(
                decisions: decisions.filter { $0.isTechnical },
                picks: run.decisionPicks
            ),
            rootCauseIdentification: rootCauseScore(case: investigationCase, run: run),
            resolutionQuality: pickAccuracy(
                decisions: decisions.filter { $0.isResolution },
                picks: run.decisionPicks
            )
        )

        return InvestigationReport(
            caseID: investigationCase.id,
            situationID: investigationCase.situationID,
            difficulty: investigationCase.difficulty,
            completedAt: Date(),
            dimensionScores: dimensionScores,
            incorrectAssumptions: incorrectAssumptions(case: investigationCase, run: run),
            citedEvidenceIDs: run.citedEvidenceIDs,
            wrongPicks: wrongPicks,
            evidenceOpenedCount: openedIDs.count,
            decisionsCorrect: decisionsCorrect,
            decisionsTotal: decisions.count
        )
    }

    // MARK: - Dimensions

    private static func evidenceInterpretationScore(
        case investigationCase: InvestigationCase,
        run: InvestigationRun,
        openedIDs: Set<String>,
        evidenceIDs: Set<String>
    ) -> Int {
        let relevant = Set(investigationCase.supportingEvidenceIDs)
            .union(run.citedEvidenceIDs)
            .intersection(evidenceIDs)
        guard !relevant.isEmpty else { return 100 }
        let opened = relevant.intersection(openedIDs).count
        return Int((Double(opened) / Double(relevant.count) * 100).rounded())
    }

    private static func efficiencyScore(wrongPicks: Int, redHerringPicks: Int) -> Int {
        if wrongPicks == 0 { return 100 }
        if wrongPicks == 1 { return 90 }
        let score = 100
            - wrongPicks * ExceptionLabScoring.wrongPickDeduction
            - redHerringPicks * ExceptionLabScoring.redHerringPickDeduction
        return max(0, score)
    }

    /// The share of the given decisions answered correctly, as a
    /// 0 to 100 score. Unanswered decisions count as incorrect.
    /// Defaults to 100 when the list is empty.
    private static func pickAccuracy(
        decisions: [InvestigationDecisionPoint],
        picks: [String: Int]
    ) -> Int {
        guard !decisions.isEmpty else { return 100 }
        let correct = decisions.filter { picks[$0.id] == $0.bestOptionIndex }.count
        return Int((Double(correct) / Double(decisions.count) * 100).rounded())
    }

    /// Root-cause identification is the diagnosis pick alone:
    /// 100 when the picked hypothesis is the correct one, 0
    /// otherwise. Citations do not change this dimension.
    private static func rootCauseScore(case investigationCase: InvestigationCase, run: InvestigationRun) -> Int {
        guard let diagnosisID = run.diagnosisHypothesisID,
              let correct = investigationCase.hypotheses.first(where: { $0.isCorrect }),
              let picked = hypothesis(for: diagnosisID, in: investigationCase) else {
            return 0
        }
        guard picked.id == correct.id else { return 0 }
        return 100
    }

    // MARK: - Incorrect assumptions

    /// The incorrect assumptions the learner held: the texts of
    /// incorrect hypotheses revised away from, in revision order,
    /// plus the diagnosis text when the diagnosis pick itself was
    /// incorrect. Each text appears once.
    private static func incorrectAssumptions(
        case investigationCase: InvestigationCase,
        run: InvestigationRun
    ) -> [String] {
        var assumptions: [String] = []
        for revision in run.hypothesisRevisions {
            if let held = hypothesis(for: revision.from, in: investigationCase),
               !held.isCorrect, !assumptions.contains(held.text) {
                assumptions.append(held.text)
            }
        }
        if let diagnosisID = run.diagnosisHypothesisID,
           let picked = hypothesis(for: diagnosisID, in: investigationCase),
           !picked.isCorrect, !assumptions.contains(picked.text) {
            assumptions.append(picked.text)
        }
        return assumptions
    }

    /// Resolves a hypothesis reference to its hypothesis, matching
    /// by id first and by exact text second, so a run record that
    /// carries texts instead of ids still scores.
    private static func hypothesis(
        for idOrText: String,
        in investigationCase: InvestigationCase
    ) -> InvestigationHypothesis? {
        if let match = investigationCase.hypotheses.first(where: { $0.id == idOrText }) {
            return match
        }
        return investigationCase.hypotheses.first(where: { $0.text == idOrText })
    }
}
