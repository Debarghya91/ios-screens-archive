// PracticeMode.swift
// PaymentForge iOS - Practice Mode for Payment Situations.
// A learner reads a real situation, decides what to do next, and only
// then sees the recommended solution. Nothing here is invented: the
// correct option is the situation's own takeaway, and every wrong
// option is the takeaway of another real situation, chosen
// deterministically the same way DailyChallengeView does it. A
// situation with no takeaway is not eligible for Practice Mode and is
// excluded, never faked.
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

    /// True when a situation can be practised: it has a non-empty
    /// takeaway and at least three other real situations have a
    /// distinct takeaway to use as distractors.
    static func isEligible(_ situation: Situation, in allSituations: [Situation]) -> Bool {
        decision(for: situation, in: allSituations) != nil
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
