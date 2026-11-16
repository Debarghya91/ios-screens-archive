// ContentManifestTests.swift
// TrainingHub iOS - Phase 1 (Release integrity) tests: the content
// manifest counts. ContentManifest is the single source of truth for
// catalogue counts; no screen should hardcode these numbers.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: the expected values
// were read from the brief and from ContentManifest itself before
// writing, and cross-checked against the catalogue where a second
// source exists.

import XCTest
@testable import TrainingHub

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

    func testChapterCountMatchesIntegratedCataloguePlusHeldOut() {
        XCTAssertEqual(ContentManifest.chapterCount, 100)
        XCTAssertEqual(
            ProductCatalogue.product(for: ProductCatalogue.integratedProductID)?.chapterIDs.count,
            99,
            "The Integrated Course covers the 99 in-book chapters; ch37 is held out and never sold."
        )
        XCTAssertEqual(
            ContentManifest.chapterCount,
            (ProductCatalogue.product(for: ProductCatalogue.integratedProductID)?.chapterIDs.count ?? 0) + ProductCatalogue.heldOutChapterIDs.count,
            "The manifest chapter count is the Integrated chapter list plus the held-out chapter."
        )
    }

    func testSituationCountMatchesCataloguePracticeProduct() {
        XCTAssertEqual(
            ContentManifest.situationCount,
            ProductCatalogue.product(for: ProductCatalogue.practiceProductID)?.situationCount,
            "The manifest situation count and the catalogue Practice Experiences count must agree at 564, not the frozen 500 in PaymentConfig."
        )
        XCTAssertEqual(ContentManifest.situationCount, 564)
    }

    func testFreeSamplesAreASmallSubsetOfAllSituations() {
        XCTAssertEqual(ProductCatalogue.freeSampleSituationIDs.count, 2)
        XCTAssertLessThan(ProductCatalogue.freeSampleSituationIDs.count, ContentManifest.situationCount)
    }

    // MARK: - Thumbnail URLs (v91)

    func testThumbnailURLResolvesRelativePathsAgainstBase() {
        let base = URL(string: "https://www.paymentstraininghub.com")!
        XCTAssertEqual(
            PFThumbnailURL.resolve("assets/thumbs/ch1s1.svg", base: base)?.absoluteString,
            "https://www.paymentstraininghub.com/assets/thumbs/ch1s1.svg"
        )
        XCTAssertEqual(
            PFThumbnailURL.resolve("/assets/thumbs/ch1s1.png", base: base)?.absoluteString,
            "https://www.paymentstraininghub.com/assets/thumbs/ch1s1.png"
        )
    }

    func testThumbnailURLPassesAbsoluteURLsThrough() {
        let base = URL(string: "https://www.paymentstraininghub.com")!
        XCTAssertEqual(
            PFThumbnailURL.resolve("https://cdn.example.com/thumb.png", base: base)?.absoluteString,
            "https://cdn.example.com/thumb.png"
        )
    }

    func testThumbnailURLReturnsNilForMissingOrBlankPaths() {
        let base = URL(string: "https://www.paymentstraininghub.com")!
        XCTAssertNil(PFThumbnailURL.resolve(nil, base: base))
        XCTAssertNil(PFThumbnailURL.resolve("", base: base))
        XCTAssertNil(PFThumbnailURL.resolve("   ", base: base))
    }

    func testThumbnailSVGDetection() {
        XCTAssertTrue(PFThumbnailURL.isSVG(URL(string: "https://example.com/thumb.svg")!))
        XCTAssertTrue(PFThumbnailURL.isSVG(URL(string: "https://example.com/thumb.SVG?v=2")!))
        XCTAssertFalse(PFThumbnailURL.isSVG(URL(string: "https://example.com/thumb.png")!))
    }
}

// MARK: - Wave 2: thumbnail data, case dedupe, audio URLs, timings
//
// UNEXECUTED: written on a Linux VM with no Xcode. Never compiled
// or run. Statically checked only.
//
// The thumbnail join, the case-list identity rule, the audio URL
// builder, and the timing labels are all exercised here with
// realistic data shapes: a full-size agendas document (881
// lessons, 100 chapters, 11 courses), 616 decoded cases, hostile
// file names, and real narration word counts. The SwiftUI
// rendering of thumbnails in each list, and the LessonView dual
// listen/read composition, stay statically checked only: they
// need a running view hierarchy, and the bundle-backed listen
// label reads Bundle.main, which is the test runner in this
// target, not the app bundle.

final class Wave2ContentDataTests: XCTestCase {

    private func agendasJSON() -> Data {
        var lessons: [String] = []
        for n in 1...881 {
            lessons.append("\"lesson-\(n)\":{\"agenda\":\"Why lesson \(n) matters.\",\"thumbnail\":\"assets/thumbs/lesson-\(n).svg\"}")
        }
        var chapters: [String] = []
        for n in 1...100 {
            chapters.append("\"ch\(n)\":{\"agenda\":\"Why chapter \(n) matters.\",\"thumbnail\":\"assets/thumbs/ch\(n).svg\"}")
        }
        var courses: [String] = ["\"integrated\":{\"agenda\":\"The full course.\",\"thumbnail\":\"assets/thumbs/integrated.svg\"}"]
        for n in 1...10 {
            courses.append("\"part-\(n)\":{\"agenda\":\"Why course \(n) matters.\",\"thumbnail\":\"assets/thumbs/part-\(n).svg\"}")
        }
        let json = "{\"lessons\":{\(lessons.joined(separator: ","))},\"chapters\":{\(chapters.joined(separator: ","))},\"courses\":{\(courses.joined(separator: ","))}}"
        return Data(json.utf8)
    }

    func testAgendasDocumentDecodesAtFullScaleWithThumbnails() throws {
        let document = try JSONDecoder().decode(AgendasDocument.self, from: agendasJSON())
        XCTAssertEqual(document.lessons.count, 881)
        XCTAssertEqual(document.chapters.count, 100)
        XCTAssertEqual(document.courses.count, 11)
        let base = URL(string: "https://www.paymentstraininghub.com/")!
        for (key, entry) in document.lessons {
            XCTAssertFalse(entry.agenda?.isEmpty ?? true, "Lesson \(key) has no agenda")
            let url = PFThumbnailURL.resolve(entry.thumbnail, base: base)
            XCTAssertNotNil(url, "Lesson \(key) thumbnail does not resolve")
            XCTAssertEqual(url?.scheme, "https")
        }
        for (key, entry) in document.chapters {
            XCTAssertNotNil(PFThumbnailURL.resolve(entry.thumbnail, base: base), "Chapter \(key)")
        }
        for (key, entry) in document.courses {
            XCTAssertNotNil(PFThumbnailURL.resolve(entry.thumbnail, base: base), "Course \(key)")
        }
    }

    private func fullSituationJSON(id: String, title: String) -> String {
        "{\"id\":\"\(id)\",\"title\":\"\(title)\",\"level\":\"core\",\"explain\":\"\(String(repeating: "word ", count: 200))\",\"takeaway\":\"\(String(repeating: "word ", count: 58))\",\"stage\":3,\"stage_name\":\"Investigation\",\"agenda\":\"Why this case matters.\",\"thumbnail\":\"assets/thumbs/\(id).svg\"}"
    }

    func testCaseDecodeAtFullScaleKeepsUniqueIDsAndThumbnails() throws {
        let items = (1...616).map { fullSituationJSON(id: "sit-\(String(format: "%03d", $0))", title: "Case \($0)") }
        let data = Data("[\(items.joined(separator: ","))]".utf8)
        let decoded = try JSONDecoder().decode([FullSituationItem].self, from: data)
        XCTAssertEqual(decoded.count, 616)
        XCTAssertEqual(Set(decoded.map(\.id)).count, 616)
        let situations = decoded.map(situation(fromFull:))
        for situation in situations {
            XCTAssertNotNil(situation.agenda)
            XCTAssertNotNil(situation.thumbnail)
        }
        XCTAssertEqual(ContentService.dedupedSituations(decoded).count, 616)
    }

    func testDedupedSituationsKeepsFirstOccurrenceInOrder() throws {
        let json = "[\(fullSituationJSON(id: "a", title: "First A")),\(fullSituationJSON(id: "b", title: "B")),\(fullSituationJSON(id: "a", title: "Second A"))]"
        let decoded = try JSONDecoder().decode([FullSituationItem].self, from: Data(json.utf8))
        let deduped = ContentService.dedupedSituations(decoded)
        XCTAssertEqual(deduped.map(\.id), ["a", "b"])
        XCTAssertEqual(deduped.first?.title, "First A")
    }

    func testAudioURLBuilderEncodesHostileFileNamesInsteadOfCrashing() {
        let spaced = ContentService.primaryAudioURL(fileName: "ch1 s1.mp3")
        XCTAssertNotNil(spaced)
        XCTAssertEqual(spaced?.absoluteString, "https://paymentforge-audio.pages.dev/audio/ch1%20s1.mp3")
        XCTAssertFalse(spaced?.absoluteString.contains(" ") ?? true)

        let slashed = ContentService.primaryAudioURL(fileName: "a/b.mp3")
        XCTAssertEqual(slashed?.absoluteString, "https://paymentforge-audio.pages.dev/audio/a%2Fb.mp3")

        XCTAssertNil(ContentService.primaryAudioURL(fileName: ""))

        let fallback = ContentService.fallbackAudioURL(fileName: "ch1 s1.mp3")
        XCTAssertEqual(fallback?.absoluteString, "https://paymentforge-audio-backup.pages.dev/audio/ch1%20s1.mp3")
        XCTAssertNotEqual(spaced, fallback)
    }

    func testReadTimeFollowsFullWordCount() {
        XCTAssertNil(ReadTime.minutes(for: ""))
        XCTAssertNil(ReadTime.minutes(for: "   \n  "))
        XCTAssertEqual(ReadTime.minutes(for: String(repeating: "word ", count: 45)), 1)
        XCTAssertEqual(ReadTime.minutes(for: String(repeating: "word ", count: 200)), 1)
        XCTAssertEqual(ReadTime.minutes(for: String(repeating: "word ", count: 201)), 2)
        XCTAssertEqual(ReadTime.minutes(for: String(repeating: "word ", count: 653)), 4)
        XCTAssertEqual(ReadTime.minutes(for: String(repeating: "word ", count: 1712)), 9)
        XCTAssertEqual(ReadTime.label(for: String(repeating: "word ", count: 653)), "About 4 min read")
    }

    func testExcerptWordCountCollapsesToOneMinute() {
        // The regression behind the "2 min read on everything"
        // report: a 152-word catalogue excerpt always reads as
        // one minute. List rows must never stamp this value; the
        // fix removes excerpt-based labels, and this test pins
        // why the excerpt input cannot be used.
        XCTAssertEqual(ReadTime.minutes(for: String(repeating: "word ", count: 152)), 1)
    }

    func testListenDurationTextBoundaries() {
        XCTAssertEqual(LessonDurations.durationText(83), "1 min")
        XCTAssertEqual(LessonDurations.durationText(961), "16 min")
        XCTAssertEqual(LessonDurations.durationText(3599), "1 hr")
        XCTAssertEqual(LessonDurations.durationText(3660), "1 hr 1 min")
        XCTAssertEqual(LessonDurations.durationText(7260), "2 hrs 1 min")
        XCTAssertNil(LessonDurations.totalLabel(seconds: 0))
        XCTAssertEqual(LessonDurations.totalLabel(seconds: 2700), "About 45 min of listening")
        XCTAssertNil(LessonDurations.listenLabel(for: "no-such-lesson"))
    }
}

// MARK: - Wave 2: play-then-pause through the audio service
//
// UNEXECUTED: written on a Linux VM with no Xcode. Never compiled
// or run. Statically checked only. The floating button and the
// main player share playButtonTapped, so exercising play, pause
// and stop on the service exercises the reviewed path. The
// hostile-name case is the regression test for the audio URL
// force unwrap: the old code crashed building the URL.

@MainActor
final class Wave2AudioPlayPauseTests: XCTestCase {

    func testPlayThenPauseLeavesPlayerStopped() {
        let player = AudioPlayerService()
        player.play(fileName: "ch1s1.mp3", lessonID: "ch1s1", title: "A lesson", chapterTitle: "A chapter")
        player.pause()
        XCTAssertFalse(player.isPlaying)
        player.stop()
        XCTAssertFalse(player.isLoading)
        XCTAssertEqual(player.currentTime, 0)
    }

    func testPlayWithHostileFileNameFailsAsLoadErrorNeverACrash() {
        let player = AudioPlayerService()
        player.play(fileName: "ch1 s1.mp3", lessonID: "ch1s1")
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isLoading)
        XCTAssertNotNil(player.errorMessage)
    }

    func testStopAfterPlayResetsToIdle() {
        let player = AudioPlayerService()
        player.play(fileName: "ch1s1.mp3", lessonID: "ch1s1")
        player.stop()
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isLoading)
        XCTAssertNil(player.errorMessage)
    }
}
