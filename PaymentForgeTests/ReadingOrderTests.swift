// ReadingOrderTests.swift
// PaymentForge iOS - Book mode reading order tests: the single map
// in ReadingOrder.swift. The map is the only source of display
// numbers in the app, so these tests pin its shape: 99 book
// chapters, ch37 held out with no book number, every internal
// chapter covered exactly once, parts contiguous, and reading
// sort order for lessons.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: the expected
// values were read from the structure document appendix before
// writing.

import XCTest
@testable import PaymentForge

final class ReadingOrderTests: XCTestCase {

    func testBookHas99ChaptersInOrder() {
        XCTAssertEqual(PFBookModeReadingOrder.internalNumbersInReadingOrder.count, 99)
        XCTAssertEqual(Set(PFBookModeReadingOrder.internalNumbersInReadingOrder).count, 99)
        for book in 1...99 {
            XCTAssertNotNil(
                PFBookModeReadingOrder.internalNumber(forBookNumber: book),
                "Book chapter \(book) has no internal chapter."
            )
        }
        XCTAssertNil(PFBookModeReadingOrder.internalNumber(forBookNumber: 0))
        XCTAssertNil(PFBookModeReadingOrder.internalNumber(forBookNumber: 100))
    }

    func testHeldOutChapter37HasNoBookNumber() {
        XCTAssertTrue(PFBookModeReadingOrder.isHeldOut(internalNumber: 37))
        XCTAssertNil(PFBookModeReadingOrder.bookNumber(forInternalNumber: 37))
        XCTAssertNil(PFBookModeReadingOrder.bookNumber(forChapterID: "ch37"))
        XCTAssertNil(PFBookModeReadingOrder.chapterLabel(forInternalNumber: 37))
        XCTAssertNil(PFBookModeReadingOrder.part(forInternalNumber: 37))
        XCTAssertFalse(PFBookModeReadingOrder.internalNumbersInReadingOrder.contains(37))
    }

    func testEveryInternalChapterCoveredExactlyOnce() {
        let covered = Set(PFBookModeReadingOrder.internalNumbersInReadingOrder)
            .union(PFBookModeReadingOrder.heldOutInternalNumbers)
        XCTAssertEqual(covered, Set(1...100))
    }

    func testSpotCheckMappingsFromAppendix() {
        XCTAssertEqual(PFBookModeReadingOrder.bookNumber(forInternalNumber: 1), 1)
        XCTAssertEqual(PFBookModeReadingOrder.bookNumber(forInternalNumber: 64), 5)
        XCTAssertEqual(PFBookModeReadingOrder.bookNumber(forInternalNumber: 38), 26)
        XCTAssertEqual(PFBookModeReadingOrder.bookNumber(forInternalNumber: 85), 99)
        XCTAssertEqual(PFBookModeReadingOrder.bookNumber(forChapterID: "ch38"), 26)
        XCTAssertEqual(PFBookModeReadingOrder.internalNumber(forBookNumber: 26), 38)
        XCTAssertEqual(PFBookModeReadingOrder.chapterLabel(forInternalNumber: 38), "Chapter 26")
    }

    func testPartsCoverBooks1To99Contiguously() {
        let parts = PFBookModeReadingOrder.parts
        XCTAssertEqual(parts.count, 10)
        var next = 1
        for part in parts {
            XCTAssertEqual(part.bookNumbers.lowerBound, next)
            XCTAssertGreaterThan(part.bookNumbers.upperBound, part.bookNumbers.lowerBound)
            next = part.bookNumbers.upperBound + 1
        }
        XCTAssertEqual(next, 100)
        XCTAssertEqual(PFBookModeReadingOrder.part(forBookNumber: 1)?.number, 1)
        XCTAssertEqual(PFBookModeReadingOrder.part(forBookNumber: 99)?.number, 10)
        XCTAssertEqual(PFBookModeReadingOrder.part(forInternalNumber: 38)?.number, 3)
    }

    func testAdjacentChaptersFollowReadingOrder() {
        let first = PFBookModeReadingOrder.adjacentChapters(forInternalNumber: 1)
        XCTAssertNil(first.previous)
        XCTAssertEqual(first.next, 2)
        let middle = PFBookModeReadingOrder.adjacentChapters(forInternalNumber: 38)
        XCTAssertEqual(middle.previous, 8)
        XCTAssertEqual(middle.next, 54)
        let last = PFBookModeReadingOrder.adjacentChapters(forInternalNumber: 85)
        XCTAssertEqual(last.previous, 27)
        XCTAssertNil(last.next)
        let heldOut = PFBookModeReadingOrder.adjacentChapters(forInternalNumber: 37)
        XCTAssertNil(heldOut.previous)
        XCTAssertNil(heldOut.next)
    }

    func testSortedForReadingOrdersChaptersThenSupplementalLast() {
        func entry(_ id: String) -> SearchEntry {
            SearchEntry(id: id, title: id, url: "", type: .lesson, text: "")
        }
        let lessons = [
            entry("ch38s2"), entry("ch1s2"), entry("ch1s1"),
            entry("ch54s901-supp"), entry("ch1s901-supp"), entry("ch37s1"),
        ]
        let sorted = PFBookModeReadingOrder.sortedForReading(lessons)
        XCTAssertEqual(
            sorted.map(\.id),
            ["ch1s1", "ch1s2", "ch1s901-supp", "ch38s2", "ch54s901-supp", "ch37s1"]
        )
    }

    func testOrderedChaptersMatchInternalOrder() {
        XCTAssertEqual(PFBookModeReadingOrder.orderedChapters.count, 99)
        XCTAssertEqual(PFBookModeReadingOrder.orderedChapters.first, "ch1")
        XCTAssertEqual(PFBookModeReadingOrder.orderedChapters[25], "ch38")
        XCTAssertEqual(PFBookModeReadingOrder.orderedChapters.last, "ch85")
        XCTAssertFalse(PFBookModeReadingOrder.mapVersion.isEmpty)
    }

    func testDisplayNumbersComeFromTheMap() {
        XCTAssertEqual(PFBookModeReadingOrder.displayNumber(forLessonID: "ch1s1"), 1)
        XCTAssertEqual(PFBookModeReadingOrder.displayNumber(forLessonID: "ch1s7"), 7)
        XCTAssertEqual(PFBookModeReadingOrder.displayNumber(forLessonID: "ch38s2"), 2)
        XCTAssertNil(PFBookModeReadingOrder.displayNumber(forLessonID: "ch54s901-supp"))
        XCTAssertNil(PFBookModeReadingOrder.displayNumber(forLessonID: "ch1s99"))
    }

    func testNextAndPreviousLessonCrossChapterBoundaries() {
        XCTAssertEqual(PFBookModeReadingOrder.nextLesson(after: "ch1s7"), "ch2s1")
        XCTAssertEqual(PFBookModeReadingOrder.previousLesson(before: "ch2s1"), "ch1s7")
        XCTAssertNil(PFBookModeReadingOrder.previousLesson(before: "ch1s1"))
        XCTAssertNil(PFBookModeReadingOrder.nextLesson(after: "ch1s99"))
    }

    func testMapDocumentDecodingAndValidation() throws {
        let json = """
        {
          "version": "test-1",
          "status": "draft",
          "parts": [
            {"part": 1, "title": "Part One", "chapters": [
              {"id": "ch1", "book_number": 1, "lessons": [
                {"id": "ch1s1", "display_number": 1}
              ]}
            ]}
          ],
          "held_out": [{"id": "ch37", "book_number": null, "reason": "Held out"}]
        }
        """
        let decoded = try JSONDecoder().decode(
            PFBookModeReadingOrder.MapDocument.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(decoded.version, "test-1")
        XCTAssertEqual(decoded.parts.first?.chapters.first?.id, "ch1")
        XCTAssertEqual(decoded.parts.first?.chapters.first?.lessons.first?.displayNumber, 1)
        XCTAssertNil(decoded.heldOut.first?.bookNumber)
        XCTAssertFalse(decoded.isValid, "A one-chapter map must not validate: 99 chapters are required.")
    }
}
