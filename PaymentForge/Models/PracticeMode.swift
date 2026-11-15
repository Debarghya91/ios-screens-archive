// PracticeMode.swift
// Payments Training Hub iOS - Practice Mode for Payment Situations.
// A learner reads a real situation, decides what to do next, and only
// then sees the recommended solution. Nothing here is invented: the
// correct option is the situation's own takeaway, and every wrong
// option is the takeaway of another real situation, chosen
// deterministically the same way DailyChallengeView does it. A
// situation with no takeaway is not eligible for Practice Mode and is
// excluded, never faked.
// Gating (v70): the eligible pool and the gated decision builder
// below are the single gate for Practice Mode. Entitled learners
// keep the full list; everyone else practises only the free
// samples plus this week's free case, and no distractor ever
// comes from a locked situation. The view gates itself through
// these functions, so every entry respects the same rule.
// No em dashes in any user-facing text.

import Foundation

// MARK: - Decision

/// One practice decision for a situation: the prompt, four options
/// taken from real takeaways, and which option is the situation's own.
struct PracticeDecision: Identifiable, Hashable {
    let id: String
    let situationID: String
    /// "What would you do next?" for this situation.
    let prompt: String
    /// Four options: the situation's own takeaway plus three other
    /// real situations' takeaways, in deterministic shuffled order.
    let options: [String]
    let correctOptionIndex: Int
    /// The full takeaway of this situation, shown as the explanation
    /// after the learner decides.
    let explanation: String
}

/// One recorded practice attempt, stored locally and mirrored to
/// Supabase when the learner is signed in. Guests keep local only.
struct PracticeAttempt: Identifiable, Codable, Hashable {
    let id: UUID
    let situationID: String
    /// The signed-in user id, nil for a guest attempt.
    let userID: String?
    let chosenOptionIndex: Int
    let isCorrect: Bool
    let timestamp: Date
    /// True once this attempt has been mirrored to Supabase.
    var synced: Bool

    init(
        id: UUID = UUID(),
        situationID: String,
        userID: String?,
        chosenOptionIndex: Int,
        isCorrect: Bool,
        timestamp: Date = Date(),
        synced: Bool = false
    ) {
        self.id = id
        self.situationID = situationID
        self.userID = userID
        self.chosenOptionIndex = chosenOptionIndex
        self.isCorrect = isCorrect
        self.timestamp = timestamp
        self.synced = synced
    }
}

// MARK: - Builder

/// Builds practice decisions from real situations only.
enum PracticeModeBuilder {

    // MARK: - Gating (v70)

    /// The situations a learner may practise, given entitlement.
    /// Entitled learners (the situations product owned, the
    /// Integrated Course owned, or a server entitlement, all
    /// folded into StoreManager.isSituationsUnlocked by the
    /// caller) keep the full list, unchanged and in order.
    /// Everyone else keeps only the free samples plus this
    /// week's free case. A situation counts as a free sample
    /// when its isFreeSample flag is set or its id is in the
    /// free sample list, so a situation built by either
    /// constructor is recognised either way. The weekly case
    /// id is supplied by the caller, picked with
    /// WeeklyFreeCaseSelector, the same selector the weekly
    /// free case screen uses; nil means no weekly case is
    /// known, and only the free samples remain. Nothing is
    /// ever added back: a weekly id that is not in the list
    /// contributes no situation.
    static func eligiblePool(
        from allSituations: [Situation],
        isSituationsUnlocked: Bool,
        weeklyCaseID: String?,
        freeSampleIDs: Set<String> = Set(ContentService.freeSampleIDs)
    ) -> [Situation] {
        guard !isSituationsUnlocked else { return allSituations }
        return allSituations.filter { situation in
            if situation.isFreeSample || freeSampleIDs.contains(situation.id) { return true }
            guard let weeklyCaseID else { return false }
            return situation.id == weeklyCaseID
        }
    }

    /// True when Practice Mode must not show this situation's
    /// content to this learner: the v69 hard gate predicate,
    /// with the weekly case identified by id instead of by the
    /// weekly path flag, because Practice Mode is reached from
    /// several entries and none of them passes that flag.
    /// Locked means not a free sample, not this week's free
    /// case, and Payment Situations not unlocked.
    static func isLocked(
        _ situation: Situation,
        isSituationsUnlocked: Bool,
        weeklyCaseID: String?,
        freeSampleIDs: Set<String> = Set(ContentService.freeSampleIDs)
    ) -> Bool {
        guard !isSituationsUnlocked else { return false }
        if situation.isFreeSample || freeSampleIDs.contains(situation.id) { return false }
        if let weeklyCaseID, situation.id == weeklyCaseID { return false }
        return true
    }

    /// True when a situation can be practised: it has a non-empty
    /// takeaway and at least three other real situations have a
    /// distinct takeaway to use as distractors.
    static func isEligible(_ situation: Situation, in allSituations: [Situation]) -> Bool {
        decision(for: situation, in: allSituations) != nil
    }

    /// True when a situation can be practised by this learner:
    /// it is in the eligible pool and a decision can be built
    /// from that pool alone. Entitled learners get the same
    /// answer as the ungated check above, because their pool
    /// is the full list.
    static func isEligible(
        _ situation: Situation,
        in allSituations: [Situation],
        isSituationsUnlocked: Bool,
        weeklyCaseID: String?,
        freeSampleIDs: Set<String> = Set(ContentService.freeSampleIDs)
    ) -> Bool {
        decision(
            for: situation,
            in: allSituations,
            isSituationsUnlocked: isSituationsUnlocked,
            weeklyCaseID: weeklyCaseID,
            freeSampleIDs: freeSampleIDs
        ) != nil
    }

    /// Build the decision for one situation from the eligible
    /// pool only, or nil when the situation is locked for this
    /// learner or no decision can be built from the pool.
    /// Entitled learners get the same decision the ungated
    /// builder returns, because the pool is the full list.
    /// Non-entitled learners get a decision whose correct
    /// option and every distractor come only from free sample
    /// and weekly case takeaways. Never falls back to locked
    /// content: a pool too small to build four distinct
    /// options yields nil, and the view shows its locked or
    /// not eligible state instead.
    static func decision(
        for situation: Situation,
        in allSituations: [Situation],
        isSituationsUnlocked: Bool,
        weeklyCaseID: String?,
        freeSampleIDs: Set<String> = Set(ContentService.freeSampleIDs),
        seedSalt: UInt64 = 0
    ) -> PracticeDecision? {
        let pool = eligiblePool(
            from: allSituations,
            isSituationsUnlocked: isSituationsUnlocked,
            weeklyCaseID: weeklyCaseID,
            freeSampleIDs: freeSampleIDs
        )
        guard let focal = pool.first(where: { $0.id == situation.id }) else { return nil }
        return decision(for: focal, in: pool, seedSalt: seedSalt)
    }

    /// Build the decision for one situation, or nil when it is not
    /// eligible. `seedSalt` lets the knowledge-assessment recall
    /// question reuse the same option pool in a different order.
    static func decision(
        for situation: Situation,
        in allSituations: [Situation],
        seedSalt: UInt64 = 0
    ) -> PracticeDecision? {
        let correctText = firstSentence(of: situation.takeaway)
        guard !correctText.isEmpty, correctText.count >= 10 else { return nil }
        guard let ownIndex = allSituations.firstIndex(where: { $0.id == situation.id }) else { return nil }

        // Three distractors: takeaways of other real situations at
        // deterministic offsets from this situation's index, the same
        // approach DailyChallengeView uses. A distractor is skipped
        // when it is empty, too short, or identical to the correct
        // option or to a distractor already picked.
        var pool: [(text: String, isCorrect: Bool)] = [(correctText, true)]
        let offsets = [97, 211, 331, 53, 149, 271, 17, 401]
        for offset in offsets {
            guard pool.count < 4 else { break }
            let other = allSituations[(ownIndex + offset) % allSituations.count]
            guard other.id != situation.id else { continue }
            let text = firstSentence(of: other.takeaway)
            guard text.count >= 10 else { continue }
            guard !pool.contains(where: { $0.text == text }) else { continue }
            pool.append((text, false))
        }
        // Small-pool fallback: with only six or seven situations
        // (the free pool for a non-entitled learner), the offsets
        // above visit only a few distinct neighbours. With six,
        // every offset lands on one of two neighbours, so the
        // decision would always fail. Scan the list in order for
        // the remaining distinct distractors. This runs only
        // when the offsets left the pool short, so the full
        // list keeps exactly the distractors it had before.
        if pool.count < 4 {
            for other in allSituations {
                guard pool.count < 4 else { break }
                guard other.id != situation.id else { continue }
                let text = firstSentence(of: other.takeaway)
                guard text.count >= 10 else { continue }
                guard !pool.contains(where: { $0.text == text }) else { continue }
                pool.append((text, false))
            }
        }
        guard pool.count == 4 else { return nil }

        let shuffled = deterministicShuffle(pool, seed: stableSeed(for: situation.id) &+ seedSalt)
        guard let correctIndex = shuffled.firstIndex(where: { $0.isCorrect }) else { return nil }
        return PracticeDecision(
            id: "practice-\(situation.id)-\(seedSalt)",
            situationID: situation.id,
            prompt: "What would you do next?",
            options: shuffled.map { $0.text },
            correctOptionIndex: correctIndex,
            explanation: situation.takeaway
        )
    }

    /// First sentence of a takeaway, capped so an option stays
    /// readable. Same rule as DailyChallengeView.
    static func firstSentence(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let range = trimmed.range(of: ". ") {
            let first = String(trimmed[..<range.lowerBound])
            if first.count >= 20 { return first + "." }
        }
        if trimmed.count > 200 {
            return String(trimmed.prefix(200)) + "..."
        }
        return trimmed
    }

    /// A stable 64-bit hash of a string (FNV-1a). Swift's own
    /// hashValue is randomised per launch, so it must never be used
    /// for a seed that has to be the same every time.
    static func stableSeed(for text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    /// Deterministic shuffle (Fisher-Yates with a linear
    /// congruential generator), so the same situation always shows
    /// the same option order on every device.
    static func deterministicShuffle<T>(_ items: [T], seed: UInt64) -> [T] {
        var shuffled = items
        var state = seed &+ 1
        guard shuffled.count > 1 else { return shuffled }
        for index in stride(from: shuffled.count - 1, through: 1, by: -1) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let swap = Int(state % UInt64(index + 1))
            shuffled.swapAt(index, swap)
        }
        return shuffled
    }
}
