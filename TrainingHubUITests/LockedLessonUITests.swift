// LockedLessonUITests.swift
// UI tests for the locked-lesson states: the lesson body lock, the
// search result row lock, and the locked-lesson deep link. These
// tests assert decided behavior only. They do not cover payment
// case surfaces, which are tested separately.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: every label,
// title, and element below was verified by grep against the app
// source before it was written.
//
// Preconditions, same as the guest launch tests: the simulator has
// completed onboarding, no purchase is owned, and the network is
// available so the course catalogue can load. The tests target one
// real non-sample lesson, ch1s2 ("Payment versus transfer"), the
// second lesson of chapter 1 in the live search index. The first
// lesson of a chapter is the free sample and opens unlocked, so a
// sample lesson must never be used here. If the live index renames
// ch1s2 or rewrites its opening sentence, the constants below must
// be updated to match the index before these tests run.
//
// The Learn tab is deliberately not used to reach the locked
// lesson: a locked lesson tapped in a chapter list opens checkout
// instead of the lesson view, so the lesson body lock is only
// reachable through search results and deep links. Both paths are
// tested here.
//
// The deep link test uses the XCUIApplication open method, which
// needs the Xcode version that introduced it (WWDC25 session 344).
// If the project builds with an older Xcode, that one test will
// not compile; the search tests are unaffected.

import XCTest

/// The locked lesson every test in this file targets.
private enum LockedLessonFixture {
    /// Catalogue id of the second lesson of chapter 1.
    static let lessonID = "ch1s2"
    /// Its title in the live search index. The search result row
    /// carries this title as its accessibility label, and the
    /// lesson header shows it above the lock.
    static let title = "Payment versus transfer"
    /// A distinctive fragment of the lesson body text in the live
    /// search index ("A transfer is a broader term than a
    /// payment."). It must never appear in a search result row.
    static let bodyFragment = "broader term than a payment"
    /// The search field placeholder, exactly as defined in the
    /// search view.
    static let searchFieldLabel = "Search lessons, guides, situations and more"
}

final class LockedLessonUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--uitest-guest-launch")
        app.launch()
    }

    /// The lesson body lock: opening a locked lesson from search
    /// shows the lock card, keeps the title visible, and shows none
    /// of the unlocked-only body sections (the quiz header is the
    /// probe: it renders unconditionally in the unlocked branch).
    func testLockedLessonFromSearchShowsLockInsteadOfBody() {
        let row = searchForLockedLesson()
        row.tap()

        XCTAssertTrue(
            app.staticTexts["Locked lesson"].waitForExistence(timeout: 10),
            "A locked lesson must show the lock card, not the lesson body."
        )
        XCTAssertTrue(app.staticTexts["Buy the course to unlock this chapter."].exists)
        XCTAssertTrue(app.buttons["See purchase options"].exists)
        // The title stays visible by design; only the body is locked.
        XCTAssertTrue(app.staticTexts[LockedLessonFixture.title].exists)
        // The quiz section exists only in the unlocked branch.
        XCTAssertFalse(app.staticTexts["Check your understanding"].exists)
    }

    /// The search row lock: a locked lesson result carries the
    /// Premium tag and the Lesson type tag, and exposes no body
    /// text in the row. Search rows show the title and tags only;
    /// there is no excerpt element to redact, so this test pins
    /// the row contents exactly as the code renders them.
    func testLockedLessonSearchRowShowsPremiumTagAndNoBodyText() {
        let row = searchForLockedLesson()

        XCTAssertTrue(row.staticTexts["Premium"].exists, "A locked lesson result must carry the Premium tag.")
        XCTAssertTrue(row.staticTexts["Lesson"].exists, "The result must still identify itself as a lesson.")
        let bodyLeak = row.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", LockedLessonFixture.bodyFragment))
        XCTAssertEqual(bodyLeak.count, 0, "No lesson body text may leak into the search result row.")
    }

    /// Searches for the fixture lesson and returns its result row.
    /// The exact-title query ranks the lesson first: a title match
    /// scores above every body match.
    private func searchForLockedLesson() -> XCUIElement {
        app.tabBars.buttons["Search"].tap()
        let searchField = app.textFields[LockedLessonFixture.searchFieldLabel]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "The search field must exist on the Search tab.")
        searchField.tap()
        searchField.typeText(LockedLessonFixture.title)
        // Dismiss the keyboard so the results underneath are tappable.
        let doneButton = app.buttons["Done"]
        if doneButton.waitForExistence(timeout: 2) {
            doneButton.tap()
        }
        let row = app.cells.containing(.staticText, identifier: LockedLessonFixture.title).firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 30),
            "The fixture lesson must appear in search results once the catalogue has loaded."
        )
        return row
    }
}

final class LockedLessonDeepLinkUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Do not launch here: the test opens the app through the
        // deep link itself, exactly as a tapped link would.
        app = XCUIApplication()
    }

    /// The deep-link lock: opening a locked lesson through its link
    /// shows the same lock card as opening it from search, in the
    /// lesson sheet, with no not-found alert. Routing applies the
    /// lesson view gate; only free sample lessons open with full
    /// content through a link.
    func testLockedLessonDeepLinkShowsLock() throws {
        let url = try XCTUnwrap(URL(string: "com.paymentstraininghub.app://lesson?id=\(LockedLessonFixture.lessonID)"))
        try app.open(url)

        XCTAssertTrue(
            app.staticTexts["Locked lesson"].waitForExistence(timeout: 30),
            "A locked lesson opened by deep link must show the lock card once the catalogue has loaded."
        )
        XCTAssertTrue(app.staticTexts["Buy the course to unlock this chapter."].exists)
        XCTAssertTrue(app.buttons["See purchase options"].exists)
        XCTAssertFalse(app.alerts["Lesson link not found"].exists)
    }
}
