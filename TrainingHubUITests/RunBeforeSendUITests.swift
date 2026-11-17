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
// CATALOGUE NAVIGATION (17 Nov correction): the Catalogue section
// does NOT render on Home's default view. Home opens on the
// Learning Journey tab; the catalogue lives on the Courses Home
// tab, behind the "Browse section" segmented picker, whose
// default segment is Courses. Tests reach it with
// openCatalogueSection(): tap the Courses Home tab, tap the
// Catalogue picker segment, then assert. Scrolling the default
// tab never reaches the catalogue, and the "Catalogue" heading
// must never be awaited there. The CoursesView struct itself is
// unconstructed dead code; the live catalogue UI is
// LearnSectionsView in the same file, embedded in HomeView.
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
    /// The Courses button in Home's pinned three-tab bar
    /// (Learning Journey, Courses, Practice). Home opens on
    /// Learning Journey; the catalogue needs this tap first.
    static let coursesHomeTabLabel = "Courses"
    /// The section header on Home's Courses tab.
    static let browseFullCourseHeading = "Browse the full course"
    /// The segmented picker on the Courses tab, offering the
    /// Courses and Catalogue sections.
    static let browseSectionPickerLabel = "Browse section"
    /// The Catalogue segment of that picker, and the heading of
    /// the section it selects.
    static let catalogueLabel = "Catalogue"
    /// The catalogue table's column headers.
    static let tableHeaderNumber = "Ch."
    static let tableHeaderChapter = "Chapter"
    /// Substring of the catalogue count line ("10 courses, 99
    /// chapters in the catalogue."): it renders only once the
    /// catalogue has loaded, so it is the load proof.
    static let catalogueCountSnippet = "chapters in the catalogue"
    /// Chapter 1 lesson count line on a fresh install (nothing
    /// complete yet): "<N> lessons", matched as a pattern, not an
    /// exact count. The count is catalogue data, not copy:
    /// Chapter 1 holds 7 regular lessons plus 1 supplemental
    /// lesson ("Book payments: moving money inside one bank"),
    /// so the line reads "8 lessons" today, and it moves again
    /// whenever content is added. The pattern proves the count
    /// line rendered once the catalogue loaded; the first-lesson
    /// row wait below is the proof the lessons themselves listed.
    static let chapterOneCountPattern = "^[0-9]+ lessons$"
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

    /// Navigate to the Catalogue section on Home: tap the
    /// Courses Home tab, then the Catalogue segment of the
    /// "Browse section" picker, and wait for the Catalogue
    /// heading. Home opens on the Learning Journey tab and the
    /// picker defaults to Courses, so both taps are required;
    /// the heading renders as soon as the section is selected,
    /// before the catalogue loads, so callers still wait for
    /// the count line as the load proof.
    func openCatalogueSection() {
        let coursesTab = buttons[RunBeforeSendFixture.coursesHomeTabLabel]
        XCTAssertTrue(
            coursesTab.waitForExistence(timeout: 10),
            "The Courses Home tab must exist."
        )
        coursesTab.tap()
        XCTAssertTrue(
            staticTexts[RunBeforeSendFixture.browseFullCourseHeading].waitForExistence(timeout: 10),
            "The Courses tab must show its 'Browse the full course' section."
        )
        let segment = segmentedControls[RunBeforeSendFixture.browseSectionPickerLabel]
            .buttons[RunBeforeSendFixture.catalogueLabel]
        if segment.waitForExistence(timeout: 5) {
            segment.tap()
        } else {
            let plainSegment = buttons[RunBeforeSendFixture.catalogueLabel]
            XCTAssertTrue(
                plainSegment.waitForExistence(timeout: 5),
                "The Catalogue picker segment must exist."
            )
            plainSegment.tap()
        }
        XCTAssertTrue(
            staticTexts[RunBeforeSendFixture.catalogueLabel].waitForExistence(timeout: 10),
            "The Catalogue heading must render after the Catalogue segment is selected."
        )
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

        // The chapter list is the Catalogue section: Home's
        // Courses tab, "Browse section" picker, Catalogue
        // segment. It never renders on the default Learning
        // Journey tab, so scrolling alone cannot reach it.
        app.openCatalogueSection()
        // The count line renders only once the catalogue has
        // loaded, so it is awaited before the table headers:
        // the headers render in the same branch and cannot
        // precede it.
        let countText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", RunBeforeSendFixture.catalogueCountSnippet)
        ).firstMatch
        XCTAssertTrue(
            countText.waitForExistence(timeout: 30),
            "The catalogue count line must render once the catalogue has loaded."
        )
        XCTAssertTrue(app.staticTexts[RunBeforeSendFixture.tableHeaderNumber].exists, "The catalogue table header must render.")
        XCTAssertTrue(app.staticTexts[RunBeforeSendFixture.tableHeaderChapter].exists, "The catalogue table header must render.")
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

        // Open chapter 1 from the Catalogue: Courses Home tab,
        // then the Catalogue picker segment.
        app.openCatalogueSection()
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
        // The chapter page lists its lessons: the "<N> lessons"
        // count line renders once the catalogue has loaded.
        let chapterCount = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", RunBeforeSendFixture.chapterOneCountPattern)
        ).firstMatch
        XCTAssertTrue(
            chapterCount.waitForExistence(timeout: 30),
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
