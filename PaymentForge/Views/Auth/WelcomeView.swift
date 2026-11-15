// WelcomeView.swift
// Payments Training Hub iOS - Sign-in screen. A standalone screen, reachable
// from Profile or the drawer "Sign in" row. It is NEVER a launch gate:
// the app opens straight into the guest experience, and this screen
// only appears when the learner asks to sign in.
// No em dashes in any user-facing text.

import SwiftUI
import AuthenticationServices

/// The welcome and sign-in screen. Guest is the default: "Explore as
/// Guest" dismisses straight back to the main app.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authService = AuthService.shared

    @State private var showEmailAuth = false
    @State private var showEmailSignup = false
    @State private var showMigrationOffer = false

    /// One alert for every auth failure, driven by authError itself.
    private var errorAlertBinding: Binding<Bool> {
        Binding(
            // Never present a sign-in error alert once signed in: a
            // stale error from an earlier failed attempt must not
            // surface on this view while it dismisses after success.
            get: { authService.authError != nil && !authService.isSignedIn },
            set: { isPresented in
                if !isPresented { authService.authError = nil }
            }
        )
    }

    var body: some View {
        ZStack {
            Color.pfHeroGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.xl) {
                    brandSection
                    headingSection
                    buttonsSection
                    legalSection
                }
                .padding(PFSpacing.xl)
            }
        }
        .sheet(isPresented: $showEmailAuth) {
            EmailAuthView()
        }
        .sheet(isPresented: $showEmailSignup) {
            EmailSignupView()
        }
        .alert("Sign-in", isPresented: errorAlertBinding) {
            Button("Continue as guest") { dismiss() }
            Button("OK", role: .cancel) { }
        } message: {
            Text(authService.authError ?? "Something went wrong. Please try again.")
        }
        .onChange(of: authService.isSignedIn) { _, signedIn in
            // When a guest-to-account migration is offered, stay
            // open so the offer alert can be answered; both of
            // its buttons dismiss this view. When the email or
            // signup sheet is up, dismissal waits for it to close
            // first (see the sheet changes below), so the sheets
            // never dismiss in the same update.
            if signedIn, !authService.offersGuestMigration, !showEmailAuth, !showEmailSignup {
                dismiss()
            }
        }
        .onChange(of: authService.offersGuestMigration) { _, offered in
            // The email and signup sheets present their own copy of
            // this offer; only show it here for direct Apple/Google
            // sign-ins. When an offer resolves while this view is
            // showing a signed-in user, dismiss: sign-in is
            // complete. A sheet closing is what dismisses this view
            // for email and signup sign-ins, never this branch
            // while one is up.
            if offered, !showEmailAuth, !showEmailSignup {
                showMigrationOffer = true
            } else if !offered, authService.isSignedIn, !showEmailAuth, !showEmailSignup {
                dismiss()
            }
        }
        .onChange(of: showEmailAuth) { _, isPresented in
            // The email sheet just closed. When sign-in completed
            // through it and no migration offer is outstanding,
            // this view's job is done: dismiss now, after the
            // child sheet has gone, never at the same time.
            if !isPresented, authService.isSignedIn, !authService.offersGuestMigration {
                dismiss()
            }
        }
        .onChange(of: showEmailSignup) { _, isPresented in
            // The signup sheet just closed. Same rule as the email
            // sheet: dismiss only after the child sheet has gone.
            if !isPresented, authService.isSignedIn, !authService.offersGuestMigration {
                dismiss()
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
    }

    // MARK: - Brand

    private var brandSection: some View {
        HStack(spacing: PFSpacing.md) {
            Text("PF")
                .font(.pfSectionTitle.weight(.bold))
                .foregroundColor(.pfNavy)
                .frame(width: 48, height: 48)
                .background(Color.pfGold)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text("Payments Training Hub")
                .font(.pfSectionTitle.weight(.bold))
                .foregroundColor(.white)
        }
        .padding(.top, PFSpacing.xxl)
    }

    // MARK: - Heading

    private var headingSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            Text("Master Banking and Payments")
                .font(.pfHeroTitle)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("Learn real-world concepts, processes and scenarios from across the payments ecosystem")
                .font(.pfBody)
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Buttons

    private var buttonsSection: some View {
        VStack(spacing: PFSpacing.md) {
            SignInWithAppleButton(.signIn, onRequest: { request in
                authService.prepareAppleRequest(request)
            }, onCompletion: { result in
                Task { await authService.completeAppleSignIn(with: result) }
            })
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .cornerRadius(PFSpacing.cornerRadius)
            .disabled(authService.isBusy)
            .opacity(authService.isBusy ? 0.6 : 1)

            Button {
                Task { await authService.signInWithGoogle() }
            } label: {
                HStack(spacing: 10) {
                    Text("G")
                        .font(.pfBody.weight(.bold))
                        .foregroundColor(.pfRoyal)
                    Text("Continue with Google")
                        .font(.pfBody.weight(.semibold))
                        .foregroundColor(.pfNavy)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white)
                .cornerRadius(PFSpacing.cornerRadius)
            }
            .buttonStyle(.plain)
            .disabled(authService.isBusy)

            Button {
                if authService.canSignIn {
                    showEmailAuth = true
                } else {
                    authService.authError = "Sign-in is not set up yet. You can keep learning as a guest, and your progress stays on this device."
                }
            } label: {
                Label("Continue with Email", systemImage: "envelope.fill")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.pfNavy)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .cornerRadius(PFSpacing.cornerRadius)
            }
            .buttonStyle(.plain)
            .disabled(authService.isBusy)

            Button {
                if authService.canSignIn {
                    showEmailSignup = true
                } else {
                    authService.authError = "Sign-in is not set up yet. You can keep learning as a guest, and your progress stays on this device."
                }
            } label: {
                Label("Create account", systemImage: "person.badge.plus")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.pfNavy)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .cornerRadius(PFSpacing.cornerRadius)
            }
            .buttonStyle(.plain)
            .disabled(authService.isBusy)

            Button {
                dismiss()
            } label: {
                Text("Explore as Guest")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.14))
                    .cornerRadius(PFSpacing.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                            .stroke(Color.white.opacity(0.4), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            if authService.isBusy {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }

            Text("No account is needed to learn. Signing in syncs your progress across devices and keeps it safe if you change phones.")
                .font(.pfCaption)
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Legal

    private var legalSection: some View {
        HStack(spacing: PFSpacing.sm) {
            Link("Terms", destination: SupabaseConfig.termsURL)
            Text("and")
                .foregroundColor(.white.opacity(0.75))
            Link("Privacy Policy", destination: SupabaseConfig.privacyPolicyURL)
        }
        .font(.pfCaption)
        .tint(.white)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, PFSpacing.xl)
    }
}
