// EmailAuthView.swift
// PaymentForge iOS - Email sign-in with a 6-digit code (OTP) sent by
// Supabase Auth. Two steps: enter the email, then enter the code.
// A magic link is also available from AuthService, but the code is the
// default because it works inside the app without leaving it.
// No em dashes in any user-facing text.

import SwiftUI

/// Email OTP sign-in. Dismisses itself once the code verifies.
struct EmailAuthView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authService = AuthService.shared

    private enum Step {
        case enterEmail
        case enterCode
    }

    @State private var step: Step = .enterEmail
    @State private var email = ""
    @State private var code = ""
    @State private var infoMessage: String?

    private var canSendCode: Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).contains("@")
    }

    private var canVerify: Bool {
        code.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.xl) {
                    headerSection
                    if step == .enterEmail {
                        emailSection
                    } else {
                        codeSection
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
            .navigationTitle("Continue with Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: authService.isSignedIn) { _, signedIn in
                if signedIn {
                    dismiss()
                }
            }
            .onAppear {
                if let pending = authService.pendingEmail {
                    email = pending
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text("Sign in with your email")
                .font(.pfScreenTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
            Text("We send a 6-digit code to your email. Enter it here to sign in or create your account.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            PFPrimaryButton(title: authService.isBusy ? "Sending..." : "Send code") {
                Task {
                    await authService.sendEmailOTP(email: email)
                    if authService.authError == nil {
                        step = .enterCode
                        infoMessage = "Code sent to \(email.trimmingCharacters(in: .whitespacesAndNewlines)). It is valid for a short time."
                    }
                }
            }
            .disabled(!canSendCode || authService.isBusy)
            .opacity(canSendCode && !authService.isBusy ? 1 : 0.5)
            Text("No password to remember. Your account is created the first time you sign in.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Step 2: code

    private var codeSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            Text("Enter the 6-digit code")
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
            TextField("123456", text: $code)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .autocapitalization(.none)
                .autocorrectionDisabled()
            PFPrimaryButton(title: authService.isBusy ? "Checking..." : "Verify and sign in") {
                Task {
                    let ok = await authService.verifyEmailOTP(email: email, code: code)
                    if ok {
                        infoMessage = "Signed in. Your guest progress is being synced to your account."
                    }
                }
            }
            .disabled(!canVerify || authService.isBusy)
            .opacity(canVerify && !authService.isBusy ? 1 : 0.5)
            Button {
                Task {
                    await authService.sendEmailOTP(email: email)
                    if authService.authError == nil {
                        infoMessage = "A new code was sent to \(email.trimmingCharacters(in: .whitespacesAndNewlines))."
                    }
                }
            } label: {
                Text("Send a new code")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.pfRoyal)
            }
            .buttonStyle(.plain)
            .disabled(authService.isBusy)
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
}
