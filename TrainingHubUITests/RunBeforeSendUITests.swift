// RunBeforeSendUITests.swift
// Payments Training Hub iOS - run-before-send UI tests: the app is
// RUN with scripted taps before any build ships. These tests find
// elements by VISIBLE TEXT and LABELS ONLY. No view file was edited
// for them and no accessibility identifier was added: every label
// below was verified by grep against the app source in the v106
// tree. If the app copy changes a label, the affected test fails
// loudly, which is the gate working, not a false alarm.
//
// Access model asserted here is the 17 Nov model: NO sign-in gate
// at launch (the v95 mandatory gate was removed), no prompt except
// at buy. A signed-out fresh launch shows the splash, then the
// four-page introduction, then the tabs.
//
// FRESH-STATE CONTRACT: the introduction tests (IntroSkipUITests,
// IntroFirstLessonUITests) need a first launch: the introduction
// shows only until onboarding completes, and completion persists
// in UserDefaults. The workflow uninstalls the app before each
// test class, so every class starts fresh. When run by hand
// without an uninstall, those two classes skip plainly instead of
// failing on an introduction that must not exist. The app honors
// no launch argument to reset onboarding, and none was added.
//
// UNEXECUTED: written on a Linux VM with no Xcode. Never compiled
// or run here. Statically checked only. The cloud workflow run is
// the first execution, and its xcresult is the proof.

import XCTest

/// Labels and copy the tests depend on, all verified by grep
/// against the app source and the live search index.
private enum RunBeforeSendFixture {
    /// Skip button on the introduction (its accessibility label;
    /// the visible title is "Skip").
    static let skipIntroductionLabel = "Skip this introduction"
    /// Page dots on the introduction, "Page N of 4".
    static let lastPageDotLabel = "Page 4 of 4"
    /// The introduction's first-lesson card button label prefix:
    /// "Start with the first lesson: <lesson title>".
    static let firstLessonCardPrefix = "Start with the first lesson"
    /// ch1s1, the first lesson of chapter 1, from the live index.
    static let firstLessonTitle = "A payment, in plain words"
    /// Chapter 1 caption in the catalogue chapter row.
    static let chapterOneCaption = "Chapter 1"
    /// Chapter 1 lesson count line on a fresh install (nothing
    /// complete yet): "7 lessons".
    static let chapterOneCount = "7 lessons"
    /// The lesson sheet's navigation bar title.
    static let lessonNavTitle = "Lesson"
    /// The Done button that closes the lesson sheet.
    static let doneLabel = "Done"
}

/// Shared helpers for the run-before-send classes.
private extension XCUIApplication {

    /// If the introduction is showing, tap Skip and wait for the
    /// tabs. Returns true when the introduction was showing.
    /// Returns false when no Skip button appears within the
    /// timeout, in which case the caller decides whether that is
    /// acceptable (tabs already showing) or a skip (a test that
    /// needs the introduction itself).
    @discardableResult
    func dismissIntroductionIfPresent(timeout: TimeInterval = 15) -> Bool {
        let skip = buttons[RunBeforeSendFixture.skipIntroductionLabel]
        guard skip.waitForExistence(timeout: timeout) else { return false }
        skip.tap()
        XCTAssertTrue(
            tabBars.buttons["Home"].waitForExistence(timeout: 10),
            "The tab bar must appear after the introduction is skipped."
        )
        return true
    }

    /// Swipe up until the element exists and is hittable, or the
    /// swipe budget runs out. Needed for lazy chapter rows below
    /// the fold and for detail-screen buttons below the fold.
    @discardableResult
    func scrollUntilHittable(_ element: XCUIElement, maxSwipes: Int = 15) -> Bool {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return true }
            swipeUp()
        }
        return element.exists && element.isHittable
    }

    /// Tap a tab by its label. Prefers the tab bar button; falls
    /// back to any button with the label.
    func tapTab(_ label: String) {
        let tabBarButton = tabBars.buttons[label]
        if tabBarButton.waitForExistence(timeout: 5) {
            tabBarButton.tap()
            return
        }
        let plain = buttons[label]
        XCTAssertTrue(
            plain.waitForExistence(timeout: 5),
            "The \(label) tab must exist."
        )
        plain.tap()
    }
}

/// (a) Launch, skip the introduction, chapter list renders.
/// Needs a first launch: skips plainly when onboarding already
/// completed (the workflow uninstalls the app first, so the
/// introduction is always showing on a gate run).
final class IntroSkipUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testSkipIntroductionShowsChapterList() throws {
        let introWasShowing = app.dismissIntroductionIfPresent(timeout: 20)
        guard introWasShowing else {
            throw XCTSkip("Needs a first launch: the introduction already completed, so there is nothing to skip. The gate run uninstalls the app first.")
        }

        // The chapter list is the Catalogue section on Home:
        // scroll to it and assert the table renders.
        let catalogueHeading = app.staticTexts["Catalogue"]
        XCTAssertTrue(
            app.scrollUntilHittable(catalogueHeading),
            "The Catalogue heading must render on Home after the introduction is skipped."
        )
        XCTAssertTrue(app.staticTexts["Ch."].exists, "The catalogue table header must render.")
        XCTAssertTrue(app.staticTexts["Chapter"].exists, "The catalogue table header must render.")
        let countText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "chapters in the catalogue")
        ).firstMatch
        XCTAssertTrue(
            countText.waitForExistence(timeout: 30),
            "The catalogue count line must render once the catalogue has loaded."
        )
        let chapterRow = app.buttons.containing(
            .staticText, identifier: RunBeforeSendFixture.chapterOneCaption
        ).firstMatch
        XCTAssertTrue(
            app.scrollUntilHittable(chapterRow),
            "A chapter row (Chapter 1) must render in the catalogue."
        )
        add(XCTAttachment(screenshot: app.screenshot()))
    }
}

/// (c) The introduction's "Start with the first lesson" card
/// opens the lesson. Needs a first launch, like IntroSkipUITests.
final class IntroFirstLessonUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testIntroFirstLessonCardOpensLesson() throws {
        guard app.buttons[RunBeforeSendFixture.skipIntroductionLabel].waitForExistence(timeout: 20) else {
            throw XCTSkip("Needs a first launch: the introduction already completed, so the card is not reachable. The gate run uninstalls the app first.")
        }

        // Page 4 holds the card: jump there with the dots.
        let lastDot = app.buttons[RunBeforeSendFixture.lastPageDotLabel]
        XCTAssertTrue(
            lastDot.waitForExistence(timeout: 5),
            "The introduction page dots must exist."
        )
        lastDot.tap()

        // The card renders only once the catalogue has loaded.
        // Its label carries the lesson title, which is the
        // assertion target: the lesson screen must show it.
        let card = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", RunBeforeSendFixture.firstLessonCardPrefix)
        ).firstMatch
        XCTAssertTrue(
            card.waitForExistence(timeout: 30),
            "The 'Start with the first lesson' card must render once the catalogue has loaded."
        )
        let cardLabel = card.label
        let titlePrefix = RunBeforeSendFixture.firstLessonCardPrefix + ": "
        guard cardLabel.hasPrefix(titlePrefix) else {
            XCTFail("The card label must carry the lesson title, got: \(cardLabel)")
            return
        }
        let lessonTitle = String(cardLabel.dropFirst(titlePrefix.count))
        XCTAssertFalse(lessonTitle.isEmpty, "The card must name a lesson.")

        XCTAssertTrue(
            app.scrollUntilHittable(card),
            "The first-lesson card must be tappable."
        )
        card.tap()

        // The lesson opens in the lesson sheet: title, Lesson
        // navigation bar, and Done button.
        XCTAssertTrue(
            app.staticTexts[lessonTitle].waitForExistence(timeout: 15),
            "The lesson screen must appear with its title after the card tap."
        )
        XCTAssertTrue(app.navigationBars[RunBeforeSendFixture.lessonNavTitle].exists)
        XCTAssertTrue(app.buttons[RunBeforeSendFixture.doneLabel].exists)
        add(XCTAttachment(screenshot: app.screenshot()))
        app.buttons[RunBeforeSendFixture.doneLabel].tap()
    }
}

/// (b) Tap the first lesson in a chapter list: the lesson screen
/// opens with its title. Tolerates an already-completed
/// introduction (the workflow still starts it fresh).
final class ChapterLessonUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testFirstLessonInChapterListOpens() {
        _ = app.dismissIntroductionIfPresent(timeout: 10)
        XCTAssertTrue(
            app.tabBars.buttons["Home"].waitForExistence(timeout: 10),
            "The Home tab must be reachable."
        )
        app.tapTab("Home")

        // Open chapter 1 from the Catalogue.
        let catalogueHeading = app.staticTexts["Catalogue"]
        XCTAssertTrue(
            app.scrollUntilHittable(catalogueHeading),
            "The Catalogue heading must render on Home."
        )
        let chapterRow = app.buttons.containing(
            .staticText, identifier: RunBeforeSendFixture.chapterOneCaption
        ).firstMatch
        XCTAssertTrue(
            app.scrollUntilHittable(chapterRow, maxSwipes: 20),
            "The Chapter 1 row must render in the catalogue."
        )
        chapterRow.tap()

        // The chapter page lists its lessons.
        XCTAssertTrue(
            app.navigationBars[RunBeforeSendFixture.chapterOneCaption].waitForExistence(timeout: 10),
            "The chapter page must open with the Chapter 1 title."
        )
        XCTAssertTrue(
            app.staticTexts[RunBeforeSendFixture.chapterOneCount].waitForExistence(timeout: 30),
            "The chapter page must list its lessons once the catalogue has loaded."
        )

        // The first lesson is free: tapping it opens the lesson
        // sheet, never checkout.
        let lessonRow = app.buttons.containing(
            .staticText, identifier: RunBeforeSendFixture.firstLessonTitle
        ).firstMatch
        XCTAssertTrue(
            app.scrollUntilHittable(lessonRow),
            "The first lesson row must render on the chapter page."
        )
        lessonRow.tap()

        XCTAssertTrue(
            app.staticTexts[RunBeforeSendFixture.firstLessonTitle].waitForExistence(timeout: 15),
            "The lesson screen must appear with its title after the lesson tap."
        )
        XCTAssertTrue(app.navigationBars[RunBeforeSendFixture.lessonNavTitle].exists)
        XCTAssertTrue(app.buttons[RunBeforeSendFixture.doneLabel].exists)
        add(XCTAttachment(screenshot: app.screenshot()))
        app.buttons[RunBeforeSendFixture.doneLabel].tap()
    }
}

/// (d) Open an Investigation Timeline: no duplicated rows. The
/// v106 defect rendered each timeline item twice (5 unique items
/// as 10 rows) because the timeline subset was concatenated with
/// the full evidence list. The assertion is general: every
/// evidence row label in the workspace must be unique, for
/// whichever free case the catalogue serves first.
final class InvestigationTimelineUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testTimelineRowsAreNotDuplicated() {
        _ = app.dismissIntroductionIfPresent(timeout: 10)
        app.tapTab("Payment Cases")

        // A free sample case: its row carries the Free pill.
        // The Free samples section renders once the catalogue
        // has loaded.
        XCTAssertTrue(
            app.staticTexts["Free samples"].waitForExistence(timeout: 30),
            "The Free samples section must render on Payment Cases once the catalogue has loaded."
        )
        let freeRow = app.buttons.containing(.staticText, identifier: "Free").firstMatch
        XCTAssertTrue(
            app.scrollUntilHittable(freeRow, maxSwipes: 20),
            "A free sample case row must render."
        )
        freeRow.tap()

        // The case detail offers the investigation.
        let investigate = app.buttons["Investigate this case"]
        XCTAssertTrue(
            app.scrollUntilHittable(investigate, maxSwipes: 20),
            "The 'Investigate this case' entry must render on a free case."
        )
        investigate.tap()

        // The briefing starts the investigation; a locked case
        // would show the unlock gate instead of this button.
        let start = app.buttons["Start the investigation"]
        XCTAssertTrue(
            start.waitForExistence(timeout: 15),
            "The briefing must offer 'Start the investigation' for a free case."
        )
        start.tap()

        // The evidence workspace, with its Timeline group.
        XCTAssertTrue(
            app.staticTexts["Evidence workspace"].waitForExistence(timeout: 15),
            "The evidence workspace must open."
        )
        XCTAssertTrue(
            app.staticTexts["Timeline"].waitForExistence(timeout: 10),
            "The Timeline group must render in the workspace."
        )

        // Every evidence row is a button labelled
        // "Evidence: <title>". No title may repeat: a repeated
        // title is the duplication defect.
        let evidenceButtons = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Evidence: ")
        )
        let count = evidenceButtons.count
        XCTAssertGreaterThan(count, 0, "The workspace must show evidence rows.")
        var labels: [String] = []
        for index in 0..<count {
            labels.append(evidenceButtons.element(boundBy: index).label)
        }
        let duplicates = Dictionary(grouping: labels, by: { $0 })
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
        XCTAssertTrue(
            duplicates.isEmpty,
            "Evidence rows must not repeat: duplicated rows: \(duplicates.joined(separator: ", "))"
        )
        add(XCTAttachment(screenshot: app.screenshot()))
    }
}
