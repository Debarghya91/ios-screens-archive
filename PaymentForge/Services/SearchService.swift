// SearchService.swift
// Payments Training Hub iOS - Intelligent search over the live catalogue.
// Debounced by the caller (SearchView waits ~0.3s after typing stops
// before calling search, and runs the search itself off the main
// thread). Ranking, typo tolerance, suggestions,
// recent searches and match highlighting live here, so the view stays
// thin. Only real catalogue entries are ever returned; counts come
// from the live index, never from hardcoded totals.
// No em dashes in any user-facing text.
// Performance: every function here is a pure static with no actor
// isolation, so callers may run it on a background task. Regexes are
// compiled once and cached, and search() splits each entry's title
// and body words once per search and skips fuzzy passes that cannot
// beat the best score already found, so a search over the whole
// catalogue never blocks the main thread for seconds.

import Foundation
import SwiftUI

/// One ranked search hit: the catalogue entry, why it matched, and
/// the term to highlight in its title (nil when the match is only in
/// the body text).
struct SearchHit: Identifiable {
    let entry: SearchEntry
    let score: Int
    let reason: String
    let matchedTerm: String?
    var id: String { entry.id }
}

/// One search suggestion: what the row shows, and the query that runs
/// when the learner taps it.
struct SearchSuggestion: Identifiable, Hashable {
    let title: String
    let query: String
    var id: String { query.lowercased() }
}

enum SearchService {
    // MARK: - Recent searches

    /// Base key for recent searches. The stored key is namespaced
    /// per account through AccountScopedStorage: recent searches
    /// are personal data and must never leak across accounts.
    private static let recentKey = "pf.search.recent.v1"
    static let maxRecentSearches = 10

    /// The last searches, most recent first, at most 10.
    static func recentSearches() -> [String] {
        AccountScopedStorage.adoptLegacyKey(recentKey)
        return (UserDefaults.standard.array(forKey: AccountScopedStorage.currentKey(recentKey)) as? [String]) ?? []
    }

    /// Record a search, most recent first, deduplicated, capped at 10.
    /// Blank queries and duplicates of the most recent entry are ignored.
    static func recordSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var recents = recentSearches()
        if recents.first?.lowercased() == trimmed.lowercased() { return }
        recents.removeAll { $0.lowercased() == trimmed.lowercased() }
        recents.insert(trimmed, at: 0)
        UserDefaults.standard.set(Array(recents.prefix(maxRecentSearches)), forKey: AccountScopedStorage.currentKey(recentKey))
    }

    static func clearRecentSearches() {
        UserDefaults.standard.removeObject(forKey: AccountScopedStorage.currentKey(recentKey))
    }

    /// Adopt any legacy recent searches into the current namespace.
    /// Recent searches hold no in-memory cache, so adoption is the
    /// whole reload. Called by AuthService on account switch.
    static func reloadForCurrentAccount() {
        AccountScopedStorage.adoptLegacyKey(recentKey)
    }

    // MARK: - Synonym, acronym and symptom map

    /// One acronym, synonym or failure-symptom mapping. `key` is what
    /// the user typed (lowercased); `expansion` is the full form shown
    /// in the "why this matched" line; `terms` are the extra terms also
    /// searched in the index. Symptom phrases get the "your search for"
    /// wording instead of the acronym wording.
    struct SearchSynonym {
        let key: String
        let expansion: String
        let terms: [String]
        let isSymptom: Bool
    }

    static let synonyms: [SearchSynonym] = [
        SearchSynonym(key: "upi", expansion: "Unified Payments Interface", terms: ["unified payments interface", "upi"], isSymptom: false),
        SearchSynonym(key: "npci", expansion: "National Payments Corporation of India", terms: ["national payments corporation of india", "npci"], isSymptom: false),
        SearchSynonym(key: "rrn", expansion: "Retrieval Reference Number", terms: ["retrieval reference number", "rrn", "reference number"], isSymptom: false),
        SearchSynonym(key: "utr", expansion: "Unique Transaction Reference", terms: ["unique transaction reference", "utr", "transaction reference"], isSymptom: false),
        SearchSynonym(key: "ifsc", expansion: "Indian Financial System Code", terms: ["indian financial system code", "ifsc"], isSymptom: false),
        SearchSynonym(key: "micr", expansion: "Magnetic Ink Character Recognition", terms: ["magnetic ink character recognition", "micr"], isSymptom: false),
        SearchSynonym(key: "neft", expansion: "National Electronic Funds Transfer", terms: ["national electronic funds transfer", "neft"], isSymptom: false),
        SearchSynonym(key: "rtgs", expansion: "Real Time Gross Settlement", terms: ["real time gross settlement", "rtgs"], isSymptom: false),
        SearchSynonym(key: "imps", expansion: "Immediate Payment Service", terms: ["immediate payment service", "imps"], isSymptom: false),
        SearchSynonym(key: "fps", expansion: "Faster Payments Service", terms: ["faster payments service", "faster payments", "fps"], isSymptom: false),
        SearchSynonym(key: "sepa", expansion: "Single Euro Payments Area", terms: ["single euro payments area", "sepa"], isSymptom: false),
        SearchSynonym(key: "swift", expansion: "Society for Worldwide Interbank Financial Telecommunication", terms: ["society for worldwide interbank financial telecommunication", "swift", "bic"], isSymptom: false),
        SearchSynonym(key: "bic", expansion: "Bank Identifier Code", terms: ["bank identifier code", "bic", "swift code"], isSymptom: false),
        SearchSynonym(key: "iban", expansion: "International Bank Account Number", terms: ["international bank account number", "iban"], isSymptom: false),
        SearchSynonym(key: "iso 20022", expansion: "ISO 20022", terms: ["iso 20022", "mx message", "pacs", "pain", "camt"], isSymptom: false),
        SearchSynonym(key: "pacs.008", expansion: "Customer Credit Transfer (pacs.008)", terms: ["customer credit transfer", "pacs.008", "pacs 008"], isSymptom: false),
        SearchSynonym(key: "pain.001", expansion: "Customer Credit Transfer Initiation (pain.001)", terms: ["customer credit transfer initiation", "pain.001", "pain 001"], isSymptom: false),
        SearchSynonym(key: "camt.029", expansion: "Resolution of Investigation (camt.029)", terms: ["resolution of investigation", "camt.029", "camt 029", "investigation"], isSymptom: false),
        SearchSynonym(key: "idempotency", expansion: "Idempotency", terms: ["idempotency", "idempotency key", "duplicate payment"], isSymptom: false),
        SearchSynonym(key: "reversal", expansion: "Reversal", terms: ["reversal", "reversed", "reverse"], isSymptom: false),
        SearchSynonym(key: "refund", expansion: "Refund", terms: ["refund", "refunded"], isSymptom: false),
        SearchSynonym(key: "chargeback", expansion: "Chargeback", terms: ["chargeback", "dispute"], isSymptom: false),
        SearchSynonym(key: "timeout", expansion: "Timeout", terms: ["timeout", "timed out", "no response"], isSymptom: false),
        SearchSynonym(key: "debit successful but beneficiary not credited", expansion: "Beneficiary not credited", terms: ["beneficiary not credited", "not credited", "reversal", "refund"], isSymptom: true),
        SearchSynonym(key: "beneficiary not credited", expansion: "Beneficiary not credited", terms: ["beneficiary not credited", "not credited", "credit not received", "reversal", "refund"], isSymptom: true),
        SearchSynonym(key: "amount debited but not credited", expansion: "Amount debited but not credited", terms: ["amount debited", "debited but not credited", "not credited", "reversal", "refund"], isSymptom: true),
        SearchSynonym(key: "payment stuck", expansion: "Payment stuck", terms: ["payment stuck", "stuck", "pending", "held", "status check"], isSymptom: true),
        SearchSynonym(key: "pending", expansion: "Pending", terms: ["pending", "awaiting", "in progress", "processing"], isSymptom: true)
    ]

    /// The synonym entries a query triggers. A single-word needle
    /// matches on whole words only, so "upi" never matches inside
    /// another word; phrases match as written. Typing the full form
    /// also triggers the entry. Longest keys first, so a symptom
    /// phrase wins over a single word inside it.
    static func triggeredSynonyms(for query: String) -> [SearchSynonym] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return synonyms
            .filter { entry in
                queryContains(q, needle: entry.key)
                    || queryContains(q, needle: entry.expansion.lowercased())
            }
            .sorted { $0.key.count > $1.key.count }
    }

    /// Whole-word match for a single word, substring match for a
    /// phrase (a needle with a space or a dot). The whole-word
    /// regexes are compiled once and cached: compiling one per
    /// synonym per search made every keystroke pay for dozens of
    /// regex compilations. A needle outside the cache (only
    /// possible for a future caller) still compiles on the spot,
    /// with the same pattern, so the match is identical.
    private static let wordBoundaryRegexes: [String: NSRegularExpression] = {
        var cache: [String: NSRegularExpression] = [:]
        for entry in synonyms {
            for needle in [entry.key, entry.expansion.lowercased()] {
                guard !needle.contains(" ") && !needle.contains(".") else { continue }
                let pattern = "\\b" + NSRegularExpression.escapedPattern(for: needle) + "\\b"
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    cache[needle] = regex
                }
            }
        }
        return cache
    }()

    static func queryContains(_ query: String, needle: String) -> Bool {
        let hasSeparator = needle.contains(" ") || needle.contains(".")
        if hasSeparator {
            return query.contains(needle)
        }
        if let regex = wordBoundaryRegexes[needle] {
            let range = NSRange(query.startIndex..., in: query)
            return regex.firstMatch(in: query, options: [], range: range) != nil
        }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: needle) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return query.contains(needle)
        }
        let range = NSRange(query.startIndex..., in: query)
        return regex.firstMatch(in: query, options: [], range: range) != nil
    }

    // MARK: - Message codes and stop words

    /// Words that carry no meaning on their own in a question
    /// ("vs", "what", "is", "how"). They add no score in the
    /// multi-word path, so a bare "vs" can never outrank a message
    /// code: "pacs.008 vs pacs.009" must rank pacs.008 and pacs.009
    /// entries first, never "X vs Y" lessons that only share "vs".
    static let stopWords: Set<String> = [
        "vs", "versus", "and", "or", "the", "a", "an", "of", "to", "in", "on",
        "for", "with", "what", "is", "how", "does", "do", "did", "explain",
        "tell", "me", "about", "difference", "between", "which", "why", "when",
        "work", "works", "working", "are", "am", "be", "by", "at", "as", "it",
        "its", "this", "that", "these", "those", "i", "you", "we", "can", "could",
        "should", "would", "please", "give", "show", "get", "got", "than", "then",
        "from", "into", "per", "vs."
    ]

    /// ISO 20022 and SWIFT message codes the curriculum covers, in
    /// canonical form: dotted for MX ("pacs.008"), plain for MT
    /// ("mt103"). Used to correct a 1-2 letter typo in a code the
    /// learner typed, for example "pace.008" to "pacs.008".
    static let knownMessageCodes: [String] = [
        "pacs.002", "pacs.003", "pacs.004", "pacs.008", "pacs.009", "pacs.010",
        "pain.001", "pain.002", "pain.008", "pain.013",
        "camt.025", "camt.029", "camt.050", "camt.053", "camt.054", "camt.056", "camt.060",
        "remt.001", "acmt.001",
        "mt101", "mt103", "mt202", "mt210", "mt900", "mt910", "mt940", "mt942", "mt950"
    ]

    /// The message-code patterns, compiled once and cached.
    /// messageCodes(in:) used to compile all four on every call,
    /// and it is called on every search.
    private static let mxCodeRegex: NSRegularExpression? = try? NSRegularExpression(pattern: #"\b(pacs|pain|camt|remt|acmt)[.\s]?(\d{3})\b"#, options: [.caseInsensitive])
    private static let mtCodeRegex: NSRegularExpression? = try? NSRegularExpression(pattern: #"\bmt[\s]?(\d{3})\b"#, options: [.caseInsensitive])
    private static let typoCodeRegex: NSRegularExpression? = try? NSRegularExpression(pattern: #"\b([a-z]{2,5})\.(\d{3})\b"#, options: [.caseInsensitive])
    private static let vsTailRegex: NSRegularExpression? = try? NSRegularExpression(pattern: #"\bvs\.?\s+(\d{1,3})\b"#, options: [.caseInsensitive])

    /// The message codes a question names, canonicalised. Handles
    /// the dotted ("pacs.008"), spaced ("pacs 008") and joined
    /// ("pacs008") spellings, MT codes ("mt103", "mt 103"), a 1-2
    /// letter typo in the code family ("pace.008" to "pacs.008"),
    /// and a "vs <digits>" tail ("pacs.008 vs 9" names pacs.009 as
    /// well). Empty when the question names no message code.
    static func messageCodes(in query: String) -> [String] {
        let q = query.lowercased()
        var found: [String] = []
        func add(_ code: String) {
            if !found.contains(code) { found.append(code) }
        }
        func matches(_ regex: NSRegularExpression?) -> [NSTextCheckingResult] {
            guard let regex else { return [] }
            return regex.matches(in: q, options: [], range: NSRange(q.startIndex..., in: q))
        }
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: q) else { return nil }
            return String(q[swiftRange])
        }
        // Dotted, spaced or joined MX codes.
        for match in matches(mxCodeRegex) {
            if let family = group(match, 1), let number = group(match, 2) {
                add("\(family).\(number)")
            }
        }
        // MT codes.
        for match in matches(mtCodeRegex) {
            if let number = group(match, 1) {
                add("mt\(number)")
            }
        }
        // Typo correction: a word shaped like <letters>.<3 digits>
        // 1-2 edits from a known dotted code.
        for match in matches(typoCodeRegex) {
            guard let family = group(match, 1), let number = group(match, 2) else { continue }
            let candidate = "\(family).\(number)"
            if found.contains(candidate) || knownMessageCodes.contains(candidate) { continue }
            var best: (distance: Int, code: String)? = nil
            for known in knownMessageCodes where known.contains(".") {
                let distance = levenshtein(candidate, known, maxDistance: 2)
                if distance <= 2, best == nil || distance < best!.distance {
                    best = (distance, known)
                }
            }
            if let best { add(best.code) }
        }
        // "vs <digits>" tail, after typo correction so the family
        // is known: "pacs.008 vs 9" names pacs.009 as well, and
        // "mt103 vs 202" names mt202 as well.
        if let match = matches(vsTailRegex).first,
           let digits = group(match, 1),
           let first = found.first {
            let padded = String(repeating: "0", count: max(0, 3 - digits.count)) + digits
            if first.contains(".") {
                let family = first.split(separator: ".").first.map(String.init) ?? ""
                add("\(family).\(padded)")
            } else if first.hasPrefix("mt") {
                add("mt\(padded)")
            }
        }
        return found
    }

    /// The spellings of one message code as it appears in catalogue
    /// titles and text: dotted, spaced and joined.
    static func messageCodeVariants(_ code: String) -> [String] {
        if let dot = code.firstIndex(of: ".") {
            let family = String(code[..<dot])
            let number = String(code[code.index(after: dot)...])
            return [code, "\(family) \(number)", "\(family)\(number)"]
        }
        let family = String(code.prefix(2))
        let number = String(code.dropFirst(2))
        return [code, "\(family) \(number)"]
    }

    /// The boost for an entry from the message codes in the
    /// question. Title match 1500 per code, id match 900, body
    /// match 600. An entry whose title names every code in the
    /// question (a comparison lesson, for example) gets 1000 more,
    /// so it ranks above single-code entries.
    static func messageCodeScore(entry: SearchEntry, codes: [String]) -> Int {
        guard !codes.isEmpty else { return 0 }
        return messageCodeScore(
            title: entry.title.lowercased(),
            id: entry.id.lowercased(),
            text: entry.text.lowercased(),
            codes: codes
        )
    }

    /// The same boost from already-lowercased strings, so search()
    /// does not lowercase every entry a second time. Same scores,
    /// same order, same result as messageCodeScore(entry:codes:).
    static func messageCodeScore(title: String, id: String, text: String, codes: [String]) -> Int {
        guard !codes.isEmpty else { return 0 }
        var total = 0
        var titleHits = 0
        for code in codes {
            let variants = messageCodeVariants(code)
            if variants.contains(where: { title.contains($0) }) {
                total += 1500
                titleHits += 1
            } else if variants.contains(where: { id.contains($0) }) {
                total += 900
            } else if variants.contains(where: { text.contains($0) }) {
                total += 600
            }
        }
        if titleHits == codes.count {
            total += 1000
        }
        return total
    }

    // MARK: - Ranked search

    /// Ranked search over the live index entries.
    ///
    /// Title match outranks body match, exact phrase outranks partial,
    /// a synonym or symptom expansion still finds the case it names,
    /// and a 1-2 edit typo still finds the right title. Free samples
    /// and lessons in the learner's current chapter (the chapter of
    /// the last lesson they opened) rank higher. Completed items are
    /// not hidden and get no penalty: the row marks them Completed.
    /// Capped at 60 hits. The fuzzy pass runs on title words first and
    /// only then on a bounded slice of body words, so 1660 entries
    /// stay fast. Each entry's lowercased strings and word lists are
    /// built once per search and shared by every needle (the query
    /// plus every expansion term): the old code re-split the title
    /// and body words for every needle and every query word, and ran
    /// the fuzzy pass over up to 300 body words per needle, which is
    /// what made a single search take seconds on the main thread.
    /// Pure and synchronous: callers run it off the main thread.
    static func search(
        entries: [SearchEntry],
        query: String,
        freeSampleIDs: Set<String> = [],
        currentChapterPrefix: String? = nil,
        limit: Int = 60
    ) -> [SearchHit] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = trimmedQuery.lowercased()
        guard !q.isEmpty else { return [] }
        // Query words for the multi-word path: trailing punctuation
        // stripped ("mt103?" to "mt103"), stop words removed, so a
        // bare "vs" or "what is an" adds no score on its own.
        let queryWords = q.split(separator: " ").map(String.init)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "?!.,;:")) }
            .filter { $0.count >= 2 && !stopWords.contains($0) }
        let synonyms = triggeredSynonyms(for: q)
        // Message codes named by the question, for the boost below.
        let codes = messageCodes(in: q)
        var hits: [SearchHit] = []
        hits.reserveCapacity(64)
        for entry in entries {
            let title = entry.title.lowercased()
            let text = entry.text.lowercased()
            let lowerID = entry.id.lowercased()
            // Built once per entry, shared by every needle below.
            // The body list is the first 300 words only, exactly
            // the slice the old code re-derived on every check,
            // built lazily so an entry that matches in its title
            // never pays for a body split at all.
            let entryTitleWords = titleWords(title)
            var cachedBodyWords: [String]? = nil
            func bodyWords() -> [String] {
                if let existing = cachedBodyWords { return existing }
                let words = Array(titleWords(text).prefix(300))
                cachedBodyWords = words
                return words
            }
            var bestScore = 0
            var bestReason = ""
            var bestTerm: String? = nil

            func consider(score: Int, reason: String, term: String?) {
                if score > bestScore {
                    bestScore = score
                    bestReason = reason
                    bestTerm = term
                }
            }

            // Direct phrase match on the query as typed.
            scoreNeedle(q, title: title, text: text, titleWords: entryTitleWords, bodyWords: bodyWords, displayQuery: trimmedQuery, currentBest: bestScore, consider: consider)
            // Extra credit when every content word lands in the title
            // ("upi timeout" against a UPI timeout situation) or body.
            // Stop words are already removed from queryWords, so a
            // single meaningful word ("mt103") earns it too.
            if !queryWords.isEmpty {
                let titleWordHits = queryWords.filter { word in
                    title.contains(word) || entryTitleWords.contains(where: { $0.hasPrefix(word) })
                }.count
                if titleWordHits == queryWords.count {
                    consider(score: 850, reason: "Matches '\(trimmedQuery)' in the title", term: q)
                } else if titleWordHits > 0 {
                    consider(score: 500 + 100 * titleWordHits, reason: "Matches: \(trimmedQuery)", term: q)
                }
                let bodyWordHits = queryWords.filter { text.contains($0) }.count
                if bodyWordHits == queryWords.count {
                    consider(score: 380, reason: "Matches: \(trimmedQuery)", term: nil)
                }
            }
            // Synonym and symptom expansion matches.
            for synonym in synonyms {
                for term in synonym.terms where term.lowercased() != q {
                    let display = synonym.isSymptom
                        ? "Matches your search for '\(synonym.key)'"
                        : "Matches '\(synonym.key)' (\(synonym.expansion))"
                    scoreNeedle(term, title: title, text: text, titleWords: entryTitleWords, bodyWords: bodyWords, displayQuery: synonym.key, currentBest: bestScore, isExpansion: true, reasonOverride: display, consider: consider)
                }
            }
            // Message-code boost: entries about the exact codes the
            // question names rank first, above any stop-word match.
            let codeScore = messageCodeScore(title: title, id: lowerID, text: text, codes: codes)
            guard bestScore > 0 || codeScore > 0 else { continue }
            // Ranking boosts. Free samples and the learner's current
            // chapter rank higher; nothing is hidden for being done.
            var score = bestScore + codeScore
            if entry.type == .situation && freeSampleIDs.contains(entry.id) {
                score += 50
            }
            if entry.type == .lesson, let prefix = currentChapterPrefix, entry.id.hasPrefix(prefix) {
                score += 80
            }
            hits.append(SearchHit(entry: entry, score: score, reason: bestReason, matchedTerm: bestTerm))
        }
        hits.sort { $0.score > $1.score }
        return Array(hits.prefix(limit))
    }

    /// Score one needle (the query or one expansion term) against a
    /// title and body. Title outranks body at every step; exact
    /// phrase outranks partial; a 1-2 edit typo on a word of 4 or more
    /// letters still counts, title first, then body. The word lists
    /// come from the caller, built once per entry, never re-split
    /// here. `currentBest` is the best score already found for this
    /// entry: passes whose top score cannot beat it are skipped,
    /// because consider() only keeps strictly better scores, so
    /// skipping them cannot change the result. That is what stops
    /// the body fuzzy pass (150) running for entries that already
    /// matched in the title.
    private static func scoreNeedle(
        _ needle: String,
        title: String,
        text: String,
        titleWords: [String],
        bodyWords: () -> [String],
        displayQuery: String,
        currentBest: Int,
        isExpansion: Bool = false,
        reasonOverride: String? = nil,
        consider: (_ score: Int, _ reason: String, _ term: String?) -> Void
    ) {
        // No needle can score above 1000, and consider() only
        // keeps strictly better scores.
        guard currentBest < 1000 else { return }
        let titleReason = reasonOverride ?? "Matches '\(displayQuery)' in the title"
        let bodyReason = reasonOverride ?? "Matches your search for '\(displayQuery)'"
        let baseTitle = isExpansion ? 650 : 800
        let baseBody = isExpansion ? 350 : 300
        let needleChars = Array(needle)
        if title.contains(needle) {
            let score = title == needle ? 1000 : (title.hasPrefix(needle) ? 900 : baseTitle)
            consider(score, titleReason, needle)
            return
        }
        if titleWords.contains(where: { $0.hasPrefix(needle) }) {
            consider(700, titleReason, needle)
            return
        }
        if currentBest < 600, let fuzzyWord = fuzzyWordMatch(needle: needle, needleChars: needleChars, words: titleWords) {
            consider(600, "Close match for '\(displayQuery)' in the title", fuzzyWord)
            return
        }
        // Every remaining pass scores at most 450, so none can
        // beat a best score of 450 or more.
        guard currentBest < 450 else { return }
        if text.contains(needle) {
            consider(text == needle ? 450 : baseBody, bodyReason, nil)
            return
        }
        if currentBest < 250, bodyWords().contains(where: { $0.hasPrefix(needle) }) {
            consider(250, bodyReason, nil)
            return
        }
        if currentBest < 150, fuzzyWordMatch(needle: needle, needleChars: needleChars, words: bodyWords()) != nil {
            consider(150, "Close match for '\(displayQuery)'", nil)
        }
    }

    /// The title word (or body word) within 1-2 edits of the needle,
    /// for a needle of 4 or more letters. Short needles never fuzzy
    /// match: "upi" must not match "up" or "api" by accident. Returns
    /// the matched word, for highlighting. The word list and the
    /// needle characters come from the caller, so neither is
    /// rebuilt for every word checked.
    private static func fuzzyWordMatch(needle: String, needleChars: [Character], words: [String]) -> String? {
        guard needle.count >= 4, !needle.contains(" ") else { return nil }
        let allowed = needle.count <= 5 ? 1 : 2
        for word in words {
            guard word.count >= 4, abs(word.count - needle.count) <= allowed else { continue }
            if levenshtein(Array(word), needleChars, maxDistance: allowed) <= allowed {
                return word
            }
        }
        return nil
    }

    /// Words of a string, lowercased, split on anything that is not a
    /// letter or a digit. Dots stay out, so "pacs.008" splits into
    /// "pacs" and "008" for the fuzzy pass only; exact matching still
    /// uses the raw string.
    static func titleWords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Levenshtein distance, capped: returns a value above
    /// maxDistance as soon as the distance is known to exceed it.
    /// Identical strings cost nothing: the fuzzy pass compares
    /// the same common words again and again.
    static func levenshtein(_ a: String, _ b: String, maxDistance: Int) -> Int {
        if a == b { return 0 }
        return levenshtein(Array(a), Array(b), maxDistance: maxDistance)
    }

    /// The same capped distance over pre-split characters, so the
    /// fuzzy pass converts each needle once instead of once per
    /// word compared. Same rows, same early exit, same result.
    private static func levenshtein(_ aChars: [Character], _ bChars: [Character], maxDistance: Int) -> Int {
        if abs(aChars.count - bChars.count) > maxDistance { return maxDistance + 1 }
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }
        var previous = Array(0...bChars.count)
        var current = [Int](repeating: 0, count: bChars.count + 1)
        for i in 1...aChars.count {
            current[0] = i
            var rowMin = current[0]
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowMin = min(rowMin, current[j])
            }
            if rowMin > maxDistance { return maxDistance + 1 }
            swap(&previous, &current)
        }
        return previous[bChars.count]
    }

    // MARK: - Suggestions

    /// Suggestions as the user types: synonym and symptom entries
    /// first (so "RRN", "idempotency" and "debit successful but
    /// beneficiary not credited" resolve to the right cases), then
    /// lesson and Situation titles that start with or contain the
    /// query. Prefix matches come before substring matches. Capped
    /// at 8, deduplicated. One pass over the entries, lowercasing
    /// each title once: the old code mapped every title and then
    /// lowercased each one twice more, on every keystroke.
    static func suggestions(query: String, entries: [SearchEntry], limit: Int = 8) -> [SearchSuggestion] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 2 else { return [] }
        var out: [SearchSuggestion] = []
        var seen: Set<String> = []
        func append(title: String, query: String) {
            let key = query.lowercased()
            guard seen.insert(key).inserted, out.count < limit else { return }
            out.append(SearchSuggestion(title: title, query: query))
        }
        for synonym in synonyms where synonym.key.hasPrefix(q) || synonym.key.contains(q) || synonym.expansion.lowercased().contains(q) {
            append(title: "\(synonym.key) (\(synonym.expansion))", query: synonym.key)
        }
        // Prefix matches append at once, in catalogue order;
        // substring-only titles are collected and appended after,
        // in catalogue order, exactly as the old two-pass version
        // produced them. A prefix title never needs the substring
        // pass: it was already appended, or deduplicated away.
        var substringTitles: [String] = []
        for entry in entries {
            let lowerTitle = entry.title.lowercased()
            if lowerTitle.hasPrefix(q) {
                append(title: entry.title, query: entry.title)
                if out.count >= limit { return out }
            } else if lowerTitle.contains(q) {
                substringTitles.append(entry.title)
            }
        }
        for title in substringTitles {
            append(title: title, query: title)
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: - Scheme detection

    /// Scheme filter options, in match order.
    static let railOptions = ["UPI", "Cards", "NEFT", "RTGS", "IMPS", "FPS", "SWIFT", "SEPA", "ISO 20022"]

    /// The patterns that name each scheme in an entry title or text.
    /// "faster payments" names FPS; "iso 20022" names ISO 20022.
    private static let railPatterns: [(display: String, patterns: [String])] = [
        ("UPI", ["upi"]),
        ("Cards", ["cards?"]),
        ("NEFT", ["neft"]),
        ("RTGS", ["rtgs"]),
        ("IMPS", ["imps"]),
        ("FPS", ["fps", "faster payments"]),
        ("SWIFT", ["swift"]),
        ("SEPA", ["sepa"]),
        ("ISO 20022", ["iso 20022"])
    ]

    /// The scheme regexes, compiled once and cached. rail(for:)
    /// is called for every rendered result row, and the old code
    /// compiled up to nine regexes per row.
    private static let railRegexes: [(display: String, regexes: [NSRegularExpression])] = railPatterns.map { rail in
        let compiled = rail.patterns.compactMap { pattern -> NSRegularExpression? in
            try? NSRegularExpression(pattern: "\\b" + pattern + "\\b", options: [.caseInsensitive])
        }
        return (display: rail.display, regexes: compiled)
    }

    /// The scheme named by an entry title or text, or nil when it
    /// names none. Whole-word matching, so a short rail never matches
    /// inside another word. Title and text only, never invented.
    static func rail(for entry: SearchEntry) -> String? {
        let haystack = entry.title + " " + entry.text
        let range = NSRange(haystack.startIndex..., in: haystack)
        for rail in railRegexes {
            for regex in rail.regexes where regex.firstMatch(in: haystack, options: [], range: range) != nil {
                return rail.display
            }
        }
        return nil
    }

    // MARK: - Dynamic counts

    /// Per-type counts from the live index entries. A type with no
    /// entries in the loaded index has no count: the caller shows no
    /// number rather than a made-up one.
    static func countsByType(entries: [SearchEntry]) -> [SearchEntryType: Int] {
        var counts: [SearchEntryType: Int] = [:]
        for entry in entries {
            counts[entry.type, default: 0] += 1
        }
        return counts
    }

    /// The chapter prefix of a lesson id, for example "ch1" for
    /// "ch1s1". Nil when the id is not a lesson id.
    static func chapterPrefix(forLessonID id: String) -> String? {
        guard let sIndex = id.lastIndex(of: "s") else { return nil }
        let prefix = String(id[..<sIndex])
        guard prefix.hasPrefix("ch"), !prefix.dropFirst(2).isEmpty else { return nil }
        return prefix
    }

    // MARK: - Match highlighting

    /// The title with every occurrence of the matched term (and of the
    /// query words) in royal blue and bold. The bold is an emphasis
    /// intent, so it inherits the row's font size. Plain text when
    /// nothing matches in the title. Built by concatenating plain and
    /// highlighted segments, so no index conversion is needed.
    static func highlightedTitle(_ title: String, matchedTerm: String?, query: String) -> AttributedString {
        var terms: [String] = []
        if let matchedTerm, !matchedTerm.isEmpty {
            terms.append(contentsOf: matchedTerm.split(separator: " ").map(String.init))
            terms.append(matchedTerm)
        }
        terms.append(contentsOf: query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(separator: " ").map(String.init))
        let uniqueTerms = Array(Set(terms.filter { $0.count >= 2 })).sorted { $0.count > $1.count }
        guard !uniqueTerms.isEmpty else { return AttributedString(title) }
        let lowerTitle = title.lowercased()
        var ranges: [Range<String.Index>] = []
        for term in uniqueTerms {
            var searchFrom = lowerTitle.startIndex
            while let range = lowerTitle.range(of: term, range: searchFrom..<lowerTitle.endIndex) {
                ranges.append(range)
                searchFrom = range.upperBound
            }
        }
        guard !ranges.isEmpty else { return AttributedString(title) }
        ranges.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for range in ranges {
            if let last = merged.last, range.lowerBound < last.upperBound {
                if range.upperBound > last.upperBound {
                    merged[merged.count - 1] = last.lowerBound..<range.upperBound
                }
            } else {
                merged.append(range)
            }
        }
        var out = AttributedString()
        var cursor = title.startIndex
        for range in merged {
            if cursor < range.lowerBound {
                out += AttributedString(String(title[cursor..<range.lowerBound]))
            }
            var highlighted = AttributedString(String(title[range]))
            highlighted.foregroundColor = Color.pfRoyal
            highlighted.inlinePresentationIntent = .stronglyEmphasized
            out += highlighted
            cursor = range.upperBound
        }
        if cursor < title.endIndex {
            out += AttributedString(String(title[cursor..<title.endIndex]))
        }
        return out
    }
}
