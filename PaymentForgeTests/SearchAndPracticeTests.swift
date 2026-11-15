// SearchAndPracticeTests.swift
// PaymentForge iOS - Phase 7 unit tests: data repositories.
// SearchService ranking (title outranks body, synonym expansion,
// typo tolerance) and PracticeStore attempt recording (history is
// kept, accuracy is nil before any attempt, never 0 as a fake
// score). No network: all entries are fixtures built in this file.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only.
//
// Phase 1 reconciliation (12 Nov 2026): PracticeStore attempts are
// now stored under the account-namespaced key
// pf.account.<namespace>.pf.practiceAttempts.v1. The old tests
// removed the raw legacy key "pf.practiceAttempts.v1", which no
// longer clears stored attempts, so they could leak attempts across
// runs. Both practice tests now clear through
// AccountScopedStorage.currentKey, and also remove the legacy raw
// key so a leftover legacy value cannot be adopted back in by the
// store's load path. SearchService recent-search tests already go
// through public APIs that namespace internally, so they are
// unchanged.

import XCTest
@testable import PaymentForge

final class SearchAndPracticeTests: XCTestCase {

    private func entry(id: String, title: String, text: String, type: SearchEntryType = .lesson) -> SearchEntry {
        SearchEntry(id: id, title: title, url: "lessons/\(id)", type: type, text: text)
    }

    private var entries: [SearchEntry] {
        [
            entry(id: "ch1s1", title: "What a payment is", text: "A payment moves money from one account to another."),
            entry(id: "ch5s2", title: "Reading a SWIFT message", text: "SWIFT messages carry payment instructions between banks."),
            entry(id: "ch3s1", title: "UPI basics", text: "The Unified Payments Interface moves money instantly in India."),
            entry(id: "ch3s3", title: "Moving money instantly", text: "The Unified Payments Interface moves money instantly in India."),
            entry(id: "ch3s2", title: "NEFT and RTGS", text: "NEFT settles in batches, RTGS settles in real time."),
            entry(id: "ABH-01", title: "Beneficiary not credited", text: "The amount was debited but the beneficiary was not credited.", type: .situation)
        ]
    }

    // MARK: - SearchService ranking

    func testTitleMatchOutranksBodyMatch() {
        let hits = SearchService.search(entries: entries, query: "SWIFT")
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits.first?.entry.id, "ch5s2", "The title match must rank first.")
        XCTAssertTrue(hits.first!.score > 0)
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(SearchService.search(entries: entries, query: "").isEmpty)
        XCTAssertTrue(SearchService.search(entries: entries, query: "   ").isEmpty)
    }

    func testSynonymExpansionFindsFullForm() {
        // "upi" expands to "Unified Payments Interface": the
        // "Moving money instantly" lesson has neither word in its
        // title, yet matches through the expansion in its body text.
        let hits = SearchService.search(entries: entries, query: "upi")
        XCTAssertTrue(hits.contains { $0.entry.id == "ch3s3" })
        XCTAssertTrue(hits.contains { $0.entry.id == "ch3s1" }, "The direct title match still ranks too.")
    }

    func testTypoToleranceFindsTitle() {
        // "swif" is one edit from "swift" and must still find it.
        let hits = SearchService.search(entries: entries, query: "swif")
        XCTAssertTrue(hits.contains { $0.entry.id == "ch5s2" })
    }

    func testSymptomPhraseFindsSituation() {
        let hits = SearchService.search(entries: entries, query: "beneficiary not credited")
        XCTAssertTrue(hits.contains { $0.entry.id == "ABH-01" })
    }

    func testFreeSampleBoostRanksSampleHigher() {
        let plain = SearchService.search(entries: entries, query: "beneficiary not credited")
        let boosted = SearchService.search(entries: entries, query: "beneficiary not credited", freeSampleIDs: ["ABH-01"])
        let plainScore = plain.first { $0.entry.id == "ABH-01" }?.score ?? 0
        let boostedScore = boosted.first { $0.entry.id == "ABH-01" }?.score ?? 0
        XCTAssertGreaterThan(boostedScore, plainScore)
    }

    func testSuggestionsIncludeSynonym() {
        let suggestions = SearchService.suggestions(query: "up", entries: entries)
        XCTAssertTrue(suggestions.contains { $0.query == "upi" })
    }

    func testCountsByType() {
        let counts = SearchService.countsByType(entries: entries)
        XCTAssertEqual(counts[.lesson], 5)
        XCTAssertEqual(counts[.situation], 1)
        XCTAssertNil(counts[.guide], "A type with no entries has no count, never a made-up zero row.")
    }

    func testChapterPrefix() {
        XCTAssertEqual(SearchService.chapterPrefix(forLessonID: "ch12s3"), "ch12")
        XCTAssertNil(SearchService.chapterPrefix(forLessonID: "ABH-01"))
    }

    func testRailDetection() {
        XCTAssertEqual(SearchService.rail(for: entry(id: "x", title: "UPI basics", text: "")), "UPI")
        XCTAssertNil(SearchService.rail(for: entry(id: "x", title: "What a payment is", text: "Money moves.")))
    }

    func testLevenshtein() {
        XCTAssertEqual(SearchService.levenshtein("kitten", "sitting", maxDistance: 3), 3)
        XCTAssertEqual(SearchService.levenshtein("swift", "swift", maxDistance: 2), 0)
        XCTAssertGreaterThan(SearchService.levenshtein("swift", "banana", maxDistance: 2), 2)
    }

    func testRecentSearchesAreCappedAndDeduplicated() {
        SearchService.clearRecentSearches()
        for i in 1...12 {
            SearchService.recordSearch("query \(i)")
        }
        let recents = SearchService.recentSearches()
        XCTAssertEqual(recents.count, 10)
        XCTAssertEqual(recents.first, "query 12")
        SearchService.recordSearch("query 12")
        XCTAssertEqual(SearchService.recentSearches().count, 10, "Re-recording the most recent search adds no duplicate.")
        SearchService.clearRecentSearches()
        XCTAssertTrue(SearchService.recentSearches().isEmpty)
    }

    // MARK: - PracticeStore

    /// Clear stored practice attempts for the current namespace, and
    /// any legacy un-namespaced value that load would adopt back in.
    private func clearPracticeStorage() {
        AccountScopedStorage.setCurrentNamespace(nil)
        UserDefaults.standard.removeObject(forKey: AccountScopedStorage.currentKey("pf.practiceAttempts.v1"))
        UserDefaults.standard.removeObject(forKey: "pf.practiceAttempts.v1")
    }

    @MainActor
    func testPracticeAttemptRecording() {
        clearPracticeStorage()
        let store = PracticeStore()
        XCTAssertEqual(store.totalAttempts, 0)
        XCTAssertNil(store.accuracy, "No attempts yet: accuracy is nil, never a fake 0.")

        let first = store.recordAttempt(situationID: "ABH-01", chosenOptionIndex: 0, isCorrect: false)
        let second = store.recordAttempt(situationID: "ABH-01", chosenOptionIndex: 2, isCorrect: true)
        XCTAssertEqual(store.totalAttempts, 2)
        XCTAssertEqual(store.correctCount, 1)
        XCTAssertEqual(store.accuracy, 50)
        XCTAssertEqual(store.attempts(for: "ABH-01").count, 2, "Both attempts are kept as history.")
        XCTAssertEqual(store.attempts(for: "ABH-01").first?.id, first.id)
        XCTAssertEqual(store.lastAttempt(for: "ABH-01")?.id, second.id)
        XCTAssertNil(store.lastAttempt(for: "ABH-99"))
        XCTAssertTrue(store.hasUnsyncedAttempts, "Guest attempts stay unsynced locally.")
        XCTAssertEqual(store.attempts(for: "ABH-01").first?.chosenOptionIndex, 0)
        XCTAssertFalse(store.attempts(for: "ABH-01").first?.synced ?? true)
    }

    @MainActor
    func testPracticeAttemptsPersistAcrossInstances() {
        clearPracticeStorage()
        let first = PracticeStore()
        first.recordAttempt(situationID: "SCN-26", chosenOptionIndex: 1, isCorrect: true)
        let second = PracticeStore()
        XCTAssertEqual(second.totalAttempts, 1)
        XCTAssertEqual(second.lastAttempt(for: "SCN-26")?.chosenOptionIndex, 1)
        clearPracticeStorage()
    }

    @MainActor
    func testPracticeAttemptsAreStoredUnderNamespacedKey() {
        clearPracticeStorage()
        let store = PracticeStore()
        store.recordAttempt(situationID: "ABH-01", chosenOptionIndex: 0, isCorrect: true)
        let namespacedKey = AccountScopedStorage.currentKey("pf.practiceAttempts.v1")
        XCTAssertNotNil(UserDefaults.standard.data(forKey: namespacedKey), "Attempts must persist under the namespaced key.")
        XCTAssertNil(UserDefaults.standard.object(forKey: "pf.practiceAttempts.v1"), "Attempts must never be written to the raw legacy key.")
        XCTAssertTrue(namespacedKey.hasPrefix("pf.account.guest."), "A guest test runs in the guest namespace.")
        clearPracticeStorage()
    }

    // MARK: - ContentService cache helpers

    func testContentCacheRoundTrip() {
        let data = "window.PA_SITUATIONS = [];".data(using: .utf8)!
        ContentService.saveCache(data, fileName: "pf-test-cache.tmp")
        XCTAssertEqual(ContentService.loadCache(fileName: "pf-test-cache.tmp"), data)
        try? FileManager.default.removeItem(at: ContentService.cacheFileURL(fileName: "pf-test-cache.tmp"))
        XCTAssertNil(ContentService.loadCache(fileName: "pf-test-cache.tmp"))
    }

    func testContentCacheMissingFileIsNil() {
        XCTAssertNil(ContentService.loadCache(fileName: "pf-does-not-exist.tmp"))
    }

    func testSituationStageResolution() throws {
        let json = """
        {"id":"ABH-01","title":"T","level":"foundation","explain":"e","takeaway":"t","stage":3,"stage_name":"Operational exceptions"}
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(FullSituationItem.self, from: json)
        XCTAssertEqual(ContentService.stage(forFullItem: item), 3)
        XCTAssertEqual(ContentService.stageSource(forFullItem: item), .authoritative)
        XCTAssertEqual(ContentService.stageName(forFullItem: item), "Operational exceptions")
    }

    // MARK: - Difficulty filter (multi-select, v91)

    /// Fixture hits for the filter tests: a Foundation lesson (text
    /// hint), an Advanced lesson (text hint), a lesson with no
    /// derivable level, and a situation with no level in the map
    /// (defaults to Core, as situation(from:) does).
    private var filterHits: [SearchHit] {
        [
            SearchHit(entry: entry(id: "ch1s1", title: "Foundation lesson", text: "foundation concepts for beginners"), score: 10, reason: "", matchedTerm: nil),
            SearchHit(entry: entry(id: "ch1s2", title: "Advanced lesson", text: "advanced topics for experts"), score: 9, reason: "", matchedTerm: nil),
            SearchHit(entry: entry(id: "ch1s3", title: "Plain lesson", text: "plain payment text with no level hint"), score: 8, reason: "", matchedTerm: nil),
            SearchHit(entry: entry(id: "ABH-01", title: "A case", text: "plain case text", type: .situation), score: 7, reason: "", matchedTerm: nil)
        ]
    }

    func testLevelFilterInactiveWhenEmptyOrFull() {
        XCTAssertFalse(SearchService.isLevelFilterActive([]))
        XCTAssertFalse(SearchService.isLevelFilterActive(Set(SearchService.allLevels)))
        XCTAssertTrue(SearchService.isLevelFilterActive([.foundation]))
        XCTAssertTrue(SearchService.isLevelFilterActive([.foundation, .core]))
    }

    func testAllLevelsSelectedReturnsHitsUnchanged() {
        let filtered = SearchService.applyLevelFilter(filterHits, selectedLevels: Set(SearchService.allLevels), situationLevelsByID: [:])
        XCTAssertEqual(filtered.map(\.entry.id), filterHits.map(\.entry.id))
        let unfiltered = SearchService.applyLevelFilter(filterHits, selectedLevels: [], situationLevelsByID: [:])
        XCTAssertEqual(unfiltered.map(\.entry.id), filterHits.map(\.entry.id))
    }

    func testPartialFilterKeepsOnlySelectedLevels() {
        let filtered = SearchService.applyLevelFilter(filterHits, selectedLevels: [.foundation, .core], situationLevelsByID: [:])
        XCTAssertEqual(Set(filtered.map(\.entry.id)), ["ch1s1", "ABH-01"])
    }

    func testUnknownLevelEntriesExcludedUnderPartialFilter() {
        let filtered = SearchService.applyLevelFilter(filterHits, selectedLevels: [.foundation], situationLevelsByID: [:])
        XCTAssertEqual(filtered.map(\.entry.id), ["ch1s1"])
    }

    func testSituationDefaultsToCoreLevel() {
        let situation = entry(id: "ABH-01", title: "A case", text: "plain case text", type: .situation)
        XCTAssertEqual(SearchService.levelForEntry(situation, situationLevelsByID: [:]), .core)
        XCTAssertEqual(
            SearchService.levelForEntry(situation, situationLevelsByID: ["ABH-01": "advanced"]),
            .advanced
        )
        let lesson = entry(id: "ch1s3", title: "Plain lesson", text: "plain payment text with no level hint")
        XCTAssertNil(SearchService.levelForEntry(lesson, situationLevelsByID: [:]))
    }

    func testSearchLimitCapsHits() {
        let many = (1...70).map { entry(id: "ch1s\($0)", title: "Payment lesson \($0)", text: "payment text") }
        let capped = SearchService.search(entries: many, query: "payment", limit: 60)
        XCTAssertEqual(capped.count, 60)
        let uncapped = SearchService.search(entries: many, query: "payment", limit: 200)
        XCTAssertEqual(uncapped.count, 70)
    }
}
