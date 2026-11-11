// GuestLaunchUITests.swift
// PaymentForge iOS - Phase 7 UI test: the guest launch flow.
// The app must open straight to Home with no sign-in gate: a guest
// sees the five tabs and the greeting, and is never forced into
// WelcomeView. NOTE: there is no UI test target in the Xcode project
// yet. The coordinator must add a UI Testing target named
// PaymentForgeUITests (bundle id com.paymentforge.app.uitests,
// target application PaymentForge) and add this file to it.

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
        XCTAssertTrue(app.textFields["Search lessons, guides, situations"].waitForExistence(timeout: 10))
    }

    func testGuestCanOpenLearnTab() {
        app.tabBars.buttons["Learn"].tap()
        XCTAssertTrue(app.staticTexts["Learn"].firstMatch.waitForExistence(timeout: 10))
    }
}
