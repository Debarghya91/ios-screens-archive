// AchievementShareCard.swift
// Payments Training Hub iOS - Shareable achievement cards: path completion,
// practical challenge completion, assessment pass and certificate.
//
// The card shows ONLY data the caller passes in. Nothing here
// reads ProgressStore, checks completion, or decides an
// achievement was earned: the caller must have verified the
// achievement with the real store before building the content.
// A card built with no score shows no score; a card built with
// no certificate id shows no id and no verification link.
//
// Certificate honesty: certificate ids in this app are generated
// on the device (D18, a known carried gap), and the verification
// address only resolves when the certificate row was written to
// the server, which happens for signed-in learners only. The
// card therefore never says "server-issued" or "verified", and
// it reuses the existing certificate wording: "Certificate of
// Completion. This certifies completion of the named course or
// path. It is not an accredited qualification." Nothing here
// implies formal accreditation, a regulated qualification, or
// endorsement by any bank.
//
// Audio sandbox: sharing here is rendered views and text only.
// The only file URL ever shared is a rendered PNG of the card
// itself, written to the temporary directory. No downloaded
// audio, no cached lesson file and no file URL of any other
// kind is ever passed to the share sheet.
// No em dashes in any user-facing text.

import SwiftUI
import UIKit

// MARK: - Achievement content

/// What kind of achievement a share card celebrates. The kind
/// decides the card heading and icon only; every fact on the
/// card comes from the content the caller passes in.
enum AchievementKind: Hashable {
    /// Every lesson of a learning path completed.
    case pathCompletion
    /// A practical challenge completed: a daily challenge, a
    /// practice decision, or an Exception Lab investigation.
    case challengeCompletion
    /// A course Final Assessment passed.
    case assessmentPass
    /// A certificate earned (path certificate or course
    /// certificate). Carries the certificate disclaimer.
    case certificate

    var heading: String {
        switch self {
        case .pathCompletion: return "Journey completed"
        case .challengeCompletion: return "Challenge completed"
        case .assessmentPass: return "Assessment passed"
        case .certificate: return "Certificate of Completion"
        }
    }

    var systemImage: String {
        switch self {
        case .pathCompletion: return "flag.checkered"
        case .challengeCompletion: return "flask.fill"
        case .assessmentPass: return "checkmark.seal.fill"
        case .certificate: return "seal.fill"
        }
    }
}

/// The earned data shown on one share card. Every field is
/// caller-supplied real data; optional fields stay absent when
/// the caller has no real value for them, and the card, the
/// share text and the LinkedIn text all omit them in that case.
struct AchievementShareContent: Hashable {
    let kind: AchievementKind
    /// The achievement title: the path title, the challenge
    /// title, or the course or certificate title.
    let title: String
    /// One detail line, for example the lesson count completed
    /// or the challenge description. Nil shows no detail line.
    let detail: String?
    /// The learner name, as shown on the certificate when there
    /// is one. Nil shows no name line.
    let learnerName: String?
    /// The date the achievement was earned.
    let earnedOn: Date
    /// A score line exactly as earned, for example "18/20 (90%)".
    /// Nil shows no score anywhere on the card or in the text.
    let scoreLine: String?
    /// The certificate id, when the achievement carries one.
    let certificateID: String?
    /// The verification address, when the achievement carries
    /// one. Shown as an address to check, never as proof that
    /// the check succeeds: the server row exists for signed-in
    /// learners only (D18, D20).
    let verificationURL: URL?

    /// Content for a learning-path certificate. The caller is
    /// CertificateView, which only builds it when the path is
    /// complete. The overall score is included only when an
    /// assessment was actually taken.
    static func pathCertificate(_ certificate: PFCertificate) -> AchievementShareContent {
        AchievementShareContent(
            kind: .certificate,
            title: certificate.pathTitle,
            detail: "Learning journey completed",
            learnerName: certificate.learnerName,
            earnedOn: certificate.issuedAt,
            scoreLine: certificate.overallScore.map { "Overall score: \(Int($0.rounded()))%" },
            certificateID: certificate.id,
            verificationURL: certificate.verificationURL
        )
    }

    /// Content for a course certificate. The caller is
    /// CourseCertificateView, which only shows earned
    /// certificates with share actions (samples get none).
    static func courseCertificate(_ certificate: CourseCertificate) -> AchievementShareContent {
        AchievementShareContent(
            kind: .certificate,
            title: certificate.courseName,
            detail: "Course completed",
            learnerName: certificate.learnerName,
            earnedOn: certificate.issuedAt,
            scoreLine: "Score: \(certificate.scoreText) (\(Int(certificate.scorePercent.rounded()))%)",
            certificateID: certificate.id,
            verificationURL: certificate.verificationURL
        )
    }

    /// Content for a completed learning path, without a
    /// certificate. The caller must have verified completion
    /// with LearningPath.isComplete before building this.
    static func pathCompletion(
        pathTitle: String,
        lessonCount: Int,
        earnedOn: Date,
        learnerName: String?
    ) -> AchievementShareContent {
        AchievementShareContent(
            kind: .pathCompletion,
            title: pathTitle,
            detail: "\(lessonCount) lessons completed",
            learnerName: learnerName,
            earnedOn: earnedOn,
            scoreLine: nil,
            certificateID: nil,
            verificationURL: nil
        )
    }

    /// Content for a completed practical challenge. The caller
    /// must have verified the completion with the real store
    /// (Daily Challenge, Practice Mode or the Exception Lab)
    /// before building this, and must pass the challenge's real
    /// title and the date it was completed.
    static func challengeCompletion(
        title: String,
        detail: String?,
        completedOn: Date,
        learnerName: String?
    ) -> AchievementShareContent {
        AchievementShareContent(
            kind: .challengeCompletion,
            title: title,
            detail: detail,
            learnerName: learnerName,
            earnedOn: completedOn,
            scoreLine: nil,
            certificateID: nil,
            verificationURL: nil
        )
    }

    /// Content for a passed assessment. The caller must have
    /// verified the pass with FinalAssessmentStore before
    /// building this. The certificate fields stay nil unless
    /// the pass actually issued a certificate.
    static func assessmentPass(
        courseName: String,
        scoreLine: String,
        passedOn: Date,
        learnerName: String?,
        certificateID: String? = nil,
        verificationURL: URL? = nil
    ) -> AchievementShareContent {
        AchievementShareContent(
            kind: .assessmentPass,
            title: courseName,
            detail: "Final Assessment passed",
            learnerName: learnerName,
            earnedOn: passedOn,
            scoreLine: scoreLine,
            certificateID: certificateID,
            verificationURL: verificationURL
        )
    }

    // MARK: - Share text

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    /// The date line, for example "Earned 12 November 2026".
    var earnedDateText: String {
        "Earned \(Self.dateFormatter.string(from: earnedOn))"
    }

    /// The honest footer for certificate cards. Non-certificate
    /// cards carry no certificate claim and no footer.
    var certificateDisclaimer: String? {
        guard kind == .certificate else { return nil }
        return "Certificate of Completion. This certifies completion of the named course or journey. It is not an accredited qualification."
    }

    /// The plain-text share: heading, title, name, date, score,
    /// certificate id and verification address when present,
    /// plus the certificate disclaimer for certificates. No
    /// statistics, no testimonials, no invented numbers.
    var shareText: String {
        var lines = [
            "Payments Training Hub: \(kind.heading)",
            title
        ]
        if let detail, !detail.isEmpty { lines.append(detail) }
        if let learnerName, !learnerName.isEmpty { lines.append("Earned by \(learnerName)") }
        lines.append(earnedDateText)
        if let scoreLine, !scoreLine.isEmpty { lines.append(scoreLine) }
        if let certificateID, !certificateID.isEmpty { lines.append("Certificate ID: \(certificateID)") }
        if let verificationURL { lines.append("Verify at \(verificationURL.absoluteString)") }
        if let certificateDisclaimer { lines.append(certificateDisclaimer) }
        return lines.joined(separator: "\n")
    }

    /// Post text for sharing the achievement on LinkedIn. The
    /// learner pastes this into their own post: LinkedIn does
    /// not accept post text through a share link, so nothing
    /// here claims the text is posted automatically. It states
    /// only the earned facts, with no statistics and no claim
    /// of accreditation or endorsement.
    var linkedInText: String {
        var paragraphs: [String] = []
        switch kind {
        case .pathCompletion:
            paragraphs.append("I completed the \(title) learning journey on Payments Training Hub.")
        case .challengeCompletion:
            paragraphs.append("I completed a practical payments challenge on Payments Training Hub: \(title).")
        case .assessmentPass:
            paragraphs.append("I passed the Final Assessment for \(title) on Payments Training Hub.")
        case .certificate:
            paragraphs.append("I earned a Certificate of Completion from Payments Training Hub: \(title).")
        }
        if let detail, !detail.isEmpty { paragraphs.append(detail) }
        if let scoreLine, !scoreLine.isEmpty { paragraphs.append(scoreLine) }
        paragraphs.append(earnedDateText)
        if let verificationURL {
            paragraphs.append("Verify at \(verificationURL.absoluteString)")
        }
        if let certificateDisclaimer { paragraphs.append(certificateDisclaimer) }
        return paragraphs.joined(separator: "\n\n")
    }

    /// The VoiceOver description of the card: the same earned
    /// facts, in reading order.
    var accessibilityLabel: String {
        shareText.replacingOccurrences(of: "\n", with: ". ")
    }
}

// MARK: - The card

/// The shareable achievement card: a hero-gradient header with
/// the kind icon and heading, the title, the learner name, the
/// detail and score when present, the earned date, and the
/// certificate id and verification address when present.
/// Rendered with DesignSystem tokens only. The card itself is
/// display-only: sharing is done by AchievementShareActions.
struct AchievementShareCard: View {
    let content: AchievementShareContent

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: PFSpacing.sm) {
                Image(systemName: content.kind.systemImage)
                    .font(.system(size: 44))
                    .foregroundColor(.pfGold)
                    .accessibilityHidden(true)
                Text(content.kind.heading.uppercased())
                    .font(.pfCaptionBold)
                    .tracking(2)
                    .foregroundColor(.pfGold)
                Text(content.title)
                    .font(.pfScreenTitle)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(PFSpacing.xl)
            .background(Color.pfHeroGradient)

            VStack(spacing: PFSpacing.sm) {
                if let learnerName = content.learnerName, !learnerName.isEmpty {
                    Text(learnerName)
                        .font(.pfSectionTitle.weight(.bold))
                        .foregroundColor(.pfNavy)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = content.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let scoreLine = content.scoreLine, !scoreLine.isEmpty {
                    Text(scoreLine)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfRoyal)
                        .multilineTextAlignment(.center)
                }
                Text(content.earnedDateText)
                    .font(.pfBody)
                    .foregroundColor(.pfNavy)
                if let certificateID = content.certificateID, !certificateID.isEmpty {
                    Text("Certificate ID: \(certificateID)")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let verificationURL = content.verificationURL {
                    Text(verificationURL.absoluteString)
                        .font(.pfCaption)
                        .foregroundColor(.pfRoyal)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let disclaimer = content.certificateDisclaimer {
                    Text(disclaimer)
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Payments Training Hub")
                    .font(.pfCaptionBold)
                    .foregroundColor(.pfNavy)
            }
            .frame(maxWidth: .infinity)
            .padding(PFSpacing.xl)
            .background(Color.pfCard)
        }
        .cornerRadius(PFSpacing.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cardRadius)
                .stroke(Color.pfGold, lineWidth: 2)
        )
        .shadow(color: Color.pfNavy.opacity(0.10), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
    }
}

// MARK: - Rendering (image only, never audio or cached files)

/// Renders an achievement card to a shareable image. The PNG is
/// written to the temporary directory, following the
/// CourseCertificateExporter pattern: a file URL conforms to
/// Transferable, a UIImage does not. The rendered card image is
/// the only file this code ever shares.
@MainActor
enum AchievementShareCardRenderer {
    /// The card rendered to an image, at a fixed width so the
    /// shared image looks the same on every device.
    static func image(for content: AchievementShareContent) -> UIImage? {
        let card = AchievementShareCard(content: content)
            .frame(width: 900)
            .background(Color.pfBackground)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        return renderer.uiImage
    }

    /// The rendered card image saved as a PNG in the temporary
    /// directory, so it can be shared through ShareLink.
    static func imageURL(for content: AchievementShareContent) -> URL? {
        guard let image = image(for: content),
              let data = image.pngData() else { return nil }
        let fileName = "PaymentsTrainingHub-Achievement-\(content.kind.heading.replacingOccurrences(of: " ", with: "-")).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Share actions

/// The share buttons for one earned achievement: share the card
/// as an image, share the details as text, and open LinkedIn's
/// share composer with the verification or site link attached.
/// The LinkedIn button copies the post text to the clipboard
/// first, because LinkedIn's share link cannot carry text: the
/// learner pastes it into their own post. The copied state is
/// shown on the button so the learner knows what happened.
/// Callers place this below their own earned content; it never
/// renders the card itself, so certificate screens are not
/// duplicated.
struct AchievementShareActions: View {
    let content: AchievementShareContent

    @State private var shareImage: UIImage? = nil
    @State private var shareImageURL: URL? = nil
    @State private var linkedInTextCopied = false

    /// The link LinkedIn's share composer attaches: the
    /// verification address when the achievement has one,
    /// otherwise the site home page.
    private var linkedInLink: URL {
        content.verificationURL ?? SupabaseConfig.siteBaseURL
    }

    var body: some View {
        VStack(spacing: PFSpacing.md) {
            if let shareImageURL, let shareImage {
                ShareLink(
                    item: shareImageURL,
                    preview: SharePreview("Payments Training Hub: \(content.title)", image: Image(uiImage: shareImage))
                ) {
                    Label("Share achievement card as image", systemImage: "square.and.arrow.up")
                        .font(.pfBody.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.pfRoyal)
                        .cornerRadius(PFSpacing.cornerRadius)
                }
            }
            ShareLink(item: content.shareText) {
                Label("Share achievement details as text", systemImage: "text.bubble")
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.pfRoyal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.pfRoyal.opacity(0.10))
                    .cornerRadius(PFSpacing.cornerRadius)
            }
            if let linkedInURL = LinkedInShare.shareOffsiteURL(for: linkedInLink) {
                Button {
                    UIPasteboard.general.string = content.linkedInText
                    linkedInTextCopied = true
                    UIApplication.shared.open(linkedInURL)
                } label: {
                    Label(
                        linkedInTextCopied ? "Post text copied. Paste it in LinkedIn" : "Share on LinkedIn",
                        systemImage: "link.badge.plus"
                    )
                    .font(.pfBody.weight(.semibold))
                    .foregroundColor(.pfRoyal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.pfRoyal.opacity(0.10))
                    .cornerRadius(PFSpacing.cornerRadius)
                }
                .accessibilityHint("Copies the post text, then opens LinkedIn sharing with the link attached. Paste the text into your post.")
            }
            Text("Sharing sends only the card image or text above. No audio and no lesson files are ever shared.")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            shareImage = AchievementShareCardRenderer.image(for: content)
            shareImageURL = AchievementShareCardRenderer.imageURL(for: content)
        }
    }
}
