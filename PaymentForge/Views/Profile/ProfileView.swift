// ProfileView.swift
// PaymentForge iOS - Profile screen, separate from the Dashboard.
// Guests see "Guest" with a Sign in button, and the account-only rows
// stay behind a sign-in prompt. Signed-in users see their name, email,
// verification badge, designation, organisation and years of
// experience, plus real stats from ProgressStore (lessons completed,
// day streak, quizzes taken). Learning time is shown on My Progress
// from recorded durations; this screen shows counts only. Learning
// reminders sit below the stats for both guests and signed-in
// users: reminders are off by default and need explicit opt-in.
// No em dashes in any user-facing text.

import SwiftUI
import PhotosUI

/// The Profile screen. Reachable from the drawer "Profile" row.
struct ProfileView: View {
    @StateObject private var authService = AuthService.shared
    @StateObject private var syncService = SyncService.shared
    @StateObject private var referralStore = ReferralStore.shared
    @ObservedObject private var progressStore = ProgressStore.shared

    @State private var showWelcome = false
    @State private var showEditProfile = false
    @State private var showCheckout = false
    @State private var showAnalyticsConsent = false
    @State private var showSignOutConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showSignedOutAlert = false
    @State private var showDeleteResultAlert = false
    @State private var deleteSucceeded = false
    @State private var deleteResultMessage = ""
    @State private var showResendErrorAlert = false
    @State private var resendErrorMessage = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var avatarImage: UIImage?
    @State private var avatarSignedURL: URL?
    @State private var photoMessage: String?
    @State private var isUploadingPhoto = false
    @State private var refreshMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.xl) {
                    if authService.isSignedIn {
                        signedInHeader
                        statsSection
                        reminderSettingsSection
                        accountSections
                    } else {
                        guestHeader
                        statsSection
                        reminderSettingsSection
                        guestPromptSection
                    }
                }
                .padding(PFSpacing.lg)
            }
            .background(Color.pfBackground)
            // Extra scrollable space at the bottom so the last row clears
            // the tab bar on every iPhone size, matching My Progress.
            .safeAreaInset(edge: .bottom) {
                // Spacing only: never intercept a tap. Color.clear
                // hit tests by default, so this strip could swallow
                // taps near the bottom of the screen.
                Color.clear.frame(height: PFSpacing.xl)
                    .allowsHitTesting(false)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showWelcome) {
                WelcomeView()
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileSheet()
            }
            .sheet(isPresented: $showCheckout) {
                CheckoutView()
            }
            .sheet(isPresented: $showAnalyticsConsent) {
                NavigationStack {
                    AnalyticsConsentView(onDecisionMade: { showAnalyticsConsent = false })
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showAnalyticsConsent = false }
                            }
                        }
                }
            }
            .confirmationDialog(
                "Sign out?",
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    Task {
                        await authService.signOut()
                        // signOut() always clears the session before
                        // returning, so this alert can only show
                        // once the learner is signed out.
                        showSignedOutAlert = true
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your progress is kept under your account. Sign in again any time to pick up where you left off.")
            }
            .alert("Signed out", isPresented: $showSignedOutAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("You are signed out. Your progress is kept under your account. Sign in again any time to pick up where you left off.")
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete my account", role: .destructive) {
                    Task {
                        // deleteAccount() returns true only after
                        // the server confirms and local state is
                        // cleared; on any failure it returns false
                        // and sets authError, with the session kept.
                        // The result alert below is driven by that
                        // return value, never shown speculatively.
                        let deleted = await authService.deleteAccount()
                        deleteSucceeded = deleted
                        deleteResultMessage = deleted
                            ? "Your account has been deleted. You are now learning as a guest."
                            : (authService.authError ?? "Account deletion is not available yet. Please try again later.")
                        showDeleteResultAlert = true
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes your account, your synced learning data, and your referral and case records. It cannot be undone. Purchase records are kept. Purchases from the App Store are not affected.")
            }
            .alert(
                deleteSucceeded ? "Account deleted" : "Account deletion failed",
                isPresented: $showDeleteResultAlert
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(deleteResultMessage)
            }
            .alert("Verification email", isPresented: $showResendErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(resendErrorMessage)
            }
            .onChange(of: selectedPhotoItem) { _, item in
                Task { await uploadPhoto(item) }
            }
        }
    }

    // MARK: - Guest header

    private var guestHeader: some View {
        PFCard {
            VStack(spacing: PFSpacing.md) {
                initialsCircle(initials: "G", size: 84)
                Text("Guest")
                    .font(.pfScreenTitle)
                    .foregroundColor(.pfNavy)
                Text("You are learning as a guest. Your progress stays on this device.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                PFPrimaryButton(title: "Sign in") {
                    showWelcome = true
                }
                Text("Signing in syncs your progress across devices and keeps it safe if you change phones.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Signed-in header

    private var signedInHeader: some View {
        PFCard {
            VStack(spacing: PFSpacing.md) {
                avatarSection
                VStack(spacing: 4) {
                    HStack(spacing: PFSpacing.sm) {
                        Text(displayName)
                            .font(.pfScreenTitle)
                            .foregroundColor(.pfNavy)
                        if let user = authService.currentUser, user.isEmailVerified {
                            Label("Verified", systemImage: "checkmark.seal.fill")
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfSuccess)
                                .labelStyle(.iconOnly)
                                .accessibilityLabel("Email verified")
                        }
                    }
                    if let email = authService.currentUser?.email {
                        Text(email)
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                    }
                    if let user = authService.currentUser, user.isEmailVerified {
                        Text("Email verified")
                            .font(.pfCaption)
                            .foregroundColor(.pfSuccess)
                    } else {
                        Text("Email not verified yet")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                        Button("Resend verification email") {
                            Task {
                                // Clear any stale error first (the
                                // same view-side clear WelcomeView
                                // uses), so a leftover error from an
                                // earlier attempt cannot surface as
                                // this tap's failure. Success is
                                // already shown inline through
                                // authInfo above; only a failure
                                // needs this alert, because authError
                                // is otherwise never shown here.
                                authService.authError = nil
                                await authService.resendVerificationEmail()
                                if let error = authService.authError {
                                    resendErrorMessage = error
                                    showResendErrorAlert = true
                                }
                            }
                        }
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .disabled(authService.isBusy)
                    }
                    if let info = authService.authInfo {
                        Text(info)
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let caseID = authService.accountCaseID {
                    detailRow(label: "Case ID", value: caseID)
                }
                detailRow(label: "Designation", value: authService.profile?.designation)
                detailRow(label: "Organisation", value: authService.profile?.organisation)
                detailRow(label: "Experience", value: experienceText)
                if let message = photoMessage {
                    Text(message)
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var avatarSection: some View {
        Group {
            if let avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 84, height: 84)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.pfGold, lineWidth: 2))
            } else if let avatarSignedURL {
                AsyncImage(url: avatarSignedURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    initialsCircle(initials: authService.currentUser?.initials ?? "?", size: 84)
                }
                .frame(width: 84, height: 84)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.pfGold, lineWidth: 2))
            } else {
                initialsCircle(initials: authService.currentUser?.initials ?? "?", size: 84)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if authService.isSignedIn && SupabaseConfig.isConfigured {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "camera.fill")
                        .font(.pfCaption.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.pfRoyal)
                        .clipShape(Circle())
                        // The visible badge stays 28pt; the tap
                        // area is the full 44pt minimum so the
                        // camera button answers first tap.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isUploadingPhoto)
            }
        }
        .onAppear {
            if !authService.isSignedIn {
                photoMessage = nil
            } else if !SupabaseConfig.isConfigured {
                photoMessage = "Photo upload needs the Supabase project to be set up."
            } else {
                Task { await loadAvatar() }
            }
        }
    }

    /// Resolve the stored avatar to a signed URL for display. The
    /// avatars bucket is private, so the stored path is never a
    /// viewable URL on its own: a fresh signed URL is fetched here
    /// (valid for one hour) and the path stays the stored value.
    private func loadAvatar() async {
        guard let stored = authService.profile?.avatarURL, !stored.isEmpty else { return }
        if let direct = URL(string: stored), direct.scheme == "https" {
            avatarSignedURL = direct
            return
        }
        guard let token = await authService.validAccessToken() else { return }
        let path = stored.hasPrefix("avatars/") ? String(stored.dropFirst("avatars/".count)) : stored
        if let signed = try? await SupabaseClient.shared.storageSignedURL(
            bucket: "avatars",
            path: path,
            expiresIn: 3600,
            accessToken: token
        ) {
            avatarSignedURL = signed
        }
    }

    private func detailRow(label: String, value: String?) -> some View {
        HStack {
            Text(label)
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
            Spacer()
            Text(value ?? "Not set")
                .font(.pfBody)
                .foregroundColor(.pfNavy)
        }
        .frame(maxWidth: .infinity)
    }

    private var displayName: String {
        // Single source of truth: the edited profile name first,
        // the sign-in provider name only as a fallback.
        if let name = authService.displayName {
            return name
        }
        return authService.currentUser?.email?.components(separatedBy: "@").first ?? "Learner"
    }

    private var experienceText: String? {
        guard let years = authService.profile?.yearsExperience else { return nil }
        return years == 1 ? "1 year" : "\(years) years"
    }

    private func initialsCircle(initials: String, size: CGFloat) -> some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Color.pfRoyal)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.pfGold, lineWidth: 2))
    }

    // MARK: - Stats (real ProgressStore data only)

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Your progress")
            HStack(spacing: PFSpacing.sm) {
                statCard(
                    value: "\(progressStore.totalLessonsCompleted)",
                    label: "Lessons completed",
                    systemImage: "book.fill"
                )
                statCard(
                    value: "\(progressStore.streakCount)",
                    label: "Day streak",
                    systemImage: "flame.fill"
                )
                statCard(
                    value: "\(progressStore.quizScores.count)",
                    label: "Quizzes taken",
                    systemImage: "checkmark.circle.fill"
                )
            }
            if authService.isSignedIn {
                if syncService.isSyncing {
                    Text("Syncing...")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                } else if let lastSynced = progressStore.lastSyncedAt {
                    Text("Last synced \(lastSynced.formatted(date: .abbreviated, time: .shortened))")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                }
                if (syncService.hasPendingSync || progressStore.pendingSync) && !syncService.isSyncing {
                    Text("Sync pending. It will retry in the background.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                }
            }
        }
    }

    private func statCard(value: String, label: String, systemImage: String) -> some View {
        VStack(spacing: PFSpacing.xs) {
            PFIconTile(systemImage: systemImage, size: 40)
            Text(value)
                .font(.pfSectionTitle)
                .foregroundColor(.pfNavy)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PFSpacing.lg)
        .background(Color.pfCard)
        .cornerRadius(PFSpacing.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                .stroke(Color.pfBorder, lineWidth: 1)
        )
        .shadow(color: Color.pfNavy.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    // MARK: - Learning reminders

    /// Reminder settings, for signed-in learners and guests alike:
    /// reminders are device-local and off by default, so guests
    /// can set them too. The settings view owns the card; this
    /// section only adds the header, matching the sections around it.
    private var reminderSettingsSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Learning reminders")
            HabitReminderSettingsView()
        }
    }

    // MARK: - Guest prompt

    private var guestPromptSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Account")
            PFCard {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    Text("Sign in to unlock your profile, synced progress, learning preferences and purchases.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    PFSecondaryButton(title: "Sign in") {
                        showWelcome = true
                    }
                    PFSecondaryButton(title: "Analytics choices") {
                        showAnalyticsConsent = true
                    }
                }
            }
            // Guests get the same Notifications entry as
            // signed-in learners: preferences are device-local
            // per account namespace, and guests can manage
            // them too.
            PFCard {
                NavigationLink(destination: NotificationSettingsView()) {
                    rowLabel(title: "Notifications", subtitle: "Choose which notifications you receive")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Account sections

    private var accountSections: some View {
        VStack(alignment: .leading, spacing: PFSpacing.xl) {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                PFSectionHeader(title: "Account")
                VStack(spacing: 0) {
                    rowButton(title: "Personal Information", subtitle: "Name, designation, organisation and experience") {
                        showEditProfile = true
                    }
                    Divider().padding(.leading, PFSpacing.lg)
                    NavigationLink(destination: LearningPreferencesView()) {
                        rowLabel(title: "Learning Profile", subtitle: "Experience level, interests and weekly goal")
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, PFSpacing.lg)
                    NavigationLink(destination: NotificationSettingsView()) {
                        rowLabel(title: "Notifications", subtitle: "Choose which notifications you receive")
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, PFSpacing.lg)
                    rowButton(title: "Refresh verification status", subtitle: refreshVerificationSubtitle) {
                        Task {
                            await authService.refreshVerificationStatus()
                            if let user = authService.currentUser {
                                refreshMessage = user.isEmailVerified
                                    ? "Session refreshed. Your email is verified."
                                    : "Session refreshed. Check your email to verify it."
                            } else {
                                refreshMessage = "Not signed in. Nothing to refresh."
                            }
                            // Clear the confirmation after a few seconds so
                            // the row returns to its normal subtitle.
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            refreshMessage = nil
                        }
                    }
                    if let refreshMessage {
                        Text(refreshMessage)
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfRoyal)
                            .padding(.horizontal, PFSpacing.lg)
                            .padding(.bottom, PFSpacing.sm)
                    }
                    Divider().padding(.leading, PFSpacing.lg)
                    rowButton(title: "Purchases and Subscriptions", subtitle: "Payment Situations, enrolment and payment") {
                        showCheckout = true
                    }
                    #if DEBUG
                    Divider().padding(.leading, PFSpacing.lg)
                    NavigationLink(destination: AdminContentView()) {
                        rowLabel(title: "Content management", subtitle: "Local content registry: versions, publication status and access")
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    #endif
                }
                .background(Color.pfCard)
                .cornerRadius(PFSpacing.cardRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                        .stroke(Color.pfBorder, lineWidth: 1)
                )
            }

            VStack(alignment: .leading, spacing: PFSpacing.md) {
                PFSectionHeader(title: "Referrals")
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        HStack {
                            Text("Your referral code")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                            Spacer()
                            Text(referralStore.referralCode ?? "Not available")
                                .font(.pfBody.weight(.semibold))
                                .foregroundColor(.pfNavy)
                        }
                        HStack {
                            Text("Referral credits")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                            Spacer()
                            Text("\(referralStore.creditBalance)")
                                .font(.pfBody.weight(.semibold))
                                .foregroundColor(.pfNavy)
                        }
                        Text("Referral credits are confirmed on the website.")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let code = referralStore.referralCode, !code.isEmpty {
                            ShareLink(item: referralStore.shareText, subject: Text("My Payments Training Hub referral code")) {
                                Text("Share your code")
                                    .font(.pfBody.weight(.semibold))
                                    .foregroundColor(.pfRoyal)
                            }
                            .buttonStyle(.plain)
                        }
                        Text("Referral discounts can only be redeemed on the website. In-app purchases use Apple In-App Purchase, which cannot apply an external discount.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: PFSpacing.md) {
                PFSectionHeader(title: "Privacy and Data")
                VStack(spacing: 0) {
                    ShareLink(item: exportPersonalDataText(), subject: Text("My Payments Training Hub data")) {
                        rowLabel(title: "Export my learning data", subtitle: "Your account, progress and preferences as JSON data")
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, PFSpacing.lg)
                    Link(destination: SupabaseConfig.privacyPolicyURL) {
                        rowLabel(title: "Privacy Policy", subtitle: "How your data is used")
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, PFSpacing.lg)
                    Button {
                        showAnalyticsConsent = true
                    } label: {
                        rowLabel(title: "Analytics choices", subtitle: "Choose whether anonymous learning counts are shared")
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, PFSpacing.lg)
                    Link(destination: SupabaseConfig.termsURL) {
                        rowLabel(title: "Terms of Use", subtitle: "The terms for using Payments Training Hub")
                    }
                    .buttonStyle(.plain)
                }
                .background(Color.pfCard)
                .cornerRadius(PFSpacing.cardRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                        .stroke(Color.pfBorder, lineWidth: 1)
                )
            }

            VStack(spacing: PFSpacing.md) {
                PFSecondaryButton(title: "Sign Out") {
                    showSignOutConfirmation = true
                }
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Text("Delete Account")
                        .font(.pfBody.weight(.semibold))
                        .foregroundColor(.pfError)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The subtitle for the "Refresh verification status" row:
    /// it says what the row does and the current state honestly.
    /// When nobody is signed in it says so, never "Signed in".
    private var refreshVerificationSubtitle: String {
        if let user = authService.currentUser {
            return user.isEmailVerified ? "Signed in, email verified. Tap to refresh your session and verification status." : "Signed in, email not verified yet. Tap to refresh your verification status."
        }
        return "Not signed in. Sign in to check your verification status."
    }

    /// One tappable row label, shared by every row control in the
    /// Account and Privacy sections (row buttons, navigation links,
    /// ShareLink, Link and plain buttons). The content shape makes
    /// the WHOLE row tappable: without it SwiftUI hit testing only
    /// reaches the text and chevron glyphs, so a tap on the empty
    /// middle of a row, on the Spacer or on the padding fell
    /// through to the card background and did nothing, which read
    /// as taps being ignored. Every row now responds first tap.
    private func rowLabel(title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.pfCaption.weight(.semibold))
                .foregroundColor(.pfSecondaryText)
        }
        .padding(PFSpacing.lg)
        .contentShape(Rectangle())
    }

    private func rowButton(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowLabel(title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Photo upload

    private func uploadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let userID = authService.currentUser?.id else { return }
        guard SupabaseConfig.isConfigured else {
            photoMessage = "Photo upload needs the Supabase project to be set up."
            return
        }
        guard let token = await authService.validAccessToken() else { return }
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            photoMessage = "That photo could not be read. Try another one."
            return
        }
        let compressed = image.jpegData(compressionQuality: 0.8) ?? data
        do {
            let path = try await SupabaseClient.shared.storageUpload(
                bucket: "avatars",
                path: "\(userID)/avatar.jpg",
                data: compressed,
                contentType: "image/jpeg",
                accessToken: token
            )
            avatarImage = image
            var updated = authService.profile ?? UserProfile(
                id: userID,
                fullName: nil,
                email: authService.currentUser?.email,
                designation: nil,
                organisation: nil,
                yearsExperience: nil,
                avatarURL: nil,
                createdAt: nil,
                updatedAt: nil
            )
            updated.avatarURL = path
            _ = await authService.saveProfile(updated)
            avatarSignedURL = nil
            await loadAvatar()
            photoMessage = "Photo saved."
        } catch {
            photoMessage = "Photo upload failed. Check your connection and try again."
        }
    }

    // MARK: - Data export

    /// The user's own learning data as a JSON file, for export and for
    /// account deletion requests. Built only from this user's data.
    /// This is the complete machine-readable export (account, profile,
    /// full progress history, preferences). The short readable backup
    /// lives on My Progress; the two serve different purposes and both
    /// are kept.
    private func exportPersonalDataText() -> String {
        var export: [String: Any] = [:]
        if let user = authService.currentUser {
            export["user_id"] = user.id
            export["email"] = user.email ?? ""
            export["email_verified"] = user.isEmailVerified
            export["case_id"] = authService.accountCaseID ?? ""
            export["referral_code"] = referralStore.referralCode ?? ""
        }
        if let profile = authService.profile,
           let profileData = try? JSONEncoder().encode(profile),
           let profileObject = try? JSONSerialization.jsonObject(with: profileData) {
            export["profile"] = profileObject
        }
        export["progress"] = progressStore.exportProgressDictionary()
        let prefs = LearningPreferences.loadLocal()
        if let prefsData = try? JSONEncoder().encode(prefs),
           let prefsObject = try? JSONSerialization.jsonObject(with: prefsData) {
            export["preferences"] = prefsObject
        }
        export["exported_at"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return progressStore.backupText()
        }
        return text
    }
}

// MARK: - Edit profile sheet

/// Edit name, designation, organisation and years of experience.
/// Saved to the profiles table when signed in. The sign-in email is
/// the account identity and is shown read-only; it can never be
/// changed from the app.
private struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authService = AuthService.shared

    @State private var fullName = ""
    @State private var designation = ""
    @State private var organisation = ""
    @State private var yearsExperience = 0
    @State private var didLoad = false
    @State private var saveMessage: String?
    @State private var showSavedAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Full name", text: $fullName)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                    HStack {
                        Text("Email")
                        Spacer()
                        Text(authService.currentUser?.email ?? "")
                            .foregroundColor(.pfSecondaryText)
                    }
                    TextField("Designation", text: $designation)
                        .autocorrectionDisabled()
                    TextField("Organisation", text: $organisation)
                        .autocorrectionDisabled()
                    Stepper(value: $yearsExperience, in: 0...50) {
                        Text("Experience: \(yearsExperience == 0 ? "Not set" : "\(yearsExperience) years")")
                    }
                } header: {
                    Text("Personal Information")
                } footer: {
                    Text("Leave experience at Not set if you would rather not say. Your sign-in email is shown above and cannot be changed here. These details are only used to personalise your learning.")
                }
                if let saveMessage {
                    Section {
                        Text(saveMessage)
                            .foregroundColor(.pfSuccess)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.pfBackground)
            .navigationTitle("Personal Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                }
            }
            .onAppear {
                if !didLoad {
                    fullName = authService.profile?.fullName ?? authService.currentUser?.displayName ?? ""
                    designation = authService.profile?.designation ?? ""
                    organisation = authService.profile?.organisation ?? ""
                    yearsExperience = authService.profile?.yearsExperience ?? 0
                    didLoad = true
                }
            }
            .alert("Profile saved", isPresented: $showSavedAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your profile details have been saved.")
            }
        }
    }

    private func save() async {
        guard let user = authService.currentUser else { return }
        let profile = UserProfile(
            id: user.id,
            fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : fullName,
            email: user.email,
            designation: designation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : designation,
            organisation: organisation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : organisation,
            yearsExperience: yearsExperience == 0 ? nil : yearsExperience,
            avatarURL: authService.profile?.avatarURL,
            createdAt: authService.profile?.createdAt,
            updatedAt: nil
        )
        let ok = await authService.saveProfile(profile)
        if ok {
            saveMessage = authService.authInfo ?? "Saved."
            // Show the saved confirmation first; the sheet
            // dismisses when the learner taps OK in the alert,
            // so the confirmation is never skipped by the dismiss.
            showSavedAlert = true
        } else {
            saveMessage = authService.authError ?? "Could not save. Please try again."
        }
    }
}
