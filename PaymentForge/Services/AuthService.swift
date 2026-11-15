// AuthService.swift
// Payments Training Hub iOS - Sign in with Apple, email OTP / magic link,
// Google sign-in, and session handling through Supabase Auth.
// Guest is the default: nothing here is ever a launch gate. The app
// opens straight into the guest experience, and auth is an upgrade
// path reached from Profile or the drawer "Sign in" row.
// Sessions live in the Keychain, never in UserDefaults: tokens are
// secrets and UserDefaults is not a safe place for them.
// When Supabase is not configured, every method fails gracefully with
// "Sign-in is not set up yet" and the app keeps working as a guest.
// Google sign-in uses the Supabase Auth authorize URL with PKCE
// (ASWebAuthenticationSession), the same pattern Supabase documents
// for OAuth providers: no custom OAuth flow and no third-party SDK.
// The callback returns to the app on the com.paymentforge.app scheme,
// which Info.plist registers; PaymentForgeApp forwards the URL to
// handleAuthCallback (see SupabaseConfig). Email OTP, the default,
// is unaffected by callback wiring.
// Account deletion goes through the delete-account edge function,
// which deletes the Auth user with the service-role key. The app
// never deletes only locally and calls it done.
// No em dashes in any user-facing text.

import Foundation
import AuthenticationServices
import Combine
import CryptoKit
import Security
import UIKit

// MARK: - Session stored in the Keychain

private struct StoredSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: AuthUser
}

/// The raw session reply from Supabase Auth.
private struct SupabaseSessionReply: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: SupabaseUserReply

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

private struct SupabaseUserReply: Decodable {
    let id: String
    let email: String?
    let emailConfirmedAt: String?
    let userMetadata: SupabaseUserMetadata?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case emailConfirmedAt = "email_confirmed_at"
        case userMetadata = "user_metadata"
    }
}

/// The two display-name fields in GoTrue user_metadata. Only these
/// are decoded: Google user_metadata also carries booleans
/// (email_verified, phone_verified), which cannot decode as
/// [String: String] and used to break sign-in with "The server reply
/// could not be read". Unknown keys are ignored by Decodable.
private struct SupabaseUserMetadata: Decodable {
    let fullName: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case name
    }
}

// MARK: - Keychain

/// Minimal Keychain storage for the session. One item, one account.
private enum SessionKeychain {
    private static let service = "com.paymentforge.app.supabase-session"
    private static let account = "session"

    static func save(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Sign in with Apple coordinator

/// Runs the Apple ID authorization sheet and hands the identity token
/// back. Kept separate from AuthService so the authorization delegate
/// does not have to fight the MainActor isolation of the service.
private enum AuthError: LocalizedError {
    case appleTokenMissing
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .appleTokenMissing:
            return "Apple did not return a sign-in token. Please try again."
        case .notConfigured:
            return "Sign-in is not set up yet. The app keeps working as a guest."
        }
    }
}

// MARK: - Password signup result

/// The outcome of a password signup: signed in at once (the project
/// confirms email automatically), or created but waiting for the
/// learner to open the email confirmation link before signing in.
enum PasswordSignupResult {
    case signedIn
    case needsEmailConfirmation
}

/// A registration waiting for its first sign-in, kept in the guest
/// namespace so it survives an app restart between account creation
/// and the confirmation sign-in. It carries the email the account
/// was created with, so it is only ever consumed by a session for
/// that same email, and the signup case ID, so the case ID is
/// stored under the right account even when the confirmation
/// sign-in happens in a later launch.
private struct PendingRegistration: Codable {
    let email: String
    let caseID: String
}

// MARK: - OAuth web session coordinator

/// Runs an ASWebAuthenticationSession for Supabase OAuth providers
/// (Google) and hands the callback URL back. Kept separate from
/// AuthService for the same reason as the Apple coordinator.
private final class OAuthWebSessionCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func start(url: URL, callbackScheme: String, completion: @escaping (Result<URL, Error>) -> Void) {
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
            if let error {
                completion(.failure(error))
            } else if let callbackURL {
                completion(.success(callbackURL))
            } else {
                completion(.failure(AuthError.appleTokenMissing))
            }
        }
        session.presentationContextProvider = self
        self.session = session
        session.start()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

/// PKCE helpers for the Supabase OAuth authorize flow. The verifier
/// lives only in memory for the length of one sign-in attempt.
private enum PKCE {
    static func randomVerifier(length: Int = 64) -> String {
        let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - AuthService

/// Owns the signed-in state for the whole app. Use AuthService.shared
/// so views work even before the coordinator wires environment objects.
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    private let client = SupabaseClient.shared

    /// The signed-in user, nil for a guest.
    @Published private(set) var currentUser: AuthUser?

    /// The profile row from the profiles table, when signed in.
    @Published private(set) var profile: UserProfile?

    /// True when a user is signed in.
    var isSignedIn: Bool { currentUser != nil }

    /// True when Supabase is configured and sign-in can work.
    var canSignIn: Bool { client.isConfigured }

    /// The name to show everywhere: the edited profile name first,
    /// then the name from the sign-in provider. The edited name
    /// always wins; the Gmail/Google name is only a fallback for a
    /// user who has never set a name. Nil when there is no name.
    var displayName: String? {
        if let name = profile?.displayName,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        if let name = currentUser?.displayName,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return nil
    }

    /// The last user-facing auth error, shown as an alert. Nil when
    /// there is no error to show.
    @Published var authError: String?

    /// The last user-facing auth notice (not an error), for example
    /// "Verification email sent". Nil when there is nothing to show.
    @Published var authInfo: String?

    /// True while a sign-in, sign-out or verification call is running.
    @Published private(set) var isBusy = false

    /// The email an OTP was sent to, so the verify screen can prefill it.
    @Published private(set) var pendingEmail: String?

    /// True when a guest-to-account migration is being offered after
    /// a fresh sign-in: guest-namespace data exists and the account
    /// namespace lacks at least one of those keys. EmailAuthView
    /// observes this and presents the Migrate / Not now choice for
    /// email sign-ins; WelcomeView presents the same choice for
    /// Apple, Google, and magic-link sign-ins. The offer is made
    /// at most once per account: accepting or declining records a
    /// resolved marker in the account namespace.
    @Published private(set) var offersGuestMigration = false

    /// True while the registration welcome popup should show: the
    /// first sign-in right after a registration completes
    /// (credentials set, terms accepted). EmailSignupView
    /// presents the popup while this is true and stays open until
    /// it goes away. The once-only rule lives in the
    /// pf.welcomeShown.v1 flag, written when the popup is first
    /// shown, so it never appears on a later login.
    @Published private(set) var showRegistrationWelcome = false

    /// The case ID shown in the registration welcome popup, in
    /// PF-XXXXXX form. Nil when no popup is showing.
    @Published private(set) var registrationWelcomeCaseID: String?

    /// The case ID for the signed-in account, in PF-XXXXXX form,
    /// when the account was created through the email signup flow.
    /// Nil for guests and for accounts created another way (Apple,
    /// Google, email code). Shown on the profile; stored per
    /// account, so it never leaks across accounts.
    @Published private(set) var accountCaseID: String?

    /// True while the set-new-password screen should show: the
    /// learner opened a password reset link and the recovery
    /// session is stored. PaymentForgeApp presents
    /// ResetPasswordView while this is true.
    @Published private(set) var showPasswordReset = false

    /// The PKCE verifier for the Google sign-in attempt in flight, if
    /// any. In memory only, cleared after the callback is handled.
    private var pendingPKCEVerifier: String?
    private var oauthCoordinator: OAuthWebSessionCoordinator?

    private var storedSession: StoredSession?

    /// The display name from the sign-in provider (the Gmail/Google
    /// full name in user_metadata). Kept separate from the effective
    /// display name so the edited profile name can win without
    /// losing the provider name as a fallback.
    private var authProviderName: String?

    init() {
        restoreSession()
    }

    // MARK: - Friendly errors

    /// Turn a thrown error into a message a learner can act on.
    /// The server's own message is used only to pick the wording;
    /// raw error bodies are never shown.
    private func friendlyAuthError(_ error: Error) -> String {
        if let supabaseError = error as? SupabaseError {
            if case .http(let status, _) = supabaseError {
                let serverText = (supabaseError.serverMessage ?? "").lowercased()
                switch status {
                case 400 where serverText.contains("expired"):
                    return "That code has expired. Ask for a new code and try again."
                case 400 where serverText.contains("invalid"):
                    return "That code did not work. Check the code and try again."
                case 422:
                    return "That code did not work. Check the code and try again."
                case 429:
                    return "Too many attempts. Wait a little while and try again."
                default:
                    break
                }
            }
            return supabaseError.localizedDescription
        }
        let text = error.localizedDescription.lowercased()
        if text.contains("cancelled") || text.contains("canceled") {
            return "Sign-in was cancelled. Nothing changed."
        }
        if text.contains("offline") || text.contains("internet") || text.contains("network") {
            return "Check your connection and try again."
        }
        return "Something went wrong. Please try again."
    }

    // MARK: - Sign in with Apple

    /// The raw nonce for the in-flight Apple request. The button's
    /// onRequest stores it here; onCompletion hands it to Supabase
    /// with the idToken so Supabase can verify the token.
    private var appleSignInNonce = ""

    /// Configure the Apple request for the SignInWithAppleButton flow.
    /// Generates a fresh nonce, stores it, and asks for name and email.
    /// Called by the button before it shows the Apple sheet.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        appleSignInNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    /// Finish the SignInWithAppleButton flow. The button already showed
    /// the Apple sheet; this takes its result and exchanges the token
    /// with Supabase. A cancelled sheet is not an error.
    /// Needs the Sign in with Apple capability (paid Developer Program)
    /// plus Supabase configured with Apple as a provider. Fails
    /// gracefully when either is missing.
    func completeAppleSignIn(with result: Result<ASAuthorization, Error>) async {
        guard client.isConfigured else {
            authError = AuthError.notConfigured.errorDescription
            return
        }
        isBusy = true
        defer { isBusy = false }
        switch result {
        case .failure(let error as NSError) where error.code == 1001:
            // The user cancelled the Apple sheet. That is not an error.
            return
        case .failure(let error):
            authError = friendlyAuthError(error)
            return
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                authError = AuthError.appleTokenMissing.errorDescription
                return
            }
            await exchangeAppleToken(idToken: idToken, nonce: appleSignInNonce)
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        for byte in bytes {
            result.append(charset[Int(byte) % charset.count])
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func exchangeAppleToken(idToken: String, nonce: String) async {
        guard let base = SupabaseConfig.authBaseURL,
              let url = URL(string: "\(base)/token?grant_type=id_token") else {
            authError = SupabaseError.invalidURL.errorDescription
            return
        }
        struct AppleTokenBody: Encodable {
            let provider: String
            let idToken: String
            let nonce: String
            enum CodingKeys: String, CodingKey {
                case provider
                case idToken = "id_token"
                case nonce
            }
        }
        do {
            let data = try await client.request(
                url: url,
                method: "POST",
                body: AppleTokenBody(provider: "apple", idToken: idToken, nonce: nonce)
            )
            try await storeSession(from: data)
        } catch {
            authError = friendlyAuthError(error)
        }
    }

    // MARK: - Email OTP and magic link

    /// Send a 6-digit sign-in code to the email address. Creates the
    /// account on first use. The code is verified with verifyEmailOTP.
    func sendEmailOTP(email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.contains("@") else {
            authError = PFSignupErrorCode.emailInvalid.message
            return
        }
        guard client.isConfigured else {
            authError = AuthError.notConfigured.errorDescription
            return
        }
        guard let base = SupabaseConfig.authBaseURL,
              let url = URL(string: "\(base)/otp") else {
            authError = SupabaseError.invalidURL.errorDescription
            return
        }
        // A fresh attempt clears any error from an earlier one, so a
        // stale message can never survive a later success and surface
        // on the presenting view after sign-in.
        authError = nil
        struct OTPBody: Encodable {
            let email: String
            let createUser: Bool
            enum CodingKeys: String, CodingKey {
                case email
                case createUser = "create_user"
            }
        }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await client.request(url: url, method: "POST", body: OTPBody(email: trimmed, createUser: true))
            pendingEmail = trimmed
        } catch {
            authError = friendlyAuthError(error)
        }
    }

    /// Verify the 6-digit code sent by sendEmailOTP and sign in.
    func verifyEmailOTP(email: String, code: String) async -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            authError = "Enter the 6-digit code sent to your email."
            return false
        }
        guard !trimmedEmail.isEmpty, trimmedEmail.contains("@") else {
            authError = PFSignupErrorCode.emailInvalid.message
            return false
        }
        guard client.isConfigured else {
            authError = AuthError.notConfigured.errorDescription
            return false
        }
        guard let base = SupabaseConfig.authBaseURL,
              let url = URL(string: "\(base)/verify") else {
            authError = SupabaseError.invalidURL.errorDescription
            return false
        }
        // A fresh attempt clears any error from an earlier one, so a
        // stale message can never survive a later success and surface
        // on the presenting view after sign-in.
        authError = nil
        struct VerifyBody: Encodable {
            let email: String
            let token: String
            let type: String
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let data = try await client.request(
                url: url,
                method: "POST",
                body: VerifyBody(email: trimmedEmail, token: trimmedCode, type: "email")
            )
            try await storeSession(from: data)
            return currentUser != nil
        } catch {
            // Each failure kind gets its own wording: a network
            // failure must not be reported as a wrong code, and a
            // rate limit must say to wait. Wrong and expired codes
            // still get code-specific wording.
            authError = friendlyAuthError(error)
            return false
        }
    }

    // MARK: - Password sign-up and sign-in (email signup)

    /// Create the account with email and password. The terms must
    /// have been accepted (TERMS_NOT_ACCEPTED otherwise) and the
    /// password must be at least 8 characters (PASSWORD_TOO_SHORT
    /// otherwise). No mobile number is collected and no code step
    /// precedes creation: Supabase email confirmation is the only
    /// verification. The terms acceptance time and the signup case
    /// ID travel in the GoTrue user_metadata. The reply decides the
    /// outcome: a session means signed in at once, no session means
    /// email confirmation is required first, and the learner signs
    /// in with signInWithPassword after opening the confirmation
    /// link. Either way the pending registration is recorded first,
    /// so the first session for this email stores the case ID and
    /// shows the welcome popup. Nil means failure, with authError
    /// set to a catalog message (EMAIL_ALREADY_REGISTERED when the
    /// email is taken).
    func signUpWithPassword(email: String, password: String, caseID: String, termsAccepted: Bool) async -> PasswordSignupResult? {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard termsAccepted else {
            authError = PFSignupErrorCode.termsNotAccepted.message
            return nil
        }
        guard password.count >= 8 else {
            authError = PFSignupErrorCode.passwordTooShort.message
            return nil
        }
        guard !trimmedEmail.isEmpty, trimmedEmail.contains("@") else {
            authError = PFSignupErrorCode.emailInvalid.message
            return nil
        }
        guard client.isConfigured else {
            authError = AuthError.notConfigured.errorDescription
            return nil
        }
        guard let base = SupabaseConfig.authBaseURL,
              let url = URL(string: "\(base)/signup") else {
            authError = SupabaseError.invalidURL.errorDescription
            return nil
        }
        struct SignupMetadata: Encodable {
            let termsAcceptedAt: String
            let signupCaseID: String

            enum CodingKeys: String, CodingKey {
                case termsAcceptedAt = "terms_accepted_at"
                case signupCaseID = "signup_case_id"
            }
        }
        struct SignupBody: Encodable {
            let email: String
            let password: String
            let data: SignupMetadata
        }
        let body = SignupBody(
            email: trimmedEmail,
            password: password,
            data: SignupMetadata(
                termsAcceptedAt: ISO8601DateFormatter().string(from: Date()),
                signupCaseID: caseID
            )
        )
        authError = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let data = try await client.request(url: url, method: "POST", body: body)
            let hasSession = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["access_token"] as? String != nil
            Self.recordPendingRegistration(email: trimmedEmail, caseID: caseID)
            Self.clearLegacySignupState()
            if hasSession {
                try await storeSession(from: data)
                return currentUser != nil ? .signedIn : nil
            }
            pendingEmail = trimmedEmail
            authInfo = "Check your email to confirm your address, then sign in."
            return .needsEmailConfirmation
        } catch {
            authError = passwordAuthError(error)
            return nil
        }
    }

    /// Sign in with email and password, the step after email
    /// confirmation when confirmation was required. Failures
    /// use catalog messages: CREDENTIALS_INVALID for a wrong
    /// password, EMAIL_NOT_VERIFIED when the confirmation link has
    /// not been opened yet.
    func signInWithPassword(email: String, password: String) async -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedEmail.isEmpty, trimmedEmail.contains("@") else {
            authError = PFSignupErrorCode.emailInvalid.message
            return false
        }
        guard client.isConfigured else {
            authError = AuthError.notConfigured.errorDescription
            return false
        }
        guard let base = SupabaseConfig.authBaseURL,
              let url = URL(string: "\(base)/token?grant_type=password") else {
            authError = SupabaseError.invalidURL.errorDescription
            return false
        }
        authError = nil
        struct PasswordTokenBody: Encodable {
            let email: String
            let password: String
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let data = try await client.request(url: url, method: "POST", body: PasswordTokenBody(email: trimmedEmail, password: password))
            try await storeSession(from: data)
            return currentUser != nil
        } catch {
            authError = passwordAuthError(error)
            return false
        }
    }

    /// Turn a password-path failure into a catalog message. GoTrue
    /// sends no catalog codes, so its stable message text is mapped
    /// (see PFSignupError.fromGoTrueMessage); a transport failure
    /// keeps the connection wording, and anything else is
    /// UNKNOWN_ERROR.
    private func passwordAuthError(_ error: Error) -> String {
        if let supabaseError = error as? SupabaseError {
            if case .network = supabaseError {
                return "Check your connection and try again."
            }
            if let serverText = supabaseError.serverMessage, !serverText.isEmpty {
                return PFSignupError.fromGoTrueMessage(serverText).localizedDescription
            }
            return PFSignupErrorCode.unknownError.message
        }
        return PFSignupErrorCode.unknownError.message
    }

    // MARK: - Password reset (email link)

    /// Request a password reset email for the account email
    /// address. Uses the Supabase Auth recover endpoint with the
    /// app callback as redirect_to, so the reset link opens the
    /// app. No SMS and no code are involved, and no new backend
    /// endpoint is used. Anti-enumeration: an unknown email gets
    /// the same generic catalog message as a valid one, and HTTP
    /// failures from the endpoint get it too, so the reply can
    /// never reveal whether an account exists. Only a missing
    /// configuration, a malformed email, or a transport failure
    /// shows a different message, and none of those reveals
    /// account existence. DEPLOY CHECKLIST: Supabase Auth email
    /// delivery (custom SMTP, recovery template, redirect URL)
    /// must be verified before this works for learners; the
    /// built-in sender does not deliver to learners.
    func requestPasswordReset(email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.contains("@") else {
            authError = PFSignupErrorCode.emailInvalid.message
            return
        }
        guard client.isConfigured else {
            authError = AuthError.notConfigured.errorDescription
            return
        }
        guard let base = SupabaseConfig.authBaseURL,
              let url = URL(string: "\(base)/recover") else {
            authError = SupabaseError.invalidURL.errorDescription
            return
        }
        authError = nil
        struct RecoverBody: Encodable {
            let email: String
            let redirectTo: String?

            enum CodingKeys: String, CodingKey {
                case email
                case redirectTo = "redirect_to"
            }
        }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await client.request(
                url: url,
                method: "POST",
                body: RecoverBody(email: trimmed, redirectTo: SupabaseConfig.authRedirectURL?.absoluteString)
            )
            authInfo = PFSignupErrorCode.passwordResetSent.message
        } catch {
            if let supabaseError = error as? SupabaseError {
                if case .network = supabaseError {
                    authError = "Check your connection and try again."
                    return
                }
            }
            // Every other failure shows the same generic message as
            // success: the caller must not learn whether the email
            // has an account.
            authInfo = PFSignupErrorCode.passwordResetSent.message
        }
    }

    /// Set a new password for the signed-in session, used after a
    /// password reset link stores a recovery session. The password
    /// must be at least 8 characters, the same rule as signup.
    /// Uses PUT /auth/v1/user with the session token: the recovery
    /// token authorises exactly this update. On success the reset
    /// screen goes away and the learner stays signed in with the
    /// new password. An expired recovery session maps to
    /// RESET_LINK_INVALID through the catalog.
    func updatePassword(newPassword: String) async -> Bool {
        guard newPassword.count >= 8 else {
            authError = PFSignupErrorCode.passwordTooShort.message
            return false
        }
        guard let token = await validAccessToken(),
              let base = SupabaseConfig.authBaseURL,
              let url = URL(string: "\(base)/user") else {
            authError = PFSignupErrorCode.sessionExpired.message
            return false
        }
        authError = nil
        struct UpdatePasswordBody: Encodable {
            let password: String
        }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await client.request(url: url, method: "PUT", body: UpdatePasswordBody(password: newPassword), accessToken: token)
            showPasswordReset = false
            authInfo = "Your password has been changed. Sign in with your new password next time."
            return true
        } catch {
            authError = passwordAuthError(error)
            return false
        }
    }

    /// Dismiss the set-new-password screen without changing the
    /// password. The caller signs out the recovery session: a
    /// recovery session must not linger as full access when the
    /// learner abandons the reset.
    func dismissPasswordReset() {
        showPasswordReset = false
    }

    // MARK: - Pending registration and welcome popup

    /// The guest-namespace key for the registration waiting for its
    /// first sign-in. Guest namespace because the account may not
    /// have a session yet; the email inside is what binds it to the
    /// right account when the session arrives.
    private static let pendingRegistrationBaseKey = "pf.registration.pending.v1"

    /// The per-account flag key for the registration welcome popup.
    /// Written when the popup is first shown, so it appears once,
    /// on the first sign-in after registration, and never again.
    private static let welcomeShownBaseKey = "pf.welcomeShown.v1"

    private static func recordPendingRegistration(email: String, caseID: String) {
        let record = PendingRegistration(email: email, caseID: caseID)
        let key = AccountScopedStorage.key(pendingRegistrationBaseKey, namespace: AccountScopedStorage.guestNamespace)
        if let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func takePendingRegistration() -> PendingRegistration? {
        let key = AccountScopedStorage.key(pendingRegistrationBaseKey, namespace: AccountScopedStorage.guestNamespace)
        guard let data = UserDefaults.standard.data(forKey: key),
              let record = try? JSONDecoder().decode(PendingRegistration.self, from: data) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: key)
        return record
    }

    private static func clearPendingRegistration() {
        let key = AccountScopedStorage.key(pendingRegistrationBaseKey, namespace: AccountScopedStorage.guestNamespace)
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Consume a pending registration for a newly stored session:
    /// store the case ID under this account, and show the welcome
    /// popup once, with the case ID. The pending record is only
    /// honoured when its email matches the session email, so a
    /// case ID can never land on the wrong account; a mismatch
    /// drops the record. The popup flag is written at show time, so
    /// killing the app while the popup is up can never make it
    /// appear again. Called from saveSession, after the namespace
    /// switch and store reload, so the case ID lands in the right
    /// namespace and is visible at once.
    private func consumePendingRegistration(for user: AuthUser) {
        guard let pending = Self.takePendingRegistration() else { return }
        guard let sessionEmail = user.email?.lowercased(), sessionEmail == pending.email.lowercased() else { return }
        Self.storeAccountCaseID(pending.caseID, for: user.id)
        accountCaseID = pending.caseID
        let flagKey = AccountScopedStorage.key(Self.welcomeShownBaseKey, namespace: user.id)
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        UserDefaults.standard.set(true, forKey: flagKey)
        registrationWelcomeCaseID = pending.caseID
        showRegistrationWelcome = true
    }

    /// The per-account key for the stored case ID. Written when a
    /// pending registration is consumed; removed with the account
    /// namespace on deletion.
    private static let accountCaseIDBaseKey = "pf.account.caseID.v1"

    private static func storeAccountCaseID(_ caseID: String, for userID: String) {
        UserDefaults.standard.set(caseID, forKey: AccountScopedStorage.key(accountCaseIDBaseKey, namespace: userID))
    }

    private static func loadAccountCaseID(for userID: String) -> String? {
        UserDefaults.standard.string(forKey: AccountScopedStorage.key(accountCaseIDBaseKey, namespace: userID))
    }

    /// Remove a stale signup draft left by the removed SMS OTP flow
    /// (v75/v76 stored it in the guest namespace). Nothing in v77
    /// writes it; this only clears leftovers on signup and on
    /// account deletion, so no dead signup state survives.
    private static func clearLegacySignupState() {
        let key = AccountScopedStorage.key("pf.signup.draft.v1", namespace: AccountScopedStorage.guestNamespace)
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Dismiss the registration welcome popup. The shown flag was
    /// already written when the popup appeared, so this only clears
    /// the presentation state.
    func dismissRegistrationWelcome() {
        showRegistrationWelcome = false
        registrationWelcomeCaseID = nil
    }

    /// Send a magic sign-in link to the email address instead of a code.
    /// The link opens the app and completes sign-in. Kept as an
    /// alternative to the OTP flow; the UI uses the code by default.
    /// The link returns to the app on the com.paymentforge.app scheme
    /// (see SupabaseConfig): PaymentForgeApp must forward the URL to
    /// handleAuthCallback for the link to complete sign-in.
    func requestMagicLink(email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.contains("@") else {
            authError = PFSignupErrorCode.emailInvalid.message
            return
        }
        guard client.isConfigured else {
            authError = AuthError.notConfigured.errorDescription
            return
        }
        guard let base = SupabaseConfig.authBaseURL,
              let url = URL(string: "\(base)/magiclink") else {
            authError = SupabaseError.invalidURL.errorDescription
            return
        }
        // A fresh attempt clears any error from an earlier one, so a
        // stale message can never survive a later success and surface
        // on the presenting view after sign-in.
        authError = nil
        struct MagicLinkBody: Encodable {
            let email: String
            let redirectTo: String?

            enum CodingKeys: String, CodingKey {
                case email
                case redirectTo = "redirect_to"
            }
        }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await client.request(
                url: url,
                method: "POST",
                body: MagicLinkBody(email: trimmed, redirectTo: SupabaseConfig.authRedirectURL?.absoluteString)
            )
            pendingEmail = trimmed
        } catch {
            authError = friendlyAuthError(error)
        }
    }

    // MARK: - Google sign-in

    /// Sign in with Google through Supabase Auth. Opens the Supabase
    /// authorize URL for the Google provider in a secure web session
    /// (ASWebAuthenticationSession) with PKCE, then exchanges the
    /// returned code for a session. No Google SDK and no custom OAuth
    /// flow: Supabase owns the provider exchange.
    /// Needs the Google provider enabled in the Supabase dashboard
    /// (Authentication > Providers) with a Google Cloud OAuth client,
    /// and the com.paymentforge.app redirect scheme registered (see
    /// SupabaseConfig). Until the provider is enabled the server
    /// returns an error and the message below says so plainly.
    func signInWithGoogle() async {
        guard client.isConfigured else {
            authError = AuthError.notConfigured.errorDescription
            return
        }
        guard let base = SupabaseConfig.authBaseURL,
              let redirectURL = SupabaseConfig.authRedirectURL else {
            authError = SupabaseError.invalidURL.errorDescription
            return
        }
        let verifier = PKCE.randomVerifier()
        let challenge = PKCE.challenge(for: verifier)
        var components = URLComponents(string: "\(base)/authorize")
        components?.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: redirectURL.absoluteString),
            URLQueryItem(name: "flow_type", value: "pkce"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256")
        ]
        guard let authorizeURL = components?.url else {
            authError = SupabaseError.invalidURL.errorDescription
            return
        }
        pendingPKCEVerifier = verifier
        isBusy = true
        defer { isBusy = false }
        let result: Result<URL, Error>
        do {
            result = try await withCheckedThrowingContinuation { continuation in
                let coordinator = OAuthWebSessionCoordinator()
                self.oauthCoordinator = coordinator
                coordinator.start(url: authorizeURL, callbackScheme: SupabaseConfig.authRedirectScheme) { outcome in
                    continuation.resume(returning: outcome)
                }
            }
        } catch {
            pendingPKCEVerifier = nil
            authError = friendlyAuthError(error)
            return
        }
        oauthCoordinator = nil
        switch result {
        case .failure(let error as NSError) where error.code == 1:
            // The user cancelled the web session. That is not an error.
            pendingPKCEVerifier = nil
            return
        case .failure(let error):
            pendingPKCEVerifier = nil
            authError = friendlyAuthError(error)
            return
        case .success(let callbackURL):
            await handleAuthCallback(url: callbackURL)
        }
    }

    /// Complete sign-in from a Supabase Auth callback URL. Call this
    /// from PaymentForgeApp.onOpenURL for every incoming URL; it
    /// returns true only for URLs on the app's auth scheme with the
    /// auth-callback host. Handles both callback shapes Supabase can return: a PKCE
    /// ?code= (Google) and an implicit #access_token=... fragment
    /// (magic link). A fragment with type=recovery (password reset
    /// link) stores the recovery session and raises
    /// showPasswordReset, so the set-new-password screen shows.
    /// Returns false for URLs that are not auth
    /// callbacks, so the caller can route them elsewhere, and never
    /// sets a sign-in error for them: deep links share the scheme.
    @discardableResult
    func handleAuthCallback(url: URL) async -> Bool {
        guard url.scheme == SupabaseConfig.authRedirectScheme,
              url.host == "auth-callback" else {
            return false
        }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let errorDescription = queryItems.first(where: { $0.name == "error_description" })?.value {
            // An expired or invalid reset link must say so in
            // catalog wording, never as raw server text. Other
            // callback errors keep their existing wording.
            let lowered = errorDescription.lowercased()
            if (lowered.contains("expired") || lowered.contains("invalid")) && (lowered.contains("token") || lowered.contains("link") || lowered.contains("otp")) {
                authError = PFSignupErrorCode.resetLinkInvalid.message
            } else {
                authError = errorDescription
            }
            pendingPKCEVerifier = nil
            return true
        }
        if let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty {
            guard let verifier = pendingPKCEVerifier else {
                authError = "Sign-in could not be completed. Please try again."
                return true
            }
            pendingPKCEVerifier = nil
            await exchangePKCECode(code: code, verifier: verifier)
            return true
        }
        if let fragment = url.fragment, !fragment.isEmpty {
            var fragmentItems: [String: String] = [:]
            for pair in fragment.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    fragmentItems[String(parts[0])] = String(parts[1])
                }
            }
            if let accessToken = fragmentItems["access_token"],
               let refreshToken = fragmentItems["refresh_token"] {
                let expiresIn = Int(fragmentItems["expires_in"] ?? "") ?? 3600
                let isRecovery = fragmentItems["type"] == "recovery"
                await storeSession(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
                if isRecovery, currentUser != nil {
                    showPasswordReset = true
                }
                return true
            }
        }
        authError = "Sign-in could not be completed. Please try again."
        return true
    }

    /// Exchange a PKCE authorization code for a Supabase session.
    /// Used by the Google OAuth sign-in, which stores its verifier
    /// before opening the browser. DEPLOY CHECKLIST (v78): a
    /// password reset link opened from Mail in PKCE ?code= form
    /// cannot complete through this path: no verifier was ever
    /// stored for it, so handleAuthCallback stops at the guard
    /// above, and this exchange must NOT raise showPasswordReset
    /// because it is shared with Google sign-in. The working
    /// recovery path is the implicit #access_token fragment with
    /// type=recovery. Which link shape Supabase sends depends on
    /// the project's email-link flow configuration and must be
    /// verified at deploy time before reset links work for
    /// learners.
    private func exchangePKCECode(code: String, verifier: String) async {
        guard let base = SupabaseConfig.authBaseURL,
              let url = URL(string: "\(base)/token?grant_type=pkce") else {
            authError = SupabaseError.invalidURL.errorDescription
            return
        }
        struct PKCEBody: Encodable {
            let authCode: String
            let codeVerifier: String

            enum CodingKeys: String, CodingKey {
                case authCode = "auth_code"
                case codeVerifier = "code_verifier"
            }
        }
        do {
            let data = try await client.request(
                url: url,
                method: "POST",
                body: PKCEBody(authCode: code, codeVerifier: verifier)
            )
            try await storeSession(from: data)
        } catch {
            authError = friendlyAuthError(error)
        }
    }

    // MARK: - Sign out and account deletion

    /// Sign out: tell Supabase, then clear the Keychain session, the
    /// in-memory user and the account's in-memory store state. The
    /// account's stored data is NOT wiped: it stays under its own
    /// namespace and loads again on the next sign-in. What the
    /// learner sees after signing out is the guest namespace, so a
    /// different account signing in next can never see this
    /// account's progress, notes or bookmarks.
    /// Downloaded audio is the one exception, and only in part:
    /// files recorded as downloaded by this account are removed,
    /// because playback of a downloaded file carries no
    /// entitlement re-check and the files would otherwise stay
    /// playable offline by a guest or the next account. Files
    /// downloaded as a guest, files owned by another identity,
    /// and files with no ownership record are kept (see
    /// LessonDownloadStore.removeDownloadsOwned). The account
    /// re-downloads its lessons on tap after the next sign-in.
    func signOut() async {
        isBusy = true
        defer { isBusy = false }
        if let token = storedSession?.accessToken,
           let base = SupabaseConfig.authBaseURL,
           let url = URL(string: "\(base)/logout") {
            _ = try? await client.request(url: url, method: "POST", accessToken: token)
        }
        // Remove only this account's downloaded audio. The user id
        // must be captured before clearSession drops it. Guest
        // downloads and unattributed files are kept.
        if let signingOutUserID = currentUser?.id {
            LessonDownloadStore.shared.removeDownloadsOwned(by: signingOutUserID)
        }
        // Drop account-scoped server entitlements so the next
        // account (or a guest) never inherits them. On-device
        // StoreKit entitlements belong to the Apple ID and are
        // untouched by this call.
        StoreManager.shared.clearAccountEntitlements()
        clearSession()
    }

    /// Delete the account through the delete-account edge function,
    /// which deletes the Supabase Auth user with the service-role key
    /// and lets the database cascade-delete the profile, preferences
    /// and progress rows. The app never deletes only locally and
    /// calls it done: when the function is not deployed yet, or the
    /// call fails, this returns false, the session stays, and the
    /// message says deletion is not available. Deploy first:
    /// supabase functions deploy delete-account, with the
    /// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY secrets set.
    /// After the function confirms, local clearing runs: pending
    /// sync operations are dropped, every UserDefaults key in the
    /// deleted account's namespace is removed, account-scoped
    /// server entitlements are dropped, the session and Keychain
    /// entry are cleared, and every store reloads into the guest
    /// namespace, so no in-memory account data survives and the
    /// next user cannot reach the deleted account's data. Only
    /// then is the completion message shown.
    /// Delete cascade audit (v78): the server side owns the
    /// database cascade (profile row, lesson progress, referral
    /// records); the case ID lives in the GoTrue user_metadata and
    /// is deleted with the Auth user, and no server case table
    /// exists. The current delete-account function relies on the
    /// database cascade, which does not yet cover the proposed
    /// referral tables, and that server gap is owned by the server
    /// worker, not fixed here. App-side, the cascade is complete: the case ID and the referral credit
    /// balance live in the account namespace and are removed with
    /// it, and the guest-namespace pending registration (plus any
    /// stale signup draft left by the removed SMS OTP flow) is
    /// cleared explicitly below (removeAllKeys cannot reach the
    /// guest namespace).
    /// Purchase rows are NOT deleted: retention is pending a
    /// decision, and App Store purchase records are owned by Apple
    /// in any case. StoreManager purchase state is never cleared
    /// here.
    /// Purchase entitlements from the App Store are not touched:
    /// Apple owns those records, not this app.
    func deleteAccount() async -> Bool {
        guard client.isConfigured else {
            authError = AuthError.notConfigured.errorDescription
            return false
        }
        guard let token = storedSession?.accessToken else {
            authError = PFSignupErrorCode.sessionExpired.message
            return false
        }
        guard let deletedUserID = currentUser?.id else {
            authError = SupabaseError.missingAccessToken.errorDescription
            return false
        }
        isBusy = true
        defer { isBusy = false }
        struct EmptyBody: Encodable {}
        do {
            let data = try await client.invokeFunction(name: "delete-account", body: EmptyBody(), accessToken: token)
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard object?["ok"] as? Bool == true else {
                authError = "Account deletion is not available yet. Please try again later."
                return false
            }
        } catch {
            authError = friendlyAuthError(error)
            return false
        }
        // The server confirmed the deletion. Only now is local state
        // cleared: on any failure above, the session stays and
        // nothing is touched.
        SyncService.shared.clearPendingOperations()
        AccountScopedStorage.removeAllKeys(in: deletedUserID)
        // The pending registration lives outside the account
        // namespace (guest namespace), so the removal above does
        // not reach it. Clear it explicitly, plus any stale signup
        // draft left by the removed SMS OTP flow: a deleted
        // account must leave no signup or case state behind on
        // this device.
        Self.clearLegacySignupState()
        Self.clearPendingRegistration()
        // The analytics local log is a file, not a UserDefaults key,
        // so removeAllKeys does not reach it. Delete it while the
        // namespace is still the deleted account's; clearSession
        // below switches to the guest namespace.
        AnalyticsService.shared.deleteLocalLogForCurrentAccount()
        // Remove the deleted account's downloaded audio, same rule
        // as sign-out: only files recorded as this account's go;
        // guest downloads and unattributed files are kept.
        LessonDownloadStore.shared.removeDownloadsOwned(by: deletedUserID)
        StoreManager.shared.clearAccountEntitlements()
        clearSession()
        // clearSession reloads every store into the guest namespace
        // and drops the account's in-memory state. The old
        // resetAll/clearLocal calls are deliberately gone: with
        // namespaced keys they would have wiped guest data instead
        // of the deleted account's data.
        // Purchase records are untouched: Apple owns them, and
        // StoreManager purchase state is never cleared here.
        authInfo = "Your account has been deleted."
        return true
    }

    // MARK: - Email verification and email change

    /// Re-read the signed-in user from Supabase Auth and update the
    /// verification status (and display name) in memory and in the
    /// stored session. Silent on failure: a stale badge is better
    /// than an error for a status refresh.
    func refreshVerificationStatus() async {
        guard let token = await validAccessToken(),
              let base = SupabaseConfig.authBaseURL,
              let url = URL(string: "\(base)/user") else {
            return
        }
        do {
            let data = try await client.request(url: url, method: "GET", accessToken: token)
            let reply = try JSONDecoder().decode(SupabaseUserReply.self, from: data)
            guard let user = currentUser, user.id == reply.id else { return }
            // The edited profile name wins over the provider name:
            // a verification refresh must never put the Gmail name
            // back after the user edited their name.
            let metadataName = reply.userMetadata?.fullName ?? reply.userMetadata?.name
            if let metadataName, !metadataName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                authProviderName = metadataName
            }
            let displayName = profile?.displayName ?? metadataName ?? user.displayName
            let updated = AuthUser(
                id: user.id,
                email: reply.email ?? user.email,
                displayName: displayName,
                isEmailVerified: reply.emailConfirmedAt != nil
            )
            currentUser = updated
            if let session = storedSession {
                let refreshed = StoredSession(
                    accessToken: session.accessToken,
                    refreshToken: session.refreshToken,
                    expiresAt: session.expiresAt,
                    user: updated
                )
                storedSession = refreshed
                if let encoded = try? JSONEncoder().encode(refreshed) {
                    SessionKeychain.save(encoded)
                }
            }
        } catch {
            // Keep the last known status; the next sign-in refreshes it.
        }
    }

    /// Send a fresh verification email to the signed-in user's
    /// address. The link confirms the address; the user stays signed
    /// in either way.
    func resendVerificationEmail() async {
        guard let email = currentUser?.email,
              let base = SupabaseConfig.authBaseURL,
              let url = URL(string: "\(base)/resend") else {
            authError = "You are not signed in. Sign in and try again."
            return
        }
        guard client.isConfigured else {
            authError = AuthError.notConfigured.errorDescription
            return
        }
        struct ResendBody: Encodable {
            let email: String
            let type: String
        }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await client.request(url: url, method: "POST", body: ResendBody(email: email, type: "signup"))
            authInfo = "Verification email sent to \(email). Open the link in it to confirm your email."
        } catch {
            authError = friendlyAuthError(error)
        }
    }

    /// Send a fresh signup confirmation email to an address whose
    /// account was created but not yet confirmed. Unlike
    /// resendVerificationEmail this needs no session: it is the
    /// resume path for an unfinished signup (the learner created
    /// the account, then closed the app before opening the
    /// confirmation link). Returns true when the email was
    /// accepted for sending.
    func resendSignupConfirmation(email: String) async -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.contains("@") else {
            authError = PFSignupErrorCode.emailInvalid.message
            return false
        }
        guard client.isConfigured else {
            authError = AuthError.notConfigured.errorDescription
            return false
        }
        guard let base = SupabaseConfig.authBaseURL,
              let url = URL(string: "\(base)/resend") else {
            authError = SupabaseError.invalidURL.errorDescription
            return false
        }
        authError = nil
        struct ResendSignupBody: Encodable {
            let email: String
            let type: String
        }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await client.request(url: url, method: "POST", body: ResendSignupBody(email: trimmed, type: "signup"))
            authInfo = PFSignupErrorCode.emailConfirmationResent.message
            return true
        } catch {
            authError = friendlyAuthError(error)
            return false
        }
    }

    // MARK: - Profile

    /// Fetch the profile row for the signed-in user, if one exists.
    func fetchProfile() async {
        guard let user = currentUser else { return }
        guard let token = await validAccessToken() else { return }
        do {
            let data = try await client.restGet(
                table: "profiles",
                query: "select=*&id=eq.\(user.id)",
                accessToken: token
            )
            let rows = try client.decodeRows(data, as: UserProfile.self)
            profile = rows.first
            syncDisplayNameFromProfile()
        } catch {
            // A missing profile is normal for a new account. Do not
            // surface it as an error.
        }
    }

    /// Create or update the profile row for the signed-in user.
    func saveProfile(_ updated: UserProfile) async -> Bool {
        guard let user = currentUser else { return false }
        guard let token = await validAccessToken() else { return false }
        var row = updated
        row.id = user.id
        row.email = row.email ?? user.email
        row.updatedAt = ISO8601DateFormatter().string(from: Date())
        do {
            _ = try await client.restUpsert(table: "profiles", rows: [row], onConflict: "id", accessToken: token)
            profile = row
            syncDisplayNameFromProfile()
            return true
        } catch {
            authError = friendlyAuthError(error)
            return false
        }
    }

    /// Make currentUser.displayName match the effective name: the
    /// edited profile name when one exists, otherwise the sign-in
    /// provider name. Called after the profile is loaded or saved,
    /// so every place that reads currentUser.displayName (Home
    /// greeting, avatar, certificates) shows the edited name
    /// instead of the Gmail name. The updated name is persisted in
    /// the stored session so it survives an app restart.
    private func syncDisplayNameFromProfile() {
        guard let user = currentUser else { return }
        let effective = profile?.displayName ?? authProviderName
        let trimmed = effective?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name = trimmed, !name.isEmpty else { return }
        guard name != user.displayName else { return }
        let updated = AuthUser(
            id: user.id,
            email: user.email,
            displayName: name,
            isEmailVerified: user.isEmailVerified
        )
        currentUser = updated
        if let session = storedSession {
            let refreshed = StoredSession(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                expiresAt: session.expiresAt,
                user: updated
            )
            storedSession = refreshed
            if let encoded = try? JSONEncoder().encode(refreshed) {
                SessionKeychain.save(encoded)
            }
        }
    }

    // MARK: - Session handling

    /// A valid access token, refreshing it first when it is expired or
    /// about to expire. Returns nil when there is no session.
    func validAccessToken() async -> String? {
        guard let session = storedSession else { return nil }
        if session.expiresAt > Date().addingTimeInterval(60) {
            return session.accessToken
        }
        return await refreshSession()
    }

    /// Refresh the session with the stored refresh token.
    @discardableResult
    func refreshSession() async -> String? {
        guard let session = storedSession,
              let base = SupabaseConfig.authBaseURL,
              let url = URL(string: "\(base)/token?grant_type=refresh_token") else {
            return nil
        }
        struct RefreshBody: Encodable {
            let refreshToken: String
            enum CodingKeys: String, CodingKey {
                case refreshToken = "refresh_token"
            }
        }
        do {
            let data = try await client.request(url: url, method: "POST", body: RefreshBody(refreshToken: session.refreshToken))
            try await storeSession(from: data)
            return storedSession?.accessToken
        } catch {
            // A failed refresh means the session is dead. Clear it so
            // the app falls back to guest instead of retrying forever.
            clearSession()
            return nil
        }
    }

    private func restoreSession() {
        guard let data = SessionKeychain.load(),
              let session = try? JSONDecoder().decode(StoredSession.self, from: data) else {
            return
        }
        storedSession = session
        AccountScopedStorage.setCurrentNamespace(session.user.id)
        reloadAllStores()
        accountCaseID = Self.loadAccountCaseID(for: session.user.id)
        currentUser = session.user
        // No migration offer on a launch restore: the offer belongs
        // to a fresh sign-in, not to every app launch.
        if session.expiresAt <= Date() {
            Task { await refreshSession() }
        } else {
            Task {
                await fetchProfile()
                await refreshVerificationStatus()
            }
        }
    }

    private func storeSession(from data: Data) async throws {
        // An empty body is not a session: fail here with a decoding
        // error instead of storing anything, so a malformed reply
        // surfaces as a sign-in error, never as a half-established
        // session.
        guard !data.isEmpty else {
            throw SupabaseError.decoding(underlying: DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Empty session reply.")))
        }
        let decoder = JSONDecoder()
        let reply: SupabaseSessionReply
        do {
            reply = try decoder.decode(SupabaseSessionReply.self, from: data)
        } catch {
            throw SupabaseError.decoding(underlying: error)
        }
        // A session that is already expired is a malformed reply:
        // storing it would bounce the learner straight back to guest
        // through a failed refresh. Fail verification instead.
        guard reply.expiresIn > 0 else {
            throw SupabaseError.decoding(underlying: DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Session expiry must be positive.")))
        }
        // The edited profile name wins over the provider name, even
        // on sign-in and token refresh. The provider name is kept as
        // the fallback for a user who has never set a name.
        let metadataName = reply.user.userMetadata?.fullName ?? reply.user.userMetadata?.name
        if let metadataName, !metadataName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            authProviderName = metadataName
        }
        let profileName = (profile?.id == reply.user.id) ? profile?.displayName : nil
        let displayName = profileName ?? metadataName
        let user = AuthUser(
            id: reply.user.id,
            email: reply.user.email,
            displayName: displayName,
            isEmailVerified: reply.user.emailConfirmedAt != nil
        )
        await saveSession(
            accessToken: reply.accessToken,
            refreshToken: reply.refreshToken,
            expiresIn: reply.expiresIn,
            user: user
        )
    }

    /// Store a session from raw tokens (implicit-flow callbacks carry
    /// tokens but no user object), fetching the user record first so
    /// the stored session always has a real user.
    private func storeSession(accessToken: String, refreshToken: String, expiresIn: Int) async {
        guard let base = SupabaseConfig.authBaseURL,
              let url = URL(string: "\(base)/user") else {
            authError = SupabaseError.invalidURL.errorDescription
            return
        }
        do {
            let data = try await client.request(url: url, method: "GET", accessToken: accessToken)
            let reply = try JSONDecoder().decode(SupabaseUserReply.self, from: data)
            // The edited profile name wins over the provider name,
            // even on an implicit-flow sign-in. The provider name is
            // kept as the fallback for a user who has never set one.
            let metadataName = reply.userMetadata?.fullName ?? reply.userMetadata?.name
            if let metadataName, !metadataName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                authProviderName = metadataName
            }
            let profileName = (profile?.id == reply.id) ? profile?.displayName : nil
            let user = AuthUser(
                id: reply.id,
                email: reply.email,
                displayName: profileName ?? metadataName,
                isEmailVerified: reply.emailConfirmedAt != nil
            )
            await saveSession(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn, user: user)
        } catch {
            authError = friendlyAuthError(error)
        }
    }

    private func saveSession(accessToken: String, refreshToken: String, expiresIn: Int, user: AuthUser) async {
        let session = StoredSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            user: user
        )
        storedSession = session
        // A stale profile from a different account must never be
        // shown under the new account, even briefly.
        if profile?.id != user.id {
            profile = nil
        }
        if let encoded = try? JSONEncoder().encode(session) {
            SessionKeychain.save(encoded)
        }
        // Switch namespaces and reload stores BEFORE currentUser is
        // set, so the migration offer is already decided when views
        // observe the sign-in, and no view can read the new account
        // through the previous account's store state.
        AccountScopedStorage.setCurrentNamespace(user.id)
        reloadAllStores()
        accountCaseID = Self.loadAccountCaseID(for: user.id)
        consumePendingRegistration(for: user)
        evaluateGuestMigrationOffer(for: user.id)
        currentUser = user
        await fetchProfile()
        // Sync the account's progress in the background. It never
        // blocks sign-in and never overwrites server data. Guest
        // progress is NOT synced here: it lives in the guest
        // namespace until the learner accepts the migration offer,
        // which copies it into this namespace and syncs then.
        Task { await SyncService.shared.syncAfterSignIn() }
        // Refresh server entitlements for the new account and record
        // on-device purchases against it. Every sign-in path funnels
        // through here (email OTP, Apple, Google PKCE, magic link
        // and token refresh), so every path is wired.
        Task { await StoreManager.shared.syncEntitlementsAfterSignIn() }
    }

    private func clearSession() {
        storedSession = nil
        currentUser = nil
        profile = nil
        authProviderName = nil
        pendingEmail = nil
        authInfo = nil
        pendingPKCEVerifier = nil
        oauthCoordinator = nil
        offersGuestMigration = false
        showRegistrationWelcome = false
        registrationWelcomeCaseID = nil
        accountCaseID = nil
        showPasswordReset = false
        AccountScopedStorage.setCurrentNamespace(nil)
        SessionKeychain.delete()
        // Every store reloads into the guest namespace, dropping the
        // previous account's in-memory values. This runs on sign-out,
        // deletion and failed refresh alike: no path may leave the
        // previous account's data on screen.
        reloadAllStores()
    }

    // MARK: - Account switching and guest migration

    /// Reload every stateful local store for the current namespace.
    /// LearningPreferences holds no in-memory state (every read goes
    /// through the current namespace), AssessmentSession state lives
    /// in per-view instances, and AudioPlayerService has no shared
    /// instance (each LessonView owns one), so none of those can be
    /// reloaded here; their storage is namespaced all the same.
    private func reloadAllStores() {
        ProgressStore.shared.reloadForCurrentAccount()
        RecentLessonsStore.shared.reloadForCurrentAccount()
        PFBookmarkStore.shared.reloadForCurrentAccount()
        PathBookmarkStore.shared.reloadForCurrentAccount()
        PFCertificateStore.reloadForCurrentAccount()
        FinalAssessmentStore.shared.reloadForCurrentAccount()
        CompetencyStore.shared.reloadForCurrentAccount()
        RevisionService.shared.reloadForCurrentAccount()
        NotesStore.shared.reloadForCurrentAccount()
        PracticeStore.shared.reloadForCurrentAccount()
        SearchService.reloadForCurrentAccount()
        OnboardingStore.shared.reloadForCurrentAccount()
        ActivePathStore.shared.reloadForCurrentAccount()
        ExceptionLabStore.shared.reloadForCurrentAccount()
        StudioDraftStore.shared.reloadForCurrentAccount()
        LearningHabitStore.shared.reloadForCurrentAccount()
        WeeklyFreeCaseStore.shared.reloadForCurrentAccount()
        CommunityChallengeStore.shared.reloadForCurrentAccount()
        AnalyticsService.shared.reloadForCurrentAccount()
        ReferralStore.shared.reloadForCurrentAccount()
    }

    /// The fixed UserDefaults base keys that may move from the guest
    /// namespace into an account namespace. This list must match the
    /// stores' own key definitions; it is duplicated here because
    /// those keys are private to each store. Device-level keys
    /// (appearance, tour) and StoreManager purchase keys are
    /// deliberately absent: they never migrate.
    private static let guestMigrationBaseKeys: [String] = [
        // ProgressStore
        "pf.completedLessons.v1",
        "pf.quizHistory.v1",
        "pf.quizAnswers.v1",
        "pf.checklist.v1",
        "pf.learningEvents.v1",
        "pf.lastLessonID.v1",
        "pf.lastLessonTitle.v1",
        "pf.weeklyGoal.v1",
        "pf.lastSyncedAt.v1",
        "pf.pendingSync.v1",
        // RecentLessonsStore
        "pf.recentLessons.v1",
        // LearningPreferences
        "pf.prefs.experienceLevel.v1",
        "pf.prefs.domainInterests.v1",
        "pf.prefs.includeAudio.v1",
        "pf.prefs.hasSaved.v1",
        // PathBookmarkStore
        "pf.pathBookmarks.v1",
        // PFCertificateStore (fixed key; per-path keys use prefixes)
        "pf.pathCertificatesSynced.v1",
        // FinalAssessmentStore
        "pf.finalAssessment.certificates.v1",
        "pf.finalAssessment.attempts.v1",
        // CompetencyStore, RevisionService, NotesStore, PracticeStore
        "pf.competencyTotals.v1",
        "pf.revisionConcepts.v1",
        "pf.notes.v1",
        "pf.practiceAttempts.v1",
        // SearchService
        "pf.search.recent.v1",
        // AudioPlayerService (fixed keys; positions use prefixes)
        "pf.audio.playbackRate.v1",
        "pf.audio.autoAdvance.v1",
        // PFBookmarkStore
        "pf.bookmarkedLessons.v1",
        "pf.bookmarkedSituations.v1",
        // OnboardingStore and ActivePathStore
        "pf.onboarding.profile.v1",
        "pf.onboarding.completed.v1",
        "pf.activePath.v1",
        // LearningHabitStore (reminder settings only; the schedule
        // is rebuilt from the migrated settings on reload)
        "pf.learningHabit.reminderSettings.v1"
    ]

    /// Base-key prefixes for per-item keys that may migrate the same
    /// way: audio positions, daily challenge records, per-path
    /// certificate dates and ids, and running exam end times.
    private static let guestMigrationBasePrefixes: [String] = [
        "pf.audio.position.v1.",
        "pf.dailyChallenge.",
        "pf.certificateIssuedAt.",
        "pf.certificateID.",
        "pf.finalAssessment.endTime."
    ]

    /// Base key for the once-only migration marker, stored in the
    /// account namespace when the offer is accepted or declined.
    private static let migrationResolvedBaseKey = "pf.migration.guestOfferResolved.v1"

    /// Decide whether to offer guest-to-account migration for a
    /// fresh sign-in. Offered only when the offer was never resolved
    /// for this account and at least one guest key exists whose
    /// account counterpart is empty. Never offered account to
    /// account: the source is always the guest namespace.
    private func evaluateGuestMigrationOffer(for userID: String) {
        guard !hasMigrationResolvedMarker(for: userID) else {
            offersGuestMigration = false
            return
        }
        offersGuestMigration = guestDataAwaitingMigration(to: userID)
    }

    private func guestDataAwaitingMigration(to userID: String) -> Bool {
        let defaults = UserDefaults.standard
        for baseKey in Self.guestMigrationBaseKeys {
            let guestHas = defaults.object(forKey: AccountScopedStorage.key(baseKey, namespace: AccountScopedStorage.guestNamespace)) != nil
            let accountHas = defaults.object(forKey: AccountScopedStorage.key(baseKey, namespace: userID)) != nil
            if guestHas, !accountHas { return true }
        }
        let guestPrefix = AccountScopedStorage.prefix(for: AccountScopedStorage.guestNamespace)
        for fullKey in defaults.dictionaryRepresentation().keys where fullKey.hasPrefix(guestPrefix) {
            let baseKey = String(fullKey.dropFirst(guestPrefix.count))
            guard Self.guestMigrationBasePrefixes.contains(where: { baseKey.hasPrefix($0) }) else { continue }
            if defaults.object(forKey: AccountScopedStorage.key(baseKey, namespace: userID)) == nil {
                return true
            }
        }
        return false
    }

    /// Accept the migration offer: copy guest data into the account
    /// namespace without overwriting anything the account already
    /// has, reload the stores so the moved data shows at once, then
    /// sync and refresh entitlements for the account. Migration
    /// copies, it does not move: the guest copy is left in place,
    /// so signing out still shows the same guest data.
    func acceptGuestMigration() async {
        guard let userID = currentUser?.id else {
            offersGuestMigration = false
            return
        }
        _ = AccountScopedStorage.migrateGuestKeys(Self.guestMigrationBaseKeys, to: userID)
        for prefix in Self.guestMigrationBasePrefixes {
            _ = AccountScopedStorage.migrateGuestKeys(withPrefix: prefix, to: userID)
        }
        markMigrationResolved(for: userID)
        offersGuestMigration = false
        reloadAllStores()
        await SyncService.shared.syncAfterSignIn()
        await StoreManager.shared.syncEntitlementsAfterSignIn()
    }

    /// Decline the migration offer. Guest data stays under the
    /// guest namespace, untouched, and the offer is not made again
    /// for this account. The learner still sees guest data after
    /// signing out; it is never synced to the account.
    func declineGuestMigration() {
        if let userID = currentUser?.id {
            markMigrationResolved(for: userID)
        }
        offersGuestMigration = false
    }

    private func hasMigrationResolvedMarker(for userID: String) -> Bool {
        UserDefaults.standard.bool(forKey: AccountScopedStorage.key(Self.migrationResolvedBaseKey, namespace: userID))
    }

    private func markMigrationResolved(for userID: String) {
        UserDefaults.standard.set(true, forKey: AccountScopedStorage.key(Self.migrationResolvedBaseKey, namespace: userID))
    }
}

// MARK: - Email resend cooldown (bot protection, Phase 1)

/// Client-side throttle on every control that sends an auth email:
/// the email-code send, the confirmation-link resend, and the
/// password-reset send. After each send the control stays disabled
/// for 60 seconds with a countdown, and no more than 5 sends per
/// hour go to one email address. The send record lives in
/// UserDefaults, keyed by a SHA-256 hash of the email address,
/// never the raw address, so the cooldown survives the view being
/// dismissed and recreated. This is a first line of defence only:
/// Supabase Auth enforces its own server-side email rate limits
/// behind it. The generic no-enumeration replies are unchanged.
/// No CAPTCHA: that is Phase 2, after a settings check.
///
/// All published state changes on the main thread: `update` and
/// `recordSend` hop there when called from an async task, so the
/// countdown timer always runs on the main run loop.
final class EmailResendCooldown: ObservableObject {
    /// Which auth email the cooldown applies to. Each kind keeps
    /// its own send record, so a reset send never blocks a code
    /// send to the same address.
    enum Kind: String {
        case confirmation
        case reset
        case emailCode
    }

    /// Seconds a control stays disabled after each send.
    static let cooldownSeconds: TimeInterval = 60
    /// Most sends to one address in any rolling hour.
    static let hourlyLimit = 5
    /// Length of the rolling window, in seconds.
    static let hourSeconds: TimeInterval = 3600
    /// Message shown when the hourly cap is hit. It describes local
    /// send attempts only and never says whether an account exists.
    static let limitMessage = "Too many emails sent. Try again later."

    /// Seconds left on the 60 second cooldown, 0 when none applies.
    @Published private(set) var secondsRemaining: Int = 0
    /// True when the hourly cap blocks another send.
    @Published private(set) var limitReached: Bool = false
    /// False while the cooldown or the hourly cap blocks a send.
    @Published private(set) var canSend: Bool = true

    private let kind: Kind
    private var email: String = ""
    private var timer: Timer?

    init(kind: Kind) {
        self.kind = kind
    }

    deinit {
        // Only the installing thread may invalidate a timer. Off
        // the main thread the timer's own closure invalidates it
        // on its next fire, because self is gone by then.
        if Thread.isMainThread {
            timer?.invalidate()
        }
    }

    /// Point the tracker at an email address and refresh the
    /// published state from its stored send record. Call on appear
    /// and whenever the typed email changes: the cooldown is per
    /// address, so a different address has its own record.
    func update(email: String) {
        let clean = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if Thread.isMainThread {
            self.email = clean
            refresh()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.email = clean
                self?.refresh()
            }
        }
    }

    /// Record one send attempt for the current address. Attempts
    /// count, not just successes: the point is that rapid repeat
    /// taps cannot queue email after email.
    func recordSend() {
        if Thread.isMainThread {
            recordSendOnMain()
        } else {
            DispatchQueue.main.async { [weak self] in self?.recordSendOnMain() }
        }
    }

    private func recordSendOnMain() {
        guard !email.isEmpty else { return }
        var stamps = storedStamps()
        stamps.append(Date().timeIntervalSince1970)
        save(stamps: stamps)
        refresh()
    }

    private func refresh() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refresh() }
            return
        }
        timer?.invalidate()
        timer = nil
        guard email.contains("@") else {
            secondsRemaining = 0
            limitReached = false
            canSend = true
            return
        }
        let now = Date().timeIntervalSince1970
        let stamps = storedStamps().filter { now - $0 < Self.hourSeconds }
        if stamps.count >= Self.hourlyLimit {
            limitReached = true
            canSend = false
            secondsRemaining = 0
            // Re-check once, when the oldest send ages out of the
            // window, instead of ticking for up to an hour.
            if let oldest = stamps.min() {
                let delay = max(1, oldest + Self.hourSeconds - now)
                timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                    self?.refresh()
                }
            }
            return
        }
        limitReached = false
        if let last = stamps.max(), now - last < Self.cooldownSeconds {
            secondsRemaining = Int(ceil(Self.cooldownSeconds - (now - last)))
            canSend = false
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                self.refresh()
            }
        } else {
            secondsRemaining = 0
            canSend = true
        }
    }

    private func storageKey() -> String {
        "pf.resend.\(kind.rawValue).\(Self.emailHash(email))"
    }

    private func storedStamps() -> [TimeInterval] {
        (UserDefaults.standard.array(forKey: storageKey()) as? [Double]) ?? []
    }

    private func save(stamps: [TimeInterval]) {
        let now = Date().timeIntervalSince1970
        let pruned = stamps.filter { now - $0 < Self.hourSeconds }
        UserDefaults.standard.set(pruned, forKey: storageKey())
    }

    private static func emailHash(_ email: String) -> String {
        let digest = SHA256.hash(data: Data("pf-resend:\(email)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
