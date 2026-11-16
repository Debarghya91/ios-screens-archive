// AuthServiceTests.swift
// TrainingHub iOS - Phase 7 unit tests: authentication.
// Guest is the default: a fresh AuthService has no user. No test
// here performs a real network sign-in: the tests cover the guards
// (invalid email, empty code, non-auth callback) and the guest
// default, which are all local. A valid-email OTP send would hit
// the live Supabase Auth endpoint and is deliberately not tested.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only.
//
// Phase 1 reconciliation (12 Nov 2026): no existing expectation
// changed. Added tests cover the new guest-migration offer state
// (default false, accept/decline from a guest are safe no-ops) and
// the validAccessToken guest guard. The deleteAccount failure path
// is covered in AccountDeletionTests; a successful server-side
// deletion needs a live Edge Function and is a manual test item.

import XCTest
@testable import TrainingHub

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

    // MARK: - Phase 1: guest migration offer and token guard

    func testMigrationOfferDefaultsToFalseForGuest() {
        let auth = AuthService()
        XCTAssertFalse(auth.offersGuestMigration, "No migration is offered to a guest: the offer belongs to a fresh sign-in.")
    }

    func testDeclineGuestMigrationFromGuestStaysGuest() {
        let auth = AuthService()
        auth.declineGuestMigration()
        XCTAssertFalse(auth.offersGuestMigration)
        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNil(auth.currentUser)
    }

    func testAcceptGuestMigrationFromGuestIsSafeNoOp() async {
        let auth = AuthService()
        await auth.acceptGuestMigration()
        XCTAssertFalse(auth.offersGuestMigration)
        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNil(auth.currentUser)
    }

    func testValidAccessTokenIsNilForGuest() async {
        let auth = AuthService()
        let token = await auth.validAccessToken()
        XCTAssertNil(token, "A guest has no stored session, so there is no token to return and no refresh is attempted.")
    }

    // MARK: - v77: password reset guards (local, no network)

    func testRequestPasswordResetRejectsInvalidEmailWithoutNetwork() async {
        let auth = AuthService()
        await auth.requestPasswordReset(email: "not-an-email")
        XCTAssertEqual(auth.authError, "Enter a valid email address.")
        XCTAssertNil(auth.authInfo)
    }

    func testUpdatePasswordRejectsShortPasswordWithoutNetwork() async {
        let auth = AuthService()
        let ok = await auth.updatePassword(newPassword: "short")
        XCTAssertFalse(ok)
        XCTAssertEqual(auth.authError, PFSignupErrorCode.passwordTooShort.message)
        XCTAssertFalse(auth.showPasswordReset)
    }

    func testSignUpRejectsShortPasswordWithoutNetwork() async {
        let auth = AuthService()
        let result = await auth.signUpWithPassword(
            email: "learner@example.com",
            password: "short",
            caseID: "PF-ABC234",
            termsAccepted: true
        )
        XCTAssertNil(result)
        XCTAssertEqual(auth.authError, PFSignupErrorCode.passwordTooShort.message)
    }

    func testSignUpRejectsMissingTermsWithoutNetwork() async {
        let auth = AuthService()
        let result = await auth.signUpWithPassword(
            email: "learner@example.com",
            password: "long-enough-password",
            caseID: "PF-ABC234",
            termsAccepted: false
        )
        XCTAssertNil(result)
        XCTAssertEqual(auth.authError, PFSignupErrorCode.termsNotAccepted.message)
    }

    func testPasswordResetScreenDefaultsToHiddenForGuest() {
        let auth = AuthService()
        XCTAssertFalse(auth.showPasswordReset)
        XCTAssertNil(auth.accountCaseID)
    }
}
