// CertifierService.swift
// PaymentForge iOS - Certifier digital credentials.
// After a learner passes a course Final Assessment, the certificate
// view asks the issue-certifier-credential edge function to issue a
// Certifier credential for that certificate. The edge function
// returns the Certifier credential reference, the Payments Training
// Hub verification link, the QR code data and a LinkedIn
// add-to-profile URL, and the certificate view shows them. The
// first call issues the credential; later calls return the stored
// record, so one certificate costs one Certifier credit. Guests
// have no server certificate row, so they never reach this service:
// the sample certificate has no verification section at all.
// No em dashes in any user-facing text.

import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// The issue-certifier-credential edge function reply, decoded.
struct CertifierCredential: Decodable, Equatable {
    let ok: Bool
    let alreadyIssued: Bool
    let certificateID: String
    let course: String
    let certifierCredentialID: String?
    let certifierPublicID: String?
    let certifierURL: String?
    let verificationURL: String
    let linkedinURL: String?
    let qrData: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case alreadyIssued = "already_issued"
        case certificateID = "certificate_id"
        case course
        case certifierCredentialID = "certifier_credential_id"
        case certifierPublicID = "certifier_public_id"
        case certifierURL = "certifier_url"
        case verificationURL = "verification_url"
        case linkedinURL = "linkedin_url"
        case qrData = "qr_data"
    }
}

/// Asks the edge function to issue (or return) the Certifier
/// credential for one earned certificate, and renders QR codes.
enum CertifierService {

    /// The four certificate courses, by App Store product ID.
    /// Any other course has no Certifier template and is never sent.
    static func courseSlug(for productID: String) -> String? {
        switch productID {
        case "com.paymentforge.app.full": return "full"
        case "com.paymentforge.app.messaging": return "messaging"
        case "com.paymentforge.app.ba-practice": return "ba-practice"
        case "com.paymentforge.app.rails": return "rails"
        default: return nil
        }
    }

    /// One in-memory result per certificate id, so opening the same
    /// certificate twice in one session does not call the server
    /// twice. The server is still the record of what was issued.
    private static var cache: [String: CertifierCredential] = [:]

    struct IssueRequestBody: Encodable {
        let certificateID: String
        let course: String
        let recipientName: String
        let recipientEmail: String

        enum CodingKeys: String, CodingKey {
            case certificateID = "certificate_id"
            case course
            case recipientName = "recipient_name"
            case recipientEmail = "recipient_email"
        }
    }

    /// Issue the Certifier credential for this certificate, or
    /// return the stored one when it was already issued. Returns
    /// nil when the learner is not signed in, the course has no
    /// Certifier template, the certificate is not on the server yet,
    /// or the server call fails. A nil result never blocks the
    /// certificate itself: the /verify page still works.
    static func requestCredential(
        for certificate: CourseCertificate,
        accessToken: String?,
        recipientEmail: String?
    ) async -> CertifierCredential? {
        if let cached = cache[certificate.id] { return cached }
        guard let course = courseSlug(for: certificate.courseID),
              let token = accessToken,
              let email = recipientEmail, !email.isEmpty else {
            return nil
        }
        let body = IssueRequestBody(
            certificateID: certificate.id,
            course: course,
            recipientName: certificate.learnerName,
            recipientEmail: email
        )
        do {
            let data = try await SupabaseClient.shared.invokeFunction(
                name: "issue-certifier-credential",
                body: body,
                accessToken: token
            )
            let decoded = try JSONDecoder().decode(CertifierCredential.self, from: data)
            guard decoded.ok else { return nil }
            cache[certificate.id] = decoded
            return decoded
        } catch {
            return nil
        }
    }

    /// A sharp QR code image for a string, for example the
    /// verification URL. Rendered with CoreImage and upscaled
    /// without interpolation so it stays scannable.
    static func qrCodeImage(for string: String, size: CGFloat) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = max(1, size / output.extent.width)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
