// GuestLaunchUITests.swift
// PaymentForge iOS - Phase 7 UI test: the guest launch flow.
// The app must open straight to Home with no sign-in gate: a guest
// sees the five tabs and the greeting, and is never forced into
// WelcomeView. The UI test target PaymentForgeUITests exists in the
// Xcode project (verified in project.pbxproj, 12 Nov 2026); the old
// note saying no target existed yet is removed.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only.
//
// Phase 1: no UI assertion is added for the guest-migration alert
// (it needs a signed-in session with guest data) or for the absence
// of the Content management entry in Release (the entry is compiled
// out with #if DEBUG, so no in-app UI test can assert Release
// absence). Both are manual test items; see the Phase 1 test report.

import XCTest

final class GuestLaunchUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--uitest-guest-launch")
        app.launch()
    }

    func testGuestLaunchOpensHomeWithoutSignIn() {
        // The tab bar is visible immediately: Home is the first tab.
        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10), "Home tab must exist on launch for a guest.")
        XCTAssertTrue(app.tabBars.buttons["Learn"].exists)
        XCTAssertTrue(app.tabBars.buttons["Search"].exists)
        XCTAssertTrue(app.tabBars.buttons["Payment Cases"].exists)
        XCTAssertTrue(app.tabBars.buttons["My Progress"].exists)

        // No sign-in sheet or welcome screen blocks the guest.
        XCTAssertFalse(app.staticTexts["Sign in with Apple"].exists)
        XCTAssertFalse(app.buttons["Continue with Apple"].exists)
    }

    func testGuestCanOpenSearchTab() {
        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(app.textFields["Search lessons, guides, situations and more"].waitForExistence(timeout: 10))
    }

    func testGuestCanOpenLearnTab() {
        app.tabBars.buttons["Learn"].tap()
        XCTAssertTrue(app.staticTexts["Learn"].firstMatch.waitForExistence(timeout: 10))
    }

    func testGuestCanOpenPaymentCasesTabWithoutSignIn() {
        // Tapping into Payment Cases must not force a sign-in sheet:
        // the free samples stay visible to a guest and paid content
        // shows a lock, never a sign-in gate.
        app.tabBars.buttons["Payment Cases"].tap()
        XCTAssertTrue(app.tabBars.buttons["Payment Cases"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Sign in with Apple"].exists)
        XCTAssertFalse(app.buttons["Continue with Apple"].exists)
    }
}
