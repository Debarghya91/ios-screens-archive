// SearchAndPracticeTests.swift
// TrainingHub iOS - Phase 7 unit tests: data repositories.
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
@testable import TrainingHub

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

// MARK: - Wave 2: pagination and level filter at catalogue scale
//
// UNEXECUTED: written on a Linux VM with no Xcode. Never compiled
// or run. Statically checked only.
//
// The search and case lists page at 20 with an explicit Load More
// action; these tests exercise the rules behind that paging with
// full-size generated fixtures (881 lessons, 616 cases), the same
// shapes the live catalogue carries. The views' @State page counts
// themselves are SwiftUI state and are statically checked only:
// what is proven here is that the search, the filter, and the
// 20-item slicing cover every result exactly once, and that the
// wave-1 all-selected filter rule holds at full size.

final class Wave2PaginationTests: XCTestCase {

    private func lessonEntries(_ count: Int) -> [SearchEntry] {
        (1...count).map { n in
            SearchEntry(
                id: "ch\(n % 100 + 1)s\(n)",
                title: "Lesson \(n) on payment settlement",
                url: "/ch\(n % 100 + 1)s\(n)",
                type: .lesson,
                text: "Payment settlement lesson \(n) covering clearing, nostro reconciliation and exception handling."
            )
        }
    }

    private func situationEntries(_ count: Int) -> [SearchEntry] {
        let levels = ["foundation", "core", "advanced"]
        return (1...count).map { n in
            SearchEntry(
                id: "sit-\(String(format: "%03d", n))",
                title: "Case \(n): payment stuck in investigation",
                url: "/case-\(n)",
                type: .situation,
                text: "A \(levels[n % 3]) payment case about an MT103 stuck in investigation with a missing cover payment."
            )
        }
    }

    func testSearchOverFullCatalogueScaleReturnsEveryEntryOnce() {
        let entries = lessonEntries(881) + situationEntries(616)
        let hits = SearchService.search(entries: entries, query: "payment", limit: 2000)
        XCTAssertEqual(hits.count, entries.count)
        XCTAssertEqual(Set(hits.map(\.id)).count, hits.count)
    }

    func testDefaultSearchLimitCapsResults() {
        let entries = lessonEntries(881) + situationEntries(616)
        let hits = SearchService.search(entries: entries, query: "payment")
        XCTAssertEqual(hits.count, 60)
    }

    func testTwentyItemPagingCoversAllResultsExactlyOnce() {
        let entries = situationEntries(616)
        let hits = SearchService.search(entries: entries, query: "payment", limit: 2000)
        var shown = 0
        var seen: Set<String> = []
        var pages = 0
        while shown < hits.count {
            let page = Array(hits[shown..<min(shown + 20, hits.count)])
            pages += 1
            for hit in page {
                XCTAssertTrue(seen.insert(hit.id).inserted, "Duplicate id \(hit.id) across pages")
            }
            shown += page.count
        }
        XCTAssertEqual(shown, 616)
        XCTAssertEqual(pages, 31)
        XCTAssertEqual(seen.count, 616)
    }

    func testAllLevelsSelectedLeavesFullResultsUnfiltered() {
        let entries = situationEntries(616)
        let hits = SearchService.search(entries: entries, query: "payment", limit: 2000)
        let levelsByID = Dictionary(uniqueKeysWithValues: entries.enumerated().map { index, entry in
            (entry.id, ["foundation", "core", "advanced"][(index + 1) % 3])
        })
        let filtered = SearchService.applyLevelFilter(
            hits,
            selectedLevels: Set(SearchService.allLevels),
            situationLevelsByID: levelsByID
        )
        XCTAssertEqual(filtered.map(\.id), hits.map(\.id))
    }

    func testEmptyLevelSelectionLeavesResultsUnfiltered() {
        let entries = situationEntries(616)
        let hits = SearchService.search(entries: entries, query: "payment", limit: 2000)
        let filtered = SearchService.applyLevelFilter(
            hits,
            selectedLevels: [],
            situationLevelsByID: [:]
        )
        XCTAssertEqual(filtered.map(\.id), hits.map(\.id))
    }

    func testPartialLevelSelectionKeepsOnlyThatLevel() {
        let entries = situationEntries(616)
        let hits = SearchService.search(entries: entries, query: "payment", limit: 2000)
        let levelsByID = Dictionary(uniqueKeysWithValues: entries.enumerated().map { index, entry in
            (entry.id, ["foundation", "core", "advanced"][(index + 1) % 3])
        })
        let filtered = SearchService.applyLevelFilter(
            hits,
            selectedLevels: [.foundation],
            situationLevelsByID: levelsByID
        )
        XCTAssertFalse(filtered.isEmpty)
        XCTAssertTrue(filtered.count < hits.count)
        for hit in filtered {
            XCTAssertEqual(
                SearchService.levelForEntry(hit.entry, situationLevelsByID: levelsByID),
                .foundation
            )
        }
    }
}

// MARK: - Numbered pagination rules (v96)

/// The PFPagination rules behind the numbered Search and Payment
/// Cases bars: 20 per page, ellipsis windows, range bounds, and
/// page slicing. Pure logic, no UI: the bars themselves are
/// statically checked only, never compiled or run here.
final class NumberedPaginationTests: XCTestCase {

    func testTotalPages() {
        XCTAssertEqual(PFPagination.totalPages(totalCount: 0), 0)
        XCTAssertEqual(PFPagination.totalPages(totalCount: 1), 1)
        XCTAssertEqual(PFPagination.totalPages(totalCount: 20), 1)
        XCTAssertEqual(PFPagination.totalPages(totalCount: 21), 2)
        XCTAssertEqual(PFPagination.totalPages(totalCount: 564), 29)
        XCTAssertEqual(PFPagination.totalPages(totalCount: 881), 45)
    }

    func testClampedPage() {
        XCTAssertEqual(PFPagination.clampedPage(0, totalPages: 29), 1)
        XCTAssertEqual(PFPagination.clampedPage(-3, totalPages: 29), 1)
        XCTAssertEqual(PFPagination.clampedPage(30, totalPages: 29), 29)
        XCTAssertEqual(PFPagination.clampedPage(7, totalPages: 29), 7)
        XCTAssertEqual(PFPagination.clampedPage(5, totalPages: 0), 1)
    }

    func testSliceCoversEveryItemExactlyOnce() {
        let items = Array(1...564)
        var seen: [Int] = []
        let pages = PFPagination.totalPages(totalCount: items.count)
        XCTAssertEqual(pages, 29)
        for page in 1...pages {
            seen += PFPagination.slice(items, page: page)
        }
        XCTAssertEqual(seen, items)
        XCTAssertEqual(PFPagination.slice(items, page: 1).count, 20)
        XCTAssertEqual(PFPagination.slice(items, page: 29), Array(561...564))
        XCTAssertEqual(PFPagination.slice(items, page: 99), Array(561...564))
        XCTAssertEqual(PFPagination.slice(items, page: 0), Array(1...20))
        XCTAssertTrue(PFPagination.slice([], page: 1).isEmpty)
    }

    func testRangeBounds() {
        XCTAssertEqual(PFPagination.rangeBounds(page: 1, totalCount: 564).first, 1)
        XCTAssertEqual(PFPagination.rangeBounds(page: 1, totalCount: 564).last, 20)
        XCTAssertEqual(PFPagination.rangeBounds(page: 29, totalCount: 564).first, 561)
        XCTAssertEqual(PFPagination.rangeBounds(page: 29, totalCount: 564).last, 564)
        XCTAssertEqual(PFPagination.rangeBounds(page: 2, totalCount: 21).first, 21)
        XCTAssertEqual(PFPagination.rangeBounds(page: 2, totalCount: 21).last, 21)
        XCTAssertEqual(PFPagination.rangeBounds(page: 1, totalCount: 0).first, 0)
        XCTAssertEqual(PFPagination.rangeBounds(page: 1, totalCount: 0).last, 0)
    }

    func testItemsForShortRangesShowEveryPage() {
        XCTAssertEqual(
            PFPagination.items(totalPages: 1, currentPage: 1),
            [.page(1)]
        )
        XCTAssertEqual(
            PFPagination.items(totalPages: 7, currentPage: 4),
            [.page(1), .page(2), .page(3), .page(4), .page(5), .page(6), .page(7)]
        )
        XCTAssertTrue(PFPagination.items(totalPages: 0, currentPage: 1).isEmpty)
    }

    func testItemsForLongRangesUseEllipsisWindows() {
        XCTAssertEqual(
            PFPagination.items(totalPages: 29, currentPage: 1),
            [.page(1), .page(2), .page(3), .page(4), .page(5), .ellipsis, .page(29)]
        )
        XCTAssertEqual(
            PFPagination.items(totalPages: 29, currentPage: 7),
            [.page(1), .ellipsis, .page(6), .page(7), .page(8), .ellipsis, .page(29)]
        )
        XCTAssertEqual(
            PFPagination.items(totalPages: 29, currentPage: 29),
            [.page(1), .ellipsis, .page(25), .page(26), .page(27), .page(28), .page(29)]
        )
        XCTAssertEqual(
            PFPagination.items(totalPages: 29, currentPage: 28),
            [.page(1), .ellipsis, .page(25), .page(26), .page(27), .page(28), .page(29)]
        )
        XCTAssertEqual(
            PFPagination.items(totalPages: 8, currentPage: 4),
            [.page(1), .page(2), .page(3), .page(4), .page(5), .ellipsis, .page(8)]
        )
    }

    func testItemsNeverExceedSevenTokens() {
        for total in 1...60 {
            for current in 1...total {
                let tokens = PFPagination.items(totalPages: total, currentPage: current)
                XCTAssertLessThanOrEqual(tokens.count, 7, "total \(total) page \(current)")
                XCTAssertTrue(tokens.contains(.page(current)), "current page missing: total \(total) page \(current)")
                XCTAssertTrue(tokens.contains(.page(1)))
                XCTAssertTrue(tokens.contains(.page(total)))
            }
        }
    }

    func testItemsNeverShowAGapOfOneHiddenPage() {
        // An ellipsis must hide at least two pages: 1 ... 3 would
        // hide only page 2 behind a gap, which reads as broken.
        // And numbers with no ellipsis between them must be
        // consecutive, so no page silently disappears.
        for total in 1...60 {
            for current in 1...total {
                let tokens = PFPagination.items(totalPages: total, currentPage: current)
                var previous: Int?
                var gapSincePrevious = false
                for token in tokens {
                    switch token {
                    case .ellipsis:
                        gapSincePrevious = true
                    case .page(let number):
                        if let prev = previous {
                            if gapSincePrevious {
                                XCTAssertGreaterThanOrEqual(
                                    number - prev, 3,
                                    "ellipsis hides one page: total \(total) page \(current)"
                                )
                            } else {
                                XCTAssertEqual(
                                    number, prev + 1,
                                    "missing page without ellipsis: total \(total) page \(current)"
                                )
                            }
                        }
                        previous = number
                        gapSincePrevious = false
                    }
                }
            }
        }
    }
}
