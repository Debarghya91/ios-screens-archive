// CertificateView.swift
// Payments Training Hub iOS - Certificates of completion.
// A certificate is issued ONLY when every required lesson of its path
// is complete, checked against ProgressStore. The learner name is the
// signed-in name when available, otherwise "Guest Learner". The overall
// score comes from CompetencyStore and is shown only when an assessment
// has actually been taken, otherwise a dash. The verification URL is
// the address where the certificate can be checked; the server-side
// verification page is live, and this screen says so plainly.
// No em dashes in any user-facing text.

import SwiftUI

struct CertificateView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @ObservedObject private var competencyStore = CompetencyStore.shared
    @StateObject private var authService = AuthService.shared
    let path: LearningPath

    private var learnerName: String {
        if let name = authService.currentUser?.displayName,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        if let name = authService.profile?.displayName {
            return name
        }
        return "Guest Learner"
    }

    private var certificate: PFCertificate? {
        PFCertificateStore.certificate(
            for: path,
            progress: progressStore,
            service: contentService,
            competency: competencyStore,
            learnerName: learnerName
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                if let certificate {
                    // Backfill the server verification copy once per
                    // appearance. Silent on failure; the local
                    // certificate is unaffected. No display change.
                    certificateCard(certificate)
                        .task {
                            await PFCertificateStore.syncCertificateToServer(certificate)
                        }
                    verificationSection(certificate)
                    ShareLink(item: certificate.shareText) {
                        Label("Share certificate", systemImage: "square.and.arrow.up")
                            .font(.pfBody.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.pfRoyal)
                            .cornerRadius(PFSpacing.cornerRadius)
                    }
                    // Shareable achievement card (image, text and
                    // LinkedIn), built only from this earned
                    // certificate's own data.
                    AchievementShareActions(content: .pathCertificate(certificate))
                } else {
                    notEarnedView
                }
            }
            .padding(PFSpacing.lg)
            .id("certificateTop")
        }
        .pfScrollToTopOnAppear("certificateTop")
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle("Certificate")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Earned certificate

    private func certificateCard(_ certificate: PFCertificate) -> some View {
        VStack(spacing: PFSpacing.lg) {
            Image(systemName: "seal.fill")
                .font(.pfHeroTitle.weight(.regular))
                .foregroundColor(.pfGold)
            Text("Certificate of Completion")
                .font(.pfScreenTitle)
                .foregroundColor(.pfNavy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("This certifies that")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
            Text(certificate.learnerName)
                .font(.pfSectionTitle.weight(.bold))
                .foregroundColor(.pfNavy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("has completed the learning path")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
            Text(certificate.pathTitle)
                .font(.pfSectionTitle)
                .foregroundColor(.pfRoyal)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text("Issued")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                    Text(Self.dateFormatter.string(from: certificate.issuedAt))
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: PFSpacing.xs) {
                    Text("Overall score")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                    if let score = certificate.overallScore {
                        Text("\(Int(score.rounded()))%")
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                    } else {
                        Text("-")
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .accessibilityLabel("No assessment taken yet, so no score")
                    }
                }
            }
            Text("Issued by Payments Training Hub")
                .font(.pfCaptionBold)
                .foregroundColor(.pfNavy)
            Text("Certificate ID: \(certificate.id)")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(PFSpacing.xl)
        .background(Color.pfCard)
        .cornerRadius(PFSpacing.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                .stroke(Color.pfGold, lineWidth: 2)
        )
        .shadow(color: Color.pfNavy.opacity(0.10), radius: 16, x: 0, y: 8)
    }

    private func verificationSection(_ certificate: PFCertificate) -> some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.sm) {
                Text("Verification")
                    .font(.pfCardTitle)
                    .foregroundColor(.pfNavy)
                Text("Check this certificate at:")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                Text(certificate.verificationURL.absoluteString)
                    .font(.pfBody)
                    .foregroundColor(.pfRoyal)
                    .fixedSize(horizontal: false, vertical: true)
                if authService.currentUser == nil {
                    Text("This certificate is stored on this device. The website verification copy is only written for signed-in learners.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Anyone can check this certificate at the address above.")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Certificate of Completion. This certifies completion of the named learning path. It is not an accredited qualification.")
                    .font(.pfBody)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Not earned yet

    private var notEarnedView: some View {
        PFCard {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                PFIconTile(systemImage: "seal", size: 48)
                Text("Certificate not earned yet")
                    .font(.pfSectionTitle)
                    .foregroundColor(.pfNavy)
                    .fixedSize(horizontal: false, vertical: true)
                let progress = path.progress(in: progressStore, service: contentService)
                Text("Complete all \(progress.total) lessons in \(path.title) to earn the \(path.certificateTitle ?? "path") certificate. You have completed \(progress.completed) so far.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if progress.total > 0 {
                    PFProgressBar(progress: Double(progress.completed) / Double(progress.total))
                }
                NavigationLink(destination: PathDetailView(path: path)) {
                    Text("Open the path")
                        .font(.pfBody.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.pfRoyal)
                        .cornerRadius(PFSpacing.cornerRadius)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Certificates list

/// All five certificate paths, with earned state from ProgressStore.
struct CertificatesListView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var storeManager: StoreManager
    @ObservedObject private var finalAssessmentStore = FinalAssessmentStore.shared
    @StateObject private var authService = AuthService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.md) {
                sampleCertificateSection
                courseCertificatesSection
                Text("Path certificates are issued only when every lesson in a path is complete. The Interview Preparation path has no certificate.")
                    .font(.pfBody)
                    .foregroundColor(.pfSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(LearningPath.certificatePaths) { path in
                    let progress = path.progress(in: progressStore, service: contentService)
                    let earned = path.isComplete(in: progressStore, service: contentService)
                    NavigationLink(destination: CertificateView(path: path)) {
                        PFCard {
                            HStack(spacing: PFSpacing.md) {
                                PFIconTile(systemImage: earned ? "seal.fill" : "seal", size: 44)
                                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                    Text(path.certificateTitle ?? path.title)
                                        .font(.pfCardTitle)
                                        .foregroundColor(.pfNavy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(earned ? "Earned" : "\(progress.completed) of \(progress.total) lessons complete")
                                        .font(.pfCaptionBold)
                                        .foregroundColor(earned ? .pfSuccess : .pfRoyal)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.pfSecondaryText)
                            }
                        }
                    }
                    .buttonStyle(PFCardButtonStyle())
                }
            }
            .padding(PFSpacing.lg)
            .id("certificatesTop")
        }
        .pfScrollToTopOnAppear("certificatesTop")
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle("Certificates")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sample certificate

    /// A preview of what a learner earns, shown to everyone
    /// including guests, like the sample certificates on Udemy and
    /// Coursera. Built on the fly from sample data and never stored,
    /// so it can never be mistaken for a real earned certificate.
    private var sampleCertificate: CourseCertificate {
        let name: String
        if let display = authService.currentUser?.displayName,
           !display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = display
        } else if let profileName = authService.profile?.displayName {
            name = profileName
        } else {
            name = "Sample Learner"
        }
        return CourseCertificate(
            id: "PF-SAMPLE-000000",
            courseID: PaymentConfig.fullCourseProductID,
            courseName: "The Integrated Course",
            learnerName: name,
            issuedAt: Date(),
            correctCount: 18,
            totalQuestions: 20
        )
    }

    private var sampleCertificateSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Sample certificate")
            NavigationLink(destination: CourseCertificateView(certificate: sampleCertificate, isSample: true)) {
                VStack(alignment: .leading, spacing: PFSpacing.sm) {
                    CourseCertificateCard(certificate: sampleCertificate)
                        .overlay(alignment: .topTrailing) {
                            Text("SAMPLE")
                                .font(.pfCaptionBold)
                                .foregroundColor(.white)
                                .padding(.horizontal, PFSpacing.sm)
                                .padding(.vertical, 4)
                                .background(Color.pfGold)
                                .cornerRadius(PFSpacing.sm)
                                .padding(PFSpacing.sm)
                        }
                    Text("This is what you are working towards. Pass a course Final Assessment, 20 questions, above 70 percent, with 3 attempts, to earn your own certificate.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Course certificates (Final Assessment)

    /// One row per assessable course: the certificate when earned, the
    /// Final Assessment when the course is owned and attempts remain, a
    /// locked note when all attempts were used, and a buy note when the
    /// course is not owned yet. Standalone products have no chapters
    /// and are not listed.
    private var courseCertificatesSection: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            PFSectionHeader(title: "Course certificates")
            Text("Pass a course Final Assessment with more than 70 percent to earn its certificate. Each course allows 3 attempts. Only four courses also carry a Certifier digital credential: The Integrated Course, Part 2: How Payments Move: Rails, Schemes and Systems, Part 3: Messages: SWIFT MT, ISO 20022 and Standards, and Part 9: The Business Analyst at Work.")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(FinalAssessmentStore.assessableCourses) { course in
                courseCertificateRow(for: course)
            }
        }
    }

    @ViewBuilder
    private func courseCertificateRow(for course: CourseProduct) -> some View {
        let certificate = finalAssessmentStore.certificate(for: course.productID)
        let remaining = finalAssessmentStore.attemptsRemaining(for: course.productID)
        let used = finalAssessmentStore.attemptsUsedCount(for: course.productID)
        let owned = storeManager.isProductUnlocked(course.productID)
        if let certificate {
            NavigationLink(destination: CourseCertificateView(certificate: certificate)) {
                PFCard {
                    HStack(spacing: PFSpacing.md) {
                        PFIconTile(systemImage: "seal.fill", size: 44)
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text(course.name)
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Certificate earned - \(certificate.scoreText) (\(Int(certificate.scorePercent.rounded()))%)")
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfSuccess)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.pfSecondaryText)
                    }
                }
            }
            .buttonStyle(PFCardButtonStyle())
        } else if owned && remaining > 0 {
            NavigationLink(destination: FinalAssessmentView(course: course)) {
                PFCard {
                    HStack(spacing: PFSpacing.md) {
                        PFIconTile(systemImage: "list.clipboard", size: 44)
                        VStack(alignment: .leading, spacing: PFSpacing.xs) {
                            Text(course.name)
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Final Assessment - \(remaining) of \(FinalAssessmentStore.maxAttempts) attempts left")
                                .font(.pfCaptionBold)
                                .foregroundColor(.pfRoyal)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.pfSecondaryText)
                    }
                }
            }
            .buttonStyle(PFCardButtonStyle())
        } else if owned {
            PFCard {
                HStack(spacing: PFSpacing.md) {
                    PFIconTile(systemImage: "lock.fill", size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text(course.name)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Final Assessment locked - all \(FinalAssessmentStore.maxAttempts) attempts used")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                    }
                    Spacer()
                }
            }
        } else {
            PFCard {
                HStack(spacing: PFSpacing.md) {
                    PFIconTile(systemImage: "seal", size: 44)
                    VStack(alignment: .leading, spacing: PFSpacing.xs) {
                        Text(course.name)
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Buy the course to unlock its Final Assessment")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                    }
                    Spacer()
                }
            }
        }
    }
}
