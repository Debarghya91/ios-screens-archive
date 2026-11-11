// ChatAnswerPipeline.swift
// PaymentForge iOS - Local answer pipeline for the chat assistant.
// This is the RETRIEVAL layer of the hybrid chatbot: it finds the
// course passages that answer a question and formats them as a
// professional local answer. A free LLM (through the chat-assistant
// edge function) may rewrite the same passages into a polished
// answer; when that call is slow or fails, this local answer is
// shown instead, so the chatbot never breaks. Everything here is
// local and token-free: no network, no API key, no AI call.
// The pipeline mirrors test-chatbot-v27.py in the project folder,
// which proves it against the live index (25/25 questions).
// Guardrails: answers only from course content, never invented.
// No em dashes in any user-facing text.

import Foundation

/// The question intent, detected from the wording. It decides
/// which entries rank first and which passages answer.
enum ChatQuestionIntent: String {
    case definition
    case comparison
    case how
    case why
    case general
}

/// One ranked candidate for the chatbot: the catalogue entry, its
/// total score (base search score plus intent boost), and the
/// intent boost alone, for debugging.
struct ChatCandidate {
    let entry: SearchEntry
    let score: Int
    let intentBoost: Int
}

/// One passage that answers the question, with the entry it came
/// from, so the answer can name the right source.
struct ChatPassage {
    let entry: SearchEntry
    let text: String
}

/// The local answer: the formatted text, the source entries in
/// order, and two follow-up questions a learner would ask next.
struct ChatLocalAnswer {
    let text: String
    let sources: [SearchEntry]
    let followUps: [String]
}

enum ChatAnswerPipeline {
    // MARK: - Intent

    /// Words that carry no meaning on their own in a question.
    /// Shared with SearchService.stopWords; kept here so the
    /// pipeline does not depend on the search internals.
    static let stopWords: Set<String> = SearchService.stopWords

    /// Multi-word subjects a question can name, longest first in
    /// use. "SEPA Instant" is one subject, not two words.
    static let phraseSubjects: [String] = [
        "iso 20022", "sepa instant", "sct inst", "faster payments",
        "nostro account", "vostro account", "retrieval reference",
        "payment stuck", "duplicate payment"
    ]

    /// Words that mark a failure or exception question.
    static let whyWords: [String] = [
        "reject", "rejected", "rejection", "refused", "refusal", "reason code", "failed", "failure",
        "stuck", "pending", "held", "duplicate", "duplicated", "timeout", "timed out",
        "error", "exception", "returned", "bounced", "missing", "not credited"
    ]

    /// Words that mark a how-it-works explanation.
    static let howWords: [String] = [
        "work", "works", "flow", "step", "steps", "process", "first", "then", "next"
    ]

    /// Titles that name a sub-topic, not the topic itself. A bare
    /// definition question ("What is UPI?") must not rank a
    /// sub-topic lesson (UPI Mandate) above the UPI introduction.
    static let subtopicMarkers: [String] = [
        "mandate", "autopay", "request to pay", "worked example",
        "checklist", "line by line"
    ]

    /// Synonyms of a why-question's problem word, so "stuck" also
    /// matches a passage about a payment "pending" or "held".
    static let whySynonyms: [String: [String]] = [
        "reject": ["reject", "rejected", "rejection"],
        "stuck": ["stuck", "pending", "held"],
        "pending": ["pending", "stuck", "held"],
        "duplicat": ["duplicat", "duplicate", "duplicated"],
        "fail": ["fail", "failed", "failure"],
        "timeout": ["timeout", "timed out"],
        "missing": ["missing", "not credited"]
    ]

    /// Words that are question phrasing, not the topic: "What does
    /// X mean?" is about X, not about "mean"; "How does X work?"
    /// is about X, not about "work". Excluded from the coverage
    /// count, so a candidate is not required to contain them.
    static let phrasingWords: Set<String> = [
        "mean", "means", "called", "known", "refers",
        "define", "definition", "explain", "explains",
        "work", "works", "happen", "happens",
        // v29: "What fields does a pacs.008 contain?" is about
        // pacs.008 fields, not about "contain"; "What is a
        // camt.053 used for?" is about camt.053, not "used".
        "contain", "contains", "used", "use", "uses"
    ]

    /// Words that are never the topic on their own (pronouns,
    /// auxiliaries, filler). Excluded when picking the distinctive
    /// term.
    static let weakWords: Set<String> = [
        "mean", "means", "called", "known", "refers",
        "define", "definition", "explain", "explains",
        "work", "works", "happen", "happens",
        "my", "was", "were", "so", "long", "taking", "say", "said",
        "could", "would", "should", "can", "happened", "case", "where",
        "when", "if", "me", "i", "you", "he", "she", "we", "they",
        "it", "its", "this", "that", "there", "here", "then", "than",
        "just", "only", "also", "even", "still", "already", "yet",
        "ever", "never", "always", "often", "sometimes", "usually",
        "first", "second", "next", "now", "today", "soon", "later",
        "early", "late", "before", "after", "during", "while", "until",
        "since", "ago"
    ]

    /// ISO reason codes a learner may ask about by code.
    static let reasonCodes: Set<String> = [
        "ac01", "ac02", "ac03", "ac04", "ac05", "ac06", "am05", "ag01", "ag02",
        "be01", "be04", "be05", "ff01", "ff02", "md01", "md02", "md07", "ms02", "ms03",
        "narr", "rc01", "rr01", "rr02", "rr03", "rr04", "tm01", "ed05"
    ]

    static func detectIntent(_ question: String) -> ChatQuestionIntent {
        let n = question.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if n.contains(" vs ") || n.contains(" vs.") || n.hasSuffix(" vs")
            || n.contains("versus") || n.contains("difference between")
            || n.hasPrefix("compare ") {
            return .comparison
        }
        if n.hasPrefix("why ") || n.hasPrefix("what happens if")
            || n.hasPrefix("what happens when") || n.hasPrefix("what if ")
            || n.hasPrefix("what happened") {
            return .why
        }
        if n.hasPrefix("how does") || n.hasPrefix("how do") || n.hasPrefix("how is")
            || n.hasPrefix("how can") || n.hasPrefix("how to") || n.hasPrefix("how would") {
            return .how
        }
        if n.hasPrefix("what is") || n.hasPrefix("what does") || n.hasPrefix("what are")
            || n.hasPrefix("what do") || n.hasPrefix("define") || n.hasPrefix("meaning of")
            || n.hasPrefix("explain what") {
            return .definition
        }
        let words = contentWords(n)
        if words.count <= 2 {
            return .definition
        }
        return .general
    }

    /// Content words: the question split on spaces, trailing
    /// punctuation stripped, stop words removed.
    static func contentWords(_ question: String) -> [String] {
        let n = question.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return n.split(separator: " ").map { word in
            String(word).trimmingCharacters(in: CharacterSet(charactersIn: "?!.,;:"))
        }.filter { $0.count >= 2 && !stopWords.contains($0) }
    }

    /// The main subject of the question: a message code, a known
    /// multi-word phrase, the problem word for a why-question, else
    /// the first content word.
    static func subjectTerm(_ question: String, intent: ChatQuestionIntent) -> String {
        let codes = SearchService.messageCodes(in: question)
        if let first = codes.first {
            return first
        }
        let n = question.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for phrase in phraseSubjects where n.contains(phrase) {
            return phrase
        }
        let words = contentWords(n)
        if intent == .why {
            // v29: "times out" / "timed out" is the same problem as
            // "timeout", but the two-word form never matches a
            // "timeout" passage by stem.
            if n.contains("times out") || n.contains("timed out") || n.contains("time out") {
                return "timeout"
            }
            for word in words {
                if word.hasPrefix("reject") || word.hasPrefix("refus")
                    || word.hasPrefix("duplicat")
                    || word.hasPrefix("stuck") || word.hasPrefix("pending")
                    || word.hasPrefix("fail") || word.hasPrefix("timeout")
                    || word.hasPrefix("missing") {
                    return word
                }
            }
            // v29: no problem word ("Why is my refund taking so
            // long?", "What happened in this case: ..."): the last
            // word ("long", "was") is filler, not the topic.
            // Return the first topic word instead ("refund").
            // distinctiveTerm (which has the index) picks the
            // rarest topic word for the coverage gate.
            return topicWords(question).first ?? words.last ?? ""
        }
        return words.first ?? ""
    }

    /// Topic words: content words minus phrasing/weak words, the
    /// words that name what the question is actually about.
    static func topicWords(_ question: String) -> [String] {
        contentWords(question).filter { !weakWords.contains($0) }
    }

    /// The word that distinguishes one side from the other: the
    /// first word of the side the other side does not share
    /// ("debit" for "debit card" vs "credit card"; "instant" for
    /// "sepa instant" vs "sepa"). The old last-word/first-word
    /// rule returned the shared word ("card" for "debit card" vs
    /// "credit card", "sepa" for both sides of "sepa" vs "sepa
    /// instant"), so ranking rewarded entries that named the
    /// shared word instead of the two things being compared.
    static func distinctiveSideWord(_ side: String, other: String) -> String {
        let words = side.split(separator: " ").map(String.init).filter { !stopWords.contains($0) }
        let otherWords = Set(other.split(separator: " ").map(String.init))
        for word in words where !otherWords.contains(word) {
            return word
        }
        return words.last ?? side
    }

    /// The two sides of a comparison question, as search terms.
    /// For codes the canonical codes are returned; for words the
    /// distinguishing word of each side (see distinctiveSideWord).
    static func comparisonSides(_ question: String) -> (String, String)? {
        let n = question.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let codes = SearchService.messageCodes(in: n)
        if codes.count >= 2 {
            return (codes[0], codes[1])
        }
        // "X vs Y" or "X versus Y": the distinguishing word of
        // each side ("cover vs serial payment" is cover and serial).
        let separators = [" vs ", " vs. ", " versus "]
        for separator in separators {
            let parts = n.components(separatedBy: separator)
            guard parts.count == 2 else { continue }
            let left = parts[0]
                .replacingOccurrences(of: #"^(what is|what are|difference between|compare|how do|how does)\s+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "?!.,;:"))
            let right = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "?!.,;:"))
            if !left.isEmpty, !right.isEmpty {
                return (distinctiveSideWord(left, other: right), distinctiveSideWord(right, other: left))
            }
        }
        if n.contains("difference between") {
            let rest = n.replacingOccurrences(of: "difference between", with: "").trimmingCharacters(in: .whitespaces)
            let parts = rest.components(separatedBy: " and ")
            if parts.count >= 2 {
                return (distinctiveSideWord(parts[0], other: parts[1]), distinctiveSideWord(parts[1], other: parts[0]))
            }
        }
        return nil
    }

    // MARK: - Intent-aware ranking

    /// Additive boosts on top of the SearchService score. Sized to
    /// break the 850-900 ties decisively, not to override a much
    /// stronger base match. `specificTopics` is the question's
    /// topic words named by fewer than 300 index entries,
    /// precomputed once by rankedCandidates (computing them per
    /// entry would rescan the index every time).
    static func intentBoost(entry: SearchEntry, question: String, intent: ChatQuestionIntent, codes: [String], specificTopics: Set<String> = []) -> Int {
        let title = entry.title.lowercased()
        let text = entry.text.lowercased()
        let body = entry.bodyText.lowercased()
        let subject = subjectTerm(question, intent: intent)
        var boost = 0
        switch intent {
        case .definition:
            if !subject.isEmpty {
                // v29: the defining-source boosts are scaled by how
                // much of the title is actually the subject
                // (titleMatch). A guide titled "SWIFT Payments
                // Explained" only matches 1 of 2 words for the
                // subject "payment", so it no longer outranks the
                // lesson "A payment, in plain words".
                let match = titleMatch(entry: entry, subject: subject)
                if entry.type == .faq && title.hasPrefix("what is") && title.contains(subject) {
                    boost += Int((1200 * match).rounded())
                }
                if entry.type == .guide && title.contains("explained") && title.contains(subject) {
                    boost += Int((1100 * match).rounded())
                }
                if entry.type == .lesson && title.hasPrefix("what " + subject) {
                    boost += Int((600 * match).rounded())
                }
                if entry.type == .lesson
                    && (title == subject || title.hasPrefix(subject + " architecture")
                        || title.hasPrefix(subject + ":") || title.hasPrefix(subject + " ")) {
                    if body.prefix(250).contains(subject) {
                        boost += Int((600 * match).rounded())
                    }
                }
                // v29: a title naming every content word of the
                // question is the definition asked for ("A payment,
                // in plain words", "Value date, finality and
                // irrevocability").
                if titleContainsAllWords(entry: entry, words: contentWords(question)) {
                    boost += 700
                }
                // v29: a reason code is a precise subject. An entry
                // that names the code (a situation about AC04) must
                // outrank generic entries that merely share the
                // question word "mean". Message codes are already
                // covered by the guide/lesson rules above; this
                // fills the reason-code gap.
                if reasonCodes.contains(subject) {
                    if title.contains(subject) {
                        boost += 1200
                    } else if body.contains(subject) {
                        boost += 900
                    }
                }
                // v29: a definition wants the concept, not a case
                // story ("What is types of bank cheques?" must rank
                // the lesson above a situation about one foreign
                // cheque).
                if entry.type == .situation {
                    boost -= 300
                }
                if subtopicMarkers.contains(where: { title.contains($0) }) {
                    boost -= 500
                }
                if body.prefix(300).contains(subject),
                   body.prefix(300).range(of: #"\b\#(NSRegularExpression.escapedPattern(for: subject))\b (is|means|refers to|is a|is an|is the)\b"#, options: .regularExpression) != nil {
                    boost += 300
                }
            }
        case .comparison:
            if let sides = comparisonSides(question) {
                // v29 round 5: whole-word matching. Substring
                // matching let 'standing' match inside
                // 'understanding', so a clearing-system FAQ about
                // direct vs indirect participation outranked the
                // direct-debit content for 'direct debit vs
                // standing order'.
                if wordPresent(title, word: sides.0) && wordPresent(title, word: sides.1) {
                    boost += 1500
                } else if wordPresent(text, word: sides.0) && wordPresent(text, word: sides.1) {
                    boost += 700
                }
                if title.contains("versus") || title.contains(" vs ") || title.contains("differ") || title.contains("comparison") {
                    boost += 500
                }
                if (title.contains("differ") || title.contains("versus") || title.contains("comparison"))
                    && wordPresent(text, word: sides.0) && wordPresent(text, word: sides.1) {
                    boost += 1200
                }
            }
            if entry.type == .guide && title.contains("versus") {
                boost += 400
            }
        case .how:
            if !subject.isEmpty {
                if entry.type == .faq && title.hasPrefix("how does") && title.contains(subject) {
                    boost += 1000
                }
                if entry.type == .guide && title.contains("explained") && title.contains(subject) {
                    boost += 900
                }
                if entry.type == .lesson && title.contains(subject)
                    && ["work", "architecture", "in depth", "explained", "flow"].contains(where: { title.contains($0) }) {
                    boost += 600
                }
                // v29: a how-question wants the mechanism, not a
                // case story. A situation ("The German Direct Debit
                // flow met the Dutch customer, and failed") must
                // not outrank the mechanism lesson for "How does
                // direct debit work?".
                if entry.type == .situation {
                    boost -= 300
                }
                if titleContainsAllWords(entry: entry, words: contentWords(question)) {
                    boost += 700
                }
                if subtopicMarkers.contains(where: { title.contains($0) }) {
                    boost -= 500
                }
                // The action word matters as much as the subject: a
                // question about UPI settlement must rank settlement
                // content above a plain UPI definition.
                for word in contentWords(question) where word != subject && !word.hasPrefix(String(subject.prefix(4))) {
                    if title.contains(word) || termMatches(title, term: word) {
                        boost += 600
                    } else if termMatches(text, term: word) {
                        boost += 300
                    }
                }
            }
        case .why:
            let problem = subjectTerm(question, intent: intent)
            if entry.type == .situation {
                boost += 900
            }
            if !problem.isEmpty && (title.contains(problem) || termMatches(title, term: problem)) {
                boost += 1200
            }
            if ["reject", "refus", "failure", "exception", "duplicate", "stuck", "timeout", "reason code", "investigation"].contains(where: { title.contains($0) }) {
                boost += 700
            }
            // v29: the rail/system matters too, not just the
            // problem. "Why did my UPI payment fail?" must rank a
            // UPI-failure entry above a pacs.009 failure entry. A
            // specific topic word in the title earns the boost.
            // "payment" (1,367 entries) is too generic to earn it.
            // v29 round 5: +900 was not enough. The pacs.009 cover
            // situation scored 4300 against 3600 for the UPI-failure
            // situations, so the entry that names the rail asked
            // about still lost. At +1800 the rail-naming entry wins;
            // the boost only applies to specific topic words, so
            // generic words cannot earn it.
            for word in specificTopics where word != problem && title.contains(word) {
                boost += 1800
            }
            // v29 round 5: the question quotes the exact case
            // figures ("GBP 4,500 failed three times"): an entry
            // whose title names that currency and amount IS the
            // case asked about.
            if let match = question.lowercased().range(of: #"\b(gbp|eur|usd|inr)\s+([\d,]+)"#, options: .regularExpression),
               title.contains(String(question.lowercased()[match])) {
                boost += 1500
            }
            // A why-question needs the reason, not just a story
            // about a rejection: entries whose body names a reason
            // code rank up.
            if body.contains("reason code") || body.contains("reason codes") {
                boost += 600
            }
            if entry.type == .guide && ["duplicate", "exception", "reject", "failure"].contains(where: { title.contains($0) }) {
                boost += 600
            }
        case .general:
            break
        }
        return boost
    }

    /// Ranked chatbot candidates: the base search over a 30-hit
    /// pool, plus term recall (entries whose title names a content
    /// word or a message code, recalled even when the base score
    /// ranks them below the top 30), then the intent boost.
    /// Capped at `limit` (default 5).
    static func rankedCandidates(question: String, entries: [SearchEntry], limit: Int = 5) -> [ChatCandidate] {
        let intent = detectIntent(question)
        let codes = SearchService.messageCodes(in: question)
        let terms = contentWords(question)
        let subject = subjectTerm(question, intent: intent)
        let baseHits = SearchService.search(entries: entries, query: question, limit: 30)
        var scored: [String: (score: Int, entry: SearchEntry)] = [:]
        for hit in baseHits {
            scored[hit.entry.id] = (hit.score, hit.entry)
        }
        // Term recall.
        var recall: [(score: Int, entry: SearchEntry)] = []
        for entry in entries where scored[entry.id] == nil {
            let title = entry.title.lowercased()
            let text = entry.text.lowercased()
            var recallScore = 0
            if !subject.isEmpty && termMatches(title, term: subject) {
                recallScore = max(recallScore, 1000)
            }
            for word in terms where termMatches(title, term: word) {
                recallScore = max(recallScore, 600)
            }
            for code in codes {
                let variants = SearchService.messageCodeVariants(code)
                if variants.contains(where: { title.contains($0) }) {
                    recallScore = max(recallScore, 900)
                }
            }
            if !subject.isEmpty && termMatches(text, term: subject) {
                // v29: a code subject mentioned in the body is a
                // strong match (900), not a weak one (300): the
                // AC04 entry names the code in its text, not its
                // title, and must reach the top 5 above generic
                // "mean" entries.
                let isCode = reasonCodes.contains(subject)
                    || SearchService.messageCodes(in: subject).count > 0
                recallScore = max(recallScore, isCode ? 900 : 300)
            }
            if recallScore > 0 {
                recall.append((recallScore, entry))
            }
        }
        recall.sort { $0.score > $1.score }
        for item in recall.prefix(10) {
            scored[item.entry.id] = (item.score, item.entry)
        }
        // v29: the question's specific topic words (named by fewer
        // than 300 index entries), computed once here so the why
        // boost can reward them without rescanning the index per
        // entry.
        let specificTopics = Set(topicWords(question).filter { entryHitCount($0, entries: entries) < 300 })
        var out: [ChatCandidate] = []
        for (_, value) in scored {
            let boost = intentBoost(entry: value.entry, question: question, intent: intent, codes: codes, specificTopics: specificTopics)
            out.append(ChatCandidate(entry: value.entry, score: value.score + boost, intentBoost: boost))
        }
        out.sort { $0.score > $1.score }
        return Array(out.prefix(limit))
    }

    // MARK: - Word stems

    /// Light stem for matching: settle/settled/settlement and
    /// duplicate/duplicated share a stem, so a passage about one
    /// counts for the other.
    static func wordStem(_ word: String) -> String {
        var w = word.lowercased()
        for suffix in ["ment", "ing", "edly", "ed", "es"] {
            if w.count > suffix.count + 3 && w.hasSuffix(suffix) {
                w = String(w.dropLast(suffix.count))
                break
            }
        }
        if w.count > 4 && w.hasSuffix("s") {
            w = String(w.dropLast())
        }
        return w
    }

    /// True when the term appears in the text, or a word in the
    /// text shares the term's stem.
    static func termMatches(_ text: String, term: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains(term.lowercased()) {
            return true
        }
        let stem = wordStem(term)
        guard stem.count >= 4 else { return false }
        return SearchService.titleWords(lower).contains { $0.hasPrefix(stem) }
    }

    // MARK: - Definition ranking helpers (v29)

    /// Fraction of the entry title's content words that are subject
    /// words (stem-matched). A guide titled "SWIFT Payments
    /// Explained" only matches 1 of 2 words for the subject
    /// "payment", so its definition boost is halved; a title that
    /// is exactly the subject matches 1.0.
    static func titleMatch(entry: SearchEntry, subject: String) -> Double {
        guard !subject.isEmpty else { return 0 }
        let subjectWords = subject.lowercased().split(separator: " ").map(String.init).filter { !stopWords.contains($0) }
        let titleWords = entry.title.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." })
            .map(String.init)
            .filter { !$0.isEmpty && !stopWords.contains($0) && $0 != "explained" }
        guard !titleWords.isEmpty, !subjectWords.isEmpty else { return 0 }
        let hits = titleWords.filter { tw in
            subjectWords.contains { sw in termMatches(tw, term: sw) }
        }.count
        return Double(hits) / Double(titleWords.count)
    }

    /// True when every content word of the question appears in the
    /// entry title (stem-matched). A title that names the whole
    /// question ("A payment, in plain words") is the definition
    /// asked for, even when the single subject word alone is loose.
    static func titleContainsAllWords(entry: SearchEntry, words: [String]) -> Bool {
        guard !words.isEmpty else { return false }
        let title = entry.title.lowercased()
        return words.allSatisfy { termMatches(title, term: $0) }
    }

    // MARK: - Coverage gate (v29, "I don't know")

    /// Dotted, undotted and spaced forms of a message code, so a
    /// typed "pacs008" matches the course's "pacs.008" (and vice
    /// versa). Non-codes return just the word.
    static func codeVariants(_ word: String) -> [String] {
        let lower = word.lowercased()
        let pattern = #"^(pacs|pain|camt|remt|acmt|mt)\.?(\d{3})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let familyRange = Range(match.range(at: 1), in: lower),
              let numberRange = Range(match.range(at: 2), in: lower) else {
            return [lower]
        }
        let family = String(lower[familyRange])
        let number = String(lower[numberRange])
        return ["\(family).\(number)", "\(family)\(number)", "\(family) \(number)"]
    }

    /// Whole-word, stem-aware presence. A regex match with
    /// lookaround boundaries handles hyphenated, dotted and
    /// numeric terms ("cut-off", "pacs.008", "50,000") that a
    /// plain tokenizer splits apart; a stem-prefix token match
    /// handles inflections ("duplicated" matches "duplicate").
    /// Substring matches inside longer words ("tea" in "team") do
    /// not count. v29: lookarounds, not \b, for the boundary. \b
    /// fails when the term starts or ends with a non-word
    /// character: "(mt192/195/196)" and "cbpr+" never matched, so
    /// the gate refused questions whose answer was the top entry.
    static func wordPresent(_ text: String, word: String) -> Bool {
        let lower = text.lowercased()
        for variant in codeVariants(word) {
            if variant.contains(" ") {
                if lower.contains(variant) { return true }
                continue
            }
            if lower.range(of: #"(?<![a-z0-9])\#(NSRegularExpression.escapedPattern(for: variant))(?![a-z0-9])"#, options: .regularExpression) != nil {
                return true
            }
            let stem = wordStem(variant)
            if stem.count >= 4 {
                let tokens = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." }).map(String.init)
                if tokens.contains(where: { $0.hasPrefix(stem) }) {
                    return true
                }
            }
        }
        return false
    }

    /// Number of index entries whose title or opening body mentions
    /// the term (whole word). The rarest content word is the most
    /// specific thing the question asks about. Uses the stored
    /// search text (not the computed bodyText) so the scan stays
    /// cheap over the whole index.
    static func entryHitCount(_ term: String, entries: [SearchEntry]) -> Int {
        entries.filter { entry in
            wordPresent(entry.title, word: term)
                || wordPresent(String(entry.text.prefix(1000)), word: term)
        }.count
    }

    /// The rarest of the given words (fewest index hits, ties
    /// broken by longest, then first), preferring words the index
    /// mentions at all. A word with zero hits is usually a
    /// phrasing mismatch ("misses" for the course's "missed" /
    /// "after the cut-off"), not proof the topic is absent; only
    /// when NO word is mentioned anywhere is the topic genuinely
    /// not covered.
    static func rarestWord(_ words: [String], entries: [SearchEntry]) -> String? {
        guard !words.isEmpty else { return nil }
        let withHits = words.filter { entryHitCount($0, entries: entries) > 0 }
        let pool = withHits.isEmpty ? words : withHits
        return pool.min { a, b in
            let ha = entryHitCount(a, entries: entries)
            let hb = entryHitCount(b, entries: entries)
            if ha != hb { return ha < hb }
            return a.count > b.count
        }
    }

    /// The question's most specific content word: the one fewest
    /// index entries mention. For why-questions it is the problem
    /// word, or (when there is none) the rarest topic word.
    /// Nil for comparisons (both sides are required instead).
    static func distinctiveTerm(question: String, intent: ChatQuestionIntent, entries: [SearchEntry]) -> String? {
        if intent == .comparison { return nil }
        if intent == .why {
            let words = contentWords(question)
            for word in words {
                if word.hasPrefix("reject") || word.hasPrefix("duplicat")
                    || word.hasPrefix("stuck") || word.hasPrefix("pending")
                    || word.hasPrefix("fail") || word.hasPrefix("timeout")
                    || word.hasPrefix("missing") {
                    return word
                }
            }
            return rarestWord(topicWords(question), entries: entries)
        }
        let words = topicWords(question)
        guard !words.isEmpty else { return nil }
        return rarestWord(words, entries: entries)
    }

    /// How many of the question's topic words a candidate must
    /// name: all of them up to three, then a strict majority. A
    /// 3-word question ("send money to Mars") needs all 3, so a
    /// fraud situation about sending money (2 of 3) is refused; a
    /// 4-word question ("the SWIFT code for Bank of America")
    /// needs 3, so a lesson about Bank of America that never
    /// mentions a code is refused.
    static func coverageNeeded(_ wordCount: Int) -> Int {
        if wordCount <= 3 { return wordCount }
        return wordCount / 2 + 1
    }

    /// A candidate is usable only if it covers the question: it
    /// must name the distinctive (most specific) term, and (except
    /// for why-questions, where the problem word is the whole ask,
    /// and comparisons, where the two-side rule already enforces
    /// coverage) at least coverageNeeded() of the question's
    /// content words. Without this gate, a passage that merely
    /// shares one generic word ("buy", "interest", "London") was
    /// presented as the answer to a question the course does not
    /// cover.
    static func candidateCovers(entry: SearchEntry, question: String, intent: ChatQuestionIntent, distinctive: String?) -> Bool {
        if intent == .comparison { return true }
        let text = (entry.title + " " + entry.bodyText).lowercased()
        if let distinctive {
            if intent == .why {
                let synonyms = whySynonyms[wordStem(distinctive)] ?? [distinctive]
                if !synonyms.contains(where: { wordPresent(text, word: $0) }) {
                    return false
                }
            } else if !wordPresent(text, word: distinctive) {
                return false
            }
        }
        if intent == .why { return true }
        let words = topicWords(question).isEmpty ? contentWords(question) : topicWords(question)
        guard !words.isEmpty else { return true }
        let found = words.filter { wordPresent(text, word: $0) }.count
        return found >= coverageNeeded(words.count)
    }

    // MARK: - Passage extraction

    /// One split passage from a body, with its kind. Steps are the
    /// pieces of a situation's arrow chain ("→ step → step").
    enum PassageKind {
        case sentence
        case keypoint
        case takeaway
        case step
    }

    /// Split a body into passages: sentences, "Key points" list
    /// items, the takeaway, and arrow-chain steps. Dotted message
    /// codes and decimals are protected so "pacs.008" never splits.
    static func splitPassages(_ body: String) -> [(kind: PassageKind, text: String)] {
        var protected: [String] = []
        var working = body
        // Protect dotted message codes ("pacs.008" never splits).
        if let regex = try? NSRegularExpression(pattern: #"\b(pacs|pain|camt|remt|acmt)\.(\d{3})\b"#, options: [.caseInsensitive]) {
            let matches = regex.matches(in: working, options: [], range: NSRange(working.startIndex..., in: working))
            var result = ""
            var cursor = working.startIndex
            for match in matches {
                guard let range = Range(match.range, in: working) else { continue }
                result += working[cursor..<range.lowerBound]
                protected.append(String(working[range]))
                result += "\u{0}\(protected.count - 1)\u{1}"
                cursor = range.upperBound
            }
            result += working[cursor...]
            working = result
        }
        // Protect decimals (10.5 stays one token).
        working = working.replacingOccurrences(of: #"(\d)\.(\d)"#, with: "$1\u{2}$2", options: .regularExpression)
        working = working.replacingOccurrences(of: #"\s*Key points:\s*"#, with: "\nKEYPOINTS: ", options: .regularExpression)
        working = working.replacingOccurrences(of: #"\s*Takeaway:\s*"#, with: "\nTAKEAWAY: ", options: .regularExpression)
        // Split on sentence ends followed by a capital or digit.
        let sentences = working.components(separatedBy: .newlines)
            .flatMap { line -> [String] in
                var out: [String] = []
                var current = ""
                let chars = Array(line)
                var i = 0
                while i < chars.count {
                    current.append(chars[i])
                    if (chars[i] == "." || chars[i] == "!" || chars[i] == "?") && i + 1 < chars.count && chars[i + 1] == " " {
                        // Look ahead: next non-space char starts a new sentence.
                        var j = i + 2
                        while j < chars.count && chars[j] == " " { j += 1 }
                        if j < chars.count && (chars[j].isUppercase || chars[j].isNumber || chars[j] == "\"") {
                            out.append(current.trimmingCharacters(in: .whitespaces))
                            current = ""
                            i = j
                            continue
                        }
                    }
                    i += 1
                }
                if !current.trimmingCharacters(in: .whitespaces).isEmpty {
                    out.append(current.trimmingCharacters(in: .whitespaces))
                }
                return out
            }
        func restore(_ text: String) -> String {
            var out = text
            for (index, token) in protected.enumerated() {
                out = out.replacingOccurrences(of: "\u{0}\(index)\u{1}", with: token)
            }
            return out.replacingOccurrences(of: "\u{2}", with: ".")
        }
        var out: [(kind: PassageKind, text: String)] = []
        for part in sentences {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("KEYPOINTS:") {
                let items = String(trimmed.dropFirst("KEYPOINTS:".count)).components(separatedBy: ";")
                for item in items {
                    let cleaned = item.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    if cleaned.count >= 15 {
                        out.append((.keypoint, restore(cleaned)))
                    }
                }
            } else if trimmed.hasPrefix("TAKEAWAY:") {
                out.append((.takeaway, restore(String(trimmed.dropFirst("TAKEAWAY:".count)).trimmingCharacters(in: .whitespacesAndNewlines))))
            } else if trimmed.contains("→") || trimmed.contains("->") {
                // Arrow chain: each step is its own passage.
                let steps = trimmed.components(separatedBy: "→").flatMap { $0.components(separatedBy: "->") }
                for step in steps {
                    let cleaned = step.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    if cleaned.count >= 15 {
                        out.append((.step, restore(cleaned)))
                    }
                }
            } else {
                out.append((.sentence, restore(trimmed)))
            }
        }
        return out
    }

    /// Score one passage against the question. Returns nil when the
    /// passage does not answer the question at all.
    static func passageScore(kind: PassageKind, text: String, terms: [String], codes: [String], intent: ChatQuestionIntent, subject: String, sides: (String, String)?) -> Int? {
        // v29 round 5: a heading fragment ("Duplicate prevention.")
        // is never an answer. Skip passages under 5 words.
        if text.split(separator: " ").count < 5 {
            return nil
        }
        let lower = text.lowercased()
        var score = 0
        var termHits = 0
        for term in terms where termMatches(lower, term: term) {
            termHits += 1
            score += 100
        }
        for code in codes {
            let variants = SearchService.messageCodeVariants(code)
            if variants.contains(where: { lower.contains($0) }) {
                termHits += 1
                score += 150
            }
        }
        if termHits == 0 {
            // A why-question passage that names the failure
            // mechanism (a reason code, a rejection) answers even
            // when it does not repeat the question's words.
            if intent == .why && ["reason code", "reason", "rjct", "reject", "rejected"].contains(where: { lower.contains($0) }) {
                termHits = 1
                score += 120
            } else {
                return nil
            }
        }
        if termHits == terms.count + codes.count && (!terms.isEmpty || !codes.isEmpty) {
            // v29 round 5: for a how-question the all-terms bonus
            // only applies when the passage has a mechanism word.
            // A lead-in that merely names the subject ("A retailer
            // needs a Payment API integration delivered in a
            // two-week sprint") must not outscore the passage that
            // describes the mechanism.
            if intent != .how || howWords.contains(where: { lower.contains($0) }) {
                score += 200
            }
        }
        if intent == .definition && !subject.isEmpty {
            if lower.range(of: #"\b\#(NSRegularExpression.escapedPattern(for: subject))\b (is|means|refers to|is a|is an|is the)\b"#, options: .regularExpression) != nil {
                score += 120
            }
            if kind == .sentence {
                score += 20
            }
        }
        // v29 round 5: a how-answer must describe the mechanism,
        // not restate the definition. A definitional opener
        // ("Faster Payments is the UK's near real time payment
        // system", "Bilateral netting is the simplest form of
        // netting") loses to a passage that says how it works.
        // v29 round 7: ANY question term, not just the subject.
        // "A direct debit is a pull payment." defines "direct
        // debit" (not the subject "sepa") and still beat the
        // mechanism passages for "How does sepa direct debit
        // work?".
        // v29 round 8: only when the passage has NO mechanism
        // word. A passage that defines a term AND describes the
        // mechanism ("Message mapping is the process of...") must
        // not be penalised; only a bare definition loses.
        if intent == .how && !howWords.contains(where: { lower.contains($0) }) {
            for term in terms {
                if lower.range(of: #"\b\#(NSRegularExpression.escapedPattern(for: term))\b (is|means|refers to|is a|is an|is the)\b"#, options: .regularExpression) != nil {
                    score -= 150
                    break
                }
            }
        }
        if intent == .comparison, let sides {
            // v29 round 5: whole-word matching ("standing" must
            // not match inside "understanding").
            if wordPresent(lower, word: sides.0) && wordPresent(lower, word: sides.1) {
                score += 250
            }
        }
        if intent == .why {
            let hits = whyWords.filter { lower.contains($0) }.count
            score += 60 * min(hits, 3)
            if lower.contains("reason") {
                score += 100
            }
            // The explanatory content for a why-question is the
            // reason code itself: it must outrank a sentence that
            // only states that a rejection happened.
            // v29 round 6: +400/+200 were so large that a generic
            // reason-code sentence with NO question terms ("The
            // reason code governs the next move.", 680) outscored
            // the passage that actually names the failure asked
            // about (390). A reason-code mention is explanatory
            // depth, not a substitute for naming the question's
            // subject.
            if lower.contains("reason code") {
                score += 200
            }
            if lower.contains("rjct") {
                score += 100
            }
        }
        if intent == .how {
            let hits = howWords.filter { lower.contains($0) }.count
            score += 40 * min(hits, 3)
        }
        if lower.contains("the requirement said") || lower.contains("the assumption was") {
            score -= 100
        }
        if kind == .keypoint {
            score -= 30
        }
        return score
    }

    /// The best passages for a question, scored across the top
    /// candidates. The best passage may come from candidate 2 or 3
    /// when candidate 1's opening does not answer the question.
    /// Returns the winning entry and its passages, or nil when
    /// nothing answers.
    static func bestPassages(question: String, intent: ChatQuestionIntent, candidates: [ChatCandidate], distinctive: String? = nil) -> (entry: SearchEntry, passages: [String])? {
        let terms = contentWords(question)
        let codes = SearchService.messageCodes(in: question)
        let subject = subjectTerm(question, intent: intent)
        let sides = comparisonSides(question)
        // (score, entry, index, kind, text)
        var best: [(score: Int, entry: SearchEntry, index: Int, kind: PassageKind, text: String)] = []
        // v29 round 5: passages inherit their candidate's rank.
        // The top-ranked entry's passages get +120, the second
        // +80, the third +40. The best passage may still come from
        // a lower candidate when it is clearly better, but a
        // 3-point margin no longer lets the second-ranked guide's
        // definitional opening beat the top-ranked FAQ's mechanism
        // passage ("How does faster payments work?").
        // v29 round 6: widened to (300, 150, 50). The ranking now
        // puts the right entry first (UPI-failure situations rank
        // #1 and #2 for "Why did my UPI payment fail?"), but a
        // generic reason-code sentence from the #3 entry ("The
        // reason code governs the next move.", 680) still outscored
        // the #1 entry's own passage (390). The top entry's
        // passages must win unless a lower entry's passage is
        // clearly better.
        let rankBonus = [300, 150, 50, 0, 0]
        for (rank, candidate) in candidates.enumerated() {
            let bonus = rankBonus[min(rank, 4)]
            let passages = splitPassages(candidate.entry.bodyText)
            var scored: [(score: Int, index: Int, kind: PassageKind, text: String)] = []
            for (index, passage) in passages.enumerated() {
                guard var score = passageScore(kind: passage.kind, text: passage.text, terms: terms, codes: codes, intent: intent, subject: subject, sides: sides) else { continue }
                // v29 round 7: a passage that names the question's
                // most specific word is about THIS question, not
                // just about the topic in general. "GBP 4,500 failed
                // three times" needs the passage that names the
                // failure ("failure" shares the stem of "failed"),
                // not a generic reason-code sentence from another
                // case.
                // v29 round 8: why ONLY. For how-questions the
                // bonus also lifts case lead-ins that merely name
                // the subject ("A retailer needs a Payment API
                // integration..."), which broke "How does api
                // integration work?" again.
                if intent == .why, let distinctive, !distinctive.isEmpty, termMatches(passage.text, term: distinctive) {
                    score += 150
                }
                score += max(0, 30 - index * 3)
                scored.append((score, index, passage.kind, passage.text))
            }
            scored.sort { $0.score > $1.score }
            for item in scored.prefix(3) {
                best.append((item.score + bonus, candidate.entry, item.index, item.kind, item.text))
            }
        }
        best.sort { $0.score > $1.score }
        if best.isEmpty {
            // v29: the top candidate covers the question (it passed
            // the coverage gate) but its body never repeats the
            // question words, so no passage scored ("Where Things
            // Go Wrong" is a lesson title, not a body phrase).
            // Lead with the entry's opening sentences instead of
            // declining.
            guard let first = candidates.first else { return nil }
            let opening = splitPassages(first.entry.bodyText)
                .filter { $0.text.count >= 15 }
                .prefix(2)
                .map { $0.text }
            guard !opening.isEmpty else { return nil }
            return (first.entry, opening)
        }
        if intent == .comparison, let sides {
            let both = best.filter { $0.text.lowercased().contains(sides.0) && $0.text.lowercased().contains(sides.1) }
            if let top = both.first {
                return (top.entry, [top.text])
            }
            let aPass = best.first { $0.text.lowercased().contains(sides.0) }
            let bPass = best.first { $0.text.lowercased().contains(sides.1) }
            if let aPass, let bPass {
                return (aPass.entry, [aPass.text, bPass.text])
            }
        }
        let top = best[0]
        var passages = [top.text]
        // A second passage from the same entry when it adds to the
        // answer and is not a near-duplicate of the first.
        let same = best.dropFirst().filter { $0.entry.id == top.entry.id }
        for candidate in same {
            let wordsA = Set(SearchService.titleWords(passages[0].lowercased()))
            let wordsB = Set(SearchService.titleWords(candidate.text.lowercased()))
            let overlap = Double(wordsA.intersection(wordsB).count) / Double(max(1, wordsA.union(wordsB).count))
            if overlap > 0.4 {
                continue
            }
            if passages[0].count < 350 {
                passages.append(candidate.text)
            }
            break
        }
        return (top.entry, passages)
    }

    // MARK: - Formatting

    /// Clean one passage for display: drop stray asterisks and a
    /// "What it is" section lead-in, end with a full stop.
    static func cleanPassage(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix("*") {
            cleaned = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        cleaned = cleaned.replacingOccurrences(of: "**", with: "")
        if let range = cleaned.range(of: #"^(What it is|What is it)\s+"#, options: .regularExpression) {
            cleaned = String(cleaned[range.upperBound...])
        }
        if !cleaned.hasSuffix(".") && !cleaned.hasSuffix("!") && !cleaned.hasSuffix("?") {
            cleaned += "."
        }
        return cleaned
    }

    /// The professional local answer: the direct answer first
    /// (2-4 sentences from the best passages), then the exact
    /// citation naming the chapter and lesson (or the type and
    /// title for a guide, Situation or FAQ). The citation is the
    /// proof: it tells the learner exactly where the answer came
    /// from, so a wrong answer can be checked, not just believed.
    static func formatLocalAnswer(entry: SearchEntry, passages: [String], secondEntry: SearchEntry?) -> String {
        var body = passages.map(cleanPassage).joined(separator: " ")
        // Trim to at most 4 sentences.
        let sentences = splitIntoSentences(body)
        if sentences.count > 4 {
            body = sentences.prefix(4).joined(separator: " ")
        }
        if body.count > 600 {
            let cut = body.prefix(600)
            if let lastSpace = cut.lastIndex(of: " ") {
                body = String(cut[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
            } else {
                body = String(cut).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
            }
        }
        var source = "Source: \(entry.citation)"
        if let secondEntry, secondEntry.title != entry.title {
            source += " and \(secondEntry.citation)"
        }
        return "\(body)\n\n\(source)"
    }

    /// Split text into sentences for the 4-sentence trim.
    static func splitIntoSentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            current.append(chars[i])
            if (chars[i] == "." || chars[i] == "!" || chars[i] == "?") && i + 1 < chars.count && chars[i + 1] == " " {
                var j = i + 2
                while j < chars.count && chars[j] == " " { j += 1 }
                if j < chars.count && (chars[j].isUppercase || chars[j].isNumber || chars[j] == "\"") {
                    out.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                    i = j
                    continue
                }
            }
            i += 1
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append(current.trimmingCharacters(in: .whitespaces))
        }
        return out
    }

    // MARK: - Follow-ups

    /// Two real follow-up questions a learner would ask next, from
    /// the intent and the subject. Never "Tell me more about
    /// <title>".
    static func followUps(question: String, intent: ChatQuestionIntent, entry: SearchEntry) -> [String] {
        let subject = subjectTerm(question, intent: intent)
        let codes = SearchService.messageCodes(in: question)
        let sides = comparisonSides(question)
        let lower = question.lowercased()
        var out: [String] = []
        switch intent {
        case .definition:
            if reasonCodes.contains(subject) {
                out.append("Why was my pacs.008 rejected?")
                out.append("What happens if a payment is duplicated?")
            } else if !codes.isEmpty {
                out.append("How does \(subject) work?")
                if subject == "pacs.008" {
                    out.append("pacs.008 vs pacs.009")
                } else if subject == "mt103" {
                    out.append("MT103 vs MT202")
                } else {
                    out.append("What is \(subject) used for?")
                }
            } else if subject == "upi" {
                out.append("How does UPI settlement work?")
                out.append("UPI vs IMPS")
            } else if subject == "nostro" {
                out.append("What is a vostro account?")
                out.append("How does nostro reconciliation work?")
            } else if subject == "sepa instant" {
                out.append("How does SEPA Instant work?")
                out.append("What is SEPA?")
            } else if subject == "iso 20022" {
                out.append("What is a pacs.008?")
                out.append("What is MT103?")
            } else if subject == "rrn" {
                out.append("What is a UTR?")
                out.append("What is a nostro account?")
            } else if !subject.isEmpty {
                out.append("How does \(subject) work?")
                out.append("What is \(subject) used for?")
            }
        case .comparison:
            if let sides {
                out.append("How does \(sides.0) work?")
                out.append("How does \(sides.1) work?")
            }
        case .how:
            if !subject.isEmpty {
                out.append("What is \(subject)?")
                if subject == "upi" {
                    out.append("UPI vs IMPS")
                } else if subject == "sepa instant" {
                    out.append("What is SEPA?")
                } else if !codes.isEmpty {
                    out.append("What does \(subject) contain?")
                } else {
                    out.append("Why does \(subject) matter?")
                }
            }
        case .why:
            if lower.contains("pacs.008") {
                out.append("What does AC01 mean?")
                out.append("What happens if a payment is duplicated?")
            } else if lower.contains("stuck") {
                out.append("What happens if a payment is duplicated?")
                out.append("How does payment tracking work?")
            } else if lower.contains("duplicat") {
                out.append("How does idempotency prevent duplicates?")
                out.append("Why is my payment stuck?")
            } else {
                out.append("What happens if a payment is duplicated?")
                out.append("Why is my payment stuck?")
            }
        case .general:
            out.append("What is an MT103?")
            out.append("How does a pacs.008 work?")
        }
        var seen = Set<String>()
        var result: [String] = []
        for item in out {
            let key = item.lowercased()
            if !seen.contains(key) && key != question.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                seen.insert(key)
                result.append(item)
            }
        }
        return Array(result.prefix(2))
    }

    // MARK: - Full local answer

    /// The complete local answer for a question: ranked
    /// candidates, best passages, formatted text, sources and
    /// follow-ups. Nil when nothing in the course answers it, so
    /// the caller can give the graceful not-found reply.
    static func localAnswer(question: String, entries: [SearchEntry]) -> ChatLocalAnswer? {
        let intent = detectIntent(question)
        let candidates = rankedCandidates(question: question, entries: entries)
        guard !candidates.isEmpty else { return nil }
        // v29 coverage gate ("I don't know"): drop every candidate
        // that does not cover the question. When none covers it,
        // the course does not cover the question and the caller
        // takes the not-found path instead of a guessed passage.
        // The top candidate is still offered as the closest covered
        // topic (see closestTopic).
        let distinctive = distinctiveTerm(question: question, intent: intent, entries: entries)
        var covered = candidates.filter { candidateCovers(entry: $0.entry, question: question, intent: intent, distinctive: distinctive) }
        if covered.isEmpty && intent == .why {
            // v29 round 6: the top 5 can all fail the gate while a
            // lower candidate covers the question. The +1800 topic
            // boost can displace the covering entry from the top 5
            // ("What happens if the intermediary bank cannot
            // identify the beneficiary?" lost its camt.053 FAQ that
            // way and wrongly refused). Check ranks 6-10 before
            // declaring the question uncovered.
            // v29 round 7: why ONLY. The displacement above is
            // caused by the why-only topic boost, and widening for
            // other intents lets an off-topic question through:
            // "What is the best way to learn guitar?" was answered
            // from "Your Learning Path Forward" (it shares the word
            // "learn") instead of refused.
            let wider = rankedCandidates(question: question, entries: entries, limit: 10)
            covered = Array(wider.dropFirst(5)).filter { candidateCovers(entry: $0.entry, question: question, intent: intent, distinctive: distinctive) }
        }
        guard !covered.isEmpty else { return nil }
        guard let (entry, passages) = bestPassages(question: question, intent: intent, candidates: covered, distinctive: distinctive) else {
            return nil
        }
        var secondEntry: SearchEntry? = nil
        if intent == .comparison && passages.count == 2, let sides = comparisonSides(question) {
            for candidate in covered where candidate.entry.id != entry.id {
                if candidate.entry.bodyText.lowercased().contains(sides.1) {
                    secondEntry = candidate.entry
                    break
                }
            }
        }
        let text = formatLocalAnswer(entry: entry, passages: passages, secondEntry: secondEntry)
        var sources = [entry]
        if let secondEntry, secondEntry.id != entry.id {
            sources.append(secondEntry)
        }
        return ChatLocalAnswer(text: text, sources: sources, followUps: followUps(question: question, intent: intent, entry: entry))
    }

    /// The closest topic for a graceful not-found: the top
    /// candidate's title, so the learner still has somewhere to go.
    static func closestTopic(question: String, entries: [SearchEntry]) -> SearchEntry? {
        rankedCandidates(question: question, entries: entries).first?.entry
    }
}
