// RegistrationWelcomePopup.swift
// Payments Training Hub iOS - The congratulations popup shown once, on the
// first sign-in right after registration completes (credentials
// set, terms accepted, signed in). It dismisses itself after about
// 3 seconds, and a tap dismisses it sooner. AuthService owns the
// once-only rule: the popup is only ever presented when the
// pf.welcomeShown.v1 flag for the account is unset, and the flag is
// written when the popup is first shown, so it can never appear on
// a later login, even if the app is killed while it is showing.
// Content: congratulations and welcome to Payments Training Hub,
// the case ID for future reference, and the next step (finish
// profile when the profile is incomplete, otherwise browse
// courses).
// No em dashes in any user-facing text.

import SwiftUI

/// The auto-dismissing registration welcome popup.
struct RegistrationWelcomePopup: View {
    /// The signup case ID, in PF-XXXXXX form.
    let caseID: String
    /// True when the profile is incomplete, so the next step points
    /// at finishing the profile instead of browsing courses.
    let profileIncomplete: Bool
    /// Called exactly once, when the popup goes away for any reason.
    let onDismiss: () -> Void

    @State private var dismissed = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(alignment: .leading, spacing: PFSpacing.md) {
                HStack(spacing: PFSpacing.sm) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.pfSectionTitle)
                        .foregroundColor(.pfSuccess)
                    Text("Congratulations!")
                        .font(.pfSectionTitle.weight(.bold))
                        .foregroundColor(.pfNavy)
                }
                Text("Welcome to Payments Training Hub.")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your case ID is \(caseID). Keep it for future reference.")
                    .font(.pfBody)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(profileIncomplete ? "Next step: finish your profile." : "Next step: browse courses.")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.pfRoyal)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Tap to continue.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
            }
            .padding(PFSpacing.xl)
            .frame(maxWidth: 340, alignment: .leading)
            .background(Color.pfCard)
            .cornerRadius(PFSpacing.cardRadius)
            .shadow(color: Color.black.opacity(0.25), radius: 20, x: 0, y: 8)
            .padding(PFSpacing.xl)
            .onTapGesture { dismiss() }
        }
        .task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            dismiss()
        }
    }

    private func dismiss() {
        guard !dismissed else { return }
        dismissed = true
        onDismiss()
    }
}
