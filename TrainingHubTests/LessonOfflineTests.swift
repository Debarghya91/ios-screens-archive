// LessonOfflineTests.swift
// TrainingHub iOS - Phase 2 item 11 (lesson experience, offline,
// audio) tests: the pure logic behind the lesson detail cache and
// the audio download store.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the final app source before writing.
//
// No test requires network. Cache filename sanitising, eviction
// selection and download URL resolution are pure functions. The
// only disk read is cachedLessonHTML for an id that was never
// cached, which must return nil without writing anything. No test
// touches the LessonDownloadStore shared instance, starts a
// download, or writes to the cache or Downloads directories.
// Live-vs-cached source selection itself needs a network fetch and
// is a manual test item; these tests cover the pure pieces it is
// built from, plus the LessonDetailSource values it reports.

import XCTest
@testable import TrainingHub

final class LessonOfflineTests: XCTestCase {

    // MARK: - Cache filename sanitising

    func testCacheFileNameKeepsPlainLessonID() {
        XCTAssertEqual(ContentService.sanitisedLessonDetailCacheFileName(for: "ch1s1"), "ch1s1.html")
    }

    func testCacheFileNameKeepsHyphenAndUnderscore() {
        XCTAssertEqual(ContentService.sanitisedLessonDetailCacheFileName(for: "ch86s1-supp"), "ch86s1-supp.html")
        XCTAssertEqual(ContentService.sanitisedLessonDetailCacheFileName(for: "ch1_s1"), "ch1_s1.html")
    }

    func testCacheFileNameReplacesUnsafeCharacters() {
        let name = ContentService.sanitisedLessonDetailCacheFileName(for: "ch1s1/../evil lesson")
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(" "))
        XCTAssertFalse(name.contains(".."))
        XCTAssertTrue(name.hasSuffix(".html"))
    }

    func testCacheFileNameForEmptyID() {
        XCTAssertEqual(ContentService.sanitisedLessonDetailCacheFileName(for: ""), "lesson.html")
    }

    func testCacheFileURLUsesSanitisedNameInCacheDirectory() {
        let url = ContentService.lessonDetailCacheFileURL(for: "ch1s1")
        XCTAssertEqual(url.lastPathComponent, "ch1s1.html")
        XCTAssertEqual(url.deletingLastPathComponent(), ContentService.lessonDetailCacheDirectoryURL())
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "LessonDetailCache")
    }

    func testCacheFileURLsDifferPerLesson() {
        let first = ContentService.lessonDetailCacheFileURL(for: "ch1s1")
        let second = ContentService.lessonDetailCacheFileURL(for: "ch1s2")
        XCTAssertNotEqual(first, second)
    }

    func testCacheBoundsAreFiftyFilesAndFiftyMegabytes() {
        XCTAssertEqual(ContentService.lessonDetailCacheMaxFiles, 50)
        XCTAssertEqual(ContentService.lessonDetailCacheMaxBytes, 50 * 1024 * 1024)
    }

    func testCachedHTMLIsNilForNeverCachedLesson() {
        let unknownID = "never-cached-\(UUID().uuidString)"
        XCTAssertNil(ContentService.cachedLessonHTML(for: unknownID))
    }

    // MARK: - Eviction selection

    private func cacheFile(_ name: String, age: TimeInterval, size: Int64) -> ContentService.LessonDetailCacheFileInfo {
        ContentService.LessonDetailCacheFileInfo(
            fileName: name,
            modificationDate: Date(timeIntervalSince1970: age),
            sizeBytes: size
        )
    }

    func testEvictionKeepsEverythingWithinBounds() {
        let files = [cacheFile("a.html", age: 100, size: 10), cacheFile("b.html", age: 200, size: 10)]
        XCTAssertEqual(ContentService.cacheFilesToEvict(files, maxFiles: 50, maxBytes: 1000), [])
    }

    func testEvictionRemovesOldestFirstOverFileCount() {
        let files = [
            cacheFile("old.html", age: 100, size: 10),
            cacheFile("mid.html", age: 200, size: 10),
            cacheFile("new.html", age: 300, size: 10)
        ]
        XCTAssertEqual(ContentService.cacheFilesToEvict(files, maxFiles: 2, maxBytes: 1000), ["old.html"])
    }

    func testEvictionRemovesOldestFirstOverTotalBytes() {
        let files = [
            cacheFile("old.html", age: 100, size: 600),
            cacheFile("mid.html", age: 200, size: 600),
            cacheFile("new.html", age: 300, size: 600)
        ]
        XCTAssertEqual(ContentService.cacheFilesToEvict(files, maxFiles: 50, maxBytes: 1000), ["old.html", "mid.html"])
    }

    func testEvictionStopsOnceBothBoundsHold() {
        let files = [
            cacheFile("a.html", age: 100, size: 400),
            cacheFile("b.html", age: 200, size: 400),
            cacheFile("c.html", age: 300, size: 400)
        ]
        XCTAssertEqual(ContentService.cacheFilesToEvict(files, maxFiles: 50, maxBytes: 800), ["a.html"])
    }

    func testEvictionWithNoFilesEvictsNothing() {
        XCTAssertEqual(ContentService.cacheFilesToEvict([], maxFiles: 50, maxBytes: 1000), [])
    }

    func testEvictionBreaksSameDateTiesByFileName() {
        let files = [
            cacheFile("b.html", age: 100, size: 10),
            cacheFile("a.html", age: 100, size: 10)
        ]
        XCTAssertEqual(ContentService.cacheFilesToEvict(files, maxFiles: 1, maxBytes: 1000), ["a.html"])
    }

    // MARK: - Lesson detail source

    func testLessonDetailSourceCasesAreDistinct() {
        XCTAssertEqual(LessonDetailSource.live, LessonDetailSource.live)
        XCTAssertEqual(LessonDetailSource.cached, LessonDetailSource.cached)
        XCTAssertNotEqual(LessonDetailSource.live, LessonDetailSource.cached)
    }

    // MARK: - Download filename sanitising

    func testDownloadFileNameKeepsPlainAudioFile() {
        XCTAssertEqual(LessonDownloadStore.sanitisedDownloadFileName(for: "ch1s1.mp3"), "ch1s1.mp3")
    }

    func testDownloadFileNameReplacesUnsafeCharacters() {
        let name = LessonDownloadStore.sanitisedDownloadFileName(for: "../ch1s1.mp3")
        XCTAssertFalse(name.contains("/"))
        XCTAssertTrue(name.hasSuffix(".mp3"))
    }

    func testDownloadFileNameForEmptyInput() {
        XCTAssertEqual(LessonDownloadStore.sanitisedDownloadFileName(for: ""), "audio.mp3")
    }

    // MARK: - Download URL resolution

    private let testDirectory = URL(fileURLWithPath: "/tmp/pf-download-tests")

    func testDownloadURLResolvesForMatchingLessonAndFile() {
        let url = LessonDownloadStore.downloadFileURL(in: testDirectory, lessonID: "ch1s1", fileName: "ch1s1.mp3")
        XCTAssertEqual(url, testDirectory.appendingPathComponent("ch1s1.mp3"))
    }

    func testDownloadURLResolvesForSupplementalLesson() {
        let url = LessonDownloadStore.downloadFileURL(in: testDirectory, lessonID: "cipsp-01-supp", fileName: "cipsp-01-supp.mp3")
        XCTAssertEqual(url?.lastPathComponent, "cipsp-01-supp.mp3")
    }

    func testDownloadURLIsNilWhenFileNameBelongsToAnotherLesson() {
        XCTAssertNil(LessonDownloadStore.downloadFileURL(in: testDirectory, lessonID: "ch1s1", fileName: "ch1s2.mp3"))
    }

    func testDownloadURLIsNilForEmptyLessonIDOrFileName() {
        XCTAssertNil(LessonDownloadStore.downloadFileURL(in: testDirectory, lessonID: "", fileName: "ch1s1.mp3"))
        XCTAssertNil(LessonDownloadStore.downloadFileURL(in: testDirectory, lessonID: "ch1s1", fileName: ""))
    }

    func testDownloadURLNeverEscapesItsDirectory() {
        let url = LessonDownloadStore.downloadFileURL(in: testDirectory, lessonID: "ch1s1", fileName: "ch1s1.mp3")
        XCTAssertEqual(url?.deletingLastPathComponent(), testDirectory)
    }

    func testDownloadsDirectoryIsNamedDownloads() {
        XCTAssertEqual(LessonDownloadStore.downloadsDirectoryURL().lastPathComponent, "Downloads")
    }

    // MARK: - Download state

    func testDownloadStateEquality() {
        XCTAssertEqual(LessonAudioDownloadState.downloaded, LessonAudioDownloadState.downloaded)
        XCTAssertNotEqual(LessonAudioDownloadState.downloading, LessonAudioDownloadState.downloaded)
        XCTAssertNotEqual(LessonAudioDownloadState.notDownloaded, LessonAudioDownloadState.downloaded)
        XCTAssertEqual(
            LessonAudioDownloadState.failed(message: "No connection"),
            LessonAudioDownloadState.failed(message: "No connection")
        )
        XCTAssertNotEqual(
            LessonAudioDownloadState.failed(message: "A"),
            LessonAudioDownloadState.failed(message: "B")
        )
    }
}
