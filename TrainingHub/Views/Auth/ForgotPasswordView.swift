// ForgotPasswordView.swift
// Payments Training Hub iOS - Email password reset, the only password
// recovery path. ForgotPasswordView requests a reset email for an
// account email address; the link in the email opens the app on
// the auth callback, AuthService stores the recovery session and
// raises showPasswordReset, and TrainingHubApp presents
// ResetPasswordView to set the new password (at least 8
// characters, the same rule as signup). No SMS, no codes, no new
// backend endpoint: the Supabase Auth recover endpoint and the
// user update endpoint, the same patterns the rest of AuthService
// uses. Success and error states use the error catalog: an
// unknown email gets the same generic message as a valid one, so
// the flow never reveals whether an account exists.
// DEPLOY CHECKLIST: Supabase Auth email delivery (custom SMTP,
// recovery template, redirect URL) must be verified before reset
// emails reach learners; the built-in sender does not deliver to
// learners.
// No em dashes in any user-facing text.

import SwiftUI

/// Request a password reset email. The reply message is the same
/// for a valid email and an unknown one.
struct ForgotPasswordView: View {
    /// The email to prefill, when the caller already knows it.
    var initialEmail: String = ""

    @Environment(\.dismiss) private var dismiss
    @StateObject private var authService = AuthService.shared
    @StateObject private var resendCooldown = EmailResendCooldown(kind: .reset)

    @State private var email = ""
    @State private var infoMessage: String?
    @State private var didPrefill = false
    /// True once the learner has tapped Send reset email: the
    /// inline email error then shows and updates live as the
    /// learner types. False on a fresh form, so nothing nags
    /// before the first tap.
    @State private var showValidation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.xl) {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("Forgot your password?")
                            .font(.pfScreenTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Enter the email address for your account. We send a reset link to set a new password.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                        PFPrimaryButton(title: resetButtonTitle) {
                            Task { await sendResetEmail() }
                        }
                        .disabled(authService.isBusy || !resendCooldown.canSend)
                        .opacity(!authService.isBusy && resendCooldown.canSend ? 1 : 0.5)
                        if resendCooldown.limitReached {
                            Text(EmailResendCooldown.limitMessage)
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
                .padding(PFSpacing.xl)
            }
            .background(Color.pfBackground)
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if !didPrefill {
                    didPrefill = true
                    if !initialEmail.isEmpty {
                        email = initialEmail
                    } else if let pending = authService.pendingEmail {
                        email = pending
                    }
                }
                resendCooldown.update(email: email)
            }
            .onChange(of: email) { _, newValue in
                resendCooldown.update(email: newValue)
            }
        }
    }

    private var resetButtonTitle: String {
        if authService.isBusy {
            return "Sending..."
        }
        if resendCooldown.secondsRemaining > 0 {
            return "Send reset email (\(resendCooldown.secondsRemaining)s)"
        }
        return "Send reset email"
    }

    private func sendResetEmail() async {
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
        infoMessage = nil
        await authService.requestPasswordReset(email: email)
        resendCooldown.recordSend()
        if authService.authError == nil, let info = authService.authInfo {
            infoMessage = info
        }
    }
}

/// Set a new password after opening a password reset link.
/// Presented by TrainingHubApp while AuthService.showPasswordReset
/// is true. Cancelling signs out the recovery session, so it
/// cannot linger as full access; the learner requests a new reset
/// email to try again.
struct ResetPasswordView: View {
    @StateObject private var authService = AuthService.shared

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var localError: String?
    /// True once the learner has tapped Set new password: inline
    /// errors then show under each invalid field and update live
    /// as the learner types. False on a fresh form, so nothing
    /// nags before the first tap.
    @State private var showValidation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.xl) {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("Set a new password")
                            .font(.pfScreenTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Choose a new password for your account. It must be at least 8 characters.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        Text("New password")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                        SecureField("At least 8 characters", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.newPassword)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                        if let error = PFFormValidation.passwordError(for: password, attempted: showValidation) {
                            Text(error)
                                .font(.pfCaption)
                                .foregroundColor(.pfError)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Confirm new password")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                        SecureField("Repeat your new password", text: $confirmPassword)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.newPassword)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                        if let error = PFFormValidation.confirmPasswordError(password: password, confirmPassword: confirmPassword, attempted: showValidation) {
                            Text(error)
                                .font(.pfCaption)
                                .foregroundColor(.pfError)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        PFPrimaryButton(title: authService.isBusy ? "Saving..." : "Set new password") {
                            Task { await savePassword() }
                        }
                        .disabled(authService.isBusy)
                        .opacity(authService.isBusy ? 0.5 : 1)
                    }
                    if let localError {
                        Text(localError)
                            .font(.pfBody)
                            .foregroundColor(.pfError)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let error = authService.authError {
                        Text(error)
                            .font(.pfBody)
                            .foregroundColor(.pfError)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if authService.authError == PFSignupErrorCode.resetLinkInvalid.message {
                        Text("Request a new reset email from the sign-in screen.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(PFSpacing.xl)
            }
            .background(Color.pfBackground)
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Task {
                            authService.dismissPasswordReset()
                            await authService.signOut()
                        }
                    }
                }
            }
        }
    }

    private func savePassword() async {
        localError = nil
        // The button stays tappable while the passwords are
        // invalid, so tapping it surfaces the inline errors
        // instead of doing nothing.
        showValidation = true
        guard password.count >= 8 else {
            localError = PFSignupErrorCode.passwordTooShort.message
            return
        }
        guard password == confirmPassword else {
            localError = PFSignupErrorCode.passwordMismatch.message
            return
        }
        _ = await authService.updatePassword(newPassword: password)
    }
}
