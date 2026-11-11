// CourseCertificateView.swift
// PaymentForge iOS - Course Certificate of Completion.
// Shown when a learner passes a course Final Assessment (more than
// 70 percent, at least 15 out of 20). The card is premium: royal
// blue and gold on white, Payments Training Hub branding, a gold certificate
// border. It can be shared as an image or saved as a PDF. The
// certificate record itself lives in FinalAssessmentStore, so it
// survives app restarts.
// No em dashes in any user-facing text.

import SwiftUI
import UIKit

/// The premium certificate card for one earned course certificate.
struct CourseCertificateCard: View {
    let certificate: CourseCertificate

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        VStack(spacing: PFSpacing.md) {
            Image(systemName: "seal.fill")
                .font(.system(size: 52))
                .foregroundColor(.pfGold)
            Text("PAYMENTS TRAINING HUB")
                .font(.pfCaptionBold)
                .tracking(3)
                .foregroundColor(.pfRoyal)
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
                .foregroundColor(.pfRoyal)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("has successfully completed")
                .font(.pfBody)
                .foregroundColor(.pfSecondaryText)
            Text(certificate.courseName)
                .font(.pfSectionTitle)
                .foregroundColor(.pfNavy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
                .overlay(Color.pfGold)
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
                    Text("Score")
                        .font(.pfCaptionBold)
                        .foregroundColor(.pfSecondaryText)
                    Text("\(certificate.scoreText) (\(Int(certificate.scorePercent.rounded()))%)")
                        .font(.pfBody)
                        .foregroundColor(.pfNavy)
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
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cardRadius - 5)
                .stroke(Color.pfGold.opacity(0.45), lineWidth: 1)
                .padding(6)
        )
        .shadow(color: Color.pfNavy.opacity(0.10), radius: 16, x: 0, y: 8)
    }
}

/// Renders a course certificate to a shareable image and a PDF file.
@MainActor
enum CourseCertificateExporter {
    /// The certificate card rendered to an image, at a fixed print
    /// width so the shared image looks the same on every device.
    static func image(for certificate: CourseCertificate) -> UIImage? {
        let card = CourseCertificateCard(certificate: certificate)
            .frame(width: 900)
            .background(Color.pfBackground)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        return renderer.uiImage
    }

    /// The rendered certificate image saved as a PNG in the temporary
    /// directory, so it can be shared through ShareLink. A file URL
    /// conforms to Transferable; a UIImage does not, and passing the
    /// UIImage itself to ShareLink fails to compile.
    static func imageURL(for certificate: CourseCertificate) -> URL? {
        guard let image = image(for: certificate),
              let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaymentsTrainingHub-Certificate-\(certificate.id).png")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// A one-page PDF holding the same rendered certificate image.
    /// Returns the file URL in the temporary directory.
    static func pdfURL(for certificate: CourseCertificate) -> URL? {
        guard let image = image(for: certificate) else { return nil }
        let pageRect = CGRect(origin: .zero, size: image.size)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaymentsTrainingHub-Certificate-\(certificate.id).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                image.draw(in: pageRect)
            }
            return url
        } catch {
            return nil
        }
    }
}

/// The full certificate screen: the card, verification note, and
/// ShareLinks to share the image or save a PDF.
struct CourseCertificateView: View {
    let certificate: CourseCertificate
    /// True for the sample preview in the Certificates list. A
    /// sample is clearly marked, has no verification section and no
    /// share actions, so it can never be passed off as earned.
    var isSample: Bool = false

    @State private var shareImage: UIImage? = nil
    @State private var shareImageURL: URL? = nil
    @State private var pdfURL: URL? = nil
    /// The Certifier credential for this certificate, fetched from
    /// the issue-certifier-credential edge function when the view
    /// opens. Nil until it arrives, and nil for good when the
    /// learner is not signed in, the template is not set yet, or
    /// the call fails; the plain verification section below still
    /// works in all of those cases.
    @State private var certifierCredential: CertifierCredential? = nil
    @State private var qrImage: UIImage? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                if isSample {
                    Text("SAMPLE CERTIFICATE - NOT EARNED")
                        .font(.pfCaptionBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, PFSpacing.sm)
                        .background(Color.pfGold)
                        .cornerRadius(PFSpacing.cornerRadius)
                }
                ZStack {
                    CourseCertificateCard(certificate: certificate)
                    if isSample {
                        Text("SAMPLE")
                            .font(.system(size: 64, weight: .bold))
                            .foregroundColor(Color.pfGold.opacity(0.35))
                            .rotationEffect(.degrees(-28))
                    }
                }
                if isSample {
                    Text("This is a sample to show what you earn. Pass a course Final Assessment, 20 questions, above 70 percent, with 3 attempts, to earn your own certificate.")
                        .font(.pfBody)
                        .foregroundColor(.pfSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !isSample {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        HStack(spacing: PFSpacing.sm) {
                            Text("Verification")
                                .font(.pfCardTitle)
                                .foregroundColor(.pfNavy)
                            Spacer()
                            if certifierCredential != nil {
                                Label("Verified", systemImage: "seal.check")
                                    .font(.pfCaptionBold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, PFSpacing.sm)
                                    .padding(.vertical, 4)
                                    .background(Color.pfGold)
                                    .cornerRadius(PFSpacing.cornerRadius)
                            }
                        }
                        Text("Check this certificate at:")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                        Link(certificate.verificationURL.absoluteString, destination: certificate.verificationURL)
                            .font(.pfBody)
                            .foregroundColor(.pfRoyal)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Anyone can check this certificate at the address above.")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if certifierCredential != nil {
                            if let qrImage {
                                HStack {
                                    Spacer()
                                    VStack(spacing: PFSpacing.xs) {
                                        Image(uiImage: qrImage)
                                            .resizable()
                                            .interpolation(.none)
                                            .frame(width: 180, height: 180)
                                            .background(Color.white)
                                            .cornerRadius(PFSpacing.cornerRadius)
                                        Text("Scan to verify")
                                            .font(.pfCaption)
                                            .foregroundColor(.pfSecondaryText)
                                    }
                                    Spacer()
                                }
                            }
                            Text("Also issued as a digital credential in Certifier. The wallet link was emailed to you.")
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Certificate of Completion. This certifies completion of the named course. It is not an accredited qualification.")
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let linkedinString = certifierCredential?.linkedinURL,
                   let linkedinURL = URL(string: linkedinString) {
                    Link(destination: linkedinURL) {
                        Label("Add to LinkedIn", systemImage: "link.badge.plus")
                            .font(.pfBody.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.pfRoyal)
                            .cornerRadius(PFSpacing.cornerRadius)
                    }
                }
                if let shareImageURL, let shareImage {
                    ShareLink(item: shareImageURL, preview: SharePreview("Payments Training Hub Certificate - \(certificate.courseName)", image: Image(uiImage: shareImage))) {
                        Label("Share certificate image", systemImage: "square.and.arrow.up")
                            .font(.pfBody.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.pfRoyal)
                            .cornerRadius(PFSpacing.cornerRadius)
                    }
                }
                if let pdfURL {
                    ShareLink(item: pdfURL, preview: SharePreview("Payments Training Hub Certificate - \(certificate.courseName)", image: Image(systemName: "doc.fill"))) {
                        Label("Save or share as PDF", systemImage: "doc.fill")
                            .font(.pfBody.weight(.semibold))
                            .foregroundColor(.pfRoyal)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.pfRoyal.opacity(0.10))
                            .cornerRadius(PFSpacing.cornerRadius)
                    }
                }
                ShareLink(item: certificate.shareText) {
                    Label("Share certificate details as text", systemImage: "text.bubble")
                        .font(.pfBody.weight(.semibold))
                        .foregroundColor(.pfSecondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                }
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
        .navigationTitle("Certificate")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            shareImage = CourseCertificateExporter.image(for: certificate)
            shareImageURL = CourseCertificateExporter.imageURL(for: certificate)
            pdfURL = CourseCertificateExporter.pdfURL(for: certificate)
            if !isSample {
                let token = await AuthService.shared.validAccessToken()
                let email = AuthService.shared.currentUser?.email
                if let credential = await CertifierService.requestCredential(for: certificate, accessToken: token, recipientEmail: email) {
                    certifierCredential = credential
                    if let qrData = credential.qrData {
                        qrImage = CertifierService.qrCodeImage(for: qrData, size: 180)
                    }
                }
            }
        }
    }
}
