// WelcomeView.swift
// Payments Training Hub iOS - Sign-in screen. The mandatory first
// step: TrainingHubApp shows this screen until a session exists,
// and no content is reachable without signing in. It is also
// reachable from Profile for a signed-out learner.
// Sign in with Apple is NOT offered here yet, deliberately: the
// button cannot work until the owner enrols in the Apple
// Developer Program and adds the Sign in with Apple capability to
// the Xcode target (the project has no entitlements file, and
// free Personal Team provisioning cannot carry the capability).
// The Apple provider is enabled in the Supabase dashboard and the
// exchange code in AuthService (prepareAppleRequest,
// completeAppleSignIn, exchangeAppleToken) is wired and ready, so
// restoring the button is one edit once the capability exists:
// put the SignInWithAppleButton back at the top of cardSection
// and re-add the AuthenticationServices import. Note for later:
// App Store Review Guideline 4.8 requires Apple sign-in alongside
// any third-party sign-in at submission time, so the button must
// return before the app is submitted with Google sign-in.
// No em dashes in any user-facing text.

import SwiftUI

/// The welcome and sign-in screen. There is no guest path: every
/// route into the app goes through a session. When presented as a
/// sheet (Profile), signing in dismisses it; as the launch gate,
/// the dismiss calls are no-ops and the gate itself flips.
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
        ScrollView {
            VStack(spacing: PFSpacing.xl) {
                brandSection
                cardSection
                signupRow
                legalSection
            }
            .padding(PFSpacing.xl)
            .frame(maxWidth: 400)
            .frame(maxWidth: .infinity)
        }
        .background(Color.pfBackground)
        .sheet(isPresented: $showEmailAuth) {
            EmailAuthView()
        }
        .sheet(isPresented: $showEmailSignup) {
            EmailSignupView()
        }
        .alert("Sign-in", isPresented: errorAlertBinding) {
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

    /// The wordmark and open-book icon, centred, with no
    /// marketing headline: the sign-in screen leads with the
    /// brand, the way Instagram and Facebook sign-in screens do.
    private var brandSection: some View {
        VStack(spacing: PFSpacing.md) {
            Image(systemName: "book.open.fill")
                .font(.system(size: 44))
                .foregroundColor(.pfRoyal)
                .accessibilityHidden(true)
            Text("Payments Training Hub")
                .font(.pfSectionTitle.weight(.bold))
                .foregroundColor(.pfNavy)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, PFSpacing.xxl)
    }

    // MARK: - Sign-in card

    /// The single centred card: Google, an "or" divider, then
    /// the email path as the one primary button. Apple sign-in is
    /// absent on purpose (see the file header): the button cannot
    /// work without the Sign in with Apple capability, and no dead
    /// button ships. Every action is unchanged; only the
    /// presentation moved.
    private var cardSection: some View {
        PFCard {
            VStack(spacing: PFSpacing.md) {
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
                    .background(Color.pfCard)
                    .cornerRadius(PFSpacing.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                            .stroke(Color.pfBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(authService.isBusy)

                orDivider

                PFPrimaryButton(title: "Continue with Email") {
                    if authService.canSignIn {
                        showEmailAuth = true
                    } else {
                        authService.authError = "Sign-in is not set up yet. Please try again later."
                    }
                }
                .disabled(authService.isBusy)

                if authService.isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                }

                Text("Sign in to start learning. Your progress syncs across your devices and stays safe if you change phones.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var orDivider: some View {
        HStack(spacing: PFSpacing.md) {
            Rectangle()
                .fill(Color.pfBorder)
                .frame(height: 1)
            Text("or")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
            Rectangle()
                .fill(Color.pfBorder)
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Sign up row

    private var signupRow: some View {
        HStack(spacing: PFSpacing.xs) {
            Text("Don't have an account?")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
            Button("Sign up") {
                if authService.canSignIn {
                    showEmailSignup = true
                } else {
                    authService.authError = "Sign-in is not set up yet. Please try again later."
                }
            }
            .font(.pfBody.weight(.semibold))
            .foregroundColor(.pfRoyal)
            .buttonStyle(.plain)
            .disabled(authService.isBusy)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Legal

    private var legalSection: some View {
        HStack(spacing: PFSpacing.sm) {
            Link("Terms", destination: SupabaseConfig.termsURL)
            Text("and")
                .foregroundColor(.pfSecondaryText)
            Link("Privacy Policy", destination: SupabaseConfig.privacyPolicyURL)
        }
        .font(.pfCaption)
        .tint(.pfRoyal)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, PFSpacing.xl)
    }
}
