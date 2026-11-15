// FinalAssessment.swift
// PaymentForge iOS - Final Assessment and course certificates.
// A Final Assessment is 20 questions drawn ONLY from the real lesson
// quiz questions of one course bundle's chapters. No question, option
// or correct answer is ever invented. The pass mark is strictly above
// 70 percent, so 15 or more correct out of 20. Each course allows at
// most 3 attempts, tracked per course in UserDefaults; when the
// attempts are exhausted without a pass the assessment locks and the
// learner must contact support. Passing issues a Certificate of
// Completion for that course, stored persistently so it survives
// restarts. Questions are PaymentForge-specific because they come
// from the real lesson quizzes, grounded in the course content, so
// they are not answerable from generic knowledge.
// This is one of two certificate systems, kept separate on purpose
// (v35 merge assessment, Nov 2026). CourseCertificate here is earned
// by passing a Final Assessment, stored as JSON, written to the
// course_certificates table, and issued in Certifier for the four
// certificate courses. PFCertificate in LearningPath.swift is earned
// by completing every lesson of a learning path, derived on read
// from ProgressStore, never written to Supabase, and carries an
// optional competency average instead of an exam score. The two
// cannot share one type without inventing exam scores for path
// certificates or changing stored IDs and verification behaviour,
// so do not merge them without a server-side decision first.
// No em dashes in any user-facing text.

import Foundation
import Combine

/// A Certificate of Completion earned by passing a course Final
/// Assessment. Stored as JSON in UserDefaults, keyed by course.
struct CourseCertificate: Identifiable, Codable, Hashable {
    let id: String
    /// The App Store product ID of the course, for example
    /// com.paymentforge.app.foundations.
    let courseID: String
    let courseName: String
    let learnerName: String
    let issuedAt: Date
    let correctCount: Int
    let totalQuestions: Int

    var scorePercent: Double {
        guard totalQuestions > 0 else { return 0 }
        return 100 * Double(correctCount) / Double(totalQuestions)
    }

    var scoreText: String { "\(correctCount)/\(totalQuestions)" }

    /// The logical, industry-trendy subject name shown on the
    /// certificate, instead of the raw course bundle name. Only the
    /// four certificate courses have a mapped name; anything else
    /// falls back to the bundle name. The certificate view already
    /// says "Certificate of Completion", so this is the subject,
    /// for example "AI Product Ownership for Payments".
    static func certificateSubjectName(for productID: String, fallback: String) -> String {
        switch productID {
        case "com.paymentforge.app.full":
            return "Digital Payments and Transaction Banking"
        case "com.paymentforge.app.messaging":
            return "ISO 20022 and SWIFT Messaging"
        case "com.paymentforge.app.ba-practice":
            return "AI Product Ownership for Payments"
        case "com.paymentforge.app.rails":
            return "Global Payment Rails"
        default:
            return fallback
        }
    }

    /// The full certificate title, for sharing and for Certifier.
    var certificateTitle: String { "Certificate in \(courseName)" }

    var verificationURL: URL {
        URL(string: "https://www.paymentstraininghub.com/verify?id=\(id)")!
    }

    var shareText: String {
        [
            "Payments Training Hub Certificate of Completion",
            courseName,
            "Issued to \(learnerName)",
            "Score: \(scoreText) (\(Int(scorePercent.rounded()))%)",
            "Certificate ID: \(id)",
            "Verify at \(verificationURL.absoluteString)",
            "Certificate of Completion. This certifies completion of the named course. It is not an accredited qualification."
        ].joined(separator: "\n")
    }
}

/// One row of the course_certificates table, for the website
/// verification page. Keys are the table's snake_case column names.
struct CourseCertificateRow: Encodable {
    let id: String
    let userID: String
    let courseID: String
    let courseName: String
    let learnerName: String
    let issuedAt: String
    let correctCount: Int
    let totalQuestions: Int
    let scorePercent: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case courseID = "course_id"
        case courseName = "course_name"
        case learnerName = "learner_name"
        case issuedAt = "issued_at"
        case correctCount = "correct_count"
        case totalQuestions = "total_questions"
        case scorePercent = "score_percent"
    }
}

/// Tracks Final Assessment attempts and issued course certificates,
/// persisted in UserDefaults so they survive app restarts. Storage
/// is namespaced per account through AccountScopedStorage: one
/// learner's attempts and certificates are never served to another.
/// This store is the single source of truth for attempts and
/// certificates.
final class FinalAssessmentStore: ObservableObject {
    static let shared = FinalAssessmentStore()

    /// Questions in one Final Assessment.
    static let questionCount = 20
    /// Pass is strictly above 70 percent of 20, so 15 or more correct.
    /// 14 correct is exactly 70 percent and does not pass.
    static let passCorrectCount = 15
    static let maxAttempts = 3

    /// Courses a Final Assessment can be taken for: every product
    /// with chapters. Situations has no chapters and no assessment.
    static var assessableCourses: [CourseProduct] {
        ProductCatalogue.products.filter { !$0.chapterIDs.isEmpty }
    }

    @Published private(set) var certificates: [String: CourseCertificate] = [:]
    @Published private(set) var attemptsUsed: [String: Int] = [:]

    private enum Keys {
        static let certificates = "pf.finalAssessment.certificates.v1"
        static let attempts = "pf.finalAssessment.attempts.v1"
    }

    init() {
        load()
    }

    /// Reload for the current account namespace, clearing the
    /// previous account's certificates and attempt counts first.
    func reloadForCurrentAccount() {
        certificates = [:]
        attemptsUsed = [:]
        load()
    }

    private func load() {
        AccountScopedStorage.adoptLegacyKey(Keys.certificates)
        AccountScopedStorage.adoptLegacyKey(Keys.attempts)
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: AccountScopedStorage.currentKey(Keys.certificates)),
           let decoded = try? JSONDecoder().decode([String: CourseCertificate].self, from: data) {
            certificates = decoded
        }
        if let data = defaults.data(forKey: AccountScopedStorage.currentKey(Keys.attempts)),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            attemptsUsed = decoded
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(certificates) {
            defaults.set(data, forKey: AccountScopedStorage.currentKey(Keys.certificates))
        }
        if let data = try? JSONEncoder().encode(attemptsUsed) {
            defaults.set(data, forKey: AccountScopedStorage.currentKey(Keys.attempts))
        }
    }

    func certificate(for courseID: String) -> CourseCertificate? {
        certificates[courseID]
    }

    func attemptsUsedCount(for courseID: String) -> Int {
        attemptsUsed[courseID] ?? 0
    }

    func attemptsRemaining(for courseID: String) -> Int {
        max(0, Self.maxAttempts - attemptsUsedCount(for: courseID))
    }

    func hasPassed(courseID: String) -> Bool {
        certificates[courseID] != nil
    }

    /// True when the learner may start a new attempt: no certificate
    /// yet and at least one attempt left.
    func canAttempt(courseID: String) -> Bool {
        certificates[courseID] == nil && attemptsRemaining(for: courseID) > 0
    }

    /// True when all 3 attempts were used without a pass.
    func isLocked(courseID: String) -> Bool {
        certificates[courseID] == nil && attemptsRemaining(for: courseID) == 0
    }

    func allCertificates() -> [CourseCertificate] {
        certificates.values.sorted { $0.issuedAt > $1.issuedAt }
    }

    /// Record one completed attempt. Increments the attempt count and
    /// persists it. When the score passes, issues and stores the
    /// certificate and returns it; otherwise returns nil. A second
    /// call after a pass never issues a second certificate.
    @discardableResult
    func recordAttempt(for course: CourseProduct, correct: Int, total: Int, learnerName: String) -> CourseCertificate? {
        let used = attemptsUsedCount(for: course.productID) + 1
        attemptsUsed[course.productID] = used
        var issued: CourseCertificate? = nil
        if correct >= Self.passCorrectCount && certificates[course.productID] == nil {
            let cert = CourseCertificate(
                id: "PF-\(course.id.uppercased())-\(UUID().uuidString.prefix(8).uppercased())",
                courseID: course.productID,
                courseName: CourseCertificate.certificateSubjectName(for: course.productID, fallback: course.name),
                learnerName: learnerName,
                issuedAt: Date(),
                correctCount: correct,
                totalQuestions: total
            )
            certificates[course.productID] = cert
            issued = cert
        }
        persist()
        if let issued {
            // Save a copy to Supabase so the certificate can be
            // verified on the website. Fire and forget: the local
            // certificate is the record of the pass, and a failed
            // save must never block it or confuse the learner.
            Task { @MainActor in
                await FinalAssessmentStore.saveCertificateToServer(issued)
            }
        }
        return issued
    }

    /// Insert one issued certificate into the course_certificates
    /// table so the website verification page can check it. Silent
    /// on failure: the local certificate still counts. Guests have
    /// no account, so their certificates stay local only.
    @MainActor
    private static func saveCertificateToServer(_ certificate: CourseCertificate) async {
        guard let userID = AuthService.shared.currentUser?.id,
              let token = await AuthService.shared.validAccessToken() else {
            return
        }
        let row = CourseCertificateRow(
            id: certificate.id,
            userID: userID,
            courseID: certificate.courseID,
            courseName: certificate.courseName,
            learnerName: certificate.learnerName,
            issuedAt: ISO8601DateFormatter().string(from: certificate.issuedAt),
            correctCount: certificate.correctCount,
            totalQuestions: certificate.totalQuestions,
            scorePercent: Int(certificate.scorePercent.rounded())
        )
        do {
            _ = try await SupabaseClient.shared.restInsert(
                table: "course_certificates",
                rows: [row],
                accessToken: token
            )
        } catch {
            // Local certificate still counts; the row is simply not
            // verifiable on the website until it is saved again.
        }
    }
}
