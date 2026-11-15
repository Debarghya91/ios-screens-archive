// CommunityChallengeView.swift
// PaymentForge iOS - Weekly community challenge.
//
// One real case per week for every learner, picked deterministically
// by CommunityChallenge from the existing lab catalogue. Taking part
// is optional: the challenge is a practice activity, never a
// requirement, and skipping a week costs nothing and loses nothing.
// The case is investigated step by step, the same way as the lab:
// read the narrative, open evidence as it is revealed, choose the
// next action at each step. The explanation (the case resolution and
// the source situation's own takeaway) is shown only after the
// challenge is completed, never before; completed weeks keep their
// explanation in the history below, so last week's explanation stays
// available after the week closes and the case rotates.
//
// Gating: this view changes no gating. It applies the lab's existing
// rule to the same content, read-only: a week whose case is grounded
// in a non-free situation shows only its title, incident type and
// level until the situations entitlement is active, with the same
// checkout path the lab uses; a week grounded in a free-sample
// situation is open to all. D101 PENDING: SituationsView currently
// shows the full situation detail when locked, which is inconsistent
// with this gate. Do not change either side without the D101
// decision; see CommunityChallenge.swift.
//
// Leaderboard honesty: there is no shared-results backend, so the
// leaderboard section shows only the learner's own progress plus an
// honest empty state. It never shows invented community rows,
// totals, or participation numbers. No name and no identifier is
// collected, and nothing about the challenge leaves this device in
// this version; the copy below states that plainly. The shareable
// result uses the standard share sheet with text only: the learner
// chooses whether to share, and the app sends nothing itself.
//
// This view carries no NavigationStack of its own, following
// DailyChallengeView and the lab: the host provides the stack, so
// the navigation title and back button belong to the host. It needs
// StoreManager in the environment, the same as the lab view.
// No em dashes in any user-facing text.

import SwiftUI

struct CommunityChallengeView: View {
    @EnvironmentObject private var storeManager: StoreManager
    @ObservedObject private var challengeStore = CommunityChallengeStore.shared

    @State private var showCheckout = false

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private var now: Date { Date() }

    private var weekKey: String { CommunityChallenge.weekKey(for: now) }

    private var weekCase: ExceptionCase? { CommunityChallenge.caseFor(date: now) }

    private var weekRangeText: String {
        guard let start = CommunityChallenge.weekStart(for: now),
              let end = CommunityChallenge.weekEnd(for: now) else { return weekKey }
        return "\(Self.displayDateFormatter.string(from: start)) to \(Self.displayDateFormatter.string(from: end))"
    }

    /// True when the learner may open this week's case: it needs no
    /// unlock, or the situations entitlement is active. The lab's
    /// existing rule, read-only; this view changes no gating.
    private func isOpen(_ exceptionCase: ExceptionCase) -> Bool {
        !exceptionCase.requiresSituationsUnlock || storeManager.isSituationsUnlocked
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.xl) {
                headerSection
                if let weekCase {
                    if isOpen(weekCase) {
                        CommunityChallengePlayView(
                            weekKey: weekKey,
                            exceptionCase: weekCase,
                            store: challengeStore
                        )
                        .id("\(weekKey)-\(weekCase.id)")
                    } else {
                        lockedWeekCard(weekCase)
                    }
                } else {
                    Text("This week's challenge is not available yet. Check back soon.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                leaderboardSection
                historySection
                privacyNote
            }
            .padding(PFSpacing.lg)
        }
        // Copy protection: the challenge case cannot be selected, a
        // faint identity watermark sits over it, and recording blurs
        // it out. The same protection the daily challenge uses.
        .pfProtectedContent()
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .navigationTitle("Community Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCheckout) {
            CheckoutView()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text("One real case a week, the same for everyone")
                .font(.pfScreenTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Text("This week's case runs \(weekRangeText). Read the case, investigate it step by step, and check yourself against the explanation when you finish. Taking part is optional, and a new case arrives every Monday.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            PFPill(text: "Week \(weekKey)")
            if let attempt = challengeStore.attempt(forWeekKey: weekKey) {
                PFPill(
                    text: "Completed this week, best \(attempt.bestTotal) out of \(attempt.bestMaximum)",
                    background: Color.pfSuccess.opacity(0.12),
                    foreground: .pfSuccess
                )
            }
        }
    }

    // MARK: - Locked week

    /// A locked week: only the title, incident type and level are
    /// shown. The narrative, evidence, steps and explanation stay
    /// hidden until the situations set is unlocked, exactly as in
    /// the lab. Weeks built from the free sample situations are
    /// open to all and never reach this card.
    private func lockedWeekCard(_ exceptionCase: ExceptionCase) -> some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.sm) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.pfSecondaryText)
                        .accessibilityHidden(true)
                    PFPill(text: exceptionCase.incidentType)
                    PFPill(
                        text: exceptionCase.level.displayName,
                        background: Color.pfGoldSoft,
                        foreground: Color.pfGoldText
                    )
                    Spacer(minLength: 0)
                    PFPill(
                        text: "Locked",
                        background: Color.pfSecondaryText.opacity(0.12),
                        foreground: .pfSecondaryText
                    )
                }
                Text(exceptionCase.title)
                    .font(.pfSectionTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Text("This week's case is built from a Payment Situation in the full set. Unlock the full set to take part this week. Weeks built from the free sample situations are open to everyone, with no purchase needed.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                PFPrimaryButton(title: "See purchase options") {
                    showCheckout = true
                }
                .accessibilityLabel("See purchase options to unlock this week's case, \(exceptionCase.title)")
            }
        }
    }

    // MARK: - Leaderboard

    /// The leaderboard, honestly labelled. No shared-results backend
    /// exists, so this section shows only the learner's own progress
    /// and says plainly that no community results exist yet. It
    /// never renders a community row, total, or participation count,
    /// because none has been collected.
    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Community leaderboard")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    let board = challengeStore.leaderboard(forWeekKey: weekKey)
                    if let best = board.personalBest {
                        HStack(spacing: PFSpacing.md) {
                            PFIconTile(systemImage: "trophy.fill")
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                Text("Your personal best")
                                    .font(.pfCardTitle)
                                    .foregroundColor(.pfNavy)
                                Text("\(best.bestTotal) out of \(best.bestMaximum), week \(best.weekKey). \(challengeStore.attempts.count) week\(challengeStore.attempts.count == 1 ? "" : "s") completed.")
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        Text("No challenge results yet. Complete a week to set your personal best.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Divider()
                    if board.hasCommunityData {
                        // Unreachable in this version: the store
                        // always returns zero community entries.
                        // Kept so a future backend fills this list
                        // from real server rows only.
                        ForEach(board.communityEntries, id: \.anonymousLabel) { entry in
                            HStack(spacing: PFSpacing.md) {
                                Text(entry.anonymousLabel)
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                                Spacer(minLength: 0)
                                Text("\(entry.total) out of \(entry.maximum)")
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                            }
                        }
                    } else {
                        PFBodyText(text: "No community results yet. There is no shared leaderboard in this version, so this screen shows only your own progress. No community totals are shown, because none have been collected. If a shared leaderboard is added later, it will show anonymous results only, with no names.", textColor: .pfSecondaryText)
                    }
                }
            }
        }
    }

    // MARK: - History

    /// Completed weeks, most recent first, each with its
    /// explanation. Only completed weeks appear: the explanation for
    /// a week is earned by finishing that week's challenge. When a
    /// stored case id is no longer in the catalogue, the score still
    /// shows and the missing case is said plainly.
    @ViewBuilder
    private var historySection: some View {
        let past = challengeStore.attempts.sorted { $0.lastCompletedAt > $1.lastCompletedAt }
        if !past.isEmpty {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                PFSectionHeader(title: "Past weeks")
                ForEach(past) { attempt in
                    historyCard(for: attempt)
                }
            }
        }
    }

    private func historyCard(for attempt: CommunityChallengeAttempt) -> some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                HStack(spacing: PFSpacing.sm) {
                    Text("Week \(attempt.weekKey)")
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                    Spacer(minLength: 0)
                    PFPill(
                        text: "Best \(attempt.bestTotal) out of \(attempt.bestMaximum)",
                        background: Color.pfSuccess.opacity(0.12),
                        foreground: .pfSuccess
                    )
                }
                if let exceptionCase = CommunityChallenge.exceptionCase(forID: attempt.caseID) {
                    Text(exceptionCase.title)
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Completed \(attempt.completions) time\(attempt.completions == 1 ? "" : "s").")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                    DisclosureGroup("Explanation") {
                        explanationContent(for: exceptionCase)
                    }
                    .font(.pfBody)
                    .foregroundColor(.pfNavy)
                } else {
                    Text("The case for this week is no longer in the catalogue. Your score is kept.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The explanation for a completed case: the resolution, the
    /// source situation's own takeaway when the case carries one,
    /// and the red herring notes. Shown only after completion, here
    /// and in the play view.
    private func explanationContent(for exceptionCase: ExceptionCase) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            PFBodyText(text: exceptionCase.resolution)
            if let takeaway = exceptionCase.sourceTakeaway {
                PFBodyText(text: "The situation's own takeaway: \(takeaway)")
            }
            ForEach(exceptionCase.evidence.filter { $0.isRedHerring }, id: \.id) { item in
                if let note = item.redHerringNote {
                    PFBodyText(text: "\(item.title): \(note)", textColor: .pfSecondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, PFSpacing.sm)
    }

    // MARK: - Privacy

    private var privacyNote: some View {
        Text("Taking part is optional. No name and no identifier is collected, and nothing about your challenge leaves this device in this version. Your results are stored on this device only, under your current account.")
            .font(.pfBody)
            .foregroundColor(.pfSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Play

/// One week's investigation: the case card, the evidence as it is
/// revealed, and one step at a time. Tapping an option is a pick:
/// a wrong pick shows that option's feedback and counts as a wrong
/// turn, and the step stays open until the best next step is picked.
/// Scoring reuses ExceptionLabScoring, so the breakdown matches the
/// lab exactly. The explanation appears only once the final step is
/// solved. Keyed by week and case id by the parent, so a new week
/// always starts fresh.
private struct CommunityChallengePlayView: View {
    let weekKey: String
    let exceptionCase: ExceptionCase
    @ObservedObject var store: CommunityChallengeStore

    @State private var stepIndex = 0
    @State private var triedOptionIndices: Set<Int> = []
    @State private var lastTriedIndex: Int? = nil
    @State private var wrongPicks = 0
    @State private var redHerringPicks = 0
    @State private var stepSolved = false
    @State private var stepResults: [ExceptionStepResult] = []
    @State private var evidenceOpenedIDs: Set<String> = []
    @State private var evidenceExpandedIDs: Set<String> = []
    @State private var completion: ExceptionLabScoreBreakdown? = nil

    private var currentStep: InvestigationStep? {
        stepIndex < exceptionCase.steps.count ? exceptionCase.steps[stepIndex] : nil
    }

    /// Evidence revealed so far: an item becomes visible once its
    /// reveal step count has been solved, the lab's own rule.
    private var visibleEvidence: [ExceptionEvidence] {
        exceptionCase.evidence.filter { $0.revealedAfterStep <= stepResults.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            caseCard
            if exceptionCase.steps.isEmpty {
                Text("This week's case has no investigation steps.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let breakdown = completion {
                completionSection(breakdown)
            } else {
                evidenceSection
                stepSection
            }
        }
    }

    // MARK: - Case

    private var caseCard: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.sm) {
                    PFPill(text: exceptionCase.incidentType)
                    PFPill(
                        text: exceptionCase.level.displayName,
                        background: Color.pfGoldSoft,
                        foreground: Color.pfGoldText
                    )
                }
                Text(exceptionCase.title)
                    .font(.pfSectionTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                PFBodyText(text: exceptionCase.narrative)
                if exceptionCase.sourceSituationID != nil {
                    Text("Built from a real Payment Situation.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                }
            }
        }
    }

    // MARK: - Evidence

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            Text("Evidence")
                .font(.pfSectionTitle)
                .foregroundColor(.pfNavy)
            Text("Open the evidence as you investigate. Opening a genuine clue adds to your score; opening a distraction costs nothing, but acting on one does.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if visibleEvidence.isEmpty {
                Text("No evidence is visible yet.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
            }
            ForEach(visibleEvidence) { item in
                evidenceRow(for: item)
            }
        }
    }

    private func evidenceRow(for item: ExceptionEvidence) -> some View {
        let expanded = evidenceExpandedIDs.contains(item.id)
        return Button {
            if expanded {
                evidenceExpandedIDs.remove(item.id)
            } else {
                evidenceExpandedIDs.insert(item.id)
                evidenceOpenedIDs.insert(item.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                HStack(spacing: PFSpacing.sm) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                        .accessibilityHidden(true)
                    Text(item.title)
                        .font(.pfBody.weight(.semibold))
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                if expanded {
                    PFBodyText(text: item.detail)
                }
            }
            .padding(PFSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.pfCard)
            .cornerRadius(PFSpacing.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                    .stroke(Color.pfBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title), evidence")
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepSection: some View {
        if let step = currentStep {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                Text("Step \(stepIndex + 1) of \(exceptionCase.steps.count)")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfSecondaryText)
                Text(step.prompt)
                    .font(.pfSectionTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(step.options.enumerated()), id: \.offset) { index, option in
                    optionButton(step: step, index: index, option: option)
                }
                feedbackSection(for: step)
                if stepSolved {
                    PFPrimaryButton(title: stepIndex + 1 >= exceptionCase.steps.count ? "Finish challenge" : "Next step") {
                        advance()
                    }
                }
            }
        }
    }

    private func optionButton(step: InvestigationStep, index: Int, option: InvestigationOption) -> some View {
        let isBest = index == step.bestOptionIndex
        let tried = triedOptionIndices.contains(index)
        let border: Color = {
            if stepSolved && isBest { return .pfSuccess }
            if tried { return .pfError }
            return .pfBorder
        }()
        let icon: String = {
            if stepSolved && isBest { return "checkmark.circle.fill" }
            if tried { return "xmark.circle.fill" }
            return "circle"
        }()
        let iconColor: Color = {
            if stepSolved && isBest { return .pfSuccess }
            if tried { return .pfError }
            return .pfSecondaryText
        }()
        return Button {
            pick(optionIndex: index)
        } label: {
            HStack(alignment: .top, spacing: PFSpacing.sm) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                Text(option.text)
                    .font(.pfBody)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(PFSpacing.md)
            .background(Color.pfCard)
            .cornerRadius(PFSpacing.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                    .stroke(border, lineWidth: (stepSolved && isBest) || tried ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(stepSolved || tried)
        .accessibilityLabel(option.text)
    }

    /// Feedback for the current step: while unsolved, the feedback
    /// of the most recent wrong pick; once solved, the best
    /// option's feedback, why it is correct, and what it reveals.
    @ViewBuilder
    private func feedbackSection(for step: InvestigationStep) -> some View {
        if stepSolved {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text(step.options[step.bestOptionIndex].feedback)
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(step.whyCorrect)
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = step.evidenceNote {
                        Text(note)
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else if let lastTriedIndex, triedOptionIndices.contains(lastTriedIndex) {
            Text(step.options[lastTriedIndex].feedback)
                .font(.pfBody)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One pick. A non-best pick counts as a wrong turn, and as a
    /// red herring pick too when the option is a red herring, the
    /// same counting the lab scoring expects. A best pick solves
    /// the step and records its result.
    private func pick(optionIndex: Int) {
        guard completion == nil, !stepSolved, let step = currentStep,
              optionIndex >= 0, optionIndex < step.options.count,
              !triedOptionIndices.contains(optionIndex) else { return }
        lastTriedIndex = optionIndex
        if optionIndex == step.bestOptionIndex {
            stepSolved = true
            stepResults.append(ExceptionStepResult(
                stepID: step.id,
                wrongPicks: wrongPicks,
                redHerringPicks: redHerringPicks,
                solved: true
            ))
        } else {
            triedOptionIndices.insert(optionIndex)
            wrongPicks += 1
            if step.options[optionIndex].isRedHerring {
                redHerringPicks += 1
            }
        }
    }

    /// Move to the next step, or finish the challenge: score it
    /// with the lab rules, record it, and reveal the explanation.
    private func advance() {
        if stepIndex + 1 >= exceptionCase.steps.count {
            let breakdown = ExceptionLabScoring.breakdown(
                for: exceptionCase,
                stepResults: stepResults,
                evidenceOpenedIDs: evidenceOpenedIDs
            )
            completion = breakdown
            store.recordCompletion(weekKey: weekKey, caseID: exceptionCase.id, breakdown: breakdown)
        } else {
            stepIndex += 1
            triedOptionIndices = []
            lastTriedIndex = nil
            wrongPicks = 0
            redHerringPicks = 0
            stepSolved = false
        }
    }

    private func resetPlay() {
        stepIndex = 0
        triedOptionIndices = []
        lastTriedIndex = nil
        wrongPicks = 0
        redHerringPicks = 0
        stepSolved = false
        stepResults = []
        evidenceOpenedIDs = []
        evidenceExpandedIDs = []
        completion = nil
    }

    // MARK: - Completion

    private func completionSection(_ breakdown: ExceptionLabScoreBreakdown) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text("Challenge complete")
                        .font(.pfSectionTitle)
                        .foregroundColor(.pfNavy)
                    Text("You scored \(breakdown.total) out of \(breakdown.maximum).")
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    scoreRow(label: "Best first steps", value: "\(breakdown.bestFirstPoints) points, \(breakdown.stepsSolvedBestFirst) of \(exceptionCase.steps.count) steps")
                    scoreRow(label: "Recovered steps", value: "\(breakdown.recoveredPoints) points, \(breakdown.stepsSolvedAfterWrongTurn) steps")
                    scoreRow(label: "Wrong turns", value: "Minus \(breakdown.wrongTurnDeductions), \(breakdown.totalWrongPicks) wrong picks")
                    scoreRow(label: "Red herrings", value: "Minus \(breakdown.redHerringDeductions), \(breakdown.totalRedHerringPicks) red herring picks")
                    scoreRow(label: "Efficiency bonus", value: "\(breakdown.efficiencyBonus) points")
                    scoreRow(label: "Evidence opened", value: "\(breakdown.thoroughnessPoints) points, \(breakdown.evidenceOpenedCount) of \(breakdown.evidenceTotalCount) genuine items")
                }
            }
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text("Explanation")
                        .font(.pfSectionTitle)
                        .foregroundColor(.pfNavy)
                    PFBodyText(text: exceptionCase.resolution)
                    if let takeaway = exceptionCase.sourceTakeaway {
                        PFBodyText(text: "The situation's own takeaway: \(takeaway)")
                    }
                    ForEach(exceptionCase.evidence.filter { $0.isRedHerring }, id: \.id) { item in
                        if let note = item.redHerringNote {
                            PFBodyText(text: "\(item.title): \(note)", textColor: .pfSecondaryText)
                        }
                    }
                }
            }
            ShareLink(
                item: CommunityChallenge.shareText(
                    weekKey: weekKey,
                    caseTitle: exceptionCase.title,
                    total: breakdown.total,
                    maximum: breakdown.maximum
                )
            ) {
                Label("Share my result", systemImage: "square.and.arrow.up")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.pfRoyal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.pfRoyal.opacity(0.08))
                    .cornerRadius(PFSpacing.cornerRadius)
            }
            .accessibilityLabel("Share my result for week \(weekKey)")
            Text("Sharing sends only the week, the case title, and your score. No answers and no personal details are shared.")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            PFSecondaryButton(title: "Try this week again") {
                resetPlay()
            }
        }
    }

    private func scoreRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: PFSpacing.md) {
            Text(label)
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.pfBody)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
