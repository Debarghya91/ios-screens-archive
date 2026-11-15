// AuthErrorCatalogTests.swift
// PaymentForge iOS - v78 tests: the shared signup error catalog
// (verbatim messages, unknown-code fallback, contract-shape
// parsing), case ID validation and generation, the deterministic
// referral code, and the GoTrue message mapping including
// password reset. The SMS OTP codes, mobile normalisation,
// masked display and verification record tests were removed with
// the SMS OTP flow in v77: no mobile number is collected and no
// SMS code is ever sent. v78 removed the last stale code that
// required a verified phone number and the server case codes,
// and aligned the reset codes and messages with the website
// catalog, so this file asserts the same 22 codes with the same
// messages as audit/ERROR-CODE-CATALOG.md.
//
// UNEXECUTED: written on a Linux VM with no Xcode. These tests were
// never compiled or run. Statically checked only: symbol names and
// signatures were read from the final app source before writing.
// The password signup and sign-in, the password reset email and
// link, and the welcome popup timing are MANUAL test items: they
// need live Supabase Auth, a real confirmation or reset email,
// and a device.

import XCTest
@testable import PaymentForge

@MainActor
final class AuthErrorCatalogTests: XCTestCase {

    // MARK: - Catalog messages (verbatim)

    func testCatalogMessagesAreVerbatim() {
        XCTAssertEqual(PFSignupErrorCode.emailAlreadyRegistered.message, "This email already has an account. Sign in instead.")
        XCTAssertEqual(PFSignupErrorCode.emailNotVerified.message, "Verify your email address first.")
        XCTAssertEqual(PFSignupErrorCode.emailInvalid.message, "Enter a valid email address.")
        XCTAssertEqual(PFSignupErrorCode.caseIDInvalid.message, "That case ID does not look right. Check it and try again.")
        XCTAssertEqual(PFSignupErrorCode.referralInvalid.message, "That referral code is not valid.")
        XCTAssertEqual(PFSignupErrorCode.referralSelf.message, "You cannot use your own referral code.")
        XCTAssertEqual(PFSignupErrorCode.referralAlreadyUsed.message, "A referral discount was already used on this account.")
        XCTAssertEqual(PFSignupErrorCode.termsNotAccepted.message, "Accept the terms and conditions to continue.")
        XCTAssertEqual(PFSignupErrorCode.credentialsInvalid.message, "Email or password does not match our records.")
        XCTAssertEqual(PFSignupErrorCode.passwordTooShort.message, "Your password must be at least 8 characters.")
        XCTAssertEqual(PFSignupErrorCode.passwordMismatch.message, "The two passwords do not match. Type the same password twice.")
        XCTAssertEqual(PFSignupErrorCode.sessionExpired.message, "Your session expired. Sign in again.")
        XCTAssertEqual(PFSignupErrorCode.emailConfirmationResent.message, "If that email address has an unfinished signup, a confirmation link is on its way. Check your inbox.")
        XCTAssertEqual(PFSignupErrorCode.passwordResetSent.message, "If an account exists for that email address, a password reset link is on its way. Check your inbox.")
        XCTAssertEqual(PFSignupErrorCode.resetLinkInvalid.message, "This password reset link has expired or was already used. Request a new one.")
        XCTAssertEqual(PFSignupErrorCode.unknownError.message, "Something went wrong. Try again, and contact support if it keeps happening.")
        XCTAssertEqual(PFSignupErrorCode.requestInvalid.message, "That request does not look right. Check the details and try again.")
        XCTAssertEqual(PFSignupErrorCode.unauthenticated.message, "Your sign-in has expired. Sign in again and try once more.")
        XCTAssertEqual(PFSignupErrorCode.serverNotConfigured.message, "This service is not available right now. Please try again later.")
        XCTAssertEqual(PFSignupErrorCode.deletionFailed.message, "Your account could not be deleted. Nothing was changed. Please try again.")
        XCTAssertEqual(PFSignupErrorCode.cascadeFailed.message, "Your account could not be fully deleted, so nothing was changed. Please try again or contact support.")
        XCTAssertEqual(PFSignupErrorCode.methodNotAllowed.message, "That request is not allowed.")
    }

    func testUnknownServerCodesFallBackToUnknownError() {
        XCTAssertEqual(PFSignupErrorCode.from(serverCode: "SOME_FUTURE_CODE"), .unknownError)
        XCTAssertEqual(PFSignupErrorCode.from(serverCode: nil), .unknownError)
        XCTAssertEqual(PFSignupErrorCode.from(serverCode: ""), .unknownError)
        XCTAssertEqual(PFSignupErrorCode.from(serverCode: "EMAIL_ALREADY_REGISTERED"), .emailAlreadyRegistered)
    }

    func testRemovedCodesFallBackToUnknownError() {
        // The SMS OTP codes, the phone-number codes, the referral
        // code that required a verified phone number, the server
        // case codes, and the pre-alignment reset codes no longer
        // exist in the catalog: a server that still sends one must
        // fall back, never crash or surface raw text.
        XCTAssertEqual(PFSignupErrorCode.from(serverCode: "OTP_EXPIRED"), .unknownError)
        XCTAssertEqual(PFSignupErrorCode.from(serverCode: "OTP_SERVICE_UNAVAILABLE"), .unknownError)
        XCTAssertEqual(PFSignupErrorCode.from(serverCode: "OTP_RATE_LIMITED"), .unknownError)
        XCTAssertEqual(PFSignupErrorCode.from(serverCode: "MOBILE_NOT_VERIFIED"), .unknownError)
        XCTAssertEqual(PFSignupErrorCode.from(serverCode: "MOBILE_ALREADY_REGISTERED"), .unknownError)
        XCTAssertEqual(PFSignupErrorCode.from(serverCode: "REFERRAL_UNVERIFIED"), .unknownError)
        XCTAssertEqual(PFSignupErrorCode.from(serverCode: "CASE_ID_NOT_FOUND"), .unknownError)
        XCTAssertEqual(PFSignupErrorCode.from(serverCode: "CASE_EXPIRED"), .unknownError)
        XCTAssertEqual(PFSignupErrorCode.from(serverCode: "CASE_ALREADY_COMPLETED"), .unknownError)
        XCTAssertEqual(PFSignupErrorCode.from(serverCode: "CASE_GENERATION_FAILED"), .unknownError)
        XCTAssertEqual(PFSignupErrorCode.from(serverCode: "RESET_LINK_EXPIRED"), .unknownError)
        XCTAssertEqual(PFSignupErrorCode.from(serverCode: "PASSWORD_RESET_EMAIL_SENT"), .unknownError)
    }

    func testErrorParsingFromContractShape() {
        let body = #"{"code":"EMAIL_ALREADY_REGISTERED","message":"taken"}"#.data(using: .utf8)!
        let parsed = PFSignupError.fromResponseData(body)
        XCTAssertEqual(parsed.code, .emailAlreadyRegistered)
        XCTAssertEqual(parsed.localizedDescription, PFSignupErrorCode.emailAlreadyRegistered.message)

        let unknownBody = #"{"code":"NOPE","message":"?"}"#.data(using: .utf8)!
        XCTAssertEqual(PFSignupError.fromResponseData(unknownBody).code, .unknownError)

        let garbage = "not json".data(using: .utf8)!
        XCTAssertEqual(PFSignupError.fromResponseData(garbage).code, .unknownError)
    }

    func testGoTrueMessageMapping() {
        XCTAssertEqual(PFSignupError.fromGoTrueMessage("User already registered").code, .emailAlreadyRegistered)
        XCTAssertEqual(PFSignupError.fromGoTrueMessage("Email not confirmed").code, .emailNotVerified)
        XCTAssertEqual(PFSignupError.fromGoTrueMessage("Invalid login credentials").code, .credentialsInvalid)
        XCTAssertEqual(PFSignupError.fromGoTrueMessage("Password should be at least 6 characters.").code, .passwordTooShort)
        XCTAssertEqual(PFSignupError.fromGoTrueMessage("Token has expired or is invalid").code, .resetLinkInvalid)
        XCTAssertEqual(PFSignupError.fromGoTrueMessage("something else entirely").code, .unknownError)
    }

    // MARK: - Case ID

    func testCaseIDValidation() {
        XCTAssertTrue(SignupCaseID.isValid("PF-ABC234"))
        XCTAssertEqual(SignupCaseID.normalized("pf-abc234"), "PF-ABC234")
        XCTAssertEqual(SignupCaseID.normalized("  PF-ABC234  "), "PF-ABC234")
        XCTAssertFalse(SignupCaseID.isValid("PF-ABC12I"))
        XCTAssertFalse(SignupCaseID.isValid("PF-ABC12O"))
        XCTAssertFalse(SignupCaseID.isValid("PF-ABC120"))
        XCTAssertFalse(SignupCaseID.isValid("PF-ABC12"))
        XCTAssertFalse(SignupCaseID.isValid("PF-ABC2345"))
        XCTAssertFalse(SignupCaseID.isValid("AB-ABC234"))
        XCTAssertNil(SignupCaseID.normalized("PF-ABC12L"))
        XCTAssertNil(SignupCaseID.normalized(""))
    }

    func testGeneratedCaseIDsAreValid() {
        for _ in 0..<20 {
            let generated = SignupCaseID.generate()
            XCTAssertTrue(SignupCaseID.isValid(generated), "Generated case ID must be valid: \(generated)")
            XCTAssertEqual(generated, SignupCaseID.normalized(generated))
        }
    }

    // MARK: - Referral code

    func testReferralCodeIsDeterministicAndWellFormed() {
        let first = ReferralStore.code(forUserID: "user-123")
        let second = ReferralStore.code(forUserID: "user-123")
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 8)
        let allowed = Set(PFCodeAlphabet.characters)
        XCTAssertTrue(first.allSatisfy { allowed.contains($0) })
        XCTAssertNotEqual(first, ReferralStore.code(forUserID: "user-456"))
    }
}
