// AuthErrorCatalogTests.swift
// TrainingHub iOS - v78 tests: the shared signup error catalog
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
@testable import TrainingHub

@MainActor
final class AuthErrorCatalogTests: XCTestCase {

    // MARK: - Catalog messages (verbatim)

    func testCatalogMessagesAreVerbatim() {
        XCTAssertEqual(PFSignupErrorCode.emailAlreadyRegistered.message, "This email already has an account. Sign in instead.")
        XCTAssertEqual(PFSignupErrorCode.emailNotVerified.message, "Verify your email address first. Check your inbox for the confirmation email, or use Resend confirmation email to send it again.")
        XCTAssertEqual(PFSignupErrorCode.emailInvalid.message, "Enter a valid email address.")
        XCTAssertEqual(PFSignupErrorCode.caseIDInvalid.message, "That case ID does not look right. Check it and try again.")
        XCTAssertEqual(PFSignupErrorCode.referralInvalid.message, "That referral code is not valid.")
        XCTAssertEqual(PFSignupErrorCode.referralSelf.message, "You cannot use your own referral code.")
        XCTAssertEqual(PFSignupErrorCode.referralAlreadyUsed.message, "A referral discount was already used on this account.")
        XCTAssertEqual(PFSignupErrorCode.termsNotAccepted.message, "Accept the terms and conditions to continue.")
        XCTAssertEqual(PFSignupErrorCode.credentialsInvalid.message, "Email or password does not match our records. The same message appears when your email is not confirmed yet: resend the confirmation email, sign in with an emailed code, or reset your password.")
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

    // MARK: - Emailed code normalisation and validation (v97)

    func testOTPCodeNormalisationStripsSpacesAndDashes() {
        XCTAssertEqual(PFOTPCode.normalized("1234 5678"), "12345678")
        XCTAssertEqual(PFOTPCode.normalized("1234-5678"), "12345678")
        XCTAssertEqual(PFOTPCode.normalized("  1234 5678\n"), "12345678")
        XCTAssertEqual(PFOTPCode.normalized("12345678"), "12345678")
    }

    func testOTPCodeValidationAcceptsSixToEightDigits() {
        XCTAssertTrue(PFOTPCode.isValid("12345678"))
        XCTAssertTrue(PFOTPCode.isValid("1234567"))
        XCTAssertTrue(PFOTPCode.isValid("123456"))
        XCTAssertTrue(PFOTPCode.isValid("1234 5678"))
        XCTAssertTrue(PFOTPCode.isValid("1234-5678"))
        XCTAssertFalse(PFOTPCode.isValid("12345"))
        XCTAssertFalse(PFOTPCode.isValid("123456789"))
        XCTAssertFalse(PFOTPCode.isValid("1234a678"))
        XCTAssertFalse(PFOTPCode.isValid(""))
        XCTAssertFalse(PFOTPCode.isValid("    "))
        XCTAssertFalse(PFOTPCode.isValid("12 34"))
    }

    func testCodeErrorUsesEightDigitWording() {
        XCTAssertEqual(
            PFFormValidation.codeError(for: "123", attempted: true),
            "Enter the 8-digit code sent to your email."
        )
        XCTAssertNil(PFFormValidation.codeError(for: "1234 5678", attempted: true))
        XCTAssertNil(PFFormValidation.codeError(for: "123", attempted: false))
    }

    func testEmailValidationTrimsCaseAndLength() {
        XCTAssertTrue(PFFormValidation.isValidEmail("  USER@Example.COM  "))
        XCTAssertTrue(PFFormValidation.isValidEmail("learner@example.com"))
        XCTAssertFalse(PFFormValidation.isValidEmail("no-at-sign"))
        XCTAssertFalse(PFFormValidation.isValidEmail("a@b"))
        XCTAssertFalse(PFFormValidation.isValidEmail("a b@c.com"))
        XCTAssertFalse(PFFormValidation.isValidEmail(String(repeating: "a", count: 250) + "@b.com"))
    }

    func testGuidanceMessagesOfferNextActions() {
        // GoTrue returns one generic error for a wrong password,
        // an unconfirmed account, and an account with no password,
        // so both messages must carry the next actions in the text.
        let credentials = PFSignupErrorCode.credentialsInvalid.message
        XCTAssertTrue(credentials.contains("resend the confirmation email"))
        XCTAssertTrue(credentials.contains("emailed code"))
        XCTAssertTrue(credentials.contains("reset your password"))
        let notVerified = PFSignupErrorCode.emailNotVerified.message
        XCTAssertTrue(notVerified.contains("Resend confirmation email"))
        XCTAssertEqual(
            PFSignupError.fromGoTrueMessage("Invalid login credentials").code,
            .credentialsInvalid
        )
    }

    // MARK: - Signup reply classification (v97)

    private func signupReplyData(_ json: String) -> Data {
        json.data(using: .utf8)!
    }

    func testSignupReplyWithSessionIsSignedIn() {
        let data = signupReplyData(#"{"access_token":"tok","refresh_token":"ref","expires_in":3600,"user":{"id":"u1","email":"a@b.com"}}"#)
        XCTAssertEqual(PFSignupReplyClassifier.classify(data: data), .signedIn)
    }

    func testSignupReplyBareNewUserIsNewAccount() {
        // The bare user object GoTrue returns when Confirm email
        // is on: confirmation sent seconds after creation.
        let data = signupReplyData(#"{"id":"u1","email":"a@b.com","created_at":"2026-11-16T12:00:00Z","confirmation_sent_at":"2026-11-16T12:00:03Z","email_confirmed_at":null,"identities":[]}"#)
        XCTAssertEqual(PFSignupReplyClassifier.classify(data: data), .newAccount)
    }

    func testSignupReplyEmptyIdentitiesNeverMeansDuplicate() {
        // The disproved signal: the project's own recorded
        // new-signup reply carries "identities": [], so an empty
        // identities array must never classify as a duplicate.
        let data = signupReplyData(#"{"id":"u1","email":"a@b.com","created_at":"2026-11-16T12:00:00.123456Z","confirmation_sent_at":"2026-11-16T12:00:02.500000Z","identities":[]}"#)
        XCTAssertEqual(PFSignupReplyClassifier.classify(data: data), .newAccount)
    }

    func testSignupReplyConfirmedUserIsConfirmedDuplicate() {
        let data = signupReplyData(#"{"id":"u1","email":"a@b.com","created_at":"2026-11-10T09:00:00Z","confirmation_sent_at":"2026-11-16T12:00:00Z","email_confirmed_at":"2026-11-10T09:05:00Z"}"#)
        XCTAssertEqual(PFSignupReplyClassifier.classify(data: data), .confirmedDuplicate)
    }

    func testSignupReplyLateResendIsUnconfirmedDuplicate() {
        // Confirmation resent an hour after creation: the account
        // already existed, and the re-signup only resent the mail.
        let data = signupReplyData(#"{"id":"u1","email":"a@b.com","created_at":"2026-11-16T11:00:00Z","confirmation_sent_at":"2026-11-16T12:00:00Z","email_confirmed_at":null}"#)
        XCTAssertEqual(PFSignupReplyClassifier.classify(data: data), .unconfirmedDuplicate)
    }

    func testSignupReplyResendWithinThresholdIsNewAccount() {
        // A resend 119 seconds after creation is within the
        // threshold: treated as a new account, never a duplicate.
        let data = signupReplyData(#"{"id":"u1","email":"a@b.com","created_at":"2026-11-16T12:00:00Z","confirmation_sent_at":"2026-11-16T12:01:59Z","email_confirmed_at":null}"#)
        XCTAssertEqual(PFSignupReplyClassifier.classify(data: data), .newAccount)
    }

    func testSignupReplyNestedUserShapeClassifies() {
        let data = signupReplyData(#"{"user":{"id":"u1","email":"a@b.com","created_at":"2026-11-16T11:00:00Z","confirmation_sent_at":"2026-11-16T12:00:00Z","email_confirmed_at":null}}"#)
        XCTAssertEqual(PFSignupReplyClassifier.classify(data: data), .unconfirmedDuplicate)
    }

    func testSignupReplyGarbageIsUnknown() {
        XCTAssertEqual(PFSignupReplyClassifier.classify(data: signupReplyData("not json")), .unknown)
        XCTAssertEqual(PFSignupReplyClassifier.classify(data: signupReplyData("{}")), .unknown)
        XCTAssertEqual(PFSignupReplyClassifier.classify(data: signupReplyData("[]")), .unknown)
    }

    func testGoTrueDateParsingHandlesFractionalSeconds() {
        XCTAssertNotNil(PFSignupReplyClassifier.parseGoTrueDate("2026-11-16T12:00:00.123456Z"))
        XCTAssertNotNil(PFSignupReplyClassifier.parseGoTrueDate("2026-11-16T12:00:00Z"))
        XCTAssertNil(PFSignupReplyClassifier.parseGoTrueDate(nil))
        XCTAssertNil(PFSignupReplyClassifier.parseGoTrueDate(""))
        XCTAssertNil(PFSignupReplyClassifier.parseGoTrueDate("yesterday"))
    }
}
