// AuthService.swift
// PaymentForge iOS - Sign in with Apple, email OTP / magic link,
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
// so Info.plist must register that scheme and PaymentForgeApp must
// forward the URL to handleAuthCallback (see SupabaseConfig). Until
// that wiring exists, Google and magic links cannot complete; email
// OTP, the default, is unaffected.
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
            authError = "Enter a valid email address."
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
        guard client.isConfigured else {
            authError = AuthError.notConfigured.errorDescription
            return false
        }
        guard let base = SupabaseConfig.authBaseURL,
              let url = URL(string: "\(base)/verify") else {
            authError = SupabaseError.invalidURL.errorDescription
            return false
        }
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
            authError = "That code did not work. Check the code and try again."
            return false
        }
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
            authError = "Enter a valid email address."
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
    /// returns true only for URLs on the app's auth scheme.
    /// Handles both callback shapes Supabase can return: a PKCE
    /// ?code= (Google) and an implicit #access_token=... fragment
    /// (magic link). Returns false for URLs that are not auth
    /// callbacks, so the caller can route them elsewhere.
    @discardableResult
    func handleAuthCallback(url: URL) async -> Bool {
        guard url.scheme == SupabaseConfig.authRedirectScheme else {
            return false
        }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let errorDescription = queryItems.first(where: { $0.name == "error_description" })?.value {
            authError = errorDescription
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
                await storeSession(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
                return true
            }
        }
        authError = "Sign-in could not be completed. Please try again."
        return true
    }

    /// Exchange a PKCE authorization code for a Supabase session.
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

    /// Sign out: tell Supabase, then clear the Keychain session and the
    /// in-memory user. Local guest progress is kept: signing out must
    /// never wipe what the learner did on this device.
    func signOut() async {
        isBusy = true
        defer { isBusy = false }
        if let token = storedSession?.accessToken,
           let base = SupabaseConfig.authBaseURL,
           let url = URL(string: "\(base)/logout") {
            _ = try? await client.request(url: url, method: "POST", accessToken: token)
        }
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
    /// Purchase entitlements from the App Store are not touched:
    /// Apple owns those records, not this app.
    func deleteAccount() async -> Bool {
        guard client.isConfigured else {
            authError = AuthError.notConfigured.errorDescription
            return false
        }
        guard let token = storedSession?.accessToken else {
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
        clearSession()
        ProgressStore.shared.resetAll()
        LearningPreferences.clearLocal()
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
        currentUser = session.user
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
        let decoder = JSONDecoder()
        let reply: SupabaseSessionReply
        do {
            reply = try decoder.decode(SupabaseSessionReply.self, from: data)
        } catch {
            throw SupabaseError.decoding(underlying: error)
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
        currentUser = user
        if let encoded = try? JSONEncoder().encode(session) {
            SessionKeychain.save(encoded)
        }
        await fetchProfile()
        // Migrate guest progress into the new account in the background.
        // It never blocks sign-in and never overwrites server data.
        Task { await SyncService.shared.syncAfterSignIn() }
    }

    private func clearSession() {
        storedSession = nil
        currentUser = nil
        profile = nil
        authProviderName = nil
        pendingEmail = nil
        authInfo = nil
        pendingPKCEVerifier = nil
        SessionKeychain.delete()
    }
}
