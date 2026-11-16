// EmailSignupView.swift
// Payments Training Hub iOS - Email signup, the same flow as the website:
// credentials (email and password), terms acceptance, then email
// confirmation. Supabase email confirmation is the only
// verification: no mobile number is collected and no SMS code is
// ever sent. The confirmation email carries both a link and an
// 8-digit code: the confirmation step accepts the code, so the
// learner can finish without leaving the app, and the link still
// works for a learner who opens the email elsewhere. The case ID
// is generated when signup starts, travels in the account
// metadata, and is shown in the welcome popup and on the profile.
// An unfinished signup resumes by opening the confirmation link
// in the email or entering the code, then signing in with email
// and password: no case ID entry is ever needed. A re-signup of
// an email that already has an account is detected from the
// signup reply and shown its own guidance: the first password
// still stands, and nothing implies the password just typed was
// saved. There is no referral code entry here: referral discount
// redemption is website-only, because Apple In-App Purchase
// cannot take an external discount. The registration welcome popup
// shows once, right after the registration completes and the
// learner signs in; AuthService owns that once-only flag. Sign-in
// is the mandatory first step: this screen is reached from the
// sign-in screen when the learner creates an account.
// No em dashes in any user-facing text.

import SwiftUI
import Combine

/// Email account creation. Dismisses itself once sign-in
/// completes (and the welcome popup, when shown, has gone away).
struct EmailSignupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authService = AuthService.shared
    @StateObject private var resendCooldown = EmailResendCooldown(kind: .confirmation)

    private enum Step {
        case credentials
        case emailConfirmation
    }

    @State private var step: Step = .credentials
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var termsAccepted = false
    @State private var signupCaseID: String?
    /// The 8-digit code from the confirmation email, entered on
    /// the confirmation step to finish without leaving the app.
    @State private var confirmationCode = ""
    /// True when the signup reply proved this email already has
    /// an unconfirmed account: the confirmation step then says
    /// the first password still stands, and its Sign in button
    /// opens the sign-in screen instead of retrying the password
    /// just typed, which was never saved.
    @State private var isUnconfirmedDuplicate = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var isBusy = false
    @State private var showMigrationOffer = false
    @State private var showEmailAuth = false
    /// True once the learner has tapped Create account: inline
    /// validation errors then show under each invalid field and
    /// update live as the learner types. False on a fresh form,
    /// so nothing nags before the first tap.
    @State private var showValidation = false

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: PFSpacing.xl) {
                        headerSection
                        switch step {
                        case .credentials:
                            credentialsSection
                        case .emailConfirmation:
                            emailConfirmationSection
                        }
                        if let infoMessage {
                            Text(infoMessage)
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.pfBody)
                                .foregroundColor(.pfError)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if errorMessage == PFSignupErrorCode.emailAlreadyRegistered.message {
                            PFSecondaryButton(title: "Sign in instead") {
                                showEmailAuth = true
                            }
                        }
                        signInRow
                    }
                    .padding(PFSpacing.xl)
                }
                .background(Color.pfBackground)

                if authService.showRegistrationWelcome, !showEmailAuth,
                   let welcomeCaseID = authService.registrationWelcomeCaseID {
                    RegistrationWelcomePopup(
                        caseID: welcomeCaseID,
                        profileIncomplete: isProfileIncomplete,
                        onDismiss: { authService.dismissRegistrationWelcome() }
                    )
                }
            }
            .navigationTitle("Create account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: authService.isSignedIn) { _, signedIn in
                // Stay open while the migration offer or the welcome
                // popup is outstanding; both dismiss this view when
                // answered. Dismissal waits for the child email
                // sheet to close first, as in WelcomeView.
                if signedIn, !authService.offersGuestMigration, !authService.showRegistrationWelcome, !showEmailAuth {
                    dismiss()
                }
            }
            .onChange(of: authService.offersGuestMigration) { _, offered in
                if offered {
                    showMigrationOffer = true
                }
            }
            .onChange(of: authService.showRegistrationWelcome) { _, showing in
                // The welcome popup just went away. When sign-in
                // completed and no migration offer is outstanding,
                // this view's job is done.
                if !showing, authService.isSignedIn, !authService.offersGuestMigration, !showEmailAuth {
                    dismiss()
                }
            }
            .onChange(of: showEmailAuth) { _, isPresented in
                if !isPresented, authService.isSignedIn, !authService.offersGuestMigration, !authService.showRegistrationWelcome {
                    dismiss()
                }
            }
            .onAppear {
                resendCooldown.update(email: email)
            }
            .onChange(of: email) { _, newValue in
                resendCooldown.update(email: newValue)
            }
            .sheet(isPresented: $showEmailAuth) {
                EmailAuthView()
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
        }
    }

    /// True when the signed-in profile has no display name yet, so
    /// the welcome popup points at finishing the profile.
    private var isProfileIncomplete: Bool {
        guard authService.isSignedIn else { return true }
        return authService.displayName == nil
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text("Create your account")
                .font(.pfScreenTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Text("Set your email and password. We send a confirmation email to verify your email address.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Step 1: credentials and terms

    private var credentialsSection: some View {
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
            Text("Confirm password")
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
            SecureField("Repeat your password", text: $confirmPassword)
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
            HStack(alignment: .top, spacing: PFSpacing.sm) {
                Button {
                    termsAccepted.toggle()
                } label: {
                    Image(systemName: termsAccepted ? "checkmark.square.fill" : "square")
                        .font(.pfBody)
                        .foregroundColor(.pfRoyal)
                }
                .buttonStyle(.plain)
                HStack(spacing: 4) {
                    Text("I accept the")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                    Link("Terms", destination: SupabaseConfig.termsURL)
                    Text("and")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                    Link("Privacy Policy", destination: SupabaseConfig.privacyPolicyURL)
                }
                .font(.pfBody)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let error = PFFormValidation.termsError(accepted: termsAccepted, attempted: showValidation) {
                Text(error)
                    .font(.pfCaption)
                    .foregroundColor(.pfError)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PFPrimaryButton(title: isBusy ? "Creating..." : "Create account and sign in") {
                Task { await createAccount() }
            }
            .disabled(isBusy)
            .opacity(isBusy ? 0.5 : 1)
            Text("Have a referral code? Referral discounts are applied on the website. In-app purchases use Apple In-App Purchase, which cannot apply an external discount.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("One account per email address. Your email is verified by a confirmation email.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func createAccount() async {
        guard !isBusy else { return }
        errorMessage = nil
        // The button stays tappable while the form is invalid, so
        // tapping it surfaces the inline errors instead of doing
        // nothing. Guards run in field order, first problem first.
        showValidation = true
        guard PFFormValidation.isValidEmail(email) else {
            errorMessage = PFSignupErrorCode.emailInvalid.message
            return
        }
        guard password.count >= 8 else {
            errorMessage = PFSignupErrorCode.passwordTooShort.message
            return
        }
        guard termsAccepted else {
            errorMessage = PFSignupErrorCode.termsNotAccepted.message
            return
        }
        guard password == confirmPassword else {
            errorMessage = PFSignupErrorCode.passwordMismatch.message
            return
        }
        // The case ID is generated once, at signup start, and reused
        // for retries of this signup, so a retry never invents a
        // second case ID for the same account.
        if signupCaseID == nil {
            signupCaseID = SignupCaseID.generate()
        }
        guard let caseID = signupCaseID else {
            errorMessage = PFSignupErrorCode.unknownError.message
            return
        }
        isBusy = true
        defer { isBusy = false }
        let result = await authService.signUpWithPassword(
            email: email,
            password: password,
            caseID: caseID,
            termsAccepted: termsAccepted
        )
        switch result {
        case .signedIn:
            infoMessage = "Signed in."
        case .needsEmailConfirmation:
            // Account creation sent the confirmation email, so the
            // resend control starts on its cooldown, like the
            // website: the signup send counts as the first send.
            resendCooldown.recordSend()
            infoMessage = nil
            showValidation = false
            step = .emailConfirmation
        case .confirmedDuplicate:
            // The email already has a confirmed account. Stay on
            // the credentials step: the "Sign in instead" button
            // below appears for this message.
            errorMessage = authService.authError ?? PFSignupErrorCode.emailAlreadyRegistered.message
        case .unconfirmedDuplicate:
            // The email already has an account that is not
            // confirmed yet. The re-signup only resent the
            // confirmation; the first password still stands, so
            // the confirmation step says so and never retries the
            // password just typed. The resend control starts on
            // its cooldown: the re-signup send counts as the
            // first send.
            resendCooldown.recordSend()
            isUnconfirmedDuplicate = true
            infoMessage = nil
            errorMessage = nil
            showValidation = false
            step = .emailConfirmation
        case .none:
            errorMessage = authService.authError ?? PFSignupErrorCode.unknownError.message
        }
    }

    // MARK: - Step 2: email confirmation

    private var emailConfirmationSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            Text("Check your email")
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
            if isUnconfirmedDuplicate {
                Text("This email already has an account that is not confirmed yet. A new confirmation email was sent to \(email.trimmingCharacters(in: .whitespacesAndNewlines)). The password you first used is still the one for this account: signing up again did not change it.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Your account is created. Open the confirmation link sent to \(email.trimmingCharacters(in: .whitespacesAndNewlines)), or enter the 8-digit code from that email below, then sign in.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("8-digit code from the email")
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
            TextField("12345678", text: $confirmationCode)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .autocapitalization(.none)
                .autocorrectionDisabled()
            if let error = PFFormValidation.codeError(for: confirmationCode, attempted: showValidation) {
                Text(error)
                    .font(.pfCaption)
                    .foregroundColor(.pfError)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PFPrimaryButton(title: isBusy ? "Checking..." : "Verify code and sign in") {
                Task { await verifyConfirmationCode() }
            }
            .disabled(isBusy)
            .opacity(isBusy ? 0.5 : 1)
            if isUnconfirmedDuplicate {
                // The password just typed was never saved, so this
                // opens the sign-in screen, where the learner
                // signs in with the first password or a code.
                PFSecondaryButton(title: "Sign in") {
                    showEmailAuth = true
                }
            } else {
                PFPrimaryButton(title: isBusy ? "Signing in..." : "Sign in") {
                    Task { await signInAfterConfirmation() }
                }
                .disabled(isBusy)
                .opacity(isBusy ? 0.5 : 1)
            }
            Button {
                Task { await resendConfirmation() }
            } label: {
                Text(resendConfirmationTitle)
            }
            .font(.pfBody.weight(.semibold))
            .foregroundColor(.pfRoyal)
            .buttonStyle(.plain)
            .disabled(isBusy || !resendCooldown.canSend)
            if resendCooldown.limitReached {
                Text(EmailResendCooldown.limitMessage)
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Use a different email") {
                step = .credentials
                isUnconfirmedDuplicate = false
                confirmationCode = ""
                infoMessage = nil
                errorMessage = nil
            }
            .font(.pfBody.weight(.semibold))
            .foregroundColor(.pfRoyal)
            .buttonStyle(.plain)
        }
    }

    /// Verify the 8-digit code from the confirmation email and
    /// sign in at once. The service tries both token types, so a
    /// signup-type code from the confirm-signup email works.
    private func verifyConfirmationCode() async {
        guard !isBusy else { return }
        errorMessage = nil
        showValidation = true
        guard PFOTPCode.isValid(confirmationCode) else {
            errorMessage = PFFormValidation.codeError(for: confirmationCode, attempted: true)
            return
        }
        isBusy = true
        defer { isBusy = false }
        let ok = await authService.verifyEmailOTP(email: email, code: confirmationCode)
        if ok {
            infoMessage = "Signed in."
        } else {
            errorMessage = authService.authError ?? PFSignupErrorCode.unknownError.message
        }
    }

    private func signInAfterConfirmation() async {
        guard !isBusy else { return }
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        let ok = await authService.signInWithPassword(email: email, password: password)
        if ok {
            infoMessage = "Signed in."
        } else {
            errorMessage = authService.authError ?? PFSignupErrorCode.unknownError.message
        }
    }

    private var resendConfirmationTitle: String {
        if resendCooldown.secondsRemaining > 0 {
            return "Resend confirmation email (\(resendCooldown.secondsRemaining)s)"
        }
        return "Resend confirmation email"
    }

    private func resendConfirmation() async {
        guard !isBusy else { return }
        if resendCooldown.limitReached {
            infoMessage = EmailResendCooldown.limitMessage
            return
        }
        guard resendCooldown.canSend else { return }
        errorMessage = nil
        infoMessage = nil
        isBusy = true
        defer { isBusy = false }
        let ok = await authService.resendSignupConfirmation(email: email)
        resendCooldown.recordSend()
        if ok {
            infoMessage = "A new confirmation email was sent. Open the link in it, then sign in."
        } else {
            errorMessage = authService.authError ?? PFSignupErrorCode.unknownError.message
        }
    }

    // MARK: - Sign in row

    private var signInRow: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text("Already have an account?")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
            Button("Sign in with an email code") {
                showEmailAuth = true
            }
            .font(.pfBody.weight(.semibold))
            .foregroundColor(.pfRoyal)
            .buttonStyle(.plain)
            if step == .credentials {
                Button("I already created my account, take me to sign in") {
                    step = .emailConfirmation
                    isUnconfirmedDuplicate = false
                    confirmationCode = ""
                    showValidation = false
                    errorMessage = nil
                    infoMessage = nil
                }
                .font(.pfBody.weight(.semibold))
                .foregroundColor(.pfRoyal)
                .buttonStyle(.plain)
            }
        }
    }
}
