// ContentManifestTests.swift
// PaymentForge iOS - Phase 1 (Release integrity) tests: the content
// manifest counts. ContentManifest is the single source of truth for
// catalogue counts; no screen should hardcode these numbers.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: the expected values
// were read from the brief and from ContentManifest itself before
// writing, and cross-checked against the catalogue where a second
// source exists.

import XCTest
@testable import PaymentForge

final class ContentManifestTests: XCTestCase {

    func testAllTenCountsEqualSpecifiedValues() {
        XCTAssertEqual(ContentManifest.chapterCount, 100)
        XCTAssertEqual(ContentManifest.lessonCount, 881)
        XCTAssertEqual(ContentManifest.situationCount, 564)
        XCTAssertEqual(ContentManifest.interviewQuestionCount, 500)
        XCTAssertEqual(ContentManifest.faqCount, 320)
        XCTAssertEqual(ContentManifest.simulatorCount, 10)
        XCTAssertEqual(ContentManifest.guideCount, 45)
        XCTAssertEqual(ContentManifest.testCount, 15)
        XCTAssertEqual(ContentManifest.labCount, 10)
        XCTAssertEqual(ContentManifest.domainCount, 15)
    }

    func testChapterCountMatchesFullCourseCatalogue() {
        XCTAssertEqual(
            ContentManifest.chapterCount,
            ProductCatalogue.product(for: ProductCatalogue.fullCourseProductID)?.chapterIDs.count,
            "The manifest chapter count and the full course chapter list must agree."
        )
    }

    func testSituationCountMatchesCatalogueSituationsProduct() {
        XCTAssertEqual(
            ContentManifest.situationCount,
            ProductCatalogue.product(for: ProductCatalogue.situationsProductID)?.situationCount,
            "The manifest situation count and the catalogue Situations count must agree at 564, not the frozen 500 in PaymentConfig."
        )
        XCTAssertEqual(ContentManifest.situationCount, 564)
    }

    func testFreeSamplesAreASmallSubsetOfAllSituations() {
        XCTAssertEqual(ProductCatalogue.freeSampleSituationIDs.count, 6)
        XCTAssertLessThan(ProductCatalogue.freeSampleSituationIDs.count, ContentManifest.situationCount)
    }
}
