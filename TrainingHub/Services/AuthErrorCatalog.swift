// AuthErrorCatalog.swift
// Payments Training Hub iOS - Shared error catalog for the email signup
// flow, the website parity contract, case IDs, and password reset.
// Signup is email plus password plus terms acceptance, with
// Supabase email confirmation as the only verification: no mobile
// number is collected and no SMS code is ever sent. v77 removed
// the SMS OTP flow and its codes; v78 removed the last stale code
// that required a verified phone number (REFERRAL_UNVERIFIED) and
// aligned this list with the website catalog, so the two surfaces
// now carry the same 22 codes with the same messages. The server
// codes and the customer-facing messages below are the FIXED
// contract shared with the website: the messages are verbatim and
// must not be reworded here. An unknown server code always falls
// back to UNKNOWN_ERROR, so a new server code can never surface
// raw text to a learner.
// v97 parity update: CREDENTIALS_INVALID and EMAIL_NOT_VERIFIED
// now carry the guiding wording the website adopted in its 16 Nov
// auth fix (commit 106bd675), because GoTrue returns one generic
// invalid-credentials error for a wrong password, an unconfirmed
// account, and an account with no password, so the message itself
// must offer the next actions. The two messages name the iOS
// controls ("Resend confirmation email") where the website names
// its own ("Resume signup"); the meaning is identical. The website
// doc audit/ERROR-CODE-CATALOG.md still carries the old wording
// (doc sync owed on a later pass); PA_ERROR_MESSAGES wins.
// No em dashes in any user-facing text.

import Foundation

// MARK: - Code alphabet

/// The alphabet shared by case IDs and referral codes: uppercase
/// letters without I, L and O, and digits without 0 and 1, so a code
/// read aloud or typed from a screenshot cannot be confused.
enum PFCodeAlphabet {
    static let characters = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
}

// MARK: - Error catalog

/// Every server error code in the signup contract, with its exact
/// customer-facing message. The order matches the canonical
/// website catalog (audit/ERROR-CODE-CATALOG.md), which wins on
/// any disagreement. Add a new code here first, with the
/// website's wording, before any call site uses it.
enum PFSignupErrorCode: String, CaseIterable {
    case emailAlreadyRegistered = "EMAIL_ALREADY_REGISTERED"
    case emailNotVerified = "EMAIL_NOT_VERIFIED"
    case emailInvalid = "EMAIL_INVALID"
    case caseIDInvalid = "CASE_ID_INVALID"
    case referralInvalid = "REFERRAL_INVALID"
    case referralSelf = "REFERRAL_SELF"
    case referralAlreadyUsed = "REFERRAL_ALREADY_USED"
    case termsNotAccepted = "TERMS_NOT_ACCEPTED"
    case credentialsInvalid = "CREDENTIALS_INVALID"
    case passwordTooShort = "PASSWORD_TOO_SHORT"
    case passwordMismatch = "PASSWORD_MISMATCH"
    case sessionExpired = "SESSION_EXPIRED"
    case emailConfirmationResent = "EMAIL_CONFIRMATION_RESENT"
    case passwordResetSent = "PASSWORD_RESET_SENT"
    case resetLinkInvalid = "RESET_LINK_INVALID"
    case unknownError = "UNKNOWN_ERROR"
    case requestInvalid = "REQUEST_INVALID"
    case unauthenticated = "UNAUTHENTICATED"
    case serverNotConfigured = "SERVER_NOT_CONFIGURED"
    case deletionFailed = "DELETION_FAILED"
    case cascadeFailed = "CASCADE_FAILED"
    case methodNotAllowed = "METHOD_NOT_ALLOWED"

    /// The customer-facing message, verbatim from the contract.
    var message: String {
        switch self {
        case .emailAlreadyRegistered:
            return "This email already has an account. Sign in instead."
        case .emailNotVerified:
            return "Verify your email address first. Check your inbox for the confirmation email, or use Resend confirmation email to send it again."
        case .emailInvalid:
            return "Enter a valid email address."
        case .caseIDInvalid:
            return "That case ID does not look right. Check it and try again."
        case .referralInvalid:
            return "That referral code is not valid."
        case .referralSelf:
            return "You cannot use your own referral code."
        case .referralAlreadyUsed:
            return "A referral discount was already used on this account."
        case .termsNotAccepted:
            return "Accept the terms and conditions to continue."
        case .credentialsInvalid:
            return "Email or password does not match our records. The same message appears when your email is not confirmed yet: resend the confirmation email, sign in with an emailed code, or reset your password."
        case .passwordTooShort:
            return "Your password must be at least 8 characters."
        case .passwordMismatch:
            return "The two passwords do not match. Type the same password twice."
        case .sessionExpired:
            return "Your session expired. Sign in again."
        case .emailConfirmationResent:
            return "If that email address has an unfinished signup, a confirmation link is on its way. Check your inbox."
        case .passwordResetSent:
            return "If an account exists for that email address, a password reset link is on its way. Check your inbox."
        case .resetLinkInvalid:
            return "This password reset link has expired or was already used. Request a new one."
        case .unknownError:
            return "Something went wrong. Try again, and contact support if it keeps happening."
        case .requestInvalid:
            return "That request does not look right. Check the details and try again."
        case .unauthenticated:
            return "Your sign-in has expired. Sign in again and try once more."
        case .serverNotConfigured:
            return "This service is not available right now. Please try again later."
        case .deletionFailed:
            return "Your account could not be deleted. Nothing was changed. Please try again."
        case .cascadeFailed:
            return "Your account could not be fully deleted, so nothing was changed. Please try again or contact support."
        case .methodNotAllowed:
            return "That request is not allowed."
        }
    }

    /// The catalog code for a raw server code string. Unknown,
    /// missing and empty codes fall back to UNKNOWN_ERROR.
    static func from(serverCode: String?) -> PFSignupErrorCode {
        guard let serverCode else { return .unknownError }
        return PFSignupErrorCode(rawValue: serverCode.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .unknownError
    }
}

/// One catalog error: a code plus its verbatim message. The catalog
/// message is always shown; the server text is kept only for
/// debugging and is never displayed. (v77 removed the {wait}
/// template handling with the SMS OTP limit codes: no remaining
/// code uses a wait template or retry_after_seconds.)
struct PFSignupError: Error, LocalizedError {
    let code: PFSignupErrorCode
    let serverMessage: String?
    let retryAfterSeconds: Int?

    init(code: PFSignupErrorCode, serverMessage: String? = nil, retryAfterSeconds: Int? = nil) {
        self.code = code
        self.serverMessage = serverMessage
        self.retryAfterSeconds = retryAfterSeconds
    }

    var errorDescription: String? {
        code.message
    }

    /// Parse an error body of the contract shape {code, message,
    /// retry_after_seconds}. Anything unparseable, or any code
    /// outside the catalog, is UNKNOWN_ERROR.
    static func fromResponseData(_ data: Data) -> PFSignupError {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return PFSignupError(code: .unknownError)
        }
        let code = PFSignupErrorCode.from(serverCode: object["code"] as? String)
        let retryAfterSeconds = (object["retry_after_seconds"] as? NSNumber)?.intValue
        return PFSignupError(code: code, serverMessage: object["message"] as? String, retryAfterSeconds: retryAfterSeconds)
    }

    /// Parse a SupabaseError carrying an HTTP body. Only a body that
    /// decodes to the contract shape yields its code; anything else
    /// is UNKNOWN_ERROR, except a transport failure, which keeps the
    /// connection wording callers already use.
    static func fromSupabaseError(_ error: Error) -> PFSignupError {
        guard let supabaseError = error as? SupabaseError else {
            return PFSignupError(code: .unknownError)
        }
        if case .http(_, let body) = supabaseError,
           let data = body.data(using: .utf8) {
            return fromResponseData(data)
        }
        return PFSignupError(code: .unknownError)
    }

    /// Map a GoTrue (Supabase Auth) message to the closest catalog
    /// code. GoTrue sends no catalog codes, so the signup,
    /// password sign-in and password reset paths match on its
    /// stable message text. Anything unmatched is UNKNOWN_ERROR.
    static func fromGoTrueMessage(_ message: String) -> PFSignupError {
        let text = message.lowercased()
        if text.contains("already registered") || text.contains("already exists") {
            return PFSignupError(code: .emailAlreadyRegistered, serverMessage: message)
        }
        if text.contains("email not confirmed") || text.contains("not confirmed") {
            return PFSignupError(code: .emailNotVerified, serverMessage: message)
        }
        if text.contains("invalid login credentials") || text.contains("invalid email or password") {
            return PFSignupError(code: .credentialsInvalid, serverMessage: message)
        }
        if text.contains("password") && (text.contains("at least") || text.contains("too short") || text.contains("weak") || text.contains("characters")) {
            return PFSignupError(code: .passwordTooShort, serverMessage: message)
        }
        if (text.contains("expired") || text.contains("invalid")) && (text.contains("token") || text.contains("link") || text.contains("otp")) {
            return PFSignupError(code: .resetLinkInvalid, serverMessage: message)
        }
        return PFSignupError(code: .unknownError, serverMessage: message)
    }
}

// MARK: - Case ID

/// A signup case ID: "PF-" plus 6 characters from the shared
/// alphabet. The app generates the case ID when signup starts (see
/// generate()); it travels in the GoTrue user_metadata, is shown in
/// the registration welcome popup and on the profile, and is the
/// account identifier for support. An unfinished signup resumes by
/// opening the email confirmation link and signing in with email
/// and password: the case ID is a reference, never an entry key,
/// and no code is ever needed to resume.
enum SignupCaseID {
    static let prefix = "PF-"
    static let suffixLength = 6

    /// Generate a new case ID. Random, from the shared alphabet.
    /// A case ID is a support reference, not a secret and not a
    /// credential, so standard library randomness is enough.
    static func generate() -> String {
        let alphabet = Array(PFCodeAlphabet.characters)
        let suffix = (0..<suffixLength).map { _ in alphabet.randomElement() ?? "A" }
        return prefix + String(suffix)
    }

    /// The normalised case ID for raw input (trimmed, uppercased),
    /// or nil when the input is not a well-formed case ID.
    static func normalized(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard isValid(cleaned) else { return nil }
        return cleaned
    }

    /// True when the value is exactly "PF-" plus 6 alphabet
    /// characters. Callers normalise first; this checks the exact
    /// shape, so lowercase input must go through normalized(_:).
    static func isValid(_ value: String) -> Bool {
        guard value.hasPrefix(prefix) else { return false }
        let suffix = String(value.dropFirst(prefix.count))
        guard suffix.count == suffixLength else { return false }
        let allowed = Set(PFCodeAlphabet.characters)
        return suffix.allSatisfy { allowed.contains($0) }
    }
}

// MARK: - Form validation (v83)

/// Client-side form validation shared by the signup, sign-in and
/// password reset screens, so a button never sits dead with no
/// explanation. The rules match the server-side guards in
/// AuthService (an email that contains "@", a password of at
/// least 8 characters, matching passwords, accepted terms):
/// the email check additionally requires text on both sides of
/// "@" and a dot in the domain, which is what Supabase requires
/// for delivery; the server remains the final arbiter and its
/// catalog message is still shown on failure. Errors are gated
/// on `attempted`: nothing nags on a fresh form, and once the
/// learner taps the button the errors appear under each invalid
/// field and update live as the learner types. All messages come
/// from PFSignupErrorCode, verbatim, except the code message,
/// which matches the wording AuthService already uses.
enum PFFormValidation {
    /// True when the email looks deliverable: trimmed, no spaces,
    /// one "@" with text on both sides, a dot in the domain, and
    /// at most 254 characters (the RFC 5321 limit), so a pasted
    /// wall of text fails here with the email message instead of
    /// going to the server.
    static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" "), trimmed.count <= 254 else { return false }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        return parts[1].contains(".")
    }

    /// The email error to show under the email field, or nil when
    /// the field is fine or the form has not been attempted yet.
    static func emailError(for email: String, attempted: Bool) -> String? {
        guard attempted, !isValidEmail(email) else { return nil }
        return PFSignupErrorCode.emailInvalid.message
    }

    /// The password error to show under the password field, or nil
    /// when the password is at least 8 characters or the form has
    /// not been attempted yet.
    static func passwordError(for password: String, attempted: Bool) -> String? {
        guard attempted, password.count < 8 else { return nil }
        return PFSignupErrorCode.passwordTooShort.message
    }

    /// The confirm-password error, or nil when the two passwords
    /// match or the form has not been attempted yet.
    static func confirmPasswordError(password: String, confirmPassword: String, attempted: Bool) -> String? {
        guard attempted, password != confirmPassword else { return nil }
        return PFSignupErrorCode.passwordMismatch.message
    }

    /// The terms error to show under the terms row, or nil when
    /// the terms are accepted or the form has not been attempted yet.
    static func termsError(accepted: Bool, attempted: Bool) -> String? {
        guard attempted, !accepted else { return nil }
        return PFSignupErrorCode.termsNotAccepted.message
    }

    /// The sign-in code error, or nil when the code is 6 to 8
    /// digits after normalisation, or the form has not been
    /// attempted yet. The dashboard sends 8-digit codes, so the
    /// wording says 8 digits; 6 and 7 digit codes are still
    /// accepted, matching the website.
    static func codeError(for code: String, attempted: Bool) -> String? {
        guard attempted, !PFOTPCode.isValid(code) else { return nil }
        return "Enter the 8-digit code sent to your email."
    }
}

// MARK: - Emailed sign-in code (v97)

/// Normalisation and validation for the emailed sign-in code.
/// The dashboard sends 8-digit codes that expire after 1 hour.
/// A pasted code often carries spaces or dashes ("1234 5678",
/// "1234-5678"); normalisation strips those before the code is
/// checked or sent, so a paste works exactly like typing. Only
/// digits survive: anything else fails validation with the code
/// message, never a server error.
enum PFOTPCode {
    /// The code length the UI promises (dashboard setting).
    static let displayDigits = 8
    /// The shortest code accepted, matching the website.
    static let minimumDigits = 6
    /// The longest code accepted, matching the website.
    static let maximumDigits = 8

    /// The code with spaces, dashes and surrounding whitespace
    /// removed. Letters and other characters are kept here so
    /// validation can reject them, instead of silently changing
    /// what the learner typed.
    static func normalized(_ raw: String) -> String {
        raw.filter { !$0.isWhitespace && $0 != "-" }
    }

    /// True when the normalised code is 6 to 8 decimal digits.
    static func isValid(_ raw: String) -> Bool {
        let code = normalized(raw)
        guard (minimumDigits...maximumDigits).contains(code.count) else { return false }
        return code.allSatisfy { $0.isNumber && $0.isASCII }
    }
}

// MARK: - Signup reply classification (v97)

/// What a successful GoTrue signup reply means. GoTrue returns
/// HTTP 200 for a re-signup of an existing email (a deliberate
/// fake success, so the reply can never confirm whether an
/// account exists), so the reply body itself must be classified:
/// a session means signed in at once, a bare new user means the
/// confirmation email is on its way, and a bare existing user
/// means the email already has an account. The classification
/// uses only the timestamps GoTrue records; it never uses the
/// `identities` array, because the project's own recorded
/// new-signup reply carries `"identities": []`, so that signal
/// would classify every new signup as a duplicate.
enum PFSignupReplyKind: Equatable {
    /// The reply carries a session: signed in at once.
    case signedIn
    /// A new account was created and the confirmation email was sent.
    case newAccount
    /// The email already has a confirmed account.
    case confirmedDuplicate
    /// The email already has an account that is not confirmed yet.
    /// The first signup's password still stands: re-signing up
    /// only resends the confirmation, it never saves a new one.
    case unconfirmedDuplicate
    /// The reply could not be read as any known shape. Callers
    /// never treat this as a new account: claiming a
    /// confirmation email was sent when the reply was not
    /// understood is wrong information.
    case unknown
}

/// Pure classification of a GoTrue signup reply body, so the
/// duplicate rules are unit-tested without any network call.
enum PFSignupReplyClassifier {
    /// A confirmation email sent more than this long after the
    /// account was created proves the account already existed:
    /// a first signup sends its confirmation within seconds of
    /// creation, while a re-signup resends it minutes, hours or
    /// days later.
    static let duplicateResendThresholdSeconds: TimeInterval = 120

    /// Classify a signup reply body. Accepts both reply shapes:
    /// the bare user object GoTrue returns when Confirm email is
    /// on, and a session reply with a nested `user` object.
    static func classify(data: Data) -> PFSignupReplyKind {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown
        }
        if object["access_token"] as? String != nil {
            return .signedIn
        }
        let user = (object["user"] as? [String: Any]) ?? object
        guard user["id"] as? String != nil else {
            return .unknown
        }
        if let confirmedAt = user["email_confirmed_at"] as? String, !confirmedAt.isEmpty {
            return .confirmedDuplicate
        }
        if let sentAt = parseGoTrueDate(user["confirmation_sent_at"] as? String),
           let createdAt = parseGoTrueDate(user["created_at"] as? String),
           sentAt.timeIntervalSince(createdAt) > duplicateResendThresholdSeconds {
            return .unconfirmedDuplicate
        }
        return .newAccount
    }

    /// Parse a GoTrue timestamp, with or without fractional
    /// seconds ("2026-11-16T12:34:56.123456Z" or
    /// "2026-11-16T12:34:56Z"). Nil for anything else.
    static func parseGoTrueDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}
