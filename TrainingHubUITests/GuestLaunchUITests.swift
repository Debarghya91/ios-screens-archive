// GuestLaunchUITests.swift
// TrainingHub iOS - UI tests: sign-in is the mandatory first step.
// A fresh launch (no stored session) opens the sign-in screen and
// shows no tab bar, no lesson, and no guest bypass: there is no
// way to reach content without a session. A stored session
// restores at launch, so a signed-in learner opens straight into
// the tabs; these tests cover the signed-out launch only.
//
// The file keeps its historical name so project.pbxproj needs no
// change; the class and the assertions are the gate tests. They
// replace the old guest-launch tests, which asserted the guest
// default (and a removed Learn tab) that the mandatory sign-in
// gate removed. The purchase-gate UI tests (LockedLessonUITests,
// SituationsGateUITests) skip plainly when the gate is showing
// and run when a session is restored.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: every label
// below was verified by grep against the app source.

import XCTest

final class SignInGateUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testFreshLaunchShowsSignInScreenAndNoTabs() {
        // The sign-in screen is the first thing a signed-out
        // learner sees: the email and create-account buttons
        // exist, and no tab bar exists at all.
        XCTAssertTrue(
            app.buttons["Continue with Email"].waitForExistence(timeout: 10),
            "The sign-in screen must show on a fresh launch."
        )
        XCTAssertTrue(app.buttons["Create account"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists, "No tab bar may exist before sign-in.")
        XCTAssertFalse(app.tabBars.buttons["Home"].exists)
        XCTAssertFalse(app.tabBars.buttons["Search"].exists)
        XCTAssertFalse(app.tabBars.buttons["Payment Cases"].exists)
        XCTAssertFalse(app.tabBars.buttons["My Progress"].exists)
    }

    func testGateHasNoGuestBypass() {
        // No control may offer guest access: the old bypass
        // buttons are gone, and a sign-in error offers only OK.
        XCTAssertTrue(app.buttons["Continue with Email"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Explore as Guest"].exists)
        XCTAssertFalse(app.buttons["Continue as guest"].exists)
    }

    func testEmailSignInSheetOpensFromGate() {
        XCTAssertTrue(app.buttons["Continue with Email"].waitForExistence(timeout: 10))
        app.buttons["Continue with Email"].tap()
        XCTAssertTrue(
            app.staticTexts["Sign in with your email"].waitForExistence(timeout: 10),
            "Tapping Continue with Email must open the email sign-in sheet."
        )
    }
}
