// SituationsGateUITests.swift
// Payments Training Hub iOS - D101 UI tests: a locked Payment Situation
// shows only its teaser plus the checkout gate, never the full
// explain or takeaway text.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: every label and
// accessibility identifier referenced here was verified by grep to
// exist in the app code (the identifiers are added by the D101
// gate implementation itself).
//
// The tests run as a fresh guest with no purchase, so every
// non-sample situation is locked (StoreManager.isPracticeUnlocked
// is false). The explain text itself comes from live website data,
// so no test can name an explain string: instead each locked test
// asserts the gate renders and every content surface is absent
// (detail tabs, content section headings, the visual heading and
// the Practice Mode entry, all of which only render with the full
// case). The free-sample test is the control: the same detail
// screen shows its full content and no gate.
//
// COORDINATOR: this file is new. Wire it into the TrainingHubUITests
// target in project.pbxproj at integration; the D101 worker does
// not edit the pbxproj.

import XCTest

final class SituationsGateUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--uitest-guest-launch")
        app.launch()
    }

    /// Open the Payment Cases tab and wait for a locked situation
    /// row to exist. Stage 1 starts expanded, so locked rows render
    /// once the catalogue loads.
    private func openPaymentCasesAndWaitForLockedRow() -> XCUIElement {
        app.tabBars.buttons["Payment Cases"].tap()
        let lockedRow = app.buttons["lockedSituationRow"].firstMatch
        XCTAssertTrue(
            lockedRow.waitForExistence(timeout: 30),
            "A locked situation row must exist in Payment Cases for a guest with no purchase."
        )
        return lockedRow
    }

    func testLockedSituationShowsGateAndNoFullContent() {
        let lockedRow = openPaymentCasesAndWaitForLockedRow()
        lockedRow.tap()

        // The gate renders: the gate card, its heading and the
        // checkout button that is the gate.
        let gate = app.descendants(matching: .any)["situationLockedGate"].firstMatch
        XCTAssertTrue(gate.waitForExistence(timeout: 10), "The locked situation gate must render.")
        XCTAssertTrue(app.staticTexts["Unlock this case"].exists)
        XCTAssertTrue(app.buttons["Go to checkout"].exists)

        // No content surface renders: no detail tabs, no content
        // section headings, no visual heading, no Practice Mode
        // entry. Every one of these only renders with the full
        // explain or takeaway text, so their absence is the
        // no-full-content assertion for live data.
        XCTAssertFalse(app.segmentedControls.firstMatch.exists)
        XCTAssertFalse(app.buttons["Overview"].exists)
        XCTAssertFalse(app.buttons["Analysis"].exists)
        XCTAssertFalse(app.buttons["Flow"].exists)
        XCTAssertFalse(app.staticTexts["Business Problem"].exists)
        XCTAssertFalse(app.staticTexts["Scenario"].exists)
        XCTAssertFalse(app.staticTexts["Key Learning Outcomes"].exists)
        XCTAssertFalse(app.staticTexts["Full case text"].exists)
        XCTAssertFalse(app.staticTexts["The flawed requirement"].exists)
        XCTAssertFalse(app.staticTexts["Root cause"].exists)
        XCTAssertFalse(app.staticTexts["Insight"].exists)
        XCTAssertFalse(app.staticTexts["Visual investigation"].exists)
        XCTAssertFalse(app.staticTexts["Practice Mode"].exists)
    }

    func testFreeSampleSituationShowsFullContentAndNoGate() {
        app.tabBars.buttons["Payment Cases"].tap()
        let freeRow = app.buttons["freeSituationRow"].firstMatch
        XCTAssertTrue(
            freeRow.waitForExistence(timeout: 30),
            "A free sample situation row must exist in Payment Cases."
        )
        freeRow.tap()

        // Full content renders: the Overview tab shows its Key
        // Learning Outcomes section, the tab picker exists, and
        // the Practice Mode entry is present.
        XCTAssertTrue(
            app.staticTexts["Key Learning Outcomes"].waitForExistence(timeout: 10),
            "A free sample situation must show its full content."
        )
        XCTAssertTrue(app.segmentedControls.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Practice Mode"].exists)

        // No gate: neither the gate card nor its heading, and no
        // checkout button (the footer upsell is hidden for free
        // samples).
        XCTAssertFalse(app.descendants(matching: .any)["situationLockedGate"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Unlock this case"].exists)
        XCTAssertFalse(app.buttons["Go to checkout"].exists)
    }

    func testLockedSituationFromSearchShowsGate() {
        app.tabBars.buttons["Search"].tap()
        let searchField = app.textFields["Search lessons, guides, situations and more"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText("payment")
        if app.keyboards.buttons["Search"].exists {
            app.keyboards.buttons["Search"].tap()
        }

        let lockedResult = app.descendants(matching: .any)["lockedSituationSearchRow"].firstMatch
        XCTAssertTrue(
            lockedResult.waitForExistence(timeout: 20),
            "A locked situation search result must exist for a broad query."
        )
        lockedResult.tap()

        let gate = app.descendants(matching: .any)["situationLockedGate"].firstMatch
        XCTAssertTrue(gate.waitForExistence(timeout: 10), "A locked situation opened from search must show the gate.")
        XCTAssertTrue(app.buttons["Go to checkout"].exists)
        XCTAssertFalse(app.staticTexts["Key Learning Outcomes"].exists)
        XCTAssertFalse(app.staticTexts["Business Problem"].exists)
        XCTAssertFalse(app.staticTexts["Full case text"].exists)
        XCTAssertFalse(app.staticTexts["Practice Mode"].exists)
    }
}
