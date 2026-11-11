// AuthServiceTests.swift
// PaymentForge iOS - Phase 7 unit tests: authentication.
// Guest is the default: a fresh AuthService has no user. No test
// here performs a real network sign-in: the tests cover the guards
// (invalid email, empty code, non-auth callback) and the guest
// default, which are all local. A valid-email OTP send would hit
// the live Supabase Auth endpoint and is deliberately not tested.

import XCTest
@testable import PaymentForge

@MainActor
final class AuthServiceTests: XCTestCase {

    func testGuestIsTheDefault() {
        let auth = AuthService()
        XCTAssertFalse(auth.isSignedIn, "A fresh AuthService must be a guest, never signed in.")
        XCTAssertNil(auth.currentUser)
        XCTAssertNil(auth.profile)
    }

    func testCanSignInReflectsConfiguration() {
        let auth = AuthService()
        XCTAssertEqual(auth.canSignIn, SupabaseConfig.isConfigured)
    }

    func testSendOTPRejectsInvalidEmailWithoutNetwork() async {
        let auth = AuthService()
        await auth.sendEmailOTP(email: "not-an-email")
        XCTAssertEqual(auth.authError, "Enter a valid email address.")
        XCTAssertNil(auth.pendingEmail)
    }

    func testSendOTPRejectsBlankEmail() async {
        let auth = AuthService()
        await auth.sendEmailOTP(email: "   ")
        XCTAssertEqual(auth.authError, "Enter a valid email address.")
    }

    func testVerifyOTPRejectsEmptyCode() async {
        let auth = AuthService()
        let ok = await auth.verifyEmailOTP(email: "learner@example.com", code: "   ")
        XCTAssertFalse(ok)
        XCTAssertEqual(auth.authError, "Enter the 6-digit code sent to your email.")
        XCTAssertFalse(auth.isSignedIn)
    }

    func testAuthCallbackRejectsNonAuthURL() async {
        let auth = AuthService()
        let handled = await auth.handleAuthCallback(url: URL(string: "https://www.paymentstraininghub.com/lessons/ch1s1")!)
        XCTAssertFalse(handled, "A non-auth URL must not be treated as a sign-in callback.")
        XCTAssertFalse(auth.isSignedIn)
    }

    func testAuthCallbackRejectsWrongScheme() async {
        let auth = AuthService()
        let handled = await auth.handleAuthCallback(url: URL(string: "otherapp://callback?code=abc123")!)
        XCTAssertFalse(handled)
    }

    func testSignOutFromGuestStaysGuest() async {
        let auth = AuthService()
        await auth.signOut()
        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNil(auth.currentUser)
    }
}
