// EmailAuthView.swift
// Payments Training Hub iOS - Email sign-in, two ways: an 8-digit code sent
// by Supabase Auth, or email and password. The code path has two
// steps: enter the email, then enter the code. A magic link is also
// available from AuthService, but the code is the default because
// it works inside the app without leaving it. The password path
// signs in with signInWithPassword and carries the "Forgot
// password?" link, which opens the email password reset flow. When
// password sign-in fails, the guidance message offers the next
// actions as buttons (resend the confirmation email, use a code,
// reset the password), because the server returns one generic
// error for a wrong password, an unconfirmed account, and an
// account with no password.
// No em dashes in any user-facing text.

import SwiftUI

/// Email sign-in, by code or by password. Dismisses itself once
/// sign-in completes.
struct EmailAuthView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authService = AuthService.shared
    @StateObject private var resendCooldown = EmailResendCooldown(kind: .emailCode)
    /// The cooldown for the "resend confirmation email" action in
    /// the password section: a separate kind, so a code send never
    /// blocks a confirmation resend to the same address.
    @StateObject private var confirmationCooldown = EmailResendCooldown(kind: .confirmation)

    private enum Step {
        case enterEmail
        case enterCode
    }

    private enum AuthMode {
        case code
        case password
    }

    @State private var step: Step = .enterEmail
    @State private var mode: AuthMode = .code
    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var infoMessage: String?
    @State private var showMigrationOffer = false
    @State private var showForgotPassword = false
    /// True once the learner has tapped a primary button: inline
    /// validation errors then show under each invalid field and
    /// update live as the learner types. False on a fresh form,
    /// so nothing nags before the first tap.
    @State private var showValidation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PFSpacing.xl) {
                    brandSection
                    PFCard {
                        VStack(alignment: .leading, spacing: PFSpacing.xl) {
                            headerSection
                            if mode == .code {
                                if step == .enterEmail {
                                    emailSection
                                } else {
                                    codeSection
                                }
                            } else {
                                passwordSection
                            }
                            if let infoMessage {
                                Text(infoMessage)
                                    .font(.pfBody)
                                    .foregroundColor(.pfSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let error = authService.authError {
                                Text(error)
                                    .font(.pfBody)
                                    .foregroundColor(.pfError)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(PFSpacing.xl)
                .frame(maxWidth: 400)
                .frame(maxWidth: .infinity)
            }
            .background(Color.pfBackground)
            .navigationTitle("Continue with Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordView(initialEmail: email)
            }
            .onChange(of: authService.isSignedIn) { _, signedIn in
                // When a guest-to-account migration is offered, stay
                // open so the offer alert can be answered; both of
                // its buttons dismiss this view.
                if signedIn, !authService.offersGuestMigration {
                    dismiss()
                }
            }
            .onChange(of: authService.offersGuestMigration) { _, offered in
                if offered {
                    showMigrationOffer = true
                }
            }
            .alert(
                "Move your guest progress to your account?",
                isPresented: $showMigrationOffer
            ) {
                Button("Move my progress") {
                    Task {
                        await authService.acceptGuestMigration()
                        dismiss()
                    }
                }
                Button("Not now", role: .cancel) {
                    authService.declineGuestMigration()
                    dismiss()
                }
            } message: {
                Text("You learned as a guest on this device. Move that progress, notes and bookmarks to your account? Anything already in your account is kept, and nothing is overwritten.")
            }
            .onAppear {
                if let pending = authService.pendingEmail {
                    email = pending
                }
                resendCooldown.update(email: email)
                confirmationCooldown.update(email: email)
            }
            .onChange(of: email) { _, newValue in
                resendCooldown.update(email: newValue)
                confirmationCooldown.update(email: newValue)
            }
        }
    }

    /// Send a sign-in code, first send or resend, behind the resend
    /// cooldown: 60 seconds between sends, 5 sends per hour per
    /// address. The cap message is shown instead of sending.
    private func sendCode(isResend: Bool) async {
        // The button stays tappable while the email is invalid, so
        // tapping it surfaces the inline error instead of doing
        // nothing. The cooldown still gates sends, with the
        // countdown in the button title and the cap message below.
        showValidation = true
        guard PFFormValidation.isValidEmail(email) else {
            authService.authError = PFSignupErrorCode.emailInvalid.message
            return
        }
        if resendCooldown.limitReached {
            infoMessage = EmailResendCooldown.limitMessage
            return
        }
        guard resendCooldown.canSend else { return }
        await authService.sendEmailOTP(email: email)
        resendCooldown.recordSend()
        if authService.authError == nil {
            if isResend {
                infoMessage = "A new code was sent to \(email.trimmingCharacters(in: .whitespacesAndNewlines)). It expires in 1 hour."
            } else {
                step = .enterCode
                infoMessage = "Code sent to \(email.trimmingCharacters(in: .whitespacesAndNewlines)). It expires in 1 hour."
            }
        }
    }

    private var sendCodeTitle: String {
        if authService.isBusy {
            return "Sending..."
        }
        if resendCooldown.secondsRemaining > 0 {
            return "Send code (\(resendCooldown.secondsRemaining)s)"
        }
        return "Send code"
    }

    private var resendCodeTitle: String {
        if resendCooldown.secondsRemaining > 0 {
            return "Send a new code (\(resendCooldown.secondsRemaining)s)"
        }
        return "Send a new code"
    }

    // MARK: - Header

    /// The wordmark and open-book icon, centred above the card,
    /// with no marketing headline.
    private var brandSection: some View {
        VStack(spacing: PFSpacing.md) {
            Image(systemName: "book.open.fill")
                .font(.system(size: 40))
                .foregroundColor(.pfRoyal)
                .accessibilityHidden(true)
            Text("Payments Training Hub")
                .font(.pfSectionTitle.weight(.bold))
                .foregroundColor(.pfNavy)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, PFSpacing.lg)
    }

    private var headerSection: some View {
        Text(mode == .code
            ? "We send an 8-digit code to your email. Enter it here to sign in or create your account."
            : "Enter your email and password to sign in.")
            .font(.pfBody)
            .foregroundColor(.pfSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Step 1: email

    private var emailSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            Text("Email address")
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
            TextField("you@example.com", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()
            if let error = PFFormValidation.emailError(for: email, attempted: showValidation) {
                Text(error)
                    .font(.pfCaption)
                    .foregroundColor(.pfError)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PFPrimaryButton(title: sendCodeTitle) {
                Task { await sendCode(isResend: false) }
            }
            .disabled(authService.isBusy || !resendCooldown.canSend)
            .opacity(!authService.isBusy && resendCooldown.canSend ? 1 : 0.5)
            if resendCooldown.limitReached {
                Text(EmailResendCooldown.limitMessage)
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("No password to remember. Your account is created the first time you sign in.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Sign in with a password instead") {
                mode = .password
                showValidation = false
                infoMessage = nil
                authService.authError = nil
            }
            .font(.pfBody.weight(.semibold))
            .foregroundColor(.pfRoyal)
            .buttonStyle(.plain)
        }
    }

    // MARK: - Step 2: code

    private var codeSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            Text("Enter the 8-digit code")
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
            TextField("12345678", text: $code)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .autocapitalization(.none)
                .autocorrectionDisabled()
            if let error = PFFormValidation.codeError(for: code, attempted: showValidation) {
                Text(error)
                    .font(.pfCaption)
                    .foregroundColor(.pfError)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PFPrimaryButton(title: authService.isBusy ? "Checking..." : "Verify and sign in") {
                Task {
                    showValidation = true
                    guard PFOTPCode.isValid(code) else {
                        authService.authError = PFFormValidation.codeError(for: code, attempted: true)
                        return
                    }
                    let ok = await authService.verifyEmailOTP(email: email, code: code)
                    if ok {
                        if authService.offersGuestMigration {
                            infoMessage = "Signed in. Choose whether to move your guest progress to your account."
                        } else {
                            infoMessage = "Signed in. Your guest progress is being synced to your account."
                        }
                    }
                }
            }
            .disabled(authService.isBusy)
            .opacity(authService.isBusy ? 0.5 : 1)
            Button {
                Task { await sendCode(isResend: true) }
            } label: {
                Text(resendCodeTitle)
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.pfRoyal)
            }
            .buttonStyle(.plain)
            .disabled(authService.isBusy || !resendCooldown.canSend)
            if resendCooldown.limitReached {
                Text(EmailResendCooldown.limitMessage)
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Use a different email") {
                step = .enterEmail
                code = ""
                infoMessage = nil
            }
            .font(.pfBody.weight(.semibold))
            .foregroundColor(.pfRoyal)
            .buttonStyle(.plain)
        }
    }

    // MARK: - Password sign-in

    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            Text("Email address")
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
            TextField("you@example.com", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()
            if let error = PFFormValidation.emailError(for: email, attempted: showValidation) {
                Text(error)
                    .font(.pfCaption)
                    .foregroundColor(.pfError)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Password")
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
            SecureField("Your password", text: $password)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .autocapitalization(.none)
                .autocorrectionDisabled()
            if showValidation && password.isEmpty {
                Text("Enter your password.")
                    .font(.pfCaption)
                    .foregroundColor(.pfError)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PFPrimaryButton(title: authService.isBusy ? "Signing in..." : "Sign in") {
                Task {
                    showValidation = true
                    guard PFFormValidation.isValidEmail(email) else {
                        authService.authError = PFSignupErrorCode.emailInvalid.message
                        return
                    }
                    guard !password.isEmpty else {
                        authService.authError = "Enter your password."
                        return
                    }
                    let ok = await authService.signInWithPassword(email: email, password: password)
                    if ok {
                        if authService.offersGuestMigration {
                            infoMessage = "Signed in. Choose whether to move your guest progress to your account."
                        } else {
                            infoMessage = "Signed in. Your guest progress is being synced to your account."
                        }
                    }
                }
            }
            .disabled(authService.isBusy)
            .opacity(authService.isBusy ? 0.5 : 1)
            if authService.authError == PFSignupErrorCode.credentialsInvalid.message {
                // The server cannot tell a wrong password from an
                // unconfirmed account, so the guidance message
                // names three next actions: this is the resend one.
                // The other two (emailed code, forgot password)
                // are the buttons below. Cooldown-gated like every
                // control that sends an auth email.
                Button {
                    Task { await resendConfirmationFromPassword() }
                } label: {
                    Text(resendConfirmationTitle)
                        .font(.pfBody.weight(.semibold))
                        .foregroundColor(.pfRoyal)
                }
                .buttonStyle(.plain)
                .disabled(authService.isBusy || !confirmationCooldown.canSend)
                if confirmationCooldown.limitReached {
                    Text(EmailResendCooldown.limitMessage)
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button("Forgot password?") {
                showForgotPassword = true
            }
            .font(.pfBody.weight(.semibold))
            .foregroundColor(.pfRoyal)
            .buttonStyle(.plain)
            Button("Use an email code instead") {
                mode = .code
                step = .enterEmail
                password = ""
                showValidation = false
                infoMessage = nil
                authService.authError = nil
            }
            .font(.pfBody.weight(.semibold))
            .foregroundColor(.pfRoyal)
            .buttonStyle(.plain)
        }
    }

    // MARK: - Resend confirmation from password sign-in

    private var resendConfirmationTitle: String {
        if confirmationCooldown.secondsRemaining > 0 {
            return "Resend confirmation email (\(confirmationCooldown.secondsRemaining)s)"
        }
        return "Resend confirmation email"
    }

    private func resendConfirmationFromPassword() async {
        if confirmationCooldown.limitReached {
            infoMessage = EmailResendCooldown.limitMessage
            return
        }
        guard confirmationCooldown.canSend else { return }
        let ok = await authService.resendSignupConfirmation(email: email)
        confirmationCooldown.recordSend()
        if ok {
            infoMessage = "If that email address has an unfinished signup, a confirmation email is on its way. Open the link in it or enter the code, then sign in."
        }
    }
}
