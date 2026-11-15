// DailyChallengeView.swift
// PaymentForge iOS - Daily Challenge: one real situation per day.
// The situation is picked deterministically from the situations by the
// calendar day, so every learner gets the same challenge each day and
// it changes daily. The question is "What is the key lesson here?":
// the correct option is the situation's own takeaway, and the wrong
// options are the takeaways of three other real situations, so every
// option is real text and none is an invented technical fact. The
// explanation is the situation's own takeaway. Completion is tracked
// locally, one per day.
//
// v70 gate: a learner without Payment Situations unlocked sees only
// the 6 free samples plus this week's free case here. The pick, the
// options, the scenario text and the post-answer takeaway all draw
// from the gated pool, so no locked explain or takeaway text can
// reach a non-entitled learner through this surface. Entitled
// learners are unaffected: the gate returns the full list unchanged
// for them, so the pick, the options and the shuffle are identical.
// No em dashes in any user-facing text.

import SwiftUI

struct DailyChallengeView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var storeManager: StoreManager

    @State private var selectedOption: Int? = nil
    @State private var answered = false

    private enum Keys {
        /// Namespaced per account: one learner's completed challenge
        /// must never show as completed for another learner.
        static func completed(for dayKey: String) -> String {
            AccountScopedStorage.currentKey("pf.dailyChallenge.completed.\(dayKey).v1")
        }
        static func correct(for dayKey: String) -> String {
            AccountScopedStorage.currentKey("pf.dailyChallenge.correct.\(dayKey).v1")
        }
    }

    /// Calendar day key, local time, for example 2026-11-11.
    private var dayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Days since the epoch, local calendar: the deterministic seed.
    private var dayNumber: Int {
        let start = Calendar.current.startOfDay(for: Date())
        let epoch = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 0))
        return Calendar.current.dateComponents([.day], from: epoch, to: start).day ?? 0
    }

    /// All real situations, full data first, search index fallback.
    private var situations: [Situation] {
        if let full = contentService.fullSituations, !full.isEmpty {
            return full.map { situation(fromFull: $0) }
        }
        return contentService.allSituations.map { situation(from: $0) }
    }

    // MARK: - Entitlement gate (v70)

    /// The situations a learner may see in this challenge. Entitled
    /// learners get the input unchanged, in catalogue order, so
    /// their pick, options and shuffle are byte-identical to the
    /// ungated behavior. Everyone else gets only the free samples
    /// (flagged by situation(from:) and situation(fromFull:) from
    /// ContentService.freeSampleIDs) plus this week's free case.
    /// A nil or unknown weekly case id leaves only the free
    /// samples: the gate never invents a situation and never falls
    /// back to locked content. Pure, so it is covered by unit tests.
    static func eligiblePool(
        from situations: [Situation],
        isSituationsUnlocked: Bool,
        weeklyCaseID: String?
    ) -> [Situation] {
        guard !isSituationsUnlocked else { return situations }
        return situations.filter { situation in
            if situation.isFreeSample { return true }
            guard let weeklyCaseID else { return false }
            return situation.id == weeklyCaseID
        }
    }

    /// This week's free case id, picked exactly the way
    /// WeeklyFreeCaseView picks it: the dedicated 52-case weekly
    /// list wins when it has loaded, otherwise the catalogue
    /// fallback. No second cycle rule lives here: the selector is
    /// WeeklyFreeCaseSelector in both places, over the same
    /// orders (weekly list in week order, catalogue order).
    private var weeklyCaseID: String? {
        if let weekly = contentService.weeklyCases, !weekly.isEmpty {
            return WeeklyFreeCaseSelector.situationID(from: weekly.map(\.id), on: Date())
        }
        return WeeklyFreeCaseSelector.situationID(from: situations.map(\.id), on: Date())
    }

    /// This week's free case from the dedicated weekly list, when
    /// it has loaded. Only needed when the catalogue source has
    /// not loaded the full data yet: the weekly item then carries
    /// the full explain and takeaway the search index excerpt
    /// cannot. Nil when the weekly list has not loaded, in which
    /// case the weekly case already sits in `situations` through
    /// the catalogue fallback pick.
    private var weeklyListSituation: Situation? {
        guard let weekly = contentService.weeklyCases, !weekly.isEmpty,
              let pickedID = WeeklyFreeCaseSelector.situationID(from: weekly.map(\.id), on: Date()),
              let item = weekly.first(where: { $0.id == pickedID }) else { return nil }
        return situation(fromFull: item)
    }

    /// The pick pool for this challenge. For entitled learners it
    /// is exactly `situations`: the weekly case is never appended
    /// for them, so the pool order and count stay exactly the
    /// catalogue order and the deterministic pick is unchanged.
    /// For everyone else the weekly case is appended when it
    /// comes from the dedicated weekly list and is not already in
    /// the catalogue source, so it is never missing from the
    /// pool, and the gate then keeps only the free samples plus
    /// that case. The pick logic lives in this view, not in a
    /// shared file, so the gate is applied here, before pick and
    /// display, and every display path below reads from this pool.
    private var eligibleSituations: [Situation] {
        let unlocked = storeManager.isSituationsUnlocked
        var source = situations
        if !unlocked,
           let weekly = weeklyListSituation,
           !source.contains(where: { $0.id == weekly.id }) {
            source.append(weekly)
        }
        return Self.eligiblePool(from: source, isSituationsUnlocked: unlocked, weeklyCaseID: weeklyCaseID)
    }

    /// Today's situation, deterministic by day. For non-entitled
    /// learners the day number cycles within the small free pool,
    /// so the same free case repeats across days: that is the
    /// documented fallback for the small pool, never a fallback
    /// to locked content.
    private var todaysSituation: Situation? {
        guard !eligibleSituations.isEmpty else { return nil }
        return eligibleSituations[dayNumber % eligibleSituations.count]
    }

    /// The four answer options: today's takeaway plus three other real
    /// takeaways, shuffled deterministically by the day number.
    /// Every option comes from the gated pool, so a non-entitled
    /// learner never sees a locked takeaway as a distractor.
    private var options: [(text: String, isCorrect: Bool)] {
        guard let today = todaysSituation else { return [] }
        let pool = eligibleSituations
        var result: [(String, Bool)] = [(firstSentence(of: today.takeaway), true)]
        let offsets = [97, 211, 331]
        for offset in offsets {
            let other = pool[(dayNumber + offset) % pool.count]
            guard other.id != today.id else { continue }
            let text = firstSentence(of: other.takeaway)
            if !result.contains(where: { $0.0 == text }) {
                result.append((text, false))
            }
        }
        // Small-pool fill: with only 6 or 7 free cases the fixed
        // offsets can land on the same case twice, leaving fewer
        // than four options. Walk the pool in day order until
        // there are four options or the pool is exhausted. With
        // the full catalogue the offset loop already yields four,
        // so this never runs for entitled learners.
        if result.count < 4 {
            var step = 1
            while result.count < 4 && step <= pool.count {
                let other = pool[(dayNumber + step) % pool.count]
                step += 1
                guard other.id != today.id else { continue }
                let text = firstSentence(of: other.takeaway)
                if !result.contains(where: { $0.0 == text }) {
                    result.append((text, false))
                }
            }
        }
        var shuffled = result
        var seed = UInt64(bitPattern: Int64(dayNumber &+ 1))
        for index in stride(from: shuffled.count - 1, through: 1, by: -1) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let swap = Int(seed % UInt64(index + 1))
            shuffled.swapAt(index, swap)
        }
        return shuffled
    }

    /// First sentence of a takeaway, capped so an option stays readable.
    private func firstSentence(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "See the situation takeaway." }
        if let range = trimmed.range(of: ". ") {
            let first = String(trimmed[..<range.lowerBound])
            if first.count >= 20 { return first + "." }
        }
        if trimmed.count > 200 {
            return String(trimmed.prefix(200)) + "..."
        }
        return trimmed
    }

    /// The scenario text: the opening of the explain, before the
    /// structured breakdown, so the question does not give the answer away.
    private var scenarioText: String {
        guard let today = todaysSituation else { return "" }
        let paragraphs = today.explain
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let opening = paragraphs.prefix(2).joined(separator: "\n\n")
        return opening.isEmpty ? today.explain : opening
    }

    private var alreadyCompletedToday: Bool {
        UserDefaults.standard.bool(forKey: Keys.completed(for: dayKey))
    }

    private var wasCorrectToday: Bool {
        UserDefaults.standard.bool(forKey: Keys.correct(for: dayKey))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.xl) {
                headerSection
                if contentService.searchIndex == nil && situations.isEmpty {
                    HStack(spacing: PFSpacing.sm) {
                        ProgressView()
                        Text("Loading today's challenge...")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                    }
                } else if let today = todaysSituation {
                    challengeCard(situation: today)
                } else {
                    Text("Today's challenge is not available yet. Check your connection and try again.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                }
            }
            .padding(PFSpacing.lg)
        }
        // Copy protection: the challenge case cannot be selected, a
        // faint identity watermark sits over it, and recording blurs
        // it out.
        .pfProtectedContent()
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle("Daily Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Adopt any pre-namespacing challenge records into the
            // current namespace once; a no-op once adopted.
            AccountScopedStorage.adoptLegacyKeys(withPrefix: "pf.dailyChallenge.")
            // Analytics, consent-gated by the service: the
            // challenge was viewed.
            AnalyticsService.shared.recordChallengeViewed()
            if alreadyCompletedToday {
                answered = true
            }
        }
        .task {
            // The weekly free case id prefers the dedicated weekly
            // list; load it so the gate uses the same weekly case
            // WeeklyFreeCaseView shows. Idempotent: a loaded list
            // is never fetched again. Until it loads, the
            // catalogue fallback pick applies, exactly as in the
            // weekly view.
            await contentService.loadWeeklyCases()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text("One real case, 3 to 5 minutes")
                .font(.pfScreenTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Text(storeManager.isSituationsUnlocked
                ? "A new situation every day, the same one for every learner. Read the case, pick the key lesson, then check yourself against the situation's own takeaway."
                : "A new free case every day, drawn from the free samples and this week's free case. Read the case, pick the key lesson, then check yourself against the situation's own takeaway.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if alreadyCompletedToday {
                PFPill(
                    text: wasCorrectToday ? "Completed today, correct" : "Completed today",
                    background: Color.pfSuccess.opacity(0.12),
                    foreground: .pfSuccess
                )
            }
        }
    }

    // MARK: - Challenge

    private func challengeCard(situation: Situation) -> some View {
        VStack(alignment: .leading, spacing: PFSpacing.lg) {
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.md) {
                    HStack(spacing: PFSpacing.sm) {
                        PFPill(text: situation.stageName)
                        PFPill(
                            text: situation.level.displayName,
                            background: Color.pfGoldSoft,
                            foreground: Color.pfGoldText
                        )
                        if let schemeName = scheme(for: situation) {
                            PFPill(text: schemeName)
                        }
                    }
                    Text(situation.title)
                        .font(.pfSectionTitle)
                        .foregroundColor(.pfNavy)
                        .fixedSize(horizontal: false, vertical: true)
                    PFBodyText(text: scenarioText)
                }
            }
            Text("What is the key lesson here?")
                .font(.pfSectionTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let isSelected = selectedOption == index
                let showResult = answered
                let border: Color = {
                    if showResult && option.isCorrect { return .pfSuccess }
                    if showResult && isSelected { return .pfError }
                    if isSelected { return .pfRoyal }
                    return .pfBorder
                }()
                Button {
                    guard !answered else { return }
                    selectedOption = index
                } label: {
                    HStack(alignment: .top, spacing: PFSpacing.sm) {
                        Image(systemName: showResult && option.isCorrect
                            ? "checkmark.circle.fill"
                            : showResult && isSelected ? "xmark.circle.fill"
                            : isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(showResult && option.isCorrect ? .pfSuccess
                                : showResult && isSelected ? .pfError
                                : isSelected ? .pfRoyal : .pfSecondaryText)
                            .padding(.top, 2)
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
                            .stroke(border, lineWidth: isSelected || (showResult && option.isCorrect) ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(answered)
            }
            if !answered {
                PFPrimaryButton(title: "Check my answer") {
                    guard let selectedOption else { return }
                    answered = true
                    let correct = options[selectedOption].isCorrect
                    UserDefaults.standard.set(true, forKey: Keys.completed(for: dayKey))
                    UserDefaults.standard.set(correct, forKey: Keys.correct(for: dayKey))
                    // Analytics, consent-gated by the service: the
                    // challenge was answered. No case text is sent.
                    AnalyticsService.shared.recordChallengeCompleted(correct: correct)
                }
                .disabled(selectedOption == nil)
                .opacity(selectedOption == nil ? 0.5 : 1)
            }
            if answered {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text(selectedOption.map { options[$0].isCorrect } == true
                            ? "Correct. That is the key lesson of this situation."
                            : "Not this time. Here is the situation's own takeaway.")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        PFBodyText(text: situation.takeaway)
                        // The detail is opened without the weekly-path
                        // flag on purpose: the D101 gate treats the
                        // weekly case as free only on the weekly path,
                        // and any other path stays gated. A weekly
                        // case reached from this challenge therefore
                        // shows the locked gate in the detail, which
                        // is the conservative option. Free samples
                        // open fully, as they do everywhere.
                        NavigationLink(destination: SituationDetailView(situation: situation)) {
                            Text("Open the full situation")
                                .font(.pfBody.weight(.semibold))
                                .foregroundColor(.pfRoyal)
                        }
                    }
                }
            }
        }
    }
}
