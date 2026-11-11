// SearchAndPracticeTests.swift
// PaymentForge iOS - Phase 7 unit tests: data repositories.
// SearchService ranking (title outranks body, synonym expansion,
// typo tolerance) and PracticeStore attempt recording (history is
// kept, accuracy is nil before any attempt, never 0 as a fake
// score). No network: all entries are fixtures built in this file.

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

    @MainActor
    func testPracticeAttemptRecording() {
        UserDefaults.standard.removeObject(forKey: "pf.practiceAttempts.v1")
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
        UserDefaults.standard.removeObject(forKey: "pf.practiceAttempts.v1")
        let first = PracticeStore()
        first.recordAttempt(situationID: "SCN-26", chosenOptionIndex: 1, isCorrect: true)
        let second = PracticeStore()
        XCTAssertEqual(second.totalAttempts, 1)
        XCTAssertEqual(second.lastAttempt(for: "SCN-26")?.chosenOptionIndex, 1)
        UserDefaults.standard.removeObject(forKey: "pf.practiceAttempts.v1")
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
}
