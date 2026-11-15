// LearningPath.swift
// PaymentForge iOS - Guided learning paths and certificates.
// A path is defined by real chapter numbers, so its required lessons
// are resolved from the loaded catalogue at runtime: only lesson ids
// that exist in the search index can ever appear, and the counts shown
// are the real counts from that catalogue. Situation ids below were
// verified against the live situations data on 11 Nov 2026.
// Chapter titles were verified against the live lesson pages the same day.
// No lesson counts, durations or scores are hardcoded here.
// No em dashes in any user-facing text.

import Foundation
import Combine

// MARK: - Learning path

/// One guided learning path: a set of real chapters, real situations,
/// assessment checkpoints and a capstone situation.
struct LearningPath: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let level: String
    let systemImage: String
    let objectives: [String]
    /// Chapter numbers whose lessons are all required for this path.
    let chapterNumbers: [Int]
    /// Real situation ids practised along the path.
    let situationIDs: [String]
    /// The capstone: one real situation, worked end to end.
    let capstoneSituationID: String
    let assessmentDimension: CompetencyStore.CompetencyDimension
    /// The certificate title earned on completion, nil when this path
    /// has no certificate (Interview Preparation).
    let certificateTitle: String?
    /// Honest plain-language entry expectations: what the learner
    /// should already be comfortable with. A level description only:
    /// nothing here is enforced, and any lesson can be opened at any
    /// time.
    let entryExpectations: String
    /// What completing this path really requires: every required
    /// lesson complete, plus the certificate note where one exists.
    /// Never claims an exam or assessment is required.
    let completionCriteria: String

    /// Required lessons, in catalogue order: every lesson of every
    /// chapter in this path. Empty while the catalogue is loading.
    func lessons(in service: ContentService) -> [SearchEntry] {
        var seen: Set<String> = []
        var result: [SearchEntry] = []
        for number in chapterNumbers {
            for lesson in PFChapterHelper.lessons(forChapter: number, in: service) {
                if seen.insert(lesson.id).inserted {
                    result.append(lesson)
                }
            }
        }
        return result
    }

    /// Chapter titles for this path, from the catalogue.
    func chapterTitles(in service: ContentService) -> [(number: Int, title: String)] {
        chapterNumbers.map { number in
            let lessons = PFChapterHelper.lessons(forChapter: number, in: service)
            return (number, PFChapterHelper.chapterTitle(for: lessons, number: number))
        }
    }

    /// The path situations, resolved from the full situations data
    /// first and the search index as fallback. Ids that are not in
    /// either source are dropped, never invented.
    func situations(in service: ContentService) -> [Situation] {
        situationIDs.compactMap { pfSituation(id: $0, in: service) }
    }

    /// The capstone situation, or nil while the catalogue is loading.
    func capstone(in service: ContentService) -> Situation? {
        pfSituation(id: capstoneSituationID, in: service)
    }

    /// Completed required lessons over total required lessons.
    func progress(in progressStore: ProgressStore, service: ContentService) -> (completed: Int, total: Int) {
        let required = lessons(in: service)
        let completed = required.filter { progressStore.isLessonComplete($0.id) }.count
        return (completed, required.count)
    }

    /// True only when every required lesson is complete.
    func isComplete(in progressStore: ProgressStore, service: ContentService) -> Bool {
        let result = progress(in: progressStore, service: service)
        return result.total > 0 && result.completed == result.total
    }

    /// The path's simulator exercises: lab-type catalogue entries
    /// whose chapter number is one of this path's chapters, resolved
    /// live. Empty when the catalogue lists no lab for these
    /// chapters: the live lab entries carry LAB and FLOW ids with
    /// no chapter number, so this is empty for every path until
    /// the catalogue links labs to chapters. Callers must show an
    /// honest empty state, never invent an exercise.
    func labs(in service: ContentService) -> [SearchEntry] {
        guard let entries = service.searchIndex?.entries else { return [] }
        let wanted = Set(chapterNumbers)
        return entries.filter { entry in
            guard entry.type == .lab, let number = entry.chapterNumber else { return false }
            return wanted.contains(number)
        }
    }

    /// The first required lesson not yet complete, in path order.
    /// Nil when every required lesson is complete, or while the
    /// catalogue is loading.
    func firstIncompleteLesson(in progress: ProgressStore, service: ContentService) -> SearchEntry? {
        lessons(in: service).first { !progress.isLessonComplete($0.id) }
    }

    /// Whole weeks to finish this path at a weekly lesson target,
    /// rounded up. Nil when the target is not positive, or when the
    /// path has no required lessons yet. The lesson count is
    /// resolved from the shared catalogue, because this signature
    /// carries no service: callers that already hold a service use
    /// the static helper with lessons(in:) instead. No minutes are
    /// invented: the count is required lessons only.
    func estimatedWeeks(weeklyTarget: Int) -> Int? {
        Self.estimatedWeeks(
            totalLessons: lessons(in: ContentService.shared).count,
            weeklyTarget: weeklyTarget
        )
    }

    /// The estimated-weeks maths, pure and exposed for tests: the
    /// ceiling of total over weekly target when both are positive,
    /// nil otherwise.
    static func estimatedWeeks(totalLessons: Int, weeklyTarget: Int) -> Int? {
        guard totalLessons > 0, weeklyTarget > 0 else { return nil }
        return (totalLessons + weeklyTarget - 1) / weeklyTarget
    }
}

/// Resolve one situation by id: full data first, search index fallback.
func pfSituation(id: String, in service: ContentService) -> Situation? {
    if let full = service.fullSituations?.first(where: { $0.id == id }) {
        return situation(fromFull: full)
    }
    if let entry = service.allSituations.first(where: { $0.id == id }) {
        return situation(from: entry)
    }
    return nil
}

// MARK: - Competency dimension chapters

extension CompetencyStore.CompetencyDimension {
    /// Chapters whose lesson quizzes feed this dimension's assessment.
    /// Chapter titles verified against the live lesson pages, 11 Nov 2026.
    var chapterNumbers: [Int] {
        switch self {
        case .architecture:
            return [25, 30, 35, 36, 48, 79]
        case .lifecycle:
            return [4, 17, 18, 72]
        case .businessAnalysis:
            return [28, 37, 45, 84]
        case .exceptionHandling:
            return [16, 41, 58, 73]
        case .reconciliation:
            return [40, 44, 71, 88, 89]
        }
    }
}

// MARK: - The six guided paths

extension LearningPath {
    static let all: [LearningPath] = [
        LearningPath(
            id: "fundamentals",
            title: "Payments Fundamentals",
            description: "What a payment is, the instruments used to make one, the parties involved, and the lifecycle from instruction to settlement.",
            level: "Foundation",
            systemImage: "book.fill",
            objectives: [
                "Explain what a payment is and how it differs from a transfer and from settlement.",
                "Name the payment instruments and the parties in a payment.",
                "Trace a payment end to end through its lifecycle.",
                "Read a payment situation and spot where the lifecycle broke down."
            ],
            chapterNumbers: [1, 2, 3, 4],
            situationIDs: ["ABH-01", "ABH-02", "INS-001", "SCN-15"],
            capstoneSituationID: "ABH-10",
            assessmentDimension: .architecture,
            certificateTitle: "Payments Fundamentals",
            entryExpectations: "No prior knowledge of payments is assumed. This foundation path starts with what a payment is and builds from there, so it is the right starting point for a complete beginner.",
            completionCriteria: "Complete every required lesson in this path to earn the Payments Fundamentals certificate. No exam or assessment is required; the assessment checkpoint is optional practice."
        ),
        LearningPath(
            id: "business-analyst",
            title: "Payments Business Analyst",
            description: "The BA craft in payments: workshops, requirements, data models, product thinking and a capstone project drawn from real bank practice.",
            level: "Intermediate",
            systemImage: "doc.text.fill",
            objectives: [
                "Run a payments BA workshop and capture requirements that hold up.",
                "Model payment data and map it across systems.",
                "Write product requirements a delivery team can build from.",
                "Present a payments case the way a senior BA would."
            ],
            chapterNumbers: [28, 37, 45, 84, 29],
            situationIDs: ["ABH-37", "INS-084", "INS-085", "INS-096"],
            capstoneSituationID: "ABH-18",
            assessmentDimension: .businessAnalysis,
            certificateTitle: "Payments Business Analyst Foundations",
            entryExpectations: "An intermediate path. It helps to already be comfortable with payments fundamentals, such as what a payment is and how one moves. No prior business analysis experience is assumed. Nothing here is enforced and any lesson can be opened at any time.",
            completionCriteria: "Complete every required lesson in this path to earn the Payments Business Analyst Foundations certificate. No exam or assessment is required; the assessment checkpoint is optional practice."
        ),
        LearningPath(
            id: "upi-specialist",
            title: "UPI Specialist",
            description: "India's instant payments in depth: UPI, IMPS, NEFT and RTGS, the Indian payments landscape, and real-time payments architecture.",
            level: "Intermediate",
            systemImage: "bolt.fill",
            objectives: [
                "Explain how a UPI payment moves from payer app to payee bank.",
                "Compare UPI, IMPS, NEFT and RTGS and pick the right rail.",
                "Describe the Indian payments landscape: NACH, BBPS and FEMA.",
                "Diagnose a failed or delayed instant payment."
            ],
            chapterNumbers: [9, 33, 46],
            situationIDs: ["INS-105", "INS-166", "INS-067", "INS-033"],
            capstoneSituationID: "SCN-36",
            assessmentDimension: .lifecycle,
            certificateTitle: "UPI Professional Foundations",
            entryExpectations: "An intermediate path. It helps to already be comfortable with payments fundamentals. No prior knowledge of Indian payment systems is assumed. Nothing here is enforced and any lesson can be opened at any time.",
            completionCriteria: "Complete every required lesson in this path to earn the UPI Professional Foundations certificate. No exam or assessment is required; the assessment checkpoint is optional practice."
        ),
        LearningPath(
            id: "cards-digital",
            title: "Cards and Digital Banking",
            description: "Card payments end to end: authorisation, clearing and settlement, networks, wallets, POS, 3D Secure, tokenization and chargebacks.",
            level: "Intermediate",
            systemImage: "creditcard.fill",
            objectives: [
                "Trace a card payment from authorisation through clearing to settlement.",
                "Explain how Visa and Mastercard networks move a transaction.",
                "Describe 3D Secure, tokenization and how wallets and POS work.",
                "Handle a chargeback and explain who bears the loss."
            ],
            chapterNumbers: [21, 22, 31, 32, 63],
            situationIDs: ["ABH-04", "INS-001", "INS-005", "RUN5-001"],
            capstoneSituationID: "RUN5-003",
            assessmentDimension: .lifecycle,
            certificateTitle: "Card Payments Fundamentals",
            entryExpectations: "An intermediate path. It helps to already be comfortable with payments fundamentals. No prior knowledge of card payments is assumed. Nothing here is enforced and any lesson can be opened at any time.",
            completionCriteria: "Complete every required lesson in this path to earn the Card Payments Fundamentals certificate. No exam or assessment is required; the assessment checkpoint is optional practice."
        ),
        LearningPath(
            id: "operations-reconciliation",
            title: "Payment Operations and Reconciliation",
            description: "The operations floor: reconciliation, exceptions and investigations, rejects and returns, and the architecture that keeps payments resilient.",
            level: "Advanced",
            systemImage: "gearshape.fill",
            objectives: [
                "Reconcile a payment book and explain every break.",
                "Work an exception from first alert to resolution.",
                "Handle rejects and returns under CBPR+.",
                "Describe the controls that keep payment operations resilient."
            ],
            chapterNumbers: [40, 41, 44, 58, 68],
            situationIDs: ["INS-161", "INS-109", "INS-162", "PAI-C001"],
            capstoneSituationID: "SCN-19",
            assessmentDimension: .reconciliation,
            certificateTitle: "Payment Operations and Reconciliation",
            entryExpectations: "An advanced path. It helps to already be comfortable with payments fundamentals and with how payments move and fail. Nothing here is enforced and any lesson can be opened at any time.",
            completionCriteria: "Complete every required lesson in this path to earn the Payment Operations and Reconciliation certificate. No exam or assessment is required; the assessment checkpoint is optional practice."
        ),
        LearningPath(
            id: "interview-preparation",
            title: "Payments Interview Preparation",
            description: "Interview-ready payments: how large banks run payments, cross-border investigations, claims and case management, and a capstone case to present.",
            level: "Advanced",
            systemImage: "person.fill.questionmark",
            objectives: [
                "Explain how large banks organise payments operations.",
                "Work a cross-border investigation from first alert to close.",
                "Answer payments interview questions with real cases, not definitions.",
                "Walk through a capstone project end to end."
            ],
            chapterNumbers: [37, 75, 73, 29],
            situationIDs: ["INS-096", "INS-085", "INS-084", "ABH-36"],
            capstoneSituationID: "ABH-37",
            assessmentDimension: .exceptionHandling,
            certificateTitle: nil,
            entryExpectations: "An advanced path for learners preparing to talk about payments work in interviews. It helps to have covered payments fundamentals first. Nothing here is enforced and any lesson can be opened at any time.",
            completionCriteria: "Complete every required lesson in this path. This path has no certificate, and no exam or assessment is required; the assessment checkpoint is optional practice."
        )
    ]

    /// The five paths that carry a certificate, in path order.
    static var certificatePaths: [LearningPath] {
        all.filter { $0.certificateTitle != nil }
    }
}

// MARK: - Path bookmarks (local only)

/// Local bookmarks for guided paths, stored in UserDefaults,
/// namespaced per account through AccountScopedStorage.
/// The mockup shows a bookmark on each pathway card; this is the
/// learner's own saved set, nothing more.
final class PathBookmarkStore: ObservableObject {
    static let shared = PathBookmarkStore()

    private enum Keys {
        static let bookmarked = "pf.pathBookmarks.v1"
    }

    @Published private(set) var bookmarkedIDs: Set<String> = [] {
        didSet { save() }
    }

    /// Suppresses save() while loading, so a reload into an account
    /// with no stored bookmarks does not write an empty set into
    /// that namespace (which would block guest migration for it).
    private var suppressSave = false

    private func withoutSaving(_ work: () -> Void) {
        let previous = suppressSave
        suppressSave = true
        defer { suppressSave = previous }
        work()
    }

    func isBookmarked(_ pathID: String) -> Bool {
        bookmarkedIDs.contains(pathID)
    }

    func toggle(_ pathID: String) {
        if bookmarkedIDs.contains(pathID) {
            bookmarkedIDs.remove(pathID)
        } else {
            bookmarkedIDs.insert(pathID)
        }
    }

    init() {
        load()
    }

    /// Reload for the current account namespace, clearing the
    /// previous account's bookmarks first.
    func reloadForCurrentAccount() {
        withoutSaving { bookmarkedIDs = [] }
        load()
    }

    private func load() {
        withoutSaving {
            AccountScopedStorage.adoptLegacyKey(Keys.bookmarked)
            bookmarkedIDs = Set(UserDefaults.standard.stringArray(forKey: AccountScopedStorage.currentKey(Keys.bookmarked)) ?? [])
        }
    }

    private func save() {
        guard !suppressSave else { return }
        UserDefaults.standard.set(Array(bookmarkedIDs), forKey: AccountScopedStorage.currentKey(Keys.bookmarked))
    }
}

// MARK: - Certificate

/// A certificate of completion for one learning path. Issued only when
/// every required lesson of the path is complete, checked against
/// ProgressStore at issue time. The completion date is the date the
/// certificate was first issued on this device: ProgressStore records
/// which lessons are complete but not the date each was finished, so
/// no earlier completion date can be honestly stated.
struct PFCertificate: Identifiable, Codable {
    let id: String
    let pathID: String
    let pathTitle: String
    let learnerName: String
    let issuedAt: Date
    /// Overall competency score at issue time, nil when no assessment
    /// had been taken yet. Never a fabricated score.
    let overallScore: Double?

    var verificationURL: URL {
        URL(string: "https://www.paymentstraininghub.com/certificate/\(id)")!
    }

    var shareText: String {
        var lines = [
            "Payments Training Hub Certificate of Completion",
            pathTitle,
            "Issued to \(learnerName)",
            "Certificate ID: \(id)",
            "Verify at \(verificationURL.absoluteString)"
        ]
        if let overallScore {
            lines.append("Overall score: \(Int(overallScore.rounded()))%")
        }
        lines.append("Certificate of Completion. This certifies completion of the named learning path. It is not an accredited qualification.")
        return lines.joined(separator: "\n")
    }
}

/// One row of the course_certificates table for a learning-path
/// certificate, for the website verification page. Path certificates
/// have no exam, so the score columns are always nil and are omitted
/// from the JSON (see encode(to:), following UserLearningPathRow):
/// no exam score is ever invented. The competency average is the
/// certificate's overallScore, itself nil when no assessment had
/// been taken yet. Keys are the table's snake_case column names.
/// Kept separate from CourseCertificateRow on purpose: the two
/// certificate systems must not merge.
struct PathCertificateRow: Encodable {
    let id: String
    let userID: String
    let courseID: String
    let courseName: String
    let learnerName: String
    let issuedAt: String
    let certificateKind: String
    let correctCount: Int?
    let totalQuestions: Int?
    let scorePercent: Int?
    let competencyAverage: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case courseID = "course_id"
        case courseName = "course_name"
        case learnerName = "learner_name"
        case issuedAt = "issued_at"
        case certificateKind = "certificate_kind"
        case correctCount = "correct_count"
        case totalQuestions = "total_questions"
        case scorePercent = "score_percent"
        case competencyAverage = "competency_average"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(courseID, forKey: .courseID)
        try container.encode(courseName, forKey: .courseName)
        try container.encode(learnerName, forKey: .learnerName)
        try container.encode(issuedAt, forKey: .issuedAt)
        try container.encode(certificateKind, forKey: .certificateKind)
        try container.encodeIfPresent(correctCount, forKey: .correctCount)
        try container.encodeIfPresent(totalQuestions, forKey: .totalQuestions)
        try container.encodeIfPresent(scorePercent, forKey: .scorePercent)
        try container.encodeIfPresent(competencyAverage, forKey: .competencyAverage)
    }
}

/// Issues and re-reads certificates. The issued date is stored the
/// first time a completed path is viewed, and never changes after that.
enum PFCertificateStore {
    private static func key(for pathID: String) -> String {
        AccountScopedStorage.currentKey("pf.certificateIssuedAt.\(pathID).v1")
    }

    /// The certificate for a path, or nil when the path is not complete
    /// yet. Never issues for an incomplete path.
    static func certificate(
        for path: LearningPath,
        progress: ProgressStore,
        service: ContentService,
        competency: CompetencyStore,
        learnerName: String
    ) -> PFCertificate? {
        guard let certificateTitle = path.certificateTitle,
              path.isComplete(in: progress, service: service) else { return nil }
        AccountScopedStorage.adoptLegacyKey("pf.certificateIssuedAt.\(path.id).v1")
        let defaults = UserDefaults.standard
        let issuedAt: Date
        if let stored = defaults.object(forKey: key(for: path.id)) as? Date {
            issuedAt = stored
        } else {
            issuedAt = Date()
            defaults.set(issuedAt, forKey: key(for: path.id))
        }
        return PFCertificate(
            id: stableCertificateID(for: path.id),
            pathID: path.id,
            pathTitle: certificateTitle,
            learnerName: learnerName,
            issuedAt: issuedAt,
            overallScore: competency.hasAssessments ? competency.overallScore : nil
        )
    }

    /// A stable certificate id per path, so the same certificate keeps
    /// the same id across views: it is generated once and stored.
    static func stableCertificateID(for pathID: String) -> String {
        let baseKey = "pf.certificateID.\(pathID).v1"
        AccountScopedStorage.adoptLegacyKey(baseKey)
        let key = AccountScopedStorage.currentKey(baseKey)
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }
        let fresh = "PF-\(pathID.uppercased())-\(UUID().uuidString.prefix(8).uppercased())"
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    // MARK: - Server verification copy (v36)

    /// UserDefaults key for the set of path certificate ids already
    /// written to the course_certificates table. An id is added only
    /// after a successful insert, never after a failure, so a failed
    /// write (for example before the matching server migration is
    /// applied) is retried on the next trigger.
    private static let syncedIDsKey = "pf.pathCertificatesSynced.v1"

    /// Ids with an insert currently in flight, so concurrent triggers
    /// (view appearance and sync) do not double-insert the same row.
    /// MainActor-isolated: only syncCertificateToServer touches it.
    @MainActor
    private static var inFlightIDs: Set<String> = []

    /// The ids already written to the server, from UserDefaults,
    /// namespaced per account: one account's synced set must never
    /// stop another account's certificates being written.
    private static var syncedIDs: Set<String> {
        get {
            AccountScopedStorage.adoptLegacyKey(syncedIDsKey)
            return Set(UserDefaults.standard.stringArray(forKey: AccountScopedStorage.currentKey(syncedIDsKey)) ?? [])
        }
        set { UserDefaults.standard.set(Array(newValue), forKey: AccountScopedStorage.currentKey(syncedIDsKey)) }
    }

    /// Adopt any legacy certificate keys into the current namespace.
    /// Certificates hold no in-memory cache (issued dates, ids and
    /// the synced set are read from UserDefaults on each access),
    /// so adoption is the whole reload; there is nothing stale to
    /// clear. Called by AuthService on account switch for symmetry
    /// with the stateful stores.
    static func reloadForCurrentAccount() {
        AccountScopedStorage.adoptLegacyKey(syncedIDsKey)
        AccountScopedStorage.adoptLegacyKeys(withPrefix: "pf.certificateIssuedAt.")
        AccountScopedStorage.adoptLegacyKeys(withPrefix: "pf.certificateID.")
    }

    /// Insert one path certificate into the course_certificates table
    /// so the website verification page can check it. Mirrors
    /// FinalAssessmentStore.saveCertificateToServer: signed-in users
    /// only, fire and forget, silent on every failure. The local
    /// certificate always still counts. Guests have no account, so
    /// their certificates stay local only. A certificate whose
    /// learner name is the "Guest Learner" fallback is never written:
    /// learner_name must be a real signed-in name. The path id and
    /// the certificate title are the row's course id and course name:
    /// paths have no product id, and nothing else may be invented.
    /// Never call this from certificate(): that function runs during
    /// SwiftUI view evaluation and must stay free of network effects.
    /// Call sites: CertificateView on appearance, and the SyncService
    /// backfill inside syncAll.
    @MainActor
    static func syncCertificateToServer(_ certificate: PFCertificate) async {
        guard !syncedIDs.contains(certificate.id),
              !inFlightIDs.contains(certificate.id) else { return }
        let trimmedName = certificate.learnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != "Guest Learner" else { return }
        inFlightIDs.insert(certificate.id)
        defer { inFlightIDs.remove(certificate.id) }
        guard let userID = AuthService.shared.currentUser?.id,
              let token = await AuthService.shared.validAccessToken() else {
            return
        }
        let row = PathCertificateRow(
            id: certificate.id,
            userID: userID,
            courseID: certificate.pathID,
            courseName: certificate.pathTitle,
            learnerName: certificate.learnerName,
            issuedAt: ISO8601DateFormatter().string(from: certificate.issuedAt),
            certificateKind: "path",
            correctCount: nil,
            totalQuestions: nil,
            scorePercent: nil,
            competencyAverage: certificate.overallScore
        )
        do {
            _ = try await SupabaseClient.shared.restInsert(
                table: "course_certificates",
                rows: [row],
                accessToken: token
            )
            var synced = syncedIDs
            synced.insert(certificate.id)
            syncedIDs = synced
        } catch {
            // Silent, exactly like course certificates: the local
            // certificate still counts, the id stays unsynced, and
            // the next trigger retries. A duplicate insert fails
            // here too; the table's primary key prevents a second row.
        }
    }
}
