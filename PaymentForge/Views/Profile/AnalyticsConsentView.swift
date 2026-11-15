// AnalyticsConsentView.swift
// Payments Training Hub iOS - Analytics opt-in consent.
//
// UNCOMPILED: written on a Linux VM with no Xcode. Statically checked
// only. Do not present this view as compiled or tested until it has
// been built in Xcode and checked on a device.
//
// A standalone consent screen. The coordinator wires presentation:
// present it inside a NavigationStack (as a sheet, following the
// PracticeSheetView pattern, or pushed from ProfileView under the
// Privacy and Data section). This view is stackless and owns no
// NavigationStack, so it stays correct in either presentation. It
// does not dismiss itself after a decision: the state on screen
// updates in place, and onDecisionMade is called so the presenter
// can react, for example by dismissing a sheet. A sheet presenter
// must supply its own Done control.
//
// The copy states exactly what AnalyticsService records and what it
// never records. If the catalogue changes, this copy must change
// with it, or the consent is no longer informed.
//
// No em dashes in any user-facing text.

import SwiftUI

/// The analytics consent screen: what is shared, what is never
/// shared, how sharing works, and the controls to opt in, decline,
/// or withdraw. The choice is per account: the guest and each
/// signed-in account decide separately.
struct AnalyticsConsentView: View {
    /// Called after the learner grants, declines, or withdraws.
    /// The presenter may use it to dismiss a sheet. Nil by default,
    /// so the view also works pushed on a navigation stack.
    var onDecisionMade: (() -> Void)? = nil

    @ObservedObject private var analytics = AnalyticsService.shared

    /// Confirmation before stopping sharing (it deletes the stored
    /// usage data), and confirmation after every decision: the
    /// presenter closes the sheet through onDecisionMade, so the
    /// choice is confirmed in the alert first and onDecisionMade
    /// runs only when the learner taps OK, never before the
    /// decision has been recorded.
    @State private var showWithdrawConfirmation = false
    @State private var showDecisionAlert = false
    @State private var decisionMessage = ""

    /// True when nobody is signed in, so the copy can say the
    /// choice applies to guest learning on this device.
    private var isGuest: Bool {
        AccountScopedStorage.currentNamespace == AccountScopedStorage.guestNamespace
    }

    private var sharedItems: [String] {
        [
            "Which lessons are opened and completed, as counts and lesson names, never your notes or answers.",
            "Quiz and assessment scores as numbers, so we can see whether scores improve over time.",
            "Which features are used: learning paths, the Daily Challenge, practice exercises, and searches with no results. Search words are never recorded.",
            "Purchase funnel counts: paywall views, purchases, restores, and failures. No payment details are recorded.",
            "Error counts: failed lesson loads, audio failures, and sync failures, so faults get fixed.",
        ]
    }

    private var neverSharedItems: [String] {
        [
            "Your name, email, or any account details.",
            "Question, answer, or note text.",
            "Your search words.",
            "Payment details or transaction identifiers.",
            "Your precise location or any device identifier.",
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                headerSection
                statusSection
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        Text("What is shared")
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                        ForEach(sharedItems, id: \.self) { item in
                            ConsentDetailRow(systemImage: "checkmark.circle.fill", tint: .pfSuccess, text: item)
                        }
                    }
                }
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        Text("What is never shared")
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                        ForEach(neverSharedItems, id: \.self) { item in
                            ConsentDetailRow(systemImage: "xmark.circle.fill", tint: .pfError, text: item)
                        }
                    }
                }
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        Text("How sharing works")
                            .font(.pfSectionTitle)
                            .foregroundColor(.pfNavy)
                        Text("Sharing is off unless you turn it on. Nothing is recorded before you opt in, and nothing recorded earlier is sent later.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Usage data stays on this device. No analytics service is connected, so nothing is sent anywhere today.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(isGuest
                            ? "This choice applies to guest learning on this device. If you sign in later, that account is asked separately."
                            : "This choice applies to the account you are signed in with. It does not change the choice for guest learning or for any other account.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("You can stop sharing any time on this screen. Stopping deletes the usage data stored on this device for this account.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                decisionSection
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .navigationTitle("Usage Data")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Stop sharing usage data?",
            isPresented: $showWithdrawConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop sharing", role: .destructive) {
                analytics.withdrawConsent()
                decisionMessage = "Sharing is off. Recording has stopped and the stored usage data for this account has been deleted from this device."
                showDecisionAlert = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Recording stops at once and the stored usage data for this account is deleted from this device. It cannot be undone.")
        }
        .alert("Usage data", isPresented: $showDecisionAlert) {
            Button("OK") { onDecisionMade?() }
        } message: {
            Text(decisionMessage)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text("Help improve Payments Training Hub")
                .font(.pfScreenTitle)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("You can choose to share anonymous usage data. It helps us see which lessons help learners most and where the app needs work.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusSection: some View {
        Group {
            if analytics.isConsented {
                PFPill(
                    text: "Sharing on",
                    background: Color.pfSuccess.opacity(0.12),
                    foreground: .pfSuccess
                )
            } else if analytics.hasMadeConsentDecision {
                PFPill(
                    text: "Sharing off",
                    background: Color.pfNavy.opacity(0.08),
                    foreground: .pfNavy
                )
            } else {
                PFPill(
                    text: "Not decided yet",
                    background: Color.pfGoldSoft,
                    foreground: Color.pfGoldText
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(analytics.isConsented
            ? "Usage data sharing is on"
            : analytics.hasMadeConsentDecision
                ? "Usage data sharing is off"
                : "Usage data sharing is not decided yet")
    }

    private var decisionSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            if analytics.isConsented {
                Text("You are sharing anonymous usage data. Stop sharing any time: recording stops at once and the stored usage data for this account is deleted from this device.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showWithdrawConfirmation = true
                } label: {
                    Text("Stop sharing")
                        .font(.pfBody).fontWeight(.semibold)
                        .foregroundColor(.pfError)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.pfError.opacity(0.08))
                        .cornerRadius(PFSpacing.cornerRadius)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop sharing usage data")
                .accessibilityHint("Stops recording and deletes stored usage data for this account.")
            } else {
                PFPrimaryButton(title: "Share anonymous usage data") {
                    analytics.grantConsent()
                    decisionMessage = "Sharing is on. Anonymous usage data will be recorded on this device."
                    showDecisionAlert = true
                }
                PFSecondaryButton(title: "Not now") {
                    analytics.declineConsent()
                    decisionMessage = "Sharing stays off. Nothing will be recorded."
                    showDecisionAlert = true
                }
                Text("You can change your mind any time on this screen.")
                    .font(.pfCaption)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One line in the shared / never-shared lists: an icon plus the
/// statement, read as a single element by VoiceOver.
private struct ConsentDetailRow: View {
    let systemImage: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: PFSpacing.sm) {
            Image(systemName: systemImage)
                .foregroundColor(tint)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(text)
                .font(.pfBody)
                .foregroundColor(.pfNavy)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
