// CatchUpV94Tests.swift
// TrainingHub iOS - v94 catch-up tests: the paged-data decodes
// (compact search index, situations index, detail chunks), the
// CrashCapture pure helpers, and the tour step list with no
// duplicates. The decodes pin the live website shapes, verified
// against the deployed files on 16 Nov 2026: the compact index
// carries tags/excerpt/chapter/domain and no full text, the
// situations index carries integer stages, and the detail chunks
// carry seq and stage as strings.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests
// were never compiled or run. Statically checked only: the
// fixture shapes were read from the live deployed files before
// writing, and every asserted value follows the decoder code.

import XCTest
@testable import TrainingHub

final class CatchUpV94Tests: XCTestCase {

    // MARK: - Situations index document

    func testSituationsIndexDocDecodesLiveShape() throws {
        let json = """
        {"total": 564, "chunkSize": 28, "items": [
            {"id": "ABH-01", "title": "A stuck payment", "level": "core", "stage": 1, "stage_name": "Payment mechanics", "domain": "Payments", "chunk": 0},
            {"id": "JEB-C01", "title": "A second case", "level": "foundation", "stage": "2", "stage_name": "Processing decisions", "domain": "Payments", "chunk": 0}
        ]}
        """
        let doc = try JSONDecoder().decode(SituationsIndexDoc.self, from: Data(json.utf8))
        XCTAssertEqual(doc.total, 564)
        XCTAssertEqual(doc.chunkSize, 28)
        XCTAssertEqual(doc.items.count, 2)
        XCTAssertEqual(doc.items[0].id, "ABH-01")
        XCTAssertEqual(doc.items[0].stage, 1)
        XCTAssertEqual(doc.items[0].stageName, "Payment mechanics")
        XCTAssertEqual(doc.items[0].chunk, 0)
        XCTAssertEqual(doc.items[1].stage, 2)
    }

    func testSituationsIndexEntryMissingStageIsNil() throws {
        let json = """
        {"id": "ABH-01", "title": "A stuck payment", "level": "core"}
        """
        let entry = try JSONDecoder().decode(SituationsIndexEntry.self, from: Data(json.utf8))
        XCTAssertNil(entry.stage)
        XCTAssertNil(entry.stageName)
        XCTAssertNil(entry.chunk)
    }

    // MARK: - Detail chunk items (string seq and stage)

    func testFullSituationItemDecodesStringSeqAndStage() throws {
        let json = """
        {"id": "ABH-01", "title": "A stuck payment", "level": "core", "seq": "1", "stage": "1", "explain": "Why it stuck.", "takeaway": "Check first."}
        """
        let item = try JSONDecoder().decode(FullSituationItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.seq, 1)
        XCTAssertEqual(item.stage, 1)
        XCTAssertEqual(item.explain, "Why it stuck.")
    }

    func testFullSituationItemDecodesIntSeqAndStage() throws {
        let json = """
        {"id": "ABH-01", "title": "A stuck payment", "level": "core", "seq": 1, "stage": 1, "explain": "Why it stuck.", "takeaway": "Check first."}
        """
        let item = try JSONDecoder().decode(FullSituationItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.seq, 1)
        XCTAssertEqual(item.stage, 1)
    }

    // MARK: - Search entries (compact and full shapes)

    func testSearchEntryDecodesCompactShape() throws {
        let json = """
        {"id": "ch1s1", "title": "What is a payment", "url": "/lessons/ch1s1", "type": "lesson", "tags": ["MT103", "payment"], "excerpt": "A short excerpt.", "chapter": "Accounts and balances", "domain": "APIs and Integration"}
        """
        let entry = try JSONDecoder().decode(SearchEntry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.text, "")
        XCTAssertEqual(entry.tags, ["MT103", "payment"])
        XCTAssertEqual(entry.excerpt, "A short excerpt.")
        XCTAssertEqual(entry.chapterName, "Accounts and balances")
        XCTAssertEqual(entry.preview, "A short excerpt.")
        XCTAssertTrue(entry.searchText.contains("MT103"))
        XCTAssertTrue(entry.searchText.contains("A short excerpt."))
    }

    func testSearchEntryDecodesFullShape() throws {
        let json = """
        {"id": "ch1s1", "title": "What is a payment", "url": "/lessons/ch1s1", "type": "lesson", "text": "The full lesson text."}
        """
        let entry = try JSONDecoder().decode(SearchEntry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.text, "The full lesson text.")
        XCTAssertEqual(entry.tags, [])
        XCTAssertNil(entry.excerpt)
        XCTAssertEqual(entry.preview, "The full lesson text.")
        XCTAssertEqual(entry.searchText, "The full lesson text.")
    }

    func testSearchEntryPreviewTruncatesAt140Characters() throws {
        let longText = String(repeating: "w", count: 200)
        let json = """
        {"id": "ch1s1", "title": "T", "url": "/u", "type": "lesson", "text": "\(longText)"}
        """
        let entry = try JSONDecoder().decode(SearchEntry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.preview.count, 143)
        XCTAssertTrue(entry.preview.hasSuffix("..."))
    }

    // MARK: - CrashCapture pure helpers

    func testCrashHeadlinePrefersExceptionLine() {
        let report = "TrainingHub crash report\nException: Index out of range\nThread 0 trace"
        XCTAssertEqual(CrashCapture.headlineFor(report), "Index out of range")
    }

    func testCrashHeadlineFallsBackToFirstLine() {
        let report = "Uncaught signal 11\nThread 0 trace"
        XCTAssertEqual(CrashCapture.headlineFor(report), "Uncaught signal 11")
    }

    func testCrashHeadlineEmptyReportIsDefault() {
        XCTAssertEqual(CrashCapture.headlineFor(""), "Crash report")
        XCTAssertEqual(CrashCapture.headlineFor("  \n  "), "Crash report")
    }

    func testFilesToKeepKeepsNewest() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let files = (0..<7).map { (name: "report-\($0).txt", modified: base.addingTimeInterval(TimeInterval($0 * 60))) }
        let kept = CrashCapture.filesToKeep(files, maxCount: 5)
        XCTAssertEqual(kept.count, 5)
        XCTAssertTrue(kept.contains("report-6.txt"))
        XCTAssertTrue(kept.contains("report-2.txt"))
        XCTAssertFalse(kept.contains("report-1.txt"))
        XCTAssertFalse(kept.contains("report-0.txt"))
    }

    func testFilesToKeepFewerThanMaxKeepsAll() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let files = (0..<3).map { (name: "report-\($0).txt", modified: base.addingTimeInterval(TimeInterval($0 * 60))) }
        XCTAssertEqual(CrashCapture.filesToKeep(files, maxCount: 5).count, 3)
    }

    func testTruncateReportShortUnchanged() {
        XCTAssertEqual(CrashCapture.truncateReport("short report"), "short report")
    }

    func testTruncateReportLongTruncatedWithMarker() {
        let long = String(repeating: "x", count: CrashCapture.maxReportChars + 1)
        let truncated = CrashCapture.truncateReport(long)
        XCTAssertTrue(truncated.hasSuffix("\n[truncated]"))
        XCTAssertEqual(truncated.count, CrashCapture.maxReportChars + "\n[truncated]".count)
    }

    // MARK: - Tour step list, no duplicates

    func testTourStepTitlesAreUnique() {
        let titles = NavigationTourOverlay.tourStepTitles
        XCTAssertEqual(titles.count, 7)
        XCTAssertEqual(Set(titles).count, titles.count)
    }

    func testTourTabStepsTargetDifferentTabs() {
        let tabIndices = NavigationTourOverlay.tourStepTabIndices.compactMap { $0 }
        XCTAssertEqual(tabIndices.count, 4)
        XCTAssertEqual(Set(tabIndices).count, tabIndices.count)
    }
}
