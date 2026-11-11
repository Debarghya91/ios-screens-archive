// ProfileView.swift
// PaymentForge iOS - Profile screen, separate from the Dashboard.
// Guests see "Guest" with a Sign in button, and the account-only rows
// stay behind a sign-in prompt. Signed-in users see their name, email,
// verification badge, designation, organisation and years of
// experience, plus real stats from ProgressStore (lessons completed,
// day streak, quizzes taken). Learning hours are not shown: the app
// tracks no minutes yet, so there is no real number to show, and this
// screen never invents one. The learning_activity table in Supabase is
// ready for session minutes when tracking is added.
// No em dashes in any user-facing text.

import SwiftUI
import PhotosUI

/// The Profile screen. Reachable from the drawer "Profile" row.
struct ProfileView: View {
    @StateObject private var authService = AuthService.shared
    @StateObject private var syncService = SyncService.shared
    @ObservedObject private var progressStore = ProgressStore.shared

    @State private var showWelcome = false
    @State private var showEditProfile = false
    @State private var showCheckout = false
    @State private var showSignOutConfirmation = false
    @State private var showDeleteConfirmation = false
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
                        accountSections
                    } else {
                        guestHeader
                        statsSection
                        guestPromptSection
                    }
                }
                .padding(PFSpacing.lg)
            }
            .background(Color.pfBackground)
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
            .confirmationDialog(
                "Sign out?",
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    Task { await authService.signOut() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your progress stays on this device. Sign in again any time to sync it back to your account.")
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete my account", role: .destructive) {
                    Task { await authService.deleteAccount() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes your account and your synced learning data. It cannot be undone. Purchases from the App Store are not affected.")
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
                            Task { await authService.resendVerificationEmail() }
                        }
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfRoyal)
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
                }
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
                        rowLabel(title: "Learning Profile", subtitle: "Experience level, interests and weekly target")
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, PFSpacing.lg)
                    rowButton(title: "My Account and Security", subtitle: accountSecuritySubtitle) {
                        Task {
                            await authService.refreshVerificationStatus()
                            refreshMessage = authService.currentUser?.isEmailVerified == true
                                ? "Session refreshed. Your email is verified."
                                : "Session refreshed. Check your email to verify it."
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
                    Divider().padding(.leading, PFSpacing.lg)
                    NavigationLink(destination: AdminContentView()) {
                        rowLabel(title: "Content management", subtitle: "Local content registry: versions, publication status and access")
                            .contentShape(Rectangle())
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

            VStack(alignment: .leading, spacing: PFSpacing.md) {
                PFSectionHeader(title: "Privacy and Data")
                VStack(spacing: 0) {
                    ShareLink(item: exportPersonalDataText(), subject: Text("My Payments Training Hub data")) {
                        rowLabel(title: "Export my learning data", subtitle: "Download your progress and preferences as a file")
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, PFSpacing.lg)
                    Link(destination: SupabaseConfig.privacyPolicyURL) {
                        rowLabel(title: "Privacy Policy", subtitle: "How your data is used")
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

    private var accountSecuritySubtitle: String {
        if let user = authService.currentUser {
            return user.isEmailVerified ? "Signed in, email verified. Tap to refresh your session and verification status." : "Signed in, email not verified yet. Tap to refresh your verification status."
        }
        return "Signed in. Tap to refresh your session."
    }

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
    private func exportPersonalDataText() -> String {
        var export: [String: Any] = [:]
        if let user = authService.currentUser {
            export["user_id"] = user.id
            export["email"] = user.email ?? ""
            export["email_verified"] = user.isEmailVerified
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
            dismiss()
        } else {
            saveMessage = authService.authError ?? "Could not save. Please try again."
        }
    }
}
